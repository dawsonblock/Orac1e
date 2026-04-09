import Foundation
import Testing
@testable import OracleOS

@Suite("Claude Config")
struct ClaudeConfigTests {

    @Test("Typed Claude config round-trips and preserves unknown fields")
    func configRoundTripsDeterministically() throws {
        let root = makeTempDirectory()
        let configURL = root.appendingPathComponent(".claude.json", isDirectory: false)
        let source = """
        {
          "mcpServers": {
            "existing": {
              "type": "stdio",
              "command": "/usr/bin/existing",
              "args": ["serve"],
              "timeout": 30
            }
          },
          "allowedTools": ["existing-tool"],
          "theme": "dark"
        }
        """
        try source.write(to: configURL, atomically: true, encoding: .utf8)

        var config = try #require(try ClaudeConfigStore.loadIfPresent(from: configURL))
        config = config.withServer(
            named: "oracle-os",
            server: ClaudeMCPServer(type: "stdio", command: "/usr/local/bin/oracle", args: ["mcp"])
        )
        config = config.withAllowedTool("mcp__oracle-os__*")
        try ClaudeConfigStore.save(config, to: configURL)

        let decoded = try #require(try ClaudeConfigStore.loadIfPresent(from: configURL))
        #expect(decoded.server(named: "oracle-os")?.command == "/usr/local/bin/oracle")
        #expect(decoded.server(named: "existing")?.additionalFields["timeout"] == .number(30))
        #expect(decoded.additionalFields["theme"] == .string("dark"))
        #expect(decoded.allowedTools == ["existing-tool", "mcp__oracle-os__*"])

        let saved = try String(contentsOf: configURL, encoding: .utf8)
        #expect(saved.contains("\"theme\" : \"dark\""))
        #expect(saved.contains("\"oracle-os\""))
    }
}