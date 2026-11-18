#!/usr/bin/env ruby
# frozen_string_literal: true

require 'base64'
require 'json'
require 'net/http'
require 'open3'
require 'openssl'
require 'time'
require 'uri'

# Queries App Store Connect for the given platform and selects the lowest open
# marketing version >= the project's MARKETING_VERSION so closed App Store
# trains never break main-branch archive uploads.
module SelectOpenVersion
  API_BASE = 'https://api.appstoreconnect.apple.com/v1'
  CLOSED_STATES = %w[
    READY_FOR_SALE
    READY_FOR_DISTRIBUTION
    PENDING_APPLE_RELEASE
    PENDING_DEVELOPER_RELEASE
    PROCESSING_FOR_APP_STORE
    REPLACED_WITH_NEW_VERSION
    REMOVED_FROM_SALE
    DEVELOPER_REMOVED_FROM_SALE
  ].freeze

  class Client
    def initialize(key_id:, issuer_id:, key_path:)
      @key_id = key_id
      @issuer_id = issuer_id
      @private_key = OpenSSL::PKey.read(File.binread(key_path))
    end

    def get_all(path, params = {})
      data = []
      current_path = path
      current_params = params.merge('limit' => '200')
      loop do
        uri = URI("#{API_BASE}#{current_path}")
        uri.query = URI.encode_www_form(current_params) unless current_params.empty?
        req = Net::HTTP::Get.new(uri)
        req['Authorization'] = "Bearer #{token}"
        req['Accept'] = 'application/json'
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 60) { |h| h.request(req) }
        raise "ASC GET #{current_path} returned #{res.code}: #{res.body}" unless res.code.to_i.between?(200, 299)

        payload = JSON.parse(res.body)
        data.concat(payload.fetch('data', []))
        next_link = payload.dig('links', 'next')
        break unless next_link

        next_uri = URI(next_link)
        raise "Unexpected pagination host #{next_uri.host}" unless next_uri.host == 'api.appstoreconnect.apple.com'

        current_path = next_uri.path.delete_prefix('/v1')
        current_params = URI.decode_www_form(next_uri.query.to_s).to_h
      end
      data
    end

    private

    def token
      now = Time.now.to_i
      header = { 'alg' => 'ES256', 'kid' => @key_id, 'typ' => 'JWT' }
      claims = { 'iss' => @issuer_id, 'iat' => now, 'exp' => now + 900, 'aud' => 'appstoreconnect-v1' }
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
    raise ArgumentError, "Invalid marketing version #{value.inspect}" unless value.match?(/\A\d+(?:\.\d+){1,2}\z/)

    nums = value.split('.').map(&:to_i)
    nums.fill(0, nums.length...3)
  end

  def self.choose(source, store_versions, trains)
    candidates = [parts(source)] + trains.map { |v| parts(v) }
    store_versions.each do |attrs|
      ver = parts(attrs.fetch('versionString'))
      ver[2] += 1 if CLOSED_STATES.include?(attrs.fetch('appStoreState'))
      candidates << ver
    end
    candidates.max.join('.')
  end

  def self.project_marketing_version(scheme)
    raw, status = Open3.capture2('/usr/bin/plutil', '-convert', 'json', '-o', '-', 'Monkeytail.xcodeproj/project.pbxproj')
    raise 'Could not read Monkeytail.xcodeproj' unless status.success?

    objects = JSON.parse(raw).fetch('objects')
    target = objects.values.find { |o| o['isa'] == 'PBXNativeTarget' && o['name'] == scheme }
    configs = objects.fetch(target.fetch('buildConfigurationList')).fetch('buildConfigurations')
    release = configs.map { |id| objects.fetch(id) }.find { |c| c['name'] == 'Release' }
    release.dig('buildSettings', 'MARKETING_VERSION') || '1.7.1'
  end

  def self.run
    scheme = ENV.fetch('SCHEME')
    platform = ENV.fetch('ASC_PLATFORM')
    source_version = project_marketing_version(scheme)
    key_id = ENV['ASC_KEY_ID'].to_s
    issuer_id = ENV['ASC_ISSUER_ID'].to_s
    key_path = ENV['ASC_KEY_PATH'].to_s
    app_id = ENV.fetch('APP_ID', '6814706725')

    selected = source_version
    if !key_id.empty? && !issuer_id.empty? && !key_path.empty? && File.file?(key_path) && File.size?(key_path)
      client = Client.new(key_id: key_id, issuer_id: issuer_id, key_path: key_path)
      versions = client.get_all("/apps/#{app_id}/appStoreVersions", 'filter[platform]' => platform).map { |v| v.fetch('attributes') }
      trains = client.get_all("/apps/#{app_id}/preReleaseVersions")
                     .map { |t| t.fetch('attributes') }
                     .select { |t| t['platform'] == platform }
                     .map { |t| t.fetch('version') }
      selected = choose(source_version, versions, trains)
    end

    puts "#{platform} (#{scheme}): source=#{source_version} -> selected=#{selected}"
    if ENV['GITHUB_ENV'] && !ENV['GITHUB_ENV'].empty?
      File.open(ENV['GITHUB_ENV'], 'a') { |f| f.puts("SELECTED_MARKETING_VERSION=#{selected}") }
    end
  end
end

SelectOpenVersion.run if $PROGRAM_NAME == __FILE__
