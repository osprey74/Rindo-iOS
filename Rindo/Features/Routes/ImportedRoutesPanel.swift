import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private let gpxType = UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml

struct ImportedRoutesPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ImportedRoute.importedAt, order: .reverse) private var routes: [ImportedRoute]

    @State private var showFilePicker = false
    @State private var importError: String?

    var onSelect: (ImportedRoute) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty && importError == nil {
                    ContentUnavailableView {
                        Label("GPX ルートなし", systemImage: "doc.badge.plus")
                    } description: {
                        Text("GPX ファイルをインポートしてください")
                    } actions: {
                        importButton
                    }
                } else {
                    routeList
                }
            }
            .navigationTitle("GPX ルート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    importButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [gpxType, .xml],
                onCompletion: handleFileImport
            )
        }
    }

    private var importButton: some View {
        Button {
            showFilePicker = true
        } label: {
            Label("インポート", systemImage: "plus")
        }
    }

    private var routeList: some View {
        List {
            if let error = importError {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            ForEach(routes) { route in
                Button {
                    onSelect(route)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        HStack(spacing: 12) {
                            Label(
                                String(format: "%.1f km", route.totalDistanceKm),
                                systemImage: "arrow.left.and.right"
                            )
                            Label(
                                route.importedAt.formatted(date: .abbreviated, time: .shortened),
                                systemImage: "clock"
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: deleteRoutes)
        }
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        importError = nil
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                importError = "ファイルへのアクセス権がありません"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let parser = GPXParser()
                let parsed = try parser.parse(data: data)
                let route = ImportedRoute(name: parsed.name, points: parsed.trackPoints)
                modelContext.insert(route)
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func deleteRoutes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(routes[index])
        }
    }
}
