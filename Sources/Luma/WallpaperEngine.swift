import AppKit
import AVFoundation
import CoreGraphics
import WebKit

/// Owns one independent renderer per display. App settings decide when playback pauses.
@MainActor
final class WallpaperEngine {
    private var sessions: [String: WallpaperSession] = [:]
    private var assignments: [String: Wallpaper] = [:]
    private var paused = false
    private var muted = true
    private let onError: (String) -> Void

    init(onError: @escaping (String) -> Void) {
        self.onError = onError
    }

    @discardableResult
    func apply(_ wallpaper: Wallpaper, to screen: NSScreen) -> Bool {
        let id = Self.screenID(screen)
        guard FileManager.default.isReadableFile(atPath: wallpaper.fileURL.path) else {
            onError("The wallpaper file is missing or unreadable: \(wallpaper.title). Import it again to restore it.")
            return false
        }
        assignments[id] = wallpaper
        sessions.removeValue(forKey: id)?.stop()
        let session = WallpaperSession(wallpaper: wallpaper, screen: screen, paused: paused, muted: muted, onError: onError)
        sessions[id] = session
        session.start()
        return true
    }

    func remove(from screenID: String) {
        assignments.removeValue(forKey: screenID)
        sessions.removeValue(forKey: screenID)?.stop()
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        for session in sessions.values { session.setPaused(paused) }
    }

    func setMuted(_ muted: Bool) {
        self.muted = muted
        for session in sessions.values { session.setMuted(muted) }
    }

    func syncScreens() {
        let screens = Dictionary(NSScreen.screens.map { (Self.screenID($0), $0) }, uniquingKeysWith: { first, _ in first })
        for id in Array(sessions.keys) where screens[id] == nil {
            sessions.removeValue(forKey: id)?.stop()
        }
        for (id, wallpaper) in Array(assignments) {
            guard let screen = screens[id] else { continue }
            if let session = sessions[id] {
                session.move(to: screen)
            } else {
                apply(wallpaper, to: screen)
            }
        }
    }

    func stopAll() {
        for session in sessions.values { session.stop() }
        sessions.removeAll()
        assignments.removeAll()
    }

    static func screenID(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let displayID = CGDirectDisplayID(number.uint32Value)
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                return CFUUIDCreateString(nil, uuid) as String
            }
            return "display-\(number.uint32Value)"
        }
        return "display-\(screen.localizedName)-\(screen.frame.origin.x)-\(screen.frame.origin.y)"
    }
}

