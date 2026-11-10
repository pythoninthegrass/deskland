import Foundation

public struct Theme: Equatable, Sendable {
    public let id: String
    public let status: String
    public let product: String?
    public let page: String?
}

public enum ThemeSwitch: Equatable {
    case rejected(keep: String)
    case unchanged
    case load(theme: String, page: String)
}

// Port of Themes.cs over prototype/themes.json.
public struct ThemeCatalog {
    public let themes: [Theme]

    public init(data: Data) throws {
        let root = try JSONValue.parse(String(decoding: data, as: UTF8.self))
        guard let list = root.objectPairs?.first(where: { $0.key == "themes" })?.value, case let .array(items) = list else {
            throw JSONError(message: "themes.json has no themes array")
        }
        themes = items.compactMap { item in
            guard let pairs = item.objectPairs else { return nil }
            func str(_ k: String) -> String? { pairs.first { $0.key == k }?.value.stringValue }
            guard let id = str("id") else { return nil }
            return Theme(id: id, status: str("status") ?? "", product: str("product"), page: str("page"))
        }
    }

    // A page is served only for ready themes.
    public func page(for id: String?) -> String? {
        guard let id, let t = themes.first(where: { $0.id == id }), t.status == "ready" else { return nil }
        return t.page
    }

    // Ready themes without a product tag are denied so a new paid theme is never free by accident.
    public func isAllowed(_ id: String?) -> Bool {
        guard page(for: id) != nil, let id, let t = themes.first(where: { $0.id == id }) else { return false }
        return t.product == "free"
    }

    public func switchRequest(to id: String?, current: String) -> ThemeSwitch {
        guard let id, isAllowed(id), let page = page(for: id) else { return .rejected(keep: current) }
        return id == current ? .unchanged : .load(theme: id, page: page)
    }
}
