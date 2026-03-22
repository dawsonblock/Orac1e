// VisionPerceptionContract.swift — Strict protocol for vision sidecar output.
//
// The vision sidecar must emit structured, typed results so the
// reconciliation layer can decide whether to trust the observation.
// Raw untyped dictionaries are never consumed directly by the world model.

import Foundation

// MARK: - Detection Result Types

/// A single UI element detected by the vision system.
public struct VisionDetection: Codable, Sendable {
    /// Unique identifier for this detection within the frame.
    public let id: String
    /// Semantic type: "button", "text_field", "link", "icon", "image", "input", "label".
    public let elementType: String
    /// Bounding box in logical screen coordinates.
    public let frame: VisionFrame
    /// Model confidence, 0.0 – 1.0.
    public let confidence: Double
    /// Recognised text content (OCR), if any.
    public let text: String?
    /// Detection source, e.g. "yolo", "ocr", "vlm".
    public let source: String
    /// ISO-8601 timestamp of the capture.
    public let timestamp: String

    public init(
        id: String,
        elementType: String,
        frame: VisionFrame,
        confidence: Double,
        text: String? = nil,
        source: String,
        timestamp: String
    ) {
        self.id = id
        self.elementType = elementType
        self.frame = frame
        self.confidence = confidence
        self.text = text
        self.source = source
        self.timestamp = timestamp
    }
}

/// Axis-aligned bounding box in logical screen coordinates.
public struct VisionFrame: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public var centerX: Double { x + width / 2 }
    public var centerY: Double { y + height / 2 }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A complete perception frame from the vision sidecar.
public struct VisionPerceptionFrame: Codable, Sendable {
    /// Detections in this frame.
    public let detections: [VisionDetection]
    /// Aggregate confidence across all detections.
    public let overallConfidence: Double
    /// ISO-8601 timestamp of the frame capture.
    public let timestamp: String
    /// Screen dimensions at capture time.
    public let screenWidth: Double
    public let screenHeight: Double

    public init(
        detections: [VisionDetection],
        overallConfidence: Double,
        timestamp: String,
        screenWidth: Double,
        screenHeight: Double
    ) {
        self.detections = detections
        self.overallConfidence = overallConfidence
        self.timestamp = timestamp
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
    }
}

// MARK: - Vision Perception Provider Protocol

/// Protocol that any vision perception source (e.g. vision sidecar) must conform
/// to when feeding observations into the world model.
public protocol VisionPerceptionProvider: Sendable {
    /// A short identifier for this provider (e.g. "vision").
    var providerID: String { get }

    /// Capture a vision perception frame for the given application, if possible.
    func capture(app: String) async throws -> VisionPerceptionFrame
}

// MARK: - Validation

/// Validates a `VisionPerceptionFrame` before the world model accepts it.
public enum VisionContractValidator {

    /// Minimum acceptable overall confidence for the frame.
    public static let minimumFrameConfidence: Double = 0.3

    /// Maximum age of a frame in seconds before it is considered stale.
    public static let maxFrameAgeSec: Double = 10.0

    /// Validate a perception frame.  Returns an array of violation descriptions
    /// (empty means the frame is valid).
    public static func validate(_ frame: VisionPerceptionFrame, now: Date = Date()) -> [String] {
        var violations: [String] = []

        if frame.overallConfidence < minimumFrameConfidence {
            violations.append(
                "Frame confidence \(frame.overallConfidence) below minimum \(minimumFrameConfidence)"
            )
        }

        if frame.detections.isEmpty {
            violations.append("Frame contains no detections")
        }

        for det in frame.detections {
            if det.confidence < 0 || det.confidence > 1 {
                violations.append("Detection \(det.id) has out-of-range confidence \(det.confidence)")
            }
            if det.frame.width <= 0 || det.frame.height <= 0 {
                violations.append("Detection \(det.id) has non-positive dimensions")
            }
            if det.elementType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                violations.append("Detection \(det.id) has empty elementType")
            }
        }

        // Check freshness.
        let isoFormatter = ISO8601DateFormatter()
        if let frameDate = isoFormatter.date(from: frame.timestamp) {
            let age = now.timeIntervalSince(frameDate)
            if age < 0 {
                violations.append("Frame timestamp '\(frame.timestamp)' is in the future relative to validation time")
            } else if age > maxFrameAgeSec {
                violations.append("Frame is \(Int(age))s old, exceeds \(Int(maxFrameAgeSec))s limit")
            }
        } else {
            violations.append("Frame timestamp '\(frame.timestamp)' is not a valid ISO-8601 date")
        }

        return violations
    }
}
