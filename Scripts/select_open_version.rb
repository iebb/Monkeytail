#!/usr/bin/env ruby
# frozen_string_literal: true

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

# Queries App Store Connect across iOS, macOS, and visionOS to detect closed
# marketing version trains (checking both appVersionState and appStoreState),
# selects the next open patch version and monotonic build number, and optionally
# writes the bumped MARKETING_VERSION back to project.yml and project.pbxproj.
module SelectOpenVersion
  API_BASE = 'https://api.appstoreconnect.apple.com/v1'
  PLATFORMS = %w[IOS MAC_OS VISION_OS].freeze
  CLOSED_STATES = %w[
    ACCEPTED
    PENDING_APPLE_RELEASE
    PENDING_DEVELOPER_RELEASE
    PENDING_CONTRACT
    PROCESSING_FOR_DISTRIBUTION
    PROCESSING_FOR_APP_STORE
    READY_FOR_DISTRIBUTION
    READY_FOR_SALE
    PREORDER_READY_FOR_SALE
    REPLACED_WITH_NEW_VERSION
    DEVELOPER_REMOVED_FROM_SALE
    REMOVED_FROM_SALE
  ].freeze

  class Client
    def initialize(key_id:, issuer_id:, key_path:)
      @key_id = key_id
      @issuer_id = issuer_id
      @private_key = OpenSSL::PKey.read(File.binread(key_path))
    end

    def get_all(path, params = {})
      data = []
      seen = {}
      current_path = path
      current_params = params.merge('limit' => '200')
      loop do
        uri = URI("#{API_BASE}#{current_path}")
        uri.query = URI.encode_www_form(current_params) unless current_params.empty?
        raise "Pagination loop on #{uri}" if seen[uri.to_s]

        seen[uri.to_s] = true
        req = Net::HTTP::Get.new(uri)
        req['Authorization'] = "Bearer #{token}"
        req['Accept'] = 'application/json'
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 60) { |h| h.request(req) }
        raise "ASC GET #{current_path} returned #{res.code}" unless res.code.to_i.between?(200, 299)

        payload = JSON.parse(res.body)
        data.concat(payload.fetch('data', []))
        next_link = payload.dig('links', 'next')
        break unless next_link

        next_uri = URI(next_link)
        raise "Unexpected pagination host #{next_uri.host}" unless next_uri.scheme == 'https' && next_uri.host == 'api.appstoreconnect.apple.com'

        current_path = next_uri.path.delete_prefix('/v1')
        current_params = URI.decode_www_form(next_uri.query.to_s).to_h
      end
      data
    end

    private

    def token
      now = Time.now.to_i
      header = { 'alg' => 'ES256', 'kid' => @key_id, 'typ' => 'JWT' }
      claims = { 'iss' => @issuer_id, 'iat' => now - 30, 'exp' => now + 600, 'aud' => 'appstoreconnect-v1' }
      signing_input = "#{b64(JSON.generate(header))}.#{b64(JSON.generate(claims))}"
      seq = OpenSSL::ASN1.decode(@private_key.sign(OpenSSL::Digest::SHA256.new, signing_input))
      sig = seq.value.map { |int| int_bytes(int.value, 32) }.join
      "#{signing_input}.#{b64(sig)}"
    end

    def int_bytes(int, len)
      hex = int.to_i.to_s(16)
      hex = "0#{hex}" if hex.length.odd?
      bytes = [hex].pack('H*')
      raise 'Invalid ES256 signature' if bytes.bytesize > len

      ("\x00" * (len - bytes.bytesize)) + bytes
    end

    def b64(val)
      Base64.urlsafe_encode64(val, padding: false)
    end
  end

  def self.parts(value)
    raise ArgumentError, "Invalid marketing version #{value.inspect}" unless value.is_a?(String) && value.match?(/\A\d+(?:\.\d+){0,2}\z/)

    nums = value.split('.').map(&:to_i)
    nums.fill(0, nums.length...3)
  end

  def self.choose(source, store_versions, trains = [], platforms = PLATFORMS)
    candidates = [parts(source)] + trains.map { |v| parts(v) }
    store_versions.each do |attrs|
      next if attrs['platform'] && !platforms.include?(attrs['platform'])

      ver = parts(attrs.fetch('versionString'))
      state = attrs['appVersionState'] || attrs['appStoreState']
      ver[2] += 1 if CLOSED_STATES.include?(state)
      candidates << ver
    end
    candidates.max.join('.')
  end

  def self.next_build_number(builds, minimum_floor)
    highest = builds.map do |attrs|
      raw = attrs['version'].to_s
      raw.match?(/\A\d+(?:\.\d+)*\z/) ? raw.split('.').first.to_i : 0
    end.max.to_i
    [highest + 1, minimum_floor].max
  end

  def self.read_repo_versions(root = '.')
    pbx = File.read(File.join(root, 'Monkeytail.xcodeproj/project.pbxproj'))
    pbx_versions = pbx.scan(/MARKETING_VERSION = "?(\d+(?:\.\d+){1,2})"?;/).flatten.uniq
    raise "Expected MARKETING_VERSION in project.pbxproj, found #{pbx_versions.inspect}" if pbx_versions.empty?

    yml_path = File.join(root, 'project.yml')
    yml_versions = File.exist?(yml_path) ? File.read(yml_path).scan(/MARKETING_VERSION:\s*['"]?(\d+(?:\.\d+){1,2})['"]?/).flatten.uniq : pbx_versions
    [pbx_versions, yml_versions]
  end

  def self.write_repo_version(version, root = '.')
    parts(version)
    pbx_path = File.join(root, 'Monkeytail.xcodeproj/project.pbxproj')
    pbx = File.read(pbx_path)
    updated_pbx = pbx.gsub(/MARKETING_VERSION = "?(\d+(?:\.\d+){1,2})"?;/, "MARKETING_VERSION = #{version};")
    File.write(pbx_path, updated_pbx) if updated_pbx != pbx

    yml_path = File.join(root, 'project.yml')
    if File.exist?(yml_path)
      yml = File.read(yml_path)
      updated_yml = yml.gsub(/MARKETING_VERSION:\s*['"]?(\d+(?:\.\d+){1,2})['"]?/, "MARKETING_VERSION: '#{version}'")
      File.write(yml_path, updated_yml) if updated_yml != yml
    end
  end

  def self.run(argv = ARGV)
    if argv[0] == '--write-version'
      target = argv.fetch(1)
      write_repo_version(target)
      puts "Updated repository MARKETING_VERSION to #{target}"
      return
    end

    pbx_versions, yml_versions = read_repo_versions
    source_version = (pbx_versions + yml_versions).map { |v| parts(v) }.max.join('.')
    files_consistent = (pbx_versions == [source_version] && yml_versions == [source_version])

    commit_count = `git rev-list --count HEAD 2>/dev/null`.strip.to_i
    build_floor = (commit_count.positive? ? commit_count : 1) + 1000
    platforms = ENV.fetch('ASC_PLATFORMS', PLATFORMS.join(',')).split(',').map(&:strip)

    key_id = ENV['ASC_KEY_ID'].to_s
    issuer_id = ENV['ASC_ISSUER_ID'].to_s
    key_path = ENV['ASC_KEY_PATH'].to_s
    app_id = ENV.fetch('APP_ID', '6814706725')

    selected = source_version
    build_number = build_floor

    if !key_id.empty? && !issuer_id.empty? && !key_path.empty? && File.file?(key_path) && File.size?(key_path)
      client = Client.new(key_id: key_id, issuer_id: issuer_id, key_path: key_path)
      versions = client.get_all("/apps/#{app_id}/appStoreVersions").map { |v| v.fetch('attributes') }
      trains = client.get_all("/apps/#{app_id}/preReleaseVersions")
                     .map { |t| t.fetch('attributes') }
                     .select { |t| platforms.include?(t['platform']) }
                     .map { |t| t.fetch('version') }
      builds = client.get_all('/builds', 'filter[app]' => app_id).map { |b| b.fetch('attributes') }
      selected = choose(source_version, versions, trains, platforms)
      build_number = next_build_number(builds, build_floor)
    end

    bumped = (selected != source_version) || !files_consistent
    puts "Monkeytail version: repo=#{source_version} -> selected=#{selected} (build #{build_number}, bumped=#{bumped})"

    if ENV['GITHUB_OUTPUT'] && !ENV['GITHUB_OUTPUT'].empty?
      File.open(ENV['GITHUB_OUTPUT'], 'a') do |f|
        f.puts("marketing_version=#{selected}")
        f.puts("build_number=#{build_number}")
        f.puts("bumped=#{bumped}")
      end
    end
    if ENV['GITHUB_ENV'] && !ENV['GITHUB_ENV'].empty?
      File.open(ENV['GITHUB_ENV'], 'a') do |f|
        f.puts("SELECTED_MARKETING_VERSION=#{selected}")
        f.puts("BUILD_NUMBER=#{build_number}")
      end
    end
  end
end

SelectOpenVersion.run if $PROGRAM_NAME == __FILE__
