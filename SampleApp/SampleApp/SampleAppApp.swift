import SwiftUI
import SampleAppFeature

@main
struct SampleAppApp: App {
    init() {
        SampleAppConfiguration.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
