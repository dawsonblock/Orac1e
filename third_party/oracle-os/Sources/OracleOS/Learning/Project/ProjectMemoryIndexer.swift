import Foundation
import SQLite3

public final class ProjectMemoryIndexer: @unchecked Sendable {
    private var db: OpaquePointer?
    private let databaseURL: URL

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw NSError(domain: "ProjectMemoryIndexer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to open project memory index at \(databaseURL.path)",
            ])
        }

        try execute("""
        CREATE TABLE IF NOT EXISTS project_memory_records (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            knowledge_class TEXT NOT NULL,
            status TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT NOT NULL,
            affected_modules TEXT NOT NULL,
            evidence_refs TEXT NOT NULL,
            source_trace_ids TEXT NOT NULL,
            path TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """)
        try? execute("ALTER TABLE project_memory_records ADD COLUMN knowledge_class TEXT NOT NULL DEFAULT 'reusable';")
    }

    deinit {
        sqlite3_close(db)
    }

    public func rebuild(from rootURLs: [URL]) {
        try? execute("DELETE FROM project_memory_records;")

        let fileManager = FileManager.default
        for rootURL in rootURLs {
            guard fileManager.fileExists(atPath: rootURL.path),
                  let enumerator = fileManager.enumerator(
                      at: rootURL,
                      includingPropertiesForKeys: [.isRegularFileKey],
                      options: [.skipsHiddenFiles]
                  )
            else {
                continue
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "md" {
                guard let record = Self.parseRecord(fileURL: fileURL) else {
                    continue
                }
                upsert(record)
            }
        }
    }

    public func upsert(_ record: ProjectMemoryRecord) {
        let sql = """
        INSERT INTO project_memory_records (
            id, kind, knowledge_class, status, title, summary, affected_modules, evidence_refs,
            source_trace_ids, path, body, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            kind = excluded.kind,
            knowledge_class = excluded.knowledge_class,
            status = excluded.status,
            title = excluded.title,
            summary = excluded.summary,
            affected_modules = excluded.affected_modules,
            evidence_refs = excluded.evidence_refs,
            source_trace_ids = excluded.source_trace_ids,
            path = excluded.path,
            body = excluded.body,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at;
        """

        withStatement(sql) { statement in
            bind(record.id, to: 1, in: statement)
            bind(record.kind.rawValue, to: 2, in: statement)
            bind(record.knowledgeClass.rawValue, to: 3, in: statement)
            bind(record.status.rawValue, to: 4, in: statement)
            bind(record.title, to: 5, in: statement)
            bind(record.summary, to: 6, in: statement)
            bind(record.affectedModules.joined(separator: ","), to: 7, in: statement)
            bind(record.evidenceRefs.joined(separator: ","), to: 8, in: statement)
            bind(record.sourceTraceIDs.joined(separator: ","), to: 9, in: statement)
            bind(record.path, to: 10, in: statement)
            bind(record.body, to: 11, in: statement)
            sqlite3_bind_double(statement, 12, record.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 13, record.updatedAt.timeIntervalSince1970)
        }
    }

    public func query(
        text: String,
        modules: [String] = [],
        kinds: [ProjectMemoryKind] = [],
        limit: Int = 10
    ) -> [ProjectMemoryRef] {
        var clauses: [String] = []
        if !text.isEmpty {
            clauses.append("(title LIKE ? OR summary LIKE ? OR body LIKE ?)")
        }
        if !modules.isEmpty {
            clauses.append("(" + modules.map { _ in "affected_modules LIKE ?" }.joined(separator: " OR ") + ")")
        }
        if !kinds.isEmpty {
            clauses.append("(" + kinds.map { _ in "kind = ?" }.joined(separator: " OR ") + ")")
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = """
        SELECT id, kind, knowledge_class, status, title, summary, path, affected_modules, evidence_refs, source_trace_ids
        FROM project_memory_records
        \(whereClause)
        ORDER BY updated_at DESC
        LIMIT ?;
        """

        var params: [String] = []
        if !text.isEmpty {
            let pattern = "%\(text)%"
            params.append(contentsOf: [pattern, pattern, pattern])
        }
        if !modules.isEmpty {
            params.append(contentsOf: modules.map { "%\($0)%" })
        }
        if !kinds.isEmpty {
            params.append(contentsOf: kinds.map(\.rawValue))
        }

        var records: [ProjectMemoryRef] = []
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var index: Int32 = 1
        for param in params {
            bind(param, to: index, in: statement)
            index += 1
        }
        sqlite3_bind_int(statement, index, Int32(limit))

        while sqlite3_step(statement) == SQLITE_ROW {
            let kind = ProjectMemoryKind(rawValue: columnText(statement, index: 1) ?? "open-problem") ?? .openProblem
            let knowledgeClass = KnowledgeClass(rawValue: columnText(statement, index: 2) ?? "reusable") ?? .reusable
            let status = ProjectMemoryStatus(rawValue: columnText(statement, index: 3) ?? "draft") ?? .draft
            let ref = ProjectMemoryRef(
                id: columnText(statement, index: 0) ?? UUID().uuidString,
                kind: kind,
                knowledgeClass: knowledgeClass,
                status: status,
                title: columnText(statement, index: 4) ?? "Untitled",
                summary: columnText(statement, index: 5) ?? "",
                path: columnText(statement, index: 6) ?? "",
                affectedModules: split(columnText(statement, index: 7)),
                evidenceRefs: split(columnText(statement, index: 8)),
                sourceTraceIDs: split(columnText(statement, index: 9))
            )
            records.append(ref)
        }

        return records
    }

    public static func parseRecord(fileURL: URL) -> ProjectMemoryRecord? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        let lines = text.components(separatedBy: .newlines)
        guard let firstHeading = lines.first(where: { $0.hasPrefix("# ") }) else {
            return nil
        }

        var metadata: [String: String] = [:]
        var inMetadata = false
        for line in lines.drop(while: { !$0.hasPrefix("# ") }).dropFirst() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if inMetadata { break }
                continue
            }
            if line.hasPrefix("## ") {
                break
            }
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                inMetadata = true
                metadata[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }

        let kind = ProjectMemoryKind(rawValue: metadata["kind"] ?? "open-problem") ?? .openProblem
        let knowledgeClass = KnowledgeClass(rawValue: metadata["knowledge_class"] ?? "reusable") ?? .reusable
        let status = ProjectMemoryStatus(rawValue: metadata["status"] ?? "draft") ?? .draft
        let id = metadata["id"] ?? fileURL.deletingPathExtension().lastPathComponent
        let createdAt = ISO8601DateFormatter().date(from: metadata["created_at"] ?? "") ?? Date()
        let updatedAt = ISO8601DateFormatter().date(from: metadata["updated_at"] ?? "") ?? createdAt

        return ProjectMemoryRecord(
            id: id,
            kind: kind,
            knowledgeClass: knowledgeClass,
            status: status,
            title: firstHeading.replacingOccurrences(of: "# ", with: "").trimmingCharacters(in: .whitespaces),
            summary: metadata["summary"] ?? "",
            affectedModules: split(metadata["affected_modules"]),
            evidenceRefs: split(metadata["evidence_refs"]),
            sourceTraceIDs: split(metadata["source_trace_ids"]),
            createdAt: createdAt,
            updatedAt: updatedAt,
            path: fileURL.path,
            body: text
        )
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(errorMessage)
            throw NSError(domain: "ProjectMemoryIndexer", code: 2, userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }
    }

    private func withStatement(_ sql: String, bindAndStep: (OpaquePointer) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return
        }
        defer { sqlite3_finalize(statement) }
        bindAndStep(statement)
        sqlite3_step(statement)
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }
}

private func split(_ value: String?) -> [String] {
    guard let value, !value.isEmpty else { return [] }
    return value
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}
