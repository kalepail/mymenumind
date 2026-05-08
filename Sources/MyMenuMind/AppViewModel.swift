import AppKit
import Foundation
import MyMenuMindCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var query = ""
    @Published var quickNote = ""
    @Published var searchResults: [MymindItem] = []
    @Published var recentItems: [MymindItem] = []
    @Published var message: String?
    @Published var isLoading = false

    let settings: SettingsStore
    private var recentTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var quickNoteTask: Task<Void, Never>?
    private var inFlightOperations = 0

    init(settings: SettingsStore) {
        self.settings = settings
    }

    deinit {
        recentTask?.cancel()
        searchTask?.cancel()
        quickNoteTask?.cancel()
    }

    func loadRecent() {
        recentTask?.cancel()
        recentTask = Task {
            await run {
                let items = try await self.client().recent(limit: 10)
                try Task.checkCancellation()
                self.recentItems = items
            }
        }
    }

    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchTask?.cancel()
            searchResults = []
            return
        }

        searchTask?.cancel()
        searchTask = Task {
            await run {
                let items = try await self.client().search(query: trimmed, limit: 20)
                try Task.checkCancellation()
                self.searchResults = items
            }
        }
    }

    func saveQuickNote() {
        let trimmed = quickNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        quickNoteTask?.cancel()
        quickNoteTask = Task {
            await run(successMessage: "Note saved") {
                let client = self.client()
                try await client.createQuickNote(text: trimmed)
                try Task.checkCancellation()
                self.quickNote = ""
                let items = try await client.recent(limit: 10)
                try Task.checkCancellation()
                self.recentItems = items
            }
        }
    }

    func saveSettings() {
        do {
            try settings.save()
            message = "Settings saved"
        } catch {
            message = error.localizedDescription
        }
    }

    func open(_ item: MymindItem) {
        guard let url = item.preferredOpenURL else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func client() -> MymindClient {
        MymindClient(configuration: settings.configuration)
    }

    private func run(successMessage: String? = nil, operation: @escaping () async throws -> Void) async {
        inFlightOperations += 1
        isLoading = true
        message = nil
        defer {
            inFlightOperations -= 1
            isLoading = inFlightOperations > 0
        }

        do {
            try await operation()
            message = successMessage
        } catch is CancellationError {
            return
        } catch {
            message = error.localizedDescription
        }
    }
}
