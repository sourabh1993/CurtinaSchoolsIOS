import SwiftUI

struct SchoolPickerView: View {
    @EnvironmentObject private var store: SchoolStore
    @State private var search = ""

    private var filtered: [School] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.schools }
        return store.schools.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.appId.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if store.schools.isEmpty && store.isLoading {
                    ProgressView("Loading schools…")
                } else if store.schools.isEmpty, let message = store.errorMessage {
                    VStack(spacing: 16) {
                        Text(message)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Try Again") { Task { await store.loadSchools() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    List(filtered) { school in
                        Button { store.select(school) } label: { SchoolRow(school: school) }
                            .foregroundColor(.primary)
                    }
                    .listStyle(.plain)
                    .searchable(text: $search, prompt: "School name or code")
                    .refreshable { await store.loadSchools() }
                }
            }
            .navigationTitle("Select Your School")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Link("Privacy Policy", destination: SchoolStore.privacyURL)
                        .font(.footnote)
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            if store.schools.isEmpty { await store.loadSchools() }
        }
    }
}

private struct SchoolRow: View {
    let school: School

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: school.logoUrl.flatMap { URL(string: $0) }) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(String(school.appId.prefix(2)))
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(school.name).font(.body.weight(.semibold))
                Text(school.appId).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