@MainActor
private final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class VideoSurface: NSView {
    let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

@MainActor
private final class WallpaperSession: NSObject, WKNavigationDelegate {
    private let wallpaper: Wallpaper
    private let window: DesktopWindow
    private let onError: (String) -> Void
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerObservation: NSKeyValueObservation?
    private var looperObservation: NSKeyValueObservation?
    private var itemObservations: [NSKeyValueObservation] = []
    private var webView: WKWebView?
    private var paused: Bool
    private var muted: Bool
    private var stopped = false
    private var reportedError = false
    private var nativeMediaSuspended = false
    private var mediaResumeInFlight = false

    init(wallpaper: Wallpaper, screen: NSScreen, paused: Bool, muted: Bool, onError: @escaping (String) -> Void) {
        self.wallpaper = wallpaper
        self.paused = paused
        self.muted = muted
        self.onError = onError
        window = DesktopWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        super.init()
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isMovable = false
        window.setFrame(screen.frame, display: false)
    }

    func start() {
        switch wallpaper.kind {
        case .video: startVideo()
        case .web: startWeb()
        }
        window.orderFrontRegardless()
    }

    func move(to screen: NSScreen) {
        window.setFrame(screen.frame, display: true)
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        if paused { player?.pause() } else { player?.play() }
        updateWebPlayback()
    }

    func setMuted(_ muted: Bool) {
        self.muted = muted
        player?.isMuted = muted
        updateWebPlayback()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        playerObservation?.invalidate()
        looperObservation?.invalidate()
        itemObservations.forEach { $0.invalidate() }
        itemObservations.removeAll()
        playerObservation = nil
        looperObservation = nil
        player?.pause()
        looper?.disableLooping()
        player?.removeAllItems()
        looper = nil
        player = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllUserScripts()
        if !nativeMediaSuspended { webView?.setAllMediaPlaybackSuspended(true, completionHandler: nil) }
        webView?.loadHTMLString("", baseURL: nil)
        webView?.removeFromSuperview()
        webView = nil
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }

    private func startVideo() {
        let item = AVPlayerItem(url: wallpaper.fileURL)
        let queue = AVQueuePlayer()
        queue.isMuted = muted
        queue.automaticallyWaitsToMinimizeStalling = false
        player = queue
        let looping = AVPlayerLooper(player: queue, templateItem: item)
        looper = looping
        window.contentView = VideoSurface(player: queue)

        playerObservation = queue.observe(\.status, options: [.initial, .new]) { [weak self] queue, _ in
            guard queue.status == .failed else { return }
            let detail = queue.error?.localizedDescription ?? "The video could not be decoded."
            Task { @MainActor [weak self] in self?.fail(detail) }
        }
        looperObservation = looping.observe(\.status, options: [.initial, .new]) { [weak self] looper, _ in
            guard looper.status == .failed else { return }
            let detail = looper.error?.localizedDescription ?? "The video could not be looped."
            Task { @MainActor [weak self] in self?.fail(detail) }
        }
        itemObservations = looping.loopingPlayerItems.map { item in
            item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                let detail = item.error?.localizedDescription ?? "The video format could not be decoded."
                Task { @MainActor [weak self] in self?.fail(detail) }
            }
        }
        if !paused { queue.play() }
    }

    private func startWeb() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // No native message bridge is exposed to wallpaper JavaScript.
        configuration.userContentController.addUserScript(WKUserScript(source: WebPlayback.bootstrap + "\n" + WebPlayback.updateScript(paused: paused, muted: muted), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.allowsBackForwardNavigationGestures = false
        view.allowsMagnification = false
        view.allowsLinkPreview = false
        view.underPageBackgroundColor = .black
        webView = view
        window.contentView = view
        view.loadFileURL(wallpaper.fileURL, allowingReadAccessTo: wallpaper.fileURL.deletingLastPathComponent())
        updateWebPlayback()
    }

    private func updateWebPlayback() {
        guard let view = webView, !stopped, !mediaResumeInFlight else { return }
        // Keep the web surface visible so pause preserves the last rendered frame.
        // Native playback must resume before JS retries playing individual media.
        if !paused && nativeMediaSuspended {
            nativeMediaSuspended = false
            mediaResumeInFlight = true
            view.setAllMediaPlaybackSuspended(false) { [weak self] in
                guard let self, !self.stopped else { return }
                self.mediaResumeInFlight = false
                self.updateWebPlayback()
            }
            return
        }
        // Suspend native media after JS records which elements need resuming.
        view.evaluateJavaScript(WebPlayback.updateScript(paused: paused, muted: muted)) { [weak self, weak view] _, _ in
            guard let self, let view, !self.stopped else { return }
            if self.paused && !self.nativeMediaSuspended {
                self.nativeMediaSuspended = true
                view.setAllMediaPlaybackSuspended(true, completionHandler: nil)
            }
        }
    }

    private func fail(_ detail: String) {
        guard !stopped, !reportedError else { return }
        reportedError = true
        onError("\(wallpaper.title): \(detail)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateWebPlayback()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { fail(error.localizedDescription) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { fail(error.localizedDescription) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("The web renderer stopped. Apply the wallpaper again to reload it.")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if !url.isFileURL { decisionHandler(.cancel); return }
        let root = wallpaper.fileURL.deletingLastPathComponent().resolvingSymlinksInPath().path + "/"
        let target = url.resolvingSymlinksInPath().path
        decisionHandler(target.hasPrefix(root) ? .allow : .cancel)
    }
}
