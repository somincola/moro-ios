import Foundation

enum MastodonLinkPagination {
    static func nextMaxID(in response: HTTPURLResponse) -> String? {
        cursor(in: response, relation: "next", parameter: "max_id")
    }

    static func prevMinID(in response: HTTPURLResponse) -> String? {
        cursor(in: response, relation: "prev", parameter: "min_id")
    }

    private static func cursor(
        in response: HTTPURLResponse,
        relation: String,
        parameter: String
    ) -> String? {
        guard let header = response.value(forHTTPHeaderField: "Link"), let source = response.url else { return nil }
        for link in header.split(separator: ",") {
            let parts = link.split(separator: ";")
            guard parts.dropFirst().contains(where: {
                let attribute = $0.trimmingCharacters(in: .whitespaces)
                return attribute == "rel=\"\(relation)\"" || attribute == "rel=\(relation)"
            }), let target = parts.first,
                let start = target.firstIndex(of: "<"), let end = target.firstIndex(of: ">"), start < end,
                let url = URL(string: String(target[target.index(after: start)..<end]), relativeTo: source)?.absoluteURL,
                url.host == source.host, url.scheme == source.scheme, url.port == source.port,
                url.path == source.path,
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let cursor = components.queryItems?.first(where: { $0.name == parameter })?.value,
                !cursor.isEmpty else { continue }
            return cursor
        }
        return nil
    }
}
