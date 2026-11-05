import AppKit
import AVFoundation
import SwiftUI
import WebKit

struct WallpaperPreview: NSViewRepresentable {
    let wallpaper: Wallpaper
    let isPaused: Bool
    let muted: Bool

    func makeNSView(context: Context) -> WallpaperPreviewView {
        WallpaperPreviewView()
    }

    func updateNSView(_ nsView: WallpaperPreviewView, context: Context) {
        nsView.update(wallpaper: wallpaper, paused: isPaused, muted: muted)
    }

    static func dismantleNSView(_ nsView: WallpaperPreviewView, coordinator: ()) {
        nsView.cleanUp()
    }
}

final class WallpaperPreviewView: NSView, WKNavigationDelegate {
    private var wallpaperID: UUID?
    private var webView: WKWebView?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var videoLayer: AVPlayerLayer?
    private var itemObservation: NSKeyValueObservation?
    private var paused = false
    private var muted = true
    private var allowedRoot: URL?
    private var mediaSuspended = false
    private var mediaTransition = 0
    private var resumePending = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer?.frame = bounds
        CATransaction.commit()
    }

    func update(wallpaper: Wallpaper, paused: Bool, muted: Bool) {
        self.paused = paused
        self.muted = muted
        if wallpaperID != wallpaper.id {
            cleanUp()
            wallpaperID = wallpaper.id
            load(wallpaper)
        }
        updatePlayback()
    }

    private func load(_ wallpaper: Wallpaper) {
        let url = wallpaper.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            showError("This wallpaper file is unavailable.")
            return
        }
        switch wallpaper.kind {
        case .video:
            let queue = AVQueuePlayer()
            let item = AVPlayerItem(url: url)
            player = queue
            looper = AVPlayerLooper(player: queue, templateItem: item)
            let video = AVPlayerLayer(player: queue)
            video.videoGravity = .resizeAspectFill
            video.frame = bounds
            layer?.addSublayer(video)
            videoLayer = video
            let observedID = wallpaper.id
            itemObservation = queue.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                DispatchQueue.main.async {
                    guard let self, self.wallpaperID == observedID else { return }
                    self.showError("This video could not be played.")
                }
            }
        case .web:
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.mediaTypesRequiringUserActionForPlayback = []
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.userContentController.addUserScript(
                WKUserScript(source: WebPlayback.bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            )
            let web = WKWebView(frame: bounds, configuration: configuration)
            web.autoresizingMask = [.width, .height]
            web.navigationDelegate = self
            web.underPageBackgroundColor = .black
            addSubview(web)
            webView = web
            let root = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            allowedRoot = root
            web.loadFileURL(url, allowingReadAccessTo: root)
        }
    }

    private func updatePlayback() {
        player?.isMuted = muted
        paused ? player?.pause() : player?.play()
        guard let web = webView else { return }
        if paused {
            web.evaluateJavaScript(WebPlayback.updateScript(paused: true, muted: muted), completionHandler: nil)
            if !mediaSuspended {
                mediaSuspended = true
                mediaTransition += 1
                resumePending = false
                web.setAllMediaPlaybackSuspended(true, completionHandler: nil)
            }
        } else if mediaSuspended {
            mediaSuspended = false
            mediaTransition += 1
            let transition = mediaTransition
            resumePending = true
            web.setAllMediaPlaybackSuspended(false) { [weak self, weak web] in
                guard let self, let web, self.webView === web, self.mediaTransition == transition else { return }
                self.resumePending = false
                guard !self.paused else { return }
                web.evaluateJavaScript(WebPlayback.updateScript(paused: false, muted: self.muted), completionHandler: nil)
            }
        } else if !resumePending {
            web.evaluateJavaScript(WebPlayback.updateScript(paused: false, muted: muted), completionHandler: nil)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame != nil,
              let url = navigationAction.request.url, url.isFileURL,
              let root = allowedRoot else {
            decisionHandler(.cancel)
            return
        }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = root.path
        decisionHandler(path == rootPath || path.hasPrefix(rootPath + "/") ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updatePlayback()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled {
            showError("This web wallpaper could not be loaded.")
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled {
            showError("This web wallpaper could not be loaded.")
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showError("The wallpaper preview stopped. Select it again to reload.")
        wallpaperID = nil
    }

    private func showError(_ message: String) {
        cleanUp()
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40)
        ])
    }

    func cleanUp() {
        itemObservation?.invalidate()
        itemObservation = nil
        player?.pause()
        looper?.disableLooping()
        player?.removeAllItems()
        looper = nil
        player = nil
        videoLayer?.removeFromSuperlayer()
        videoLayer = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.removeFromSuperview()
        webView = nil
        allowedRoot = nil
        mediaSuspended = false
        mediaTransition += 1
        resumePending = false
        subviews.forEach { $0.removeFromSuperview() }
    }

}
