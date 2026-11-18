import Foundation

enum AppLinks {
    static let website = URL(string: "https://tools.cloakyard.com/")!
    static let repository = URL(string: "https://github.com/cloakyard/cloaktools")!
    static let issues = repository.appending(path: "issues/new")
    static let privacy = URL(string: "https://tools.cloakyard.com/privacy/")!
    static let support = URL(string: "https://ko-fi.com/sumitsahoo21")!
}
