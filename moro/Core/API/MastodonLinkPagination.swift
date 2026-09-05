import Foundation

enum MastodonLinkPagination {
    static func nextMaxID(in response: HTTPURLResponse) -> String? {
        guard let header = response.value(forHTTPHeaderField: "Link"), let source = response.url else { return nil }
        for link in header.split(separator: ",") {
            let parts = link.split(separator: ";")
            guard parts.dropFirst().contains(where: {
                let attribute = $0.trimmingCharacters(in: .whitespaces)
                return attribute == "rel=\"next\"" || attribute == "rel=next"
            }), let target = parts.first,
                let start = target.firstIndex(of: "<"), let end = target.firstIndex(of: ">"), start < end,
                let url = URL(string: String(target[target.index(after: start)..<end]), relativeTo: source)?.absoluteURL,
                url.host == source.host, url.scheme == source.scheme, url.port == source.port,
                url.path == source.path,
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let cursor = components.queryItems?.first(where: { $0.name == "max_id" })?.value,
                !cursor.isEmpty else { continue }
            return cursor
        }
        return nil
    }
}
