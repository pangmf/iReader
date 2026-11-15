//
//  WeReadLikeApp.swift
//  WeReadLike
//

import SwiftUI

@main
struct WeReadLikeApp: App {

    @StateObject private var store = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .tint(WD.accent)
        }
    }
}
