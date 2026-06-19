import Foundation
import CoreGraphics

public enum DOMFlattener {
    public static func flatten(_ rawElements: [[String: Any]]) -> [PageIndexedElement] {
        rawElements.enumerated().map { index, candidate in
            let x = candidate["x"] as? Double ?? Double(candidate["x"] as? Int ?? 0)
            let y = candidate["y"] as? Double ?? Double(candidate["y"] as? Int ?? 0)
            let width = candidate["width"] as? Double ?? Double(candidate["width"] as? Int ?? 0)
            let height = candidate["height"] as? Double ?? Double(candidate["height"] as? Int ?? 0)
            let label = firstNonEmpty(
                candidate["label"] as? String,
                candidate["ariaLabel"] as? String,
                candidate["text"] as? String,
                candidate["placeholder"] as? String,
                candidate["title"] as? String,
                candidate["id"] as? String
            )
            let domID = candidate["id"] as? String
            return PageIndexedElement(
                id: domID.flatMap { !$0.isEmpty ? $0 : nil } ?? "page-\(index + 1)",
                index: index + 1,
                role: firstNonEmpty(candidate["role"] as? String),
                label: label,
                value: firstNonEmpty(candidate["value"] as? String),
                domID: domID,
                tag: firstNonEmpty(candidate["tag"] as? String),
                className: firstNonEmpty(candidate["className"] as? String),
                frame: CGRect(x: x, y: y, width: width, height: height),
                focused: candidate["focused"] as? Bool ?? false,
                enabled: candidate["enabled"] as? Bool ?? true,
                visible: candidate["visible"] as? Bool ?? true
            )
        }
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.first { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? nil
    }
}
