// VisionBridge.swift - HTTP client to the Python vision sidecar
//
// Oracle OS v2 calls the vision sidecar when the AX tree can't find
// what the agent needs (web apps with generic AXGroup roles, dynamic
// content, etc.).
//
// Architecture:
//   Oracle OS (Swift) --HTTP--> Vision Sidecar (Python) --MLX--> ShowUI-2B
//
// The sidecar runs on localhost:9876. VisionBridge auto-starts it when
// needed via the `oracle-vision` launcher script.
//
// VisionBridge handles:
//   1. Health check (is the sidecar running?)
//   2. VLM grounding (find element coordinates from screenshot + description)
//   3. Sidecar lifecycle management (auto-start, track PID)

import Foundation

/// Bridge between Oracle OS v2 and the Python vision sidecar.
/// All methods are synchronous (blocking) because the MCP server is synchronous.
public enum VisionBridge {

    /// Default sidecar URL. Can be overridden via ORACLE_VISION_URL env var.
    private static let baseURL: String = {
        if let url = ProcessInfo.processInfo.environment["ORACLE_VISION_URL"] {
            return url
        }
        let port = ProcessInfo.processInfo.environment["ORACLE_VISION_PORT"] ?? "9876"
        return "http://127.0.0.1:\(port)"
    }()

    /// Timeout for health checks (short — just checking if process is alive).
    private static let healthTimeout: TimeInterval = 2.0

    /// Timeout for VLM grounding (model inference can take 3-5s on first call,
    /// then 0.5-3s on subsequent calls with warm model).
    private static let groundTimeout: TimeInterval = 30.0

    /// Timeout for the first grounding call which also loads the model (~10-15s).
    private static let firstGroundTimeout: TimeInterval = 60.0

    /// Sidecar lifecycle state machine.
    public enum SidecarState: Sendable {
        case stopped
        case starting
        case ready
        case failed
    }

    /// Thread-safe container for mutable sidecar state.
    private final class SidecarLifecycle: @unchecked Sendable {
        private let lock = NSLock()
        private var _state: SidecarState = .stopped
        private var _process: Process?
        private var _hasCompletedFirstGround = false

        var state: SidecarState {
            get { lock.lock(); defer { lock.unlock() }; return _state }
            set { lock.lock(); defer { lock.unlock() }; _state = newValue }
        }

        var process: Process? {
            get { lock.lock(); defer { lock.unlock() }; return _process }
            set { lock.lock(); defer { lock.unlock() }; _process = newValue }
        }

