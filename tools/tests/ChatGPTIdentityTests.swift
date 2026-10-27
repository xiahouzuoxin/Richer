// Offline security regression tests. Compile alongside ChatGPTIdentity.swift.
import Foundation
import Security

enum ChatGPTAuthError: Error { case message(String) }
@MainActor enum ChatGPTAuth {
    static var keys: [[String: Any]] = []
    static func json(_ request: URLRequest) async throws -> [String: Any] {
        if request.url!.path.contains("openid-configuration") {
            return ["issuer": "https://auth.openai.com", "jwks_uri": "https://auth.openai.com/keys"]
        }
        return ["keys": keys]
    }
}

@main struct IdentityTests {
    static func b64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func part(_ object: [String: Any]) throws -> String { b64(try JSONSerialization.data(withJSONObject: object)) }
    static func readDER(_ bytes: [UInt8], index: inout Int) -> [UInt8] {
        index += 1
        var count = Int(bytes[index]); index += 1
        if count & 128 != 0 {
            let lengthBytes = count & 127; count = 0
            for _ in 0..<lengthBytes { count = count * 256 + Int(bytes[index]); index += 1 }
        }
        let result = Array(bytes[index..<index + count]); index += count
        return result
    }
    @MainActor static func main() async throws {
        let privateKey = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048] as CFDictionary, nil)!
        let publicKey = SecKeyCopyPublicKey(privateKey)!
        let external = SecKeyCopyExternalRepresentation(publicKey, nil)! as Data
        var index = 0
        let sequence = readDER(Array(external), index: &index)
        index = 0
        let modulus = readDER(sequence, index: &index)
        let exponent = readDER(sequence, index: &index)
        ChatGPTAuth.keys = [["kid": "test-key", "kty": "RSA", "n": b64(Data(modulus)), "e": b64(Data(exponent))]]
        let base: [String: Any] = ["iss": "https://auth.openai.com", "aud": "oaiapp_test",
            "sub": "account-1", "email": "test@example.com", "nonce": "expected-nonce",
            "exp": Date().timeIntervalSince1970 + 300]
        func token(_ claims: [String: Any], alg: String = "RS256", kid: String = "test-key") throws -> String {
            let message = try part(["alg": alg, "kid": kid]) + "." + part(claims)
            let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256,
                Data(message.utf8) as CFData, nil)! as Data
            return message + "." + b64(signature)
        }
        let valid = try token(base)
        let identity = try await ChatGPTIdentity.validate(valid, clientID: "oaiapp_test", nonce: "expected-nonce")
        precondition(identity.subject == "account-1" && identity.email == "test@example.com")
        var rejected = 0
        func reject(_ jwt: String, nonce: String = "expected-nonce") async throws {
            do {
                _ = try await ChatGPTIdentity.validate(jwt, clientID: "oaiapp_test", nonce: nonce)
            } catch { rejected += 1; return }
            fatalError("Invalid token accepted")
        }
        try await reject(valid, nonce: "wrong-nonce")
        for (field, value) in [("aud", "another-app" as Any), ("iss", "https://evil.example" as Any),
                               ("exp", 1 as Any), ("nbf", Date().timeIntervalSince1970 + 600 as Any)] {
            var claims = base; claims[field] = value
            try await reject(token(claims))
        }
        var multiple = base; multiple["aud"] = ["oaiapp_test", "another-app"]
        try await reject(token(multiple))
        try await reject(token(base, alg: "none"))
        try await reject(token(base, kid: "unknown"))
        var tampered = valid.components(separatedBy: ".")
        var claims = base; claims["sub"] = "attacker"; tampered[1] = try part(claims)
        try await reject(tampered.joined(separator: "."))
        try await reject("malformed")
        precondition(rejected == 10)
        print("PASS: valid identity and 10 invalid identity cases")
    }
}
