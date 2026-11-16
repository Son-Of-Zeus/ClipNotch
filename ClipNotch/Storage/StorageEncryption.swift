import CryptoKit
import Foundation
import Security

struct StorageEncryption: Sendable {
    enum Purpose: String {
        case database, images, imageNames, palette, preferences
    }

    private let masterKey: SymmetricKey

    init(keyData: Data) throws {
        guard keyData.count == 32 else { throw EncryptedStorageError.invalidKey }
        masterKey = SymmetricKey(data: keyData)
    }

    func key(for purpose: Purpose) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: Data("ClipNotch.encrypted-v3".utf8),
            info: Data(purpose.rawValue.utf8),
            outputByteCount: 32
        )
    }

    func seal(_ data: Data, purpose: Purpose, context: String = "") throws -> Data {
        try AES.GCM.seal(data, using: key(for: purpose), authenticating: authentication(purpose, context)).combined!
    }

    func open(_ data: Data, purpose: Purpose, context: String = "") throws -> Data {
        try AES.GCM.open(
            AES.GCM.SealedBox(combined: data),
            using: key(for: purpose),
            authenticating: authentication(purpose, context)
        )
    }

    func write(_ data: Data, to url: URL, purpose: Purpose, context: String = "") throws {
        let encrypted = try seal(data, purpose: purpose, context: context)
        try Self.createDirectory(url.deletingLastPathComponent())
        try encrypted.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func read(from url: URL, purpose: Purpose, context: String = "") throws -> Data {
        try open(Data(contentsOf: url), purpose: purpose, context: context)
    }

    func imageName(hash: String, type: String) -> String {
        HMAC<SHA256>.authenticationCode(
            for: Data("\(hash)\u{0}\(type)".utf8),
            using: key(for: .imageNames)
        ).map { String(format: "%02x", $0) }.joined() + ".enc"
    }

    static func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
    }

    private func authentication(_ purpose: Purpose, _ context: String) -> Data {
        Data("ClipNotch.encrypted-v3.\(purpose.rawValue).\(context)".utf8)
    }
}

protocol StorageKeyStoring {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

struct KeychainStorageKeyStore: StorageKeyStoring {
    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.clipnotch.app.encrypted-storage",
            kSecAttrAccount as String: "master-key-v3",
            kSecAttrSynchronizable as String: false
        ]
    }

    func load() throws -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw EncryptedStorageError.keychain(status) }
        guard let data = result as? Data else { throw EncryptedStorageError.invalidKey }
        return data
    }

    func save(_ data: Data) throws {
        var query = query
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw EncryptedStorageError.keychain(status) }
    }
}

struct EncryptedStorage {
    let directory: URL
    let encryption: StorageEncryption

    static func prepare(
        baseDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("ClipNotch", isDirectory: true),
        keyStore: any StorageKeyStoring = KeychainStorageKeyStore(),
        defaults: UserDefaults = .standard
    ) throws -> EncryptedStorage {
        let directory = baseDirectory.appendingPathComponent("encrypted-v3", isDirectory: true)
        let manager = FileManager.default
        let hasEncryptedData = try manager.fileExists(atPath: directory.path)
            && !manager.contentsOfDirectory(atPath: directory.path).isEmpty
        let keyData: Data
        if let savedKey = try keyStore.load() {
            keyData = savedKey
        } else {
            guard !hasEncryptedData else { throw EncryptedStorageError.missingKey }
            keyData = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            try keyStore.save(keyData)
        }
        let encryption = try StorageEncryption(keyData: keyData)
        try StorageEncryption.createDirectory(directory)
        try removeCleartextData(from: baseDirectory, defaults: defaults)
        return EncryptedStorage(directory: directory, encryption: encryption)
    }

    static func removeCleartextData(from directory: URL, defaults: UserDefaults) throws {
        let manager = FileManager.default
        let paths = ["clipnotch.db", "clipnotch-v2.sqlite"].flatMap { name in
            [name, name + "-wal", name + "-shm", name + "-journal"]
        } + ["items", "payloads-v2", "data-palette.json"]
        for path in paths {
            let url = directory.appendingPathComponent(path)
            if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
        }
        for key in [
            "hasCompletedOnboarding", "onboardingStep", "retentionHours", "maxItemCount", "maxDiskMB",
            "maxMemoryMB", "launchAtLogin", "shortcutConfiguration", "autofillEnabled", "autofillExcludedHosts"
        ] {
            defaults.removeObject(forKey: key)
        }
        guard defaults.synchronize() else { throw EncryptedStorageError.preferencesResetFailed }
    }
}

enum EncryptedStorageError: LocalizedError {
    case missingKey
    case invalidKey
    case keychain(OSStatus)
    case preferencesResetFailed

    var errorDescription: String? {
        switch self {
        case .missingKey: "The Keychain key for the encrypted data is missing. Existing data was not changed."
        case .invalidKey: "The storage key is invalid."
        case .keychain(let status): "macOS Keychain could not provide the storage key (\(status))."
        case .preferencesResetFailed: "Old preferences could not be removed."
        }
    }
}
