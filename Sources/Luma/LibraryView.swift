import AppKit
import SwiftUI

private let canvas = Color(hex: 0x101216)
private let panel = Color(hex: 0x191C22)
private let accent = Color(hex: 0xBDF4CD)

enum LibraryFilter: String, CaseIterable {
    case all = "All wallpapers", favorites = "Favorites", imported = "Imported"
    var symbol: String {
        switch self { case .all: return "square.grid.2x2"; case .favorites: return "heart"; case .imported: return "tray.and.arrow.down" }
    }
}

struct LibraryView: View {
    @ObservedObject var state: AppState
    @State private var filter: LibraryFilter = .all
    @State private var search = ""
    @State private var showSettings = false

    private var visibleWallpapers: [Wallpaper] {
        state.wallpapers.filter {
            (filter != .favorites || state.favorites.contains($0.id)) &&
            (filter != .imported || !$0.builtIn) &&
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.white.opacity(0.055)).frame(width: 1)
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 23) {
                        if let wallpaper = state.selected {
                            hero(wallpaper)
                        }
                        collection
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 28)
                }
                displayBar
            }
        }
        .background(canvas)
        .foregroundStyle(Color.white.opacity(0.92))
        .preferredColorScheme(.dark)
        .frame(minWidth: 980, minHeight: 700)
        .sheet(isPresented: $showSettings) { settings }
        .alert("Something needs your attention", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK") { state.errorMessage = nil }
        } message: { Text(state.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(accent)
                    Image(systemName: "sun.horizon.fill").font(.system(size: 23, weight: .medium)).foregroundStyle(Color(hex: 0x18392C))
                }.frame(width: 40, height: 40)
                Text("luma").font(.system(size: 29, weight: .semibold, design: .rounded)).tracking(-1.5)
            }.padding(.top, 54).padding(.bottom, 44)

            Text("WORKSPACE").font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(.white.opacity(0.3)).padding(.leading, 12).padding(.bottom, 12)
            ForEach(LibraryFilter.allCases, id: \.self) { item in
                Button { filter = item } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.symbol).font(.system(size: 14)).frame(width: 19)
                        Text(item.rawValue).font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 2)
                        if item == .all { Text("\(state.wallpapers.count)").font(.system(size: 10, weight: .medium)).opacity(0.5) }
                    }
                    .foregroundStyle(filter == item ? accent : Color.white.opacity(0.5))
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(filter == item ? accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.bottom, 5)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle().fill(state.activeCount > 0 && !state.isPaused ? accent : Color.white.opacity(0.3)).frame(width: 6, height: 6)
                    Text(state.activeCount > 0 ? (state.isPaused ? "Taking a breath" : "Your desktop is alive") : "Make yourself at home")
                        .font(.system(size: 11, weight: .medium))
                }
                Text(state.activeCount > 0 ? "Luma stays in your menu bar.\nClose this window, keep the calm." : "Choose a scene and bring\na little life to your desktop.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.35)).lineSpacing(4)
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 16)
            Button { showSettings = true } label: {
                Label("Settings", systemImage: "slider.horizontal.3").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(12)
            }.buttonStyle(.plain)
            HStack { Text("LUMA FOR MAC"); Spacer(); Text("0.1") }.font(.system(size: 8, weight: .medium)).tracking(1.4).foregroundStyle(.white.opacity(0.2)).padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 21)
        }
        .padding(.horizontal, 16)
        .frame(width: 200)
        .background(Color(hex: 0x121519))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    Text("Your space, in motion.").font(.system(size: 27, weight: .semibold)).tracking(-0.8)
                    Text("BETA").font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(accent.opacity(0.8)).padding(.horizontal, 6).padding(.vertical, 4).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                Text("A living backdrop for whatever comes next.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Button { state.importWallpaper() } label: {
                HStack(spacing: 7) {
                    if state.isImporting { ProgressView().controlSize(.small) } else { Image(systemName: "plus").fontWeight(.medium) }
                    Text(state.isImporting ? "Importing…" : "Add wallpaper")
                }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 15).frame(height: 35)
            }
            .buttonStyle(.plain).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08)))
            .disabled(state.isImporting)
            .keyboardShortcut("o")
        }
        .padding(.horizontal, 30).padding(.top, 46).padding(.bottom, 25)
    }

    private func hero(_ wallpaper: Wallpaper) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                WallpaperPreview(wallpaper: wallpaper, isPaused: state.isPaused || !state.previewVisible || !state.applicationActive, muted: state.muted)
                    .allowsHitTesting(false)
                LinearGradient(colors: [.clear, .black.opacity(0.08), .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 7) {
                    Text(wallpaper.title).font(.system(size: 30, weight: .medium)).tracking(-0.6)
                    Text(wallpaper.detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }.padding(24)
                VStack {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(state.isPaused ? .white.opacity(0.5) : accent).frame(width: 5, height: 5)
                            Text(state.isPaused ? "PREVIEW PAUSED" : "LIVE PREVIEW").font(.system(size: 8, weight: .semibold)).tracking(1.5)
                        }.padding(.horizontal, 10).padding(.vertical, 8).background(.black.opacity(0.25), in: Capsule())
                        Spacer()
                        Button { state.toggleFavorite(wallpaper) } label: {
                            Image(systemName: state.favorites.contains(wallpaper.id) ? "heart.fill" : "heart")
                                .font(.system(size: 13)).foregroundStyle(state.favorites.contains(wallpaper.id) ? accent : .white)
                                .frame(width: 31, height: 31).background(.black.opacity(0.25), in: Circle())
                        }.buttonStyle(.plain).help("Add or remove favorite")
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        Button { state.togglePaused() } label: {
                            Image(systemName: state.isPaused ? "play.fill" : "pause.fill").font(.system(size: 12)).frame(width: 32, height: 32).background(.white.opacity(0.12), in: Circle())
                        }.buttonStyle(.plain).help(state.isPaused ? "Resume wallpapers" : "Pause wallpapers")
                    }
                }.padding(17)
            }
            .frame(height: 295)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.07)))
        }
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(filter.rawValue).font(.system(size: 14, weight: .semibold))
                Text("\(visibleWallpapers.count)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                Spacer()
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10))
                    TextField("Find your next backdrop", text: $search).font(.system(size: 11)).textFieldStyle(.plain).frame(width: 150)
                }.foregroundStyle(.white.opacity(0.4))
            }
            if visibleWallpapers.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: filter == .favorites ? "heart" : "tray").font(.system(size: 24)).foregroundStyle(accent.opacity(0.6))
                    Text(search.isEmpty ? (filter == .favorites ? "Your favorites will feel at home here." : "Bring your own world.") : "No wallpapers found.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    if filter == .imported && search.isEmpty { Button("Add a video or web wallpaper") { state.importWallpaper() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent) }
                }.frame(maxWidth: .infinity).frame(height: 137).background(panel, in: RoundedRectangle(cornerRadius: 10))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 17) {
                    ForEach(visibleWallpapers) { wallpaper in wallpaperCard(wallpaper) }
                }
            }
        }
    }

    private func wallpaperCard(_ wallpaper: Wallpaper) -> some View {
        Button { state.selectedID = wallpaper.id } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    SceneArtwork(palette: wallpaper.palette).frame(height: 104).clipped()
                    if state.selectedID == wallpaper.id {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: 0x153529)).frame(width: 20, height: 20).background(accent, in: Circle()).padding(9)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(state.selectedID == wallpaper.id ? accent.opacity(0.8) : Color.white.opacity(0.06), lineWidth: state.selectedID == wallpaper.id ? 1.5 : 1))
                HStack {
                    Text(wallpaper.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer()
                    if state.favorites.contains(wallpaper.id) { Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(accent) }
                    Label(wallpaper.kind.label, systemImage: wallpaper.kind.symbol).font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                }
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(state.favorites.contains(wallpaper.id) ? "Remove from Favorites" : "Add to Favorites") { state.toggleFavorite(wallpaper) }
            if !wallpaper.builtIn {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([wallpaper.fileURL]) }
                Button("Remove from Library", role: .destructive) { state.remove(wallpaper) }
            }
        }
        .accessibilityLabel("\(wallpaper.title), \(wallpaper.kind.label)\(state.selectedID == wallpaper.id ? ", selected" : "")")
    }

    private var displayBar: some View {
        HStack(spacing: 15) {
            Image(systemName: "display").font(.system(size: 21, weight: .light)).foregroundStyle(.white.opacity(0.5))
            VStack(alignment: .leading, spacing: 4) {
                Picker("Display", selection: $state.selectedScreenID) {
                    ForEach(state.displays) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 210, alignment: .leading).fixedSize(horizontal: true, vertical: false)
                Text(state.assignments[state.selectedScreenID].flatMap { id in state.wallpapers.first { $0.id == id }?.title }.map { "Current: \($0)" } ?? "Using your macOS wallpaper")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
            }
            Spacer(minLength: 8)
            Button { state.muted.toggle() } label: {
                Image(systemName: state.muted ? "speaker.slash" : "speaker.wave.2").font(.system(size: 14)).frame(width: 29, height: 32)
            }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).help(state.muted ? "Unmute wallpapers" : "Mute wallpapers")
            Menu {
                Button("Apply to All Displays") { state.applySelected(allDisplays: true) }
                Button("Restore macOS Wallpaper on This Display") { state.clearDisplay() }
                Button("Restore macOS Wallpaper on All Displays") { state.clearAll() }
            } label: { Image(systemName: "ellipsis").frame(width: 22, height: 32) }
                .menuStyle(.borderlessButton).fixedSize().help("Display options")
            Button { state.applySelected() } label: {
                HStack(spacing: 9) {
                    Text(state.assignments[state.selectedScreenID] == state.selectedID ? "Applied to display" : "Set wallpaper")
                    Image(systemName: state.assignments[state.selectedScreenID] == state.selectedID ? "checkmark" : "arrow.up.right")
                }.font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0x18392C)).padding(.horizontal, 20).frame(height: 39)
            }.buttonStyle(.plain).background(accent, in: RoundedRectangle(cornerRadius: 8)).disabled(state.selected == nil || state.selectedScreenID.isEmpty)
        }
        .padding(.horizontal, 30).padding(.vertical, 18)
        .background(Color(hex: 0x15181D))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.055)).frame(height: 1) }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack { Text("Make it yours").font(.system(size: 23, weight: .semibold)); Spacer(); Button { showSettings = false } label: { Image(systemName: "xmark").font(.system(size: 11)).frame(width: 25, height: 25) }.buttonStyle(.plain) }
            Text("Little details. A lighter footprint.").font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            Toggle("Mute wallpaper audio", isOn: $state.muted)
            Toggle("Pause in Low Power Mode", isOn: $state.pauseOnLowPower)
            Text("Wallpapers also pause when your displays sleep or your desktop session becomes inactive. Built-in scenes render at up to 30 fps.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Bring your own wallpaper").font(.system(size: 13, weight: .medium))
                Text("Videos: MP4, MOV and M4V supported by macOS.\nWeb: a local HTML file or a folder containing index.html. Keep imported web folders in their original location.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5)
            }
            HStack { Text("Luma 0.1 · Native for Mac").font(.system(size: 10)).foregroundStyle(.tertiary); Spacer(); Button("Done") { showSettings = false }.keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 450).background(canvas).tint(accent)
    }
}

