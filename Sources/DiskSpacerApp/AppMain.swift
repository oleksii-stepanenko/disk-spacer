import SwiftUI

@main
struct DiskSpacerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
