import ABSClient
import AppFeatures
import SwiftUI
import UIKit

/// Signed in: Listen Now, Library and Search, with the mini-player pill above the tab bar.
struct MainTabsView: View {
    enum AppTab: Hashable {
        case listen
        case library
        case search
    }

    let signIn: SignInModel
    private let client: ABSClient
    @State private var library: LibraryModel
    @State private var player: PlayerController
    @State private var covers: CoverStore
    @State private var selection: AppTab = .library

    init(client: ABSClient, signIn: SignInModel) {
        self.signIn = signIn
        self.client = client
        _library = State(initialValue: LibraryModel(client: client, onSessionExpired: { await signIn.sessionExpired() }))
        _player = State(initialValue: PlayerController(client: client))
        _covers = State(initialValue: CoverStore(client: client))
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Listen Now", systemImage: "headphones", value: AppTab.listen) {
                NowPlayingView(player: player, covers: covers)
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryView(library: library, covers: covers, signIn: signIn, player: player, client: client, play: start)
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView(library: library, covers: covers, client: client, play: start)
            }
        }
        // Set here, not per screen: the tab bar takes its colours from the TabView.
        .preferredColorScheme(selection == .listen ? .dark : .light)
        .tint(selection == .listen ? .white : Theme.plum)
        .miniPlayer(visible: selection != .listen && player.loadState == .ready) {
            MiniPlayerView(player: player, covers: covers) { selection = .listen }
        }
        .task { await library.load() }
        .onChange(of: player.isPlaying) { _, _ in
            Task { await library.refreshProgress() }
        }
    }

    private func start(_ book: ABSBookSummary) {
        selection = .listen
        Task { await player.start(book, deviceID: Self.deviceID) }
    }

    private static var deviceID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "earmark-iphone"
    }
}

private extension View {
    /// `tabViewBottomAccessory(isEnabled:)` needs iOS 26.1; on 26.0 there is simply no pill.
    @ViewBuilder
    func miniPlayer<Accessory: View>(visible: Bool, @ViewBuilder _ accessory: () -> Accessory) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: visible, content: accessory)
        } else {
            self
        }
    }
}
