import Foundation
import Testing
@testable import Luma

@Suite("Wallpaper imports and library persistence")
struct WallpaperTests {
    @Test("Video imports accept supported extensions regardless of case")
    func videoExtensions() throws {
        try withTemporaryDirectory { directory in
            for name in ["Wallpaper.MP4", "Wallpaper.m4v", "Wallpaper.MoV"] {
                let video = try makeFile(name, in: directory)
                let result = try WallpaperImport.entryPoint(for: video)
                #expect(result.kind == .video)
                #expect(result.entry == video)
                #expect(result.directory == nil)
            }
        }
    }

    @Test("Unsupported and missing files have distinct errors")
    func unsupportedAndMissingFiles() throws {
        try withTemporaryDirectory { directory in
            let unsupported = try makeFile("Wallpaper.exe", in: directory)
            expectImportError(.unsupported, from: unsupported)
            expectImportError(.missing, from: directory.appendingPathComponent("missing.mp4"))
        }
    }

    @Test("Web folders require a top-level index and preserve the asset root")
    func webFolderEntryPoint() throws {
        try withTemporaryDirectory { directory in
            let folder = directory.appendingPathComponent("Scene", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            expectImportError(.noIndex, from: folder)
            let entry = folder.appendingPathComponent("index.html")
            try Data("<!doctype html><title>Scene</title>".utf8).write(to: entry)
            let result = try WallpaperImport.entryPoint(for: folder)
            #expect(result.kind == .web)
            #expect(result.entry == entry)
            #expect(result.directory == folder)
        }
    }

    @Test("Standalone HTML keeps its parent directory for relative assets")
    func standaloneHTMLAssetRoot() throws {
        try withTemporaryDirectory { directory in
            for name in ["custom.HTML", "custom.htm"] {
                let html = try makeFile(name, in: directory)
                let result = try WallpaperImport.entryPoint(for: html)
                #expect(result.kind == .web)
                #expect(result.entry == html)
                #expect(result.directory == directory)
            }
        }
    }

    @Test("A directory named index.html is not a web entry point")
    func indexMustBeFile() throws {
        try withTemporaryDirectory { directory in
            let folder = directory.appendingPathComponent("InvalidScene", isDirectory: true)
            let fakeEntry = folder.appendingPathComponent("index.html", isDirectory: true)
            try FileManager.default.createDirectory(at: fakeEntry, withIntermediateDirectories: true)
            expectImportError(.noIndex, from: folder)
        }
    }

    @Test("Settings preserve wallpapers, Unicode paths, favorites and display assignments")
    func settingsRoundTrip() throws {
        try withTemporaryDirectory { directory in
            let wallpaper = Wallpaper(
                id: UUID(), title: "夜の空", detail: "Stars above the mountains", kind: .web,
                source: directory.appendingPathComponent("夜の空/index.html").path,
                builtIn: false, palette: .imported
            )
            let settings = LibrarySettings(
                imported: [wallpaper], assignments: ["display-1": wallpaper.id, "display-2": wallpaper.id],
                favorites: [wallpaper.id], muted: false, pauseOnLowPower: false
            )
            let decoded = try JSONDecoder().decode(LibrarySettings.self, from: settings.encoded())
            #expect(decoded.imported == [wallpaper])
            #expect(decoded.assignments == settings.assignments)
            #expect(decoded.favorites == settings.favorites)
            #expect(!decoded.muted)
            #expect(!decoded.pauseOnLowPower)
            let imported = try #require(decoded.imported.first)
            #expect(imported.fileURL.path == wallpaper.source)
        }
    }

    @Test("Bundled wallpaper identifiers remain stable across install paths")
    func bundledIdentifiers() {
        let first = Wallpaper.bundled(in: URL(fileURLWithPath: "/Applications/Luma.app/Scenes"))
        let second = Wallpaper.bundled(in: URL(fileURLWithPath: "/tmp/Luma.app/Scenes"))
        #expect(first.map(\.id) == second.map(\.id))
        #expect(Set(first.map(\.id)).count == first.count)
        #expect(first.allSatisfy { $0.builtIn && $0.kind == .web })
        #expect(first.first?.source != second.first?.source)
    }
}

private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LumaTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

private func makeFile(_ name: String, in directory: URL) throws -> URL {
    let file = directory.appendingPathComponent(name)
    try Data().write(to: file)
    return file
}

private func expectImportError(_ expected: WallpaperImport.ImportError, from url: URL) {
    do {
        _ = try WallpaperImport.entryPoint(for: url)
        Issue.record("Expected import error \(expected) for \(url.lastPathComponent)")
    } catch {
        guard let actual = error as? WallpaperImport.ImportError else {
            Issue.record("Unexpected error type: \(error)")
            return
        }
        switch (actual, expected) {
        case (.missing, .missing), (.unsupported, .unsupported), (.noIndex, .noIndex): break
        default: Issue.record("Expected \(expected), received \(actual)")
        }
    }
}
