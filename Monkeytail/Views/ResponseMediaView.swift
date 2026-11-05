import SwiftUI
import AVKit
import Combine
import WebKit
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

/// Renders HTML like Postman's Preview, without scripts, navigation, or remote loads.
struct HTMLPreviewView {
    let html: String
    static let policy = #"<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline' data:; img-src data:; font-src data:">"#
    func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = coordinator
        view.setAccessibilityIdentifier("Response HTML preview")
        return view
    }
    func load(_ view: WKWebView, _ coordinator: Coordinator) {
        guard coordinator.loaded != html else { return }
        coordinator.loaded = html
        view.loadHTMLString(Self.policy + html, baseURL: nil)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.navigationType == .other && action.targetFrame?.isMainFrame == true && action.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
        }
    }
}
#if os(iOS) || os(visionOS)
extension HTMLPreviewView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { let view = makeWebView(context.coordinator); load(view, context.coordinator); return view }
    func updateUIView(_ view: WKWebView, context: Context) { load(view, context.coordinator) }
}
private extension WKWebView { func setAccessibilityIdentifier(_ value: String) { accessibilityIdentifier = value } }
#else
extension HTMLPreviewView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { let view = makeWebView(context.coordinator); load(view, context.coordinator); return view }
    func updateNSView(_ view: WKWebView, context: Context) { load(view, context.coordinator) }
}
#endif

struct ResponseBytesView: View {
    let bytes: [UInt8]
    let totalCount: Int
    let binary: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = binary ? 4 : geometry.size.width >= 600 ? 16 : 8
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if bytes.isEmpty { Text("Empty response body").foregroundStyle(.secondary) }
                    ForEach(0..<(bytes.count + width - 1) / width, id: \.self) { row in
                        let start = row * width
                        Text(ByteFormatter.row(bytes[start..<min(start + width, bytes.count)], offset: start, width: width, binary: binary))
                            .font(.system(.caption, design: .monospaced)).lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false).textSelection(.enabled)
                    }
                    if totalCount > bytes.count {
                        Text("Preview limited to 1 MB. Save for the full body.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(12).frame(minWidth: geometry.size.width, alignment: .topLeading)
            }.defaultScrollAnchor(.topLeading).accessibilityIdentifier("Response bytes")
        }.background(Palette.surface.opacity(0.5))
    }
}

/// Zoom without decoding the original image again on the main thread.
#if os(iOS) || os(visionOS)
struct ResponseImageView: UIViewRepresentable {
    let image: CGImage
    func makeUIView(context: Context) -> ImageScrollView { ImageScrollView(image: image) }
    func updateUIView(_ view: ImageScrollView, context: Context) {}

    final class ImageScrollView: UIScrollView, UIScrollViewDelegate {
        private let imageView: UIImageView
        private var previousSize = CGSize.zero
        init(image: CGImage) {
            imageView = UIImageView(image: UIImage(cgImage: image))
            super.init(frame: .zero)
            delegate = self
            addSubview(imageView)
            accessibilityIdentifier = "Response image"
            imageView.isAccessibilityElement = true
            imageView.accessibilityLabel = String(localized: "Response image preview")
            backgroundColor = .secondarySystemBackground
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size != previousSize, bounds.width > 0, bounds.height > 0 else { return }
            previousSize = bounds.size
            let fit = min(bounds.width / imageView.bounds.width, bounds.height / imageView.bounds.height)
            minimumZoomScale = min(fit, 1)
            maximumZoomScale = max(fit, 1) * 8
            zoomScale = minimumZoomScale
            centerImage()
        }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
        private func centerImage() {
            contentInset = UIEdgeInsets(top: max(0, (bounds.height - imageView.frame.height) / 2), left: max(0, (bounds.width - imageView.frame.width) / 2), bottom: 0, right: 0)
        }
    }
}

#else
struct ResponseImageView: NSViewRepresentable {
    let image: CGImage
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = true
        scroll.allowsMagnification = true; scroll.minMagnification = 0.1; scroll.maxMagnification = 8
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: image.width, height: image.height))
        view.image = NSImage(cgImage: image, size: view.frame.size); view.imageScaling = .scaleNone
        view.setAccessibilityLabel(String(localized: "Response image preview")); scroll.documentView = view; return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {}
}
#endif

struct ResponseMediaView: View {
    let url: URL?
    let error: String?
    let audio: Bool
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var duration = 0.0
    @Environment(\.scenePhase) private var scenePhase

    static func asset(for url: URL) -> AVURLAsset {
        // Preview only downloaded bytes; never fetch referenced playlists or resources.
        AVURLAsset(url: url, options: [AVURLAssetReferenceRestrictionsKey: NSNumber(value: AVAssetReferenceRestrictions.forbidAll.rawValue)])
    }

    var body: some View {
        VStack(spacing: 12) {
            if failed || error != nil {
                Image(systemName: "exclamationmark.circle").font(.title)
                Text(error ?? String(localized: "Unsupported media. Use Hex or save the response.")).font(.callout)
                    .accessibilityIdentifier("Media preview error")
            } else if let player {
                if audio {
                    AudioResponseControls(player: player, duration: duration).accessibilityIdentifier("Response media player")
                } else {
                    VideoPlayer(player: player).accessibilityIdentifier("Response media player")
                }
            } else { ProgressView() }
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: url) {
                player?.pause(); player = nil; failed = false
                guard let url else { failed = true; return }
                let asset = Self.asset(for: url)
                do {
                    let (playable, length) = try await asset.load(.isPlayable, .duration)
                    guard playable, !Task.isCancelled else { failed = true; return }
                    duration = length.seconds.isFinite ? max(length.seconds, 0) : 0
                    player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                } catch { failed = true }
            }
            .onDisappear { player?.pause() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { player?.pause() } }
    }
}

private struct AudioResponseControls: View {
    let player: AVPlayer
    let duration: Double
    @State private var playing = false
    @State private var position = 0.0
    @State private var scrubbing = false
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    if playing { player.pause() }
                    else {
                        if position >= duration { player.seek(to: .zero) }
                        player.play()
                    }
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill").font(.title2).frame(width: 44, height: 44)
                }.accessibilityLabel(playing ? "Pause audio" : "Play audio")
                Slider(value: $position, in: 0...max(duration, 0.01)) { editing in
                    scrubbing = editing
                    if !editing { player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
                }.accessibilityLabel("Audio position")
            }
            HStack { Text(time(position)); Spacer(); Text(time(duration)) }
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .onReceive(player.publisher(for: \.timeControlStatus)) { playing = $0 == .playing }
            .onReceive(timer) { _ in
                if !scrubbing {
                    let seconds = player.currentTime().seconds
                    position = seconds.isFinite ? min(max(seconds, 0), duration) : 0
                }
            }
    }
    private func time(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}
