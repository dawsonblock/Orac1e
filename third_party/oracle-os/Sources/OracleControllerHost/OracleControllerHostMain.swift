import Foundation
import OracleControllerShared

@main
struct OracleControllerHostMain {
    static func main() async {
        let output = HostOutput()
        let bridge = await MainActor.run { ControllerRuntimeBridge() }
        let server = ControllerHostServer(output: output, bridge: bridge)
        let decoder = ControllerJSONCoding.makeDecoder()

        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                guard let data = line.data(using: .utf8), !data.isEmpty else {
                    continue
                }

                do {
                    let request = try decoder.decode(ControllerHostRequest.self, from: data)
                    await server.handle(request)
                } catch {
                    await output.send(response: ControllerHostResponse(
                        requestID: UUID().uuidString,
                        command: .ping,
                        acknowledged: false,
                        errorMessage: "Failed to decode request: \(error.localizedDescription)"
                    ))
                }
            }
        } catch {
            await output.send(response: ControllerHostResponse(
                requestID: UUID().uuidString,
                command: .ping,
                acknowledged: false,
                errorMessage: "Host input stream failed: \(error.localizedDescription)"
            ))
        }
    }
}
