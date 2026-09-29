import CryptoKit
import Darwin
import Foundation
import PasswordGeneratorCore

@main
struct PasswordGeneratorChecksum {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            FileHandle.standardError.write(
                Data("Aufruf: PasswordGeneratorChecksum <sha256|sha3-512> <Datei>\n".utf8)
            )
            Darwin.exit(64)
        }

        let data = try Data(
            contentsOf: URL(fileURLWithPath: arguments[2]),
            options: [.mappedIfSafe]
        )
        let digest: Data
        switch arguments[1] {
        case "sha256":
            digest = Data(SHA256.hash(data: data))
        case "sha3-512":
            digest = SHA3.hash512(data)
        default:
            FileHandle.standardError.write(
                Data("Unbekannter Algorithmus: \(arguments[1])\n".utf8)
            )
            Darwin.exit(64)
        }
        print(digest.map { String(format: "%02x", $0) }.joined())
    }
}
