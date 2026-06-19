import Foundation

public final class ApprovalStore: @unchecked Sendable {
    private let rootDirectory: URL
    private let requestsDirectory: URL
    private let receiptsDirectory: URL
    private let stateDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        self.requestsDirectory = rootDirectory.appendingPathComponent("requests", isDirectory: true)
        self.receiptsDirectory = rootDirectory.appendingPathComponent("receipts", isDirectory: true)
        self.stateDirectory = rootDirectory.appendingPathComponent("state", isDirectory: true)

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        try? FileManager.default.createDirectory(at: requestsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: receiptsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    }

    public convenience init() {
        self.init(rootDirectory: OracleProductPaths.approvalsDirectory)
    }

    public func isActive() -> Bool {
        FileManager.default.fileExists(atPath: rootDirectory.path)
    }

    public func createRequest(_ request: ApprovalRequest) throws -> ApprovalRequest {
        let fileURL = requestFileURL(for: request.id)
        let data = try encoder.encode(request)
        try data.write(to: fileURL)
        return request
    }

    public func listPendingRequests() -> [ApprovalRequest] {
        loadRequests().filter { $0.status == .pending }.sorted { $0.createdAt < $1.createdAt }
    }

    public func approve(requestID: String) throws -> ApprovalReceipt {
        let request = try loadRequest(id: requestID)
        let approved = ApprovalRequest(
            id: request.id,
            createdAt: request.createdAt,
            surface: request.surface,
            toolName: request.toolName,
            appName: request.appName,
            displayTitle: request.displayTitle,
            reason: request.reason,
            riskLevel: request.riskLevel,
            protectedOperation: request.protectedOperation,
            actionFingerprint: request.actionFingerprint,
            appProtectionProfile: request.appProtectionProfile,
            status: .approved
        )
        try encoder.encode(approved).write(to: requestFileURL(for: requestID))

        let receipt = ApprovalReceipt(requestID: requestID, actionFingerprint: request.actionFingerprint)
        try encoder.encode(receipt).write(to: receiptFileURL(for: requestID))
        return receipt
    }

    public func reject(requestID: String) throws {
        let request = try loadRequest(id: requestID)
        let rejected = ApprovalRequest(
            id: request.id,
            createdAt: request.createdAt,
            surface: request.surface,
            toolName: request.toolName,
            appName: request.appName,
            displayTitle: request.displayTitle,
            reason: request.reason,
            riskLevel: request.riskLevel,
            protectedOperation: request.protectedOperation,
            actionFingerprint: request.actionFingerprint,
            appProtectionProfile: request.appProtectionProfile,
            status: .rejected
        )
        try encoder.encode(rejected).write(to: requestFileURL(for: requestID))
        try? FileManager.default.removeItem(at: receiptFileURL(for: requestID))
    }

    public func consumeApprovedReceipt(requestID: String, actionFingerprint: String) -> ApprovalReceipt? {
        let fileURL = receiptFileURL(for: requestID)
        guard let data = try? Data(contentsOf: fileURL),
              let receipt = try? decoder.decode(ApprovalReceipt.self, from: data),
              receipt.actionFingerprint == actionFingerprint
        else {
            return nil
        }

        try? FileManager.default.removeItem(at: fileURL)

        if let request = try? loadRequest(id: requestID) {
            let executed = ApprovalRequest(
                id: request.id,
                createdAt: request.createdAt,
                surface: request.surface,
                toolName: request.toolName,
                appName: request.appName,
                displayTitle: request.displayTitle,
                reason: request.reason,
                riskLevel: request.riskLevel,
                protectedOperation: request.protectedOperation,
                actionFingerprint: request.actionFingerprint,
                appProtectionProfile: request.appProtectionProfile,
                status: .executed
            )
            try? encoder.encode(executed).write(to: requestFileURL(for: requestID))
        }

        return ApprovalReceipt(
            requestID: receipt.requestID,
            approvedAt: receipt.approvedAt,
            actionFingerprint: receipt.actionFingerprint,
            approvedBy: receipt.approvedBy,
            consumed: true
        )
    }

    public func writeControllerHeartbeat(sessionID: String) {
        let state = [
            "session_id": sessionID,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
            try? data.write(to: controllerHeartbeatFileURL())
        }
    }

    public func controllerConnected(maxAgeSeconds: TimeInterval = 10) -> Bool {
        let fileURL = controllerHeartbeatFileURL()
        guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
              let modifiedAt = values.contentModificationDate
        else {
            return false
        }

        return Date().timeIntervalSince(modifiedAt) <= maxAgeSeconds
    }

    private func loadRequests() -> [ApprovalRequest] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: requestsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ApprovalRequest.self, from: data)
        }
    }

    private func loadRequest(id: String) throws -> ApprovalRequest {
        let fileURL = requestFileURL(for: id)
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(ApprovalRequest.self, from: data)
    }

    private func requestFileURL(for id: String) -> URL {
        requestsDirectory.appendingPathComponent("\(id).json")
    }

    private func receiptFileURL(for id: String) -> URL {
        receiptsDirectory.appendingPathComponent("\(id).json")
    }

    private func controllerHeartbeatFileURL() -> URL {
        stateDirectory.appendingPathComponent("controller-heartbeat.json")
    }
}
