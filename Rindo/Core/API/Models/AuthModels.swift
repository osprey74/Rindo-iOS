import Foundation

struct LoginResponse: Codable, Sendable {
    let token: String
    let user: User?
}

struct UserResponse: Codable, Sendable {
    let user: User
}

struct User: Codable, Sendable, Identifiable {
    let id: Int
    let email: String?
    let name: String?
}
