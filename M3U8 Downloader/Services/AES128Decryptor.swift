import CommonCrypto
import Foundation

nonisolated struct AES128Decryptor: Sendable {
    func decrypt(data: Data, key: Data, initializationVector: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128, initializationVector.count == kCCBlockSizeAES128 else {
            throw CryptoError.invalidAES128Input
        }

        let outputCapacity = data.count + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var outputLength = 0

        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    initializationVector.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            data.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw CryptoError.decryptionFailed(status)
        }
        output.removeSubrange(outputLength..<output.count)
        return output
    }
}

nonisolated enum CryptoError: LocalizedError {
    case invalidAES128Input
    case decryptionFailed(CCCryptorStatus)

    var errorDescription: String? {
        switch self {
        case .invalidAES128Input:
            String(localized: .invalidAes128KeyOrInitializationVector)
        case .decryptionFailed(let status):
            String(localized: .aes128DecryptionFailedWithStatus(Int(status)))
        }
    }
}
