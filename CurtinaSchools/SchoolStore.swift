import Foundation

struct School: Codable, Identifiable, Equatable {
    let appId: String
    let name: String
    let loginUrl: String
    let logoUrl: String?

    var id: String { appId }
}

@MainActor
final class SchoolStore: ObservableObject {
    /// Maintained on the server, so adding a school needs no app update.
    static let listURL = URL(string: "https://curtina.in/_mobile/schools.json")!
    private static let selectedKey = "selectedSchool"

    @Published private(set) var schools: [School] = []
    @Published private(set) var selected: School?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.selectedKey) {
            selected = try? JSONDecoder().decode(School.self, from: data)
        }
    }

    func loadSchools() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let request = URLRequest(url: Self.listURL, cachePolicy: .reloadIgnoringLocalCacheData)
            let (data, _) = try await URLSession.shared.data(for: request)
            schools = try JSONDecoder().decode([School].self, from: data)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = "Could not load the school list. Check your internet connection and try again."
        }
    }

    func select(_ school: School) {
        UserDefaults.standard.set(try? JSONEncoder().encode(school), forKey: Self.selectedKey)
        selected = school
    }

    func clearSelection() {
        UserDefaults.standard.removeObject(forKey: Self.selectedKey)
        selected = nil
    }
}
