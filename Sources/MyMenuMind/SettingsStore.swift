import Foundation
import MyMenuMindCore

@MainActor
final class SettingsStore: ObservableObject {
    @Published var configuration: APIConfiguration

    private let defaults: UserDefaults
    private let key = "apiConfiguration"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: key),
           var saved = try? JSONDecoder().decode(APIConfiguration.self, from: data) {
            let legacyCredentials = MymindCredentials(keyID: saved.keyID, secret: saved.secret)
            var credentials = KeychainCredentialsStore.load()

            // Older builds could have encoded credentials in UserDefaults. Move them
            // into Keychain once, then rewrite defaults with blank credential fields.
            if credentials.isEmpty && !legacyCredentials.isEmpty,
               (try? KeychainCredentialsStore.save(legacyCredentials)) != nil {
                credentials = legacyCredentials
            }

            saved.keyID = credentials.keyID
            saved.secret = credentials.secret
            configuration = saved
            scrubPersistedCredentialsIfNeeded(legacyCredentials)
        } else {
            var fallback = APIConfiguration()
            let credentials = KeychainCredentialsStore.load()
            fallback.keyID = credentials.keyID
            fallback.secret = credentials.secret
            configuration = fallback
        }
    }

    func save() throws {
        try KeychainCredentialsStore.save(MymindCredentials(keyID: configuration.keyID, secret: configuration.secret))

        var persisted = configuration
        persisted.keyID = ""
        persisted.secret = ""
        let data = try JSONEncoder().encode(persisted)
        defaults.set(data, forKey: key)
    }

    private func scrubPersistedCredentialsIfNeeded(_ credentials: MymindCredentials) {
        guard !credentials.isEmpty else {
            return
        }

        var persisted = configuration
        persisted.keyID = ""
        persisted.secret = ""
        if let data = try? JSONEncoder().encode(persisted) {
            defaults.set(data, forKey: key)
        }
    }
}

private extension MymindCredentials {
    var isEmpty: Bool {
        keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
