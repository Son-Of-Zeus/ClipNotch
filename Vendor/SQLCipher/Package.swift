// swift-tools-version: 5.9
import PackageDescription

// Amalgamation generated from sqlcipher/sqlcipher v4.10.0,
// commit d41a25f448ba08ce24c0a599cf322046bdaa135a, with `make sqlite3.c`.
let package = Package(
    name: "SQLCipher",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SQLCipher", type: .static, targets: ["SQLCipher"])],
    targets: [
        .target(
            name: "SQLCipher",
            path: ".",
            sources: ["sqlite3.c"],
            publicHeadersPath: "include",
            cSettings: [
                .define("NDEBUG"),
                .define("SQLITE_HAS_CODEC"),
                .define("SQLITE_TEMP_STORE", to: "2"),
                .define("SQLITE_THREADSAFE", to: "1"),
                .define("SQLITE_EXTRA_INIT", to: "sqlcipher_extra_init"),
                .define("SQLITE_EXTRA_SHUTDOWN", to: "sqlcipher_extra_shutdown"),
                .define("SQLCIPHER_CRYPTO_CC")
            ],
            linkerSettings: [.linkedFramework("Security")]
        )
    ]
)