struct SceneArtwork: View {
    let palette: ScenePalette
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let colors: [Color]
            switch palette {
            case .aurora: colors = [Color(hex: 0x061219), Color(hex: 0x173B3C), Color(hex: 0x082226)]
            case .ember: colors = [Color(hex: 0x210C11), Color(hex: 0x793C28), Color(hex: 0x291619)]
            case .tide: colors = [Color(hex: 0x061124), Color(hex: 0x163C66), Color(hex: 0x082237)]
            case .imported: colors = [Color(hex: 0x202337), Color(hex: 0x514760), Color(hex: 0x252637)]
            }
            context.fill(Path(rect), with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            if palette == .ember {
                let center = CGPoint(x: size.width * 0.54, y: size.height * 0.65)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 48, y: center.y - 48, width: 96, height: 96)), with: .radialGradient(Gradient(colors: [Color(hex: 0xFFC080).opacity(0.9), Color(hex: 0xEB7F43).opacity(0.65), .clear]), center: center, startRadius: 0, endRadius: 55))
                context.fill(Path(ellipseIn: CGRect(x: center.x - 27, y: center.y - 27, width: 54, height: 54)), with: .color(Color(hex: 0xFFC991).opacity(0.8)))
            } else {
                for line in 0..<20 {
                    var path = Path()
                    for step in 0...70 {
                        let x = CGFloat(step) / 70 * size.width
                        let base = palette == .aurora ? size.height * 0.35 : size.height * 0.56
                        let y = base + sin(x / size.width * 5 + Double(line) * 0.11) * size.height * 0.23 + CGFloat(line) * 1.4
                        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(path, with: .color((palette == .aurora ? Color(hex: 0x7EE9BA) : Color(hex: 0x6DB9DF)).opacity(0.08 + Double(line % 4) * 0.045)), lineWidth: palette == .aurora ? 3 : 0.8)
                }
            }
            for star in 0..<28 {
                let x = CGFloat((star * 127 + 13) % 997) / 997 * size.width
                let y = CGFloat((star * 73 + 21) % 197) / 197 * size.height * 0.8
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(0.15 + Double(star % 3) * 0.13)))
            }
            if palette == .aurora {
                var mountain = Path()
                mountain.move(to: CGPoint(x: 0, y: size.height))
                for step in 0...18 {
                    mountain.addLine(to: CGPoint(x: CGFloat(step) / 18 * size.width, y: size.height * (0.76 + sin(Double(step) * 2.4) * 0.09)))
                }
                mountain.addLine(to: CGPoint(x: size.width, y: size.height)); mountain.closeSubpath()
                context.fill(mountain, with: .color(Color(hex: 0x061115)))
            }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
