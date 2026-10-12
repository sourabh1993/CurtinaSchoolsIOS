import SwiftUI

@main
struct CurtinaSchoolsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = SchoolStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: SchoolStore

    var body: some View {
        if let school = store.selected {
            PortalView(school: school)
                .id(school.appId)
        } else {
            SchoolPickerView()
        }
    }
}
