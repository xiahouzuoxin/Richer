import Foundation
import Security

/// Verify RS256 OIDC tokens using the issuer's published keys before trusting claims.
enum ChatGPTIdentity {
    static func decode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    @MainActor
    static func validate(_ token: String, clientID: String, nonce: String) async throws -> (subject: String, email: String) {
        let invalid = ChatGPTAuthError.message("ChatGPT identity verification failed. Please sign in again.")
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let headerData = decode(parts[0]), let claimsData = decode(parts[1]), let signature = decode(parts[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
              header["alg"] as? String == "RS256", let kid = header["kid"] as? String else { throw invalid }
        let config = try await ChatGPTAuth.json(URLRequest(url: URL(string: "https://auth.openai.com/.well-known/openid-configuration")!))
        guard config["issuer"] as? String == "https://auth.openai.com",
              let jwks = config["jwks_uri"] as? String, let url = URL(string: jwks),
              url.scheme == "https", url.host == "auth.openai.com" else { throw invalid }
        let keys = try await ChatGPTAuth.json(URLRequest(url: url))
        guard let key = (keys["keys"] as? [[String: Any]])?.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }),
              let n = key["n"] as? String, let e = key["e"] as? String,
              let modulus = decode(n), let exponent = decode(e) else { throw invalid }
        let der = tagged(0x30, integer(modulus) + integer(exponent))
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        guard let publicKey = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil),
              SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                Data((parts[0] + "." + parts[1]).utf8) as CFData, signature as CFData, nil) else { throw invalid }
        let audiences = claims["aud"] as? [String] ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard claims["iss"] as? String == "https://auth.openai.com", audiences.contains(clientID),
              audiences.count == 1 || claims["azp"] as? String == clientID,
              let expiry = claims["exp"] as? Double, expiry > Date().timeIntervalSince1970,
              claims["nonce"] as? String == nonce,
              let subject = claims["sub"] as? String, !subject.isEmpty else { throw invalid }
        if let nbf = claims["nbf"] as? Double, nbf > Date().timeIntervalSince1970 + 30 { throw invalid }
        return (subject, claims["email"] as? String ?? subject)
    }

    private static func integer(_ bytes: Data) -> Data {
        var value = Data(bytes.drop(while: { $0 == 0 }))
        if value.isEmpty { value.append(0) }
        if value.first! & 0x80 != 0 { value.insert(0, at: 0) }
        return tagged(0x02, value)
    }

    private static func tagged(_ tag: UInt8, _ bytes: Data) -> Data {
        var result = Data([tag])
        if bytes.count < 128 { result.append(UInt8(bytes.count)) }
        else {
            var count = bytes.count; var length: [UInt8] = []
            while count > 0 { length.insert(UInt8(count & 255), at: 0); count >>= 8 }
            result.append(0x80 | UInt8(length.count)); result.append(contentsOf: length)
        }
        result.append(bytes); return result
    }
}
