#if DEBUG
    import AppCore
    import Foundation

    /// Debug builds only: `POST /api/dev/test-login`, for Simulator automation.
    ///
    /// Hand-written on purpose: the `dev` tag isn't in the generated client (D22), and this whole
    /// file is compiled out of Release builds, so no Release binary can even form the request.
    /// The server answers 404 unless `ALLOW_TEST_LOGIN` is on in a local profile, and only
    /// accepts `@glow.test` addresses.
    struct TestSignIn: Sendable {
        let apiBaseURL: URL

        struct Session: Decodable, Sendable {
            let accessToken: String
            let refreshToken: String
            let expiresIn: Int
            let userId: String
        }

        static let domain = "@glow.test"

        func session(for rawEmail: String) async throws(SessionError) -> Session {
            guard let email = SignInInput.email(rawEmail), email.hasSuffix(Self.domain) else {
                throw .invalidEmail
            }
            var request = URLRequest(url: apiBaseURL.appending(path: "api/dev/test-login"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["email": email])

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession(configuration: .glowAuth).data(for: request)
            } catch {
                throw SupabaseAuthBackend.map(error, invalid: .unexpected)
            }
            guard let status = (response as? HTTPURLResponse)?.statusCode else { throw .unexpected }
            switch status {
            case 200:
                guard let session = try? JSONDecoder().decode(Session.self, from: data) else { throw .unexpected }
                return session
            case 400: throw .invalidEmail
            case 429: throw .rateLimited
            // 404: the server doesn't allow test sign-in (ALLOW_TEST_LOGIN is off).
            default: throw .notConfigured
            }
        }
    }
#endif
