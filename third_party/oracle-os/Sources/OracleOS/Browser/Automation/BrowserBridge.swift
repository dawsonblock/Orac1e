// BrowserBridge.swift — High-level browser interaction bridge.
//
// Provides a unified interface for browser DOM access, abstracting
// over the CDP (Chrome DevTools Protocol) transport layer.
//
// The bridge exposes semantic operations that the perception and
// execution layers consume:
//
//   querySelector    — find element by CSS selector
//   getBoundingRect  — element geometry in viewport coordinates
//   getText          — read text content from the page
//   click            — click an element by selector
//   type             — type text into an element by selector
//
// Perception can read the DOM directly through BrowserBridge,
// bypassing the often-unreliable AX tree for web content.

import Foundation

/// Unified browser bridge for DOM access and interaction.
///
/// Wraps ``DOMScanner`` (Chrome DevTools Protocol) and provides a
/// clean, selector-based API that the perception engine and action
/// executor can consume without knowledge of the transport layer.
@MainActor
public struct BrowserBridge: Sendable {
    public init() {}

    // MARK: - Availability

    /// Whether the bridge can currently communicate with the browser.
    public var isAvailable: Bool {
        DOMScanner.isAvailable()
    }

    // MARK: - Query

    /// Find an element by CSS selector and return its bounding rectangle
    /// in viewport coordinates.
    ///
    /// Returns `nil` when the selector matches nothing or the bridge is
    /// unavailable.
    public func querySelector(_ selector: String, tabIndex: Int = 0) -> BrowserElement? {
        guard let results = DOMScanner.evaluateJS(
            """
            (function() {
                const el = document.querySelector(\(escapeJSString(selector)));
                if (!el) return JSON.stringify(null);
                const rect = el.getBoundingClientRect();
                return JSON.stringify({
                    tag: el.tagName.toLowerCase(),
                    text: (el.textContent || '').trim().substring(0, 200),
                    id: el.id || '',
                    x: Math.round(rect.x),
                    y: Math.round(rect.y),
                    width: Math.round(rect.width),
                    height: Math.round(rect.height)
                });
            })()
            """,
            tabIndex: tabIndex
        ),
              let data = results.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return BrowserElement(
            tag: json["tag"] as? String ?? "",
            text: json["text"] as? String ?? "",
            id: json["id"] as? String ?? "",
            x: json["x"] as? Int ?? 0,
            y: json["y"] as? Int ?? 0,
            width: json["width"] as? Int ?? 0,
            height: json["height"] as? Int ?? 0
        )
    }

    /// Return the bounding rectangle of an element matched by CSS selector.
    public func getBoundingRect(_ selector: String, tabIndex: Int = 0) -> BrowserRect? {
        guard let element = querySelector(selector, tabIndex: tabIndex) else {
            return nil
        }
        return BrowserRect(
            x: element.x,
            y: element.y,
            width: element.width,
            height: element.height
        )
    }

    /// Read visible text content from an element matched by CSS selector.
    public func getText(_ selector: String, tabIndex: Int = 0) -> String? {
        guard let result = DOMScanner.evaluateJS(
            """
            (function() {
                const el = document.querySelector(\(escapeJSString(selector)));
                if (!el) return '';
                return (el.textContent || '').trim();
            })()
            """,
            tabIndex: tabIndex
        ) else {
            return nil
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - Interaction

    /// Click an element matched by CSS selector.
    ///
    /// Dispatches a JavaScript click event in the page context.
    @discardableResult
    public func click(_ selector: String, tabIndex: Int = 0) -> Bool {
        guard let result = DOMScanner.evaluateJS(
            """
            (function() {
                const el = document.querySelector(\(escapeJSString(selector)));
                if (!el) return 'false';
                el.click();
                return 'true';
            })()
            """,
            tabIndex: tabIndex
        ) else {
            return false
        }
        return result == "true"
    }

    /// Type text into an input or textarea matched by CSS selector.
    ///
    /// Focuses the element, optionally clears existing content, then
    /// sets the value and dispatches an input event.
    @discardableResult
    public func type(_ selector: String, text: String, clear: Bool = true, tabIndex: Int = 0) -> Bool {
        guard let result = DOMScanner.evaluateJS(
            """
            (function() {
                const el = document.querySelector(\(escapeJSString(selector)));
                if (!el) return 'false';
                el.focus();
                \(clear ? "el.value = '';" : "")
                el.value = \(escapeJSString(text));
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
                return 'true';
            })()
            """,
            tabIndex: tabIndex
        ) else {
            return false
        }
        return result == "true"
    }

    // MARK: - Private

    private func escapeJSString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }
}

// MARK: - Supporting types

/// A DOM element with its bounding rectangle in viewport coordinates.
public struct BrowserElement: Sendable, Codable {
    public let tag: String
    public let text: String
    public let id: String
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    /// Center point in viewport coordinates.
    public var centerX: Int { x + width / 2 }
    public var centerY: Int { y + height / 2 }
}

/// A bounding rectangle in viewport coordinates.
public struct BrowserRect: Sendable, Codable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
}
