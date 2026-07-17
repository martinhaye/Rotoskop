//
//  RotoskopApp.swift
//  Rotoskop (iOS app shell)
//
//  Entry point. Real navigation (repo list → file browser → editor → debugger)
//  will be built out as each component lands; for now this boots a demo that
//  proves the app links against the core package.
//

import SwiftUI

@main
struct RotoskopApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
