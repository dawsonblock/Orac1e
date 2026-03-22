import Foundation

public enum PageTextReducer {
    public static func reduce(
        title: String?,
        url: String?,
        elements: [PageIndexedElement]
    ) -> String {
        var lines: [String] = []
        if let title, !title.isEmpty { lines.append("Title: \(title)") }
        if let url, !url.isEmpty { lines.append("URL: \(url)") }
        for element in elements.prefix(20) {
            let descriptor = [
                "\(element.index).",
                element.label,
                element.role,
                element.tag,
            ]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !descriptor.isEmpty {
                lines.append(descriptor)
            }
        }
        return lines.joined(separator: "\n")
    }
}
