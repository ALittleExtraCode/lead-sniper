import Foundation
import Security

/// The keychain, for the one thing in this app that is actually a secret.
///
/// A Slack or Discord webhook URL is not a preference. Anyone holding it can
/// post into that channel as often as they like, and it was being written into
/// `UserDefaults` -- a plain plist in ~/Library/Preferences that any process
/// running as this user can read, including anything the customer installs
/// later. Nothing else the app stores is sensitive: subreddit names, keywords
/// and post titles are all public to begin with.
enum Secret {

    private static let service = "com.leadsniper.app.webhook"

    /// Stored per workspace, because somebody running two products sends each
    /// one's leads to a different channel.
    static func save(_ value: String, for workspaceID: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return remove(for: workspaceID) }

        var query = base(workspaceID)
        query[kSecValueData as String] = Data(trimmed.utf8)
        // Only readable when the Mac is unlocked, and never synced to iCloud or
        // carried in a backup to another machine.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        SecItemDelete(base(workspaceID) as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(for workspaceID: String) -> String {
        var query = base(workspaceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return "" }
        return value
    }

    static func remove(for workspaceID: String) {
        SecItemDelete(base(workspaceID) as CFDictionary)
    }

    private static func base(_ workspaceID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: workspaceID,
        ]
    }
}
