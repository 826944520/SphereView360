import SwiftUI

@main
struct SphereView360MobileApp: App {
    @StateObject private var store = ViewerStore()

    var body: some Scene {
        WindowGroup {
            MobileContentView(store: store)
                .onOpenURL { url in
                    store.open(url)
                }
        }
    }
}
