import AppKit
import Foundation

enum WallpaperKind: String, Codable {
    case web, video

    var label: String { self == .web ? "Live scene" : "Video" }
    var symbol: String { self == .web ? "sparkles" : "film" }
}

enum ScenePalette: String, Codable, CaseIterable {
    case aurora, ember, tide, imported
}

struct Wallpaper: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var detail: String
    var kind: WallpaperKind
    var source: String
    var builtIn: Bool
    var palette: ScenePalette

    var fileURL: URL { URL(fileURLWithPath: source) }

    static func bundled(in root: URL) -> [Wallpaper] {
        [
            Wallpaper(id: UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!, title: "Aurora", detail: "A little wonder, after dark.", kind: .web, source: root.appendingPathComponent("Aurora/index.html").path, builtIn: true, palette: .aurora),
            Wallpaper(id: UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!, title: "Ember", detail: "The quiet warmth of a distant sun.", kind: .web, source: root.appendingPathComponent("Ember/index.html").path, builtIn: true, palette: .ember),
            Wallpaper(id: UUID(uuidString: "A0000000-0000-4000-8000-000000000003")!, title: "Tide", detail: "Find your own wavelength.", kind: .web, source: root.appendingPathComponent("Tide/index.html").path, builtIn: true, palette: .tide)
        ]
    }
}

struct LibrarySettings: Codable {
    var imported: [Wallpaper] = []
    var assignments: [String: UUID] = [:]
    var favorites: Set<UUID> = []
    var muted = true
    var pauseOnLowPower = true

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

enum WallpaperImport {
    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov"]

    static func entryPoint(for url: URL, fileManager: FileManager = .default) throws -> (kind: WallpaperKind, entry: URL, directory: URL?) {
        var directory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &directory) else {
            throw ImportError.missing
        }
        if directory.boolValue {
            let entry = url.appendingPathComponent("index.html")
            var entryIsDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &entryIsDirectory), !entryIsDirectory.boolValue else { throw ImportError.noIndex }
            return (.web, entry, url)
        }
        if ["html", "htm"].contains(url.pathExtension.lowercased()) {
            return (.web, url, url.deletingLastPathComponent())
        }
        guard videoExtensions.contains(url.pathExtension.lowercased()) else { throw ImportError.unsupported }
        return (.video, url, nil)
    }

    enum ImportError: LocalizedError {
        case missing, noIndex, unsupported
        var errorDescription: String? {
            switch self {
            case .missing: return "This file is no longer available. Import it again from its current location."
            case .noIndex: return "Choose a web wallpaper folder with an index.html file at its top level."
            case .unsupported: return "Choose an MP4, MOV, M4V, or a web wallpaper folder containing index.html."
            }
        }
    }
}

struct DisplayInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let dimensions: String
}