        var hasCompletedFirstGround: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _hasCompletedFirstGround }
            set { lock.lock(); defer { lock.unlock() }; _hasCompletedFirstGround = newValue }
        }

        /// Atomically transition from an expected state to a new state.
        /// Returns true if the transition was performed.
        @discardableResult
        func transition(from expected: SidecarState, to desired: SidecarState) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard _state == expected else { return false }
            _state = desired
            return true
        }
    }

    private static let lifecycle = SidecarLifecycle()

    // MARK: - Health Check

    /// Check if the vision sidecar is running and responsive.
    public static func isAvailable() -> Bool {
        guard let result = httpGet(path: "/health", timeout: healthTimeout) else {
            return false
        }
        return result["status"] != nil
    }

    /// Get detailed health status from the sidecar.
    public static func healthCheck() -> [String: Any]? {
        httpGet(path: "/health", timeout: healthTimeout)
    }

    // MARK: - VLM Grounding

    /// Result from a VLM grounding call.
    public struct GroundResult {
        /// X coordinate in logical screen points.
        public let x: Double
        /// Y coordinate in logical screen points.
        public let y: Double
        /// Confidence (0-1). 0 means coordinates couldn't be parsed.
        public let confidence: Double
        /// Raw model output text.
        public let raw: String
        /// Method used: "full-screen" or "crop-based".
        public let method: String
        /// Inference time in milliseconds.
        public let inferenceMs: Int
    }

    /// Find precise coordinates for a UI element using VLM grounding.
    ///
    /// Auto-starts the vision sidecar if it's not already running.
    ///
    /// - Parameters:
    ///   - imageBase64: Base64-encoded PNG screenshot
    ///   - description: What to find (e.g., "Compose button", "Send button")
    ///   - screenWidth: Logical screen width in points (default 1728)
    ///   - screenHeight: Logical screen height in points (default 1117)
    ///   - cropBox: Optional crop region [x1, y1, x2, y2] in logical points.
    ///              When provided, the sidecar crops the image first, runs VLM
    ///              on the crop, then maps coordinates back to full screen.
    ///              This dramatically improves accuracy for overlapping panels.
    /// - Returns: GroundResult with coordinates, or nil if grounding failed.
    public static func ground(
        imageBase64: String,
        description: String,
        screenWidth: Double = 1728,
        screenHeight: Double = 1117,
        cropBox: [Double]? = nil
    ) -> GroundResult? {
        // Auto-start sidecar if not running
        if !isAvailable() {
            Log.info("Vision sidecar not running, attempting auto-start...")
            if !startSidecar() {
                Log.warn("Vision sidecar auto-start failed")
                return nil
            }
        }

        var payload: [String: Any] = [
            "image": imageBase64,
            "description": description,
            "screen_w": screenWidth,
            "screen_h": screenHeight,
        ]
        if let cropBox, cropBox.count == 4 {
            payload["crop_box"] = cropBox
        }

        // Use longer timeout for first call (model needs to load ~10-15s)
        let timeout = lifecycle.hasCompletedFirstGround ? groundTimeout : firstGroundTimeout

        guard let result = httpPost(path: "/ground", body: payload, timeout: timeout) else {
            Log.warn("Vision sidecar /ground request failed")
            return nil
        }

        guard let x = result["x"] as? Double,
              let y = result["y"] as? Double,
              let confidence = result["confidence"] as? Double
        else {
            Log.warn("Vision sidecar /ground returned invalid response: \(result)")
            return nil
        }

        lifecycle.hasCompletedFirstGround = true
        return GroundResult(
            x: x,
            y: y,
            confidence: confidence,
            raw: result["raw"] as? String ?? "",
            method: result["method"] as? String ?? "unknown",
            inferenceMs: result["inference_ms"] as? Int ?? 0
        )
    }

    // MARK: - Element Detection

    /// Detect all interactive elements on screen using YOLO.
    public static func detect(
        imageBase64: String,
        screenWidth: Double = 1728,
        screenHeight: Double = 1117
    ) -> [String: Any]? {
        let payload: [String: Any] = [
            "image": imageBase64,
            "screen_w": screenWidth,
            "screen_h": screenHeight,
        ]
        return httpPost(path: "/detect", body: payload, timeout: groundTimeout)
    }

    // MARK: - Screen Parsing

    /// Parse screen into a structured element map.
    public static func parse(
        imageBase64: String,
        screenWidth: Double = 1728,
        screenHeight: Double = 1117
    ) -> [String: Any]? {
        let payload: [String: Any] = [
            "image": imageBase64,
            "screen_w": screenWidth,
            "screen_h": screenHeight,
        ]
        return httpPost(path: "/parse", body: payload, timeout: groundTimeout)
    }

    // MARK: - Batch Grounding

    /// Result from a batch grounding call.
    public struct BatchGroundResult {
        /// Results for each description, in order.
        public let results: [GroundResult]
        /// Number of successful grounds.
        public let count: Int
        /// Whether any result was served from cache.
        public let hadCacheHits: Bool
    }

    /// Find precise coordinates for multiple UI elements in a single screenshot.
    ///
    /// More efficient than calling `ground()` multiple times — the image is
    /// sent once and the VLM runs multiple grounding queries.
    ///
    /// - Parameters:
    ///   - imageBase64: Base64-encoded PNG screenshot (shared for all descriptions)
    ///   - descriptions: What to find (e.g., ["Compose button", "Send button"])
    ///   - screenWidth: Logical screen width in points
    ///   - screenHeight: Logical screen height in points
    ///   - cropBox: Optional crop region [x1, y1, x2, y2]
    /// - Returns: BatchGroundResult, or nil if the request failed.
    public static func groundBatch(
        imageBase64: String,
        descriptions: [String],
        screenWidth: Double = 1728,
        screenHeight: Double = 1117,
        cropBox: [Double]? = nil
    ) -> BatchGroundResult? {
        if !isAvailable() {
            if !startSidecar() { return nil }
        }

        var payload: [String: Any] = [
            "image": imageBase64,
            "descriptions": descriptions,
            "screen_w": screenWidth,
            "screen_h": screenHeight,
        ]
        if let cropBox, cropBox.count == 4 {
            payload["crop_box"] = cropBox
        }

        let timeout = lifecycle.hasCompletedFirstGround ? groundTimeout : firstGroundTimeout

        guard let result = httpPost(path: "/ground_batch", body: payload, timeout: timeout),
              let resultsArray = result["results"] as? [[String: Any]]
        else {
            Log.warn("Vision sidecar /ground_batch request failed")
            return nil
        }

        let results: [GroundResult] = resultsArray.compactMap { item in
            guard let x = item["x"] as? Double,
                  let y = item["y"] as? Double,
                  let confidence = item["confidence"] as? Double
            else { return nil }
            return GroundResult(
                x: x, y: y, confidence: confidence,
                raw: item["raw"] as? String ?? "",
                method: item["method"] as? String ?? "unknown",
                inferenceMs: item["inference_ms"] as? Int ?? 0
            )
        }

        let hadCacheHits = resultsArray.contains { ($0["cached"] as? Bool) == true }
        lifecycle.hasCompletedFirstGround = true

        return BatchGroundResult(
            results: results,
            count: results.count,
            hadCacheHits: hadCacheHits
        )
    }

    // MARK: - Screenshot Diffing

    /// Result from a screenshot diff.
    public struct DiffResult {
        /// Whether any meaningful changes were detected.
        public let hasChanges: Bool
        /// Fraction of pixels that changed (0-1).
        public let changeRatio: Double
        /// Number of pixels that changed.
        public let changedPixels: Int
        /// Total pixels in the image.
        public let totalPixels: Int
        /// Mean per-pixel difference (0-255).
        public let meanDiff: Double
        /// Maximum per-pixel difference (0-255).
        public let maxDiff: Double
        /// Bounding box of changed region [x1, y1, x2, y2], or nil if no changes.
        public let bbox: [Int]?
        /// Threshold used for change detection.
        public let threshold: Double
        /// Inference time in milliseconds.
        public let inferenceMs: Int
    }

    /// Detect changes between two screenshots.
    ///
    /// Useful for verifying that a click/type action had the expected effect.
    ///
    /// - Parameters:
    ///   - imageA: Base64-encoded PNG screenshot (before action)
    ///   - imageB: Base64-encoded PNG screenshot (after action)
    ///   - threshold: Change sensitivity 0-1 (default 0.1)
    /// - Returns: DiffResult, or nil if the request failed.
    public static func diff(
        imageA: String,
        imageB: String,
        threshold: Double = 0.1
    ) -> DiffResult? {
        if !isAvailable() {
            if !startSidecar() { return nil }
        }

        let payload: [String: Any] = [
            "image_a": imageA,
            "image_b": imageB,
            "threshold": threshold,
        ]

        guard let result = httpPost(path: "/diff", body: payload, timeout: groundTimeout) else {
            Log.warn("Vision sidecar /diff request failed")
            return nil
        }

        guard let hasChanges = result["has_changes"] as? Bool,
              let changeRatio = result["change_ratio"] as? Double,
              let changedPixels = result["changed_pixels"] as? Int,
              let totalPixels = result["total_pixels"] as? Int,
              let meanDiff = result["mean_diff"] as? Double,
              let maxDiff = result["max_diff"] as? Double,
              let inferenceMs = result["inference_ms"] as? Int
        else {
            Log.warn("Vision sidecar /diff returned invalid response: \(result)")
            return nil
        }

        return DiffResult(
            hasChanges: hasChanges,
            changeRatio: changeRatio,
            changedPixels: changedPixels,
            totalPixels: totalPixels,
            meanDiff: meanDiff,
            maxDiff: maxDiff,
            bbox: result["bbox"] as? [Int],
            threshold: threshold,
            inferenceMs: inferenceMs
        )
    }

    // MARK: - Metrics & Diagnostics

    /// Get Prometheus-format metrics from the sidecar.
    public static func metrics() -> String? {
        guard let url = URL(string: baseURL + "/metrics") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: healthTimeout)
        request.httpMethod = "GET"

        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { data, _, _ in
            if let data {
                result = String(data: data, encoding: .utf8)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + healthTimeout + 2.0)
        return result
    }

    /// Get the sidecar configuration.
    public static func config() -> [String: Any]? {
        httpGet(path: "/config", timeout: healthTimeout)
    }

    /// Reload the VLM model without restarting the sidecar.
    public static func reloadModel() -> Bool {
        guard let result = httpPost(path: "/reload", body: [:], timeout: 30.0) else {
            return false
        }
        return result["status"] as? String == "success"
    }

    // MARK: - Sidecar Lifecycle

    /// Attempt to start the vision sidecar process.
    /// Looks for `oracle-vision` launcher script, then falls back to running server.py directly.
    /// Uses a state machine to prevent concurrent double-start attempts.
    @discardableResult
    public static func startSidecar() -> Bool {
        // Check if already running
        if isAvailable() {
            lifecycle.state = .ready
            Log.info("Vision sidecar already running")
            return true
        }

        // Atomically claim the starting transition; if another caller is already
        // starting, wait for that attempt to finish instead of double-starting.
        guard lifecycle.transition(from: .stopped, to: .starting)
            || lifecycle.transition(from: .failed, to: .starting) else {
            // Another start is in progress — wait for it.
            if lifecycle.state == .starting {
                Log.info("Vision sidecar start already in progress, waiting...")
                if waitForSidecar() {
                    // Re-check state after waiting — another thread may have moved it.
                    return lifecycle.state == .ready || isAvailable()
                }
            }
            // If state is .ready, we're good
            if lifecycle.state == .ready { return true }
            return false
        }

        // Strategy 1: Use oracle-vision launcher script (handles venv/Python resolution)
        if let launcher = findOracleVisionBinary() {
            Log.info("Starting vision sidecar via \(launcher)")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launcher)
            process.arguments = ["--idle-timeout", "600"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.standardError

            do {
                try process.run()
                lifecycle.process = process
            } catch {
                Log.error("Failed to start vision sidecar via launcher: \(error)")
                lifecycle.state = .failed
                return false
            }

            if waitForSidecar() {
                lifecycle.state = .ready
                Log.info("Vision sidecar started (PID \(process.processIdentifier))")
                return true
            }
            lifecycle.state = .failed
            Log.warn("Vision sidecar launched but not responding after 10s")
            return false
        }

        // Strategy 2: Run server.py directly with best available Python
        if let script = findServerScript() {
            Log.info("Starting vision sidecar from \(script)")

            guard let python = findPython() else {
                Log.warn("No Python with mlx_vlm found — cannot start vision sidecar")
                lifecycle.state = .failed
                return false
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [script, "--idle-timeout", "600"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.standardError

            do {
                try process.run()
                lifecycle.process = process
            } catch {
                Log.error("Failed to start vision sidecar: \(error)")
                lifecycle.state = .failed
                return false
            }

            if waitForSidecar() {
                lifecycle.state = .ready
                Log.info("Vision sidecar started (PID \(process.processIdentifier))")
                return true
            }
            lifecycle.state = .failed
            Log.warn("Vision sidecar launched but not responding after 10s")
            return false
        }

        lifecycle.state = .failed
        Log.warn("Could not find or start vision sidecar")
        return false
    }

    /// Wait for the sidecar to become responsive (up to 10 seconds).
    private static func waitForSidecar() -> Bool {
        for _ in 0..<100 {
            Thread.sleep(forTimeInterval: 0.1)
            if isAvailable() {
                return true
            }
        }
        Log.warn("Vision sidecar started but not responding after 10s")
        return false
    }

    /// Find the oracle-vision launcher script/binary.
    private static func findOracleVisionBinary() -> String? {
        let executableDirectory = (ProcessInfo.processInfo.arguments[0] as NSString).deletingLastPathComponent
        let candidates: [String] = [
            OracleProductPaths.visionInstallDirectory.appendingPathComponent("oracle-vision", isDirectory: false).path,
            OracleProductPaths.bundledVisionBootstrapDirectory?.appendingPathComponent("oracle-vision", isDirectory: false).path,
            "/opt/homebrew/bin/oracle-vision",
            "/usr/local/bin/oracle-vision",
            executableDirectory + "/oracle-vision",
            executableDirectory + "/../vision-sidecar/oracle-vision",
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Find the server.py script in expected locations.
    private static func findServerScript() -> String? {
        let executableDirectory = (ProcessInfo.processInfo.arguments[0] as NSString).deletingLastPathComponent
        let bundledVisionDirectory = OracleProductPaths.bundledVisionBootstrapDirectory
        let candidates: [String] = [
            OracleProductPaths.visionInstallDirectory.appendingPathComponent("server.py", isDirectory: false).path,
            bundledVisionDirectory?.appendingPathComponent("server.py", isDirectory: false).path,
            "/opt/homebrew/share/oracle-os/vision-sidecar/server.py",
            "/usr/local/share/oracle-os/vision-sidecar/server.py",
            executableDirectory + "/vision-sidecar/server.py",
            (executableDirectory as NSString).deletingLastPathComponent + "/vision-sidecar/server.py",
            ((executableDirectory as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent + "/vision-sidecar/server.py",
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Find the best Python executable with mlx_vlm available.
    /// Returns nil if no suitable Python is found.
    private static func findPython() -> String? {
        // Check venv first (most likely to have mlx_vlm)
        let candidates = [
            OracleProductPaths.visionInstallDirectory
                .appendingPathComponent(".venv/bin/python3", isDirectory: false)
                .path,
            NSHomeDirectory() + "/.oracle-os/venv/bin/python3",
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        // Homebrew Python
        for path in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    // MARK: - Model Path Resolution

    /// Check if the ShowUI-2B model exists at any known location.
    /// Returns the path if found, nil otherwise.
    public static func findModelPath() -> String? {
        let candidates = [
            OracleProductPaths.visionModelDirectory.path,
            "/opt/homebrew/share/oracle-os/models/ShowUI-2B",
            NSHomeDirectory() + "/.oracle-os/models/ShowUI-2B",
            NSHomeDirectory() + "/.oracle-os/models/llm/ShowUI-2B-bf16-8bit",
        ]

        for path in candidates {
            let safetensors = (path as NSString).appendingPathComponent("model.safetensors")
            let config = (path as NSString).appendingPathComponent("config.json")
            if FileManager.default.fileExists(atPath: safetensors)
                && FileManager.default.fileExists(atPath: config)
            {
                return path
            }
        }
        return nil
    }

    // MARK: - HTTP Helpers

    /// Synchronous HTTP GET. Returns parsed JSON or nil.
    private static func httpGet(path: String, timeout: TimeInterval) -> [String: Any]? {
        guard let url = URL(string: baseURL + path) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"

        return performRequest(request)
    }

    /// Synchronous HTTP POST with JSON body. Returns parsed JSON or nil.
    private static func httpPost(
        path: String,
        body: [String: Any],
        timeout: TimeInterval
    ) -> [String: Any]? {
        guard let url = URL(string: baseURL + path) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            Log.error("Vision: Failed to serialize request body")
            return nil
        }
        request.httpBody = jsonData

        return performRequest(request)
    }

    /// Perform a synchronous URLSession request. Blocks the calling thread
    /// using a semaphore (acceptable since MCP server is single-threaded).
    private static func performRequest(_ request: URLRequest) -> [String: Any]? {
        let semaphore = DispatchSemaphore(value: 0)

        // Use nonisolated Sendable box to shuttle data across the closure boundary.
        // The class must be nonisolated to escape @MainActor default isolation,
        // since the URLSession completion handler runs on a background thread.
        nonisolated final class ResponseBox: @unchecked Sendable {
            var data: Data?
            var error: (any Error)?
        }
        let box = ResponseBox()

        // Use a detached session to avoid MainActor issues
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { data, _, error in
            box.data = data
            box.error = error
            semaphore.signal()
        }
        task.resume()

        // Bounded wait: use the URLRequest's own timeout + 5s grace period.
        // This prevents indefinite blocking when called from @MainActor context
        // (e.g. ObservationBuilder → VisionScanner → VisionBridge).
        let deadline = DispatchTime.now() + request.timeoutInterval + 5.0
        let waitResult = semaphore.wait(timeout: deadline)
        if waitResult == .timedOut {
            task.cancel()
            Log.warn("Vision HTTP request timed out (semaphore deadline exceeded)")
            return nil
        }

        if let error = box.error {
            // Don't log connection refused as error — sidecar might not be running
            let nsError = error as NSError
            if nsError.code == NSURLErrorCannotConnectToHost ||
               nsError.code == NSURLErrorTimedOut ||
               nsError.code == NSURLErrorNetworkConnectionLost
            {
                Log.debug("Vision sidecar not reachable: \(error.localizedDescription)")
            } else {
                Log.warn("Vision HTTP error: \(error.localizedDescription)")
            }
            return nil
        }

        guard let data = box.data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return json
    }
}
