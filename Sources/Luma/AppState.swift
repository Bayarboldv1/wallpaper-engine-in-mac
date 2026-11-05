import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var wallpapers: [Wallpaper] = []
    @Published var selectedID: UUID?
    @Published var selectedScreenID = ""
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var assignments: [String: UUID] = [:]
    @Published private(set) var favorites: Set<UUID> = []
    @Published private(set) var manuallyPaused = false
    @Published private(set) var systemPaused = false
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var muted = true { didSet { engine.setMuted(muted); persist() } }
    @Published var pauseOnLowPower = true { didSet { updatePlayback(); persist() } }
    @Published var errorMessage: String?
    @Published var isImporting = false
    @Published var previewVisible = true
    @Published var applicationActive = true

    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private let supportURL: URL
    private let settingsURL: URL
    private var restored = false
    private var pauseReasons: Set<String> = []
    private lazy var engine = WallpaperEngine { [weak self] message in self?.errorMessage = message }

    var selected: Wallpaper? { wallpapers.first { $0.id == selectedID } }
    var isPaused: Bool { manuallyPaused || systemPaused || (pauseOnLowPower && lowPowerMode) }
    var activeCount: Int { displays.filter { assignments[$0.id] != nil }.count }
    var status: String {
        if systemPaused { return "Paused while your Mac is away" }
        if manuallyPaused { return "Playback paused" }
        if pauseOnLowPower && lowPowerMode { return "Paused for Low Power Mode" }
        return activeCount == 0 ? "Ready when you are" : "Playing on \(activeCount) display\(activeCount == 1 ? "" : "s")"
    }

    init(supportURL: URL? = nil) {
        self.supportURL = supportURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Luma", isDirectory: true)
        settingsURL = self.supportURL.appendingPathComponent("library.json")
        // SwiftPM's generated accessor expects resources beside the executable;
        // packaged macOS apps keep them in Contents/Resources instead.
        let resourceBundle = Bundle.main.url(forResource: "Luma_Luma", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? Bundle.module
        let sceneRoot = resourceBundle.url(forResource: "Scenes", withExtension: nil)!
        wallpapers = Wallpaper.bundled(in: sceneRoot)
        if let data = try? Data(contentsOf: settingsURL) {
            do {
                let saved = try JSONDecoder().decode(LibrarySettings.self, from: data)
                wallpapers += saved.imported
                assignments = saved.assignments
                favorites = saved.favorites
                muted = saved.muted
                pauseOnLowPower = saved.pauseOnLowPower
            } catch {
                errorMessage = "Luma couldn't read the saved library. Your wallpaper files are still in Application Support/Luma. \(error.localizedDescription)"
            }
        }
        selectedID = wallpapers.first?.id
        refreshDisplays()
        observeSystem()
    }

    func restorePlayback() {
        guard !restored else { return }
        restored = true
        for screen in NSScreen.screens {
            if let id = assignments[WallpaperEngine.screenID(screen)], let wallpaper = wallpapers.first(where: { $0.id == id }) {
                engine.apply(wallpaper, to: screen)
            }
        }
        engine.setMuted(muted)
        updatePlayback()
    }

    func applySelected(allDisplays: Bool = false) {
        guard let wallpaper = selected else { return }
        let screens = NSScreen.screens.filter { allDisplays || WallpaperEngine.screenID($0) == selectedScreenID }
        for screen in screens {
            if engine.apply(wallpaper, to: screen) {
                assignments[WallpaperEngine.screenID(screen)] = wallpaper.id
            }
        }
        engine.setMuted(muted)
        updatePlayback()
        persist()
    }

    func clearDisplay() {
        engine.remove(from: selectedScreenID)
        assignments.removeValue(forKey: selectedScreenID)
        persist()
    }

    func clearAll() {
        engine.stopAll()
        assignments.removeAll()
        persist()
    }

    func togglePaused() {
        manuallyPaused.toggle()
        updatePlayback()
    }

    func toggleFavorite(_ wallpaper: Wallpaper) {
        if favorites.contains(wallpaper.id) { favorites.remove(wallpaper.id) }
        else { favorites.insert(wallpaper.id) }
        persist()
    }

    func remove(_ wallpaper: Wallpaper) {
        guard !wallpaper.builtIn else { return }
        let affected = assignments.filter { $0.value == wallpaper.id }.map(\.key)
        for id in affected { engine.remove(from: id); assignments.removeValue(forKey: id) }
        wallpapers.removeAll { $0.id == wallpaper.id }
        favorites.remove(wallpaper.id)
        if selectedID == wallpaper.id { selectedID = wallpapers.first?.id }
        // Imported videos are owned copies; web folders remain at the selected location.
        let ownedDirectory = supportURL.appendingPathComponent("Wallpapers/\(wallpaper.id.uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: ownedDirectory.path) {
            do { try FileManager.default.removeItem(at: ownedDirectory) }
            catch { errorMessage = "Removed from the library, but couldn't delete its media copy: \(error.localizedDescription)" }
        }
        persist()
    }

    func importWallpaper() {
        let panel = NSOpenPanel()
        panel.title = "Add a wallpaper"
        panel.message = "Choose a video or a web folder with index.html. Web folders stay at their original location."
        panel.prompt = "Add to Library"
        panel.allowedContentTypes = [.movie, .html, .folder]
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        isImporting = true
        Task {
            defer { isImporting = false }
            for url in urls {
                do {
                    let source = try WallpaperImport.entryPoint(for: url)
                    let id = UUID()
                    var fileURL = source.entry
                    if source.kind == .video {
                        guard try await AVURLAsset(url: url).load(.isPlayable) else {
                            throw NSError(domain: "Luma", code: 1, userInfo: [NSLocalizedDescriptionKey: "macOS cannot play this video. Try an H.264 or HEVC MP4 file."])
                        }
                        let destination = supportURL.appendingPathComponent("Wallpapers/\(id.uuidString)", isDirectory: true)
                        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                        fileURL = destination.appendingPathComponent(url.lastPathComponent)
                        let target = fileURL
                        // Copy large videos away from the main thread so the library stays responsive.
                        try await Task.detached { try FileManager.default.copyItem(at: url, to: target) }.value
                    }
                    let name = source.directory == url ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
                    let wallpaper = Wallpaper(id: id, title: name, detail: source.kind == .web ? "Your own corner of the web." : "A moment, on repeat.", kind: source.kind, source: fileURL.path, builtIn: false, palette: .imported)
                    wallpapers.append(wallpaper)
                    selectedID = id
                    persist()
                } catch { errorMessage = "Couldn't add \(url.lastPathComponent). \(error.localizedDescription)" }
            }
        }
    }

    func shutdown() { engine.stopAll() }

    private func persist() {
        let settings = LibrarySettings(imported: wallpapers.filter { !$0.builtIn }, assignments: assignments, favorites: favorites, muted: muted, pauseOnLowPower: pauseOnLowPower)
        do {
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            try settings.encoded().write(to: settingsURL, options: .atomic)
        } catch { errorMessage = "Couldn't save your library: \(error.localizedDescription)" }
    }

    private func updatePlayback() {
        // Publishing this update also refreshes computed playback status in the menu bar.
        objectWillChange.send()
        engine.setPaused(isPaused)
    }

    private func refreshDisplays() {
        displays = NSScreen.screens.map {
            DisplayInfo(id: WallpaperEngine.screenID($0), name: $0.localizedName, dimensions: "\(Int($0.frame.width * $0.backingScaleFactor)) × \(Int($0.frame.height * $0.backingScaleFactor))")
        }
        if !displays.contains(where: { $0.id == selectedScreenID }) { selectedScreenID = displays.first?.id ?? "" }
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshDisplays()
                self.engine.syncScreens()
                if self.restored {
                    for screen in NSScreen.screens {
                        if let id = self.assignments[WallpaperEngine.screenID(screen)], let wallpaper = self.wallpapers.first(where: { $0.id == id }) {
                            self.engine.apply(wallpaper, to: screen)
                        }
                    }
                    self.engine.setMuted(self.muted)
                    self.updatePlayback()
                }
            }
        })
        observers.append(center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                self?.updatePlayback()
            }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, "system"), (NSWorkspace.screensDidSleepNotification, "display"), (NSWorkspace.sessionDidResignActiveNotification, "session")] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.pauseReasons.insert(reason)
                    self?.systemPaused = !(self?.pauseReasons.isEmpty ?? true)
                    self?.updatePlayback()
                }
            })
        }
        for (name, reason) in [(NSWorkspace.didWakeNotification, "system"), (NSWorkspace.screensDidWakeNotification, "display"), (NSWorkspace.sessionDidBecomeActiveNotification, "session")] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.pauseReasons.remove(reason)
                    self?.systemPaused = !(self?.pauseReasons.isEmpty ?? true)
                    self?.updatePlayback()
                }
            })
        }
    }
}
