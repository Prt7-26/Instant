import Foundation

public struct SearchSource: Codable, Equatable, Identifiable, Sendable {
    public let title: String
    public let url: URL
    public var id: String { url.absoluteString }
    public init?(title: String, address: String) {
        guard var components = URLComponents(string: address),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        components.fragment = nil
        guard let url = components.url else { return nil }
        self.url = url
        let clean = title.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = clean.isEmpty ? host : String(clean.prefix(250))
    }
    public static func unique(_ sources: [Self]) -> [Self] {
        var seen = Set<String>()
        return sources.filter { seen.insert($0.id).inserted }.prefix(50).map { $0 }
    }
    private enum CodingKeys: String, CodingKey { case title, url }
    public init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        let title = try data.decode(String.self, forKey: .title)
        let url = try data.decode(URL.self, forKey: .url)
        guard let source = Self(title: title, address: url.absoluteString) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: data, debugDescription: "Invalid search-source URL")
        }
        self = source
    }
}
