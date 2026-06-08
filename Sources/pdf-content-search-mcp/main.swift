import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Stdio ↔ HTTP Bridge for PDF Content Search MCP server.
// Claude Desktop's file-based mcpServers schema accepts only stdio — this
// tool reads JSON-RPC from stdin, forwards each message to the app's HTTP
// endpoint at http://127.0.0.1:<PORT>/mcp with a Bearer token, and writes
// the response to stdout as newline-delimited JSON.
//
// Configuration via environment variables (set by the MCP client config):
//   PDF_CS_TOKEN : Bearer token matching the app's API server token (required)
//   PDF_CS_PORT  : port number (default: 44477)
//   PDF_CS_HOST  : host (default: 127.0.0.1)
//
// Behavior:
// - First "initialize" response's Mcp-Session-Id header is cached and
//   attached to all subsequent HTTP requests.
// - Notifications (no "id") receive a 202 Accepted and produce no stdout
//   output, matching the MCP stdio transport spec.
// - Transport errors surface as JSON-RPC error responses so the client can
//   display them instead of getting stuck.

enum BridgeError: Error {
    case missingToken
    case invalidUrl
}

struct Config {
    let host: String
    let port: Int
    let token: String

    static func fromEnvironment() throws -> Config {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["PDF_CS_TOKEN"], !token.isEmpty else {
            throw BridgeError.missingToken
        }
        let host = env["PDF_CS_HOST"] ?? "127.0.0.1"
        let port = Int(env["PDF_CS_PORT"] ?? "44477") ?? 44477
        return Config(host: host, port: port, token: token)
    }

    var endpoint: URL? {
        URL(string: "http://\(host):\(port)/mcp")
    }
}

final class Bridge {
    private let config: Config
    private let session: URLSession
    private var sessionId: String?
    private let stderr = FileHandle.standardError
    private let stdout = FileHandle.standardOutput

    init(config: Config) {
        self.config = config
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: c)
    }

    func run() {
        let input = FileHandle.standardInput
        var buffer = Data()

        while true {
            let chunk = input.availableData
            if chunk.isEmpty {
                return
            }
            buffer.append(chunk)

            // newline-delimited JSON: drain complete lines
            while let newlineIdx = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: 0..<newlineIdx)
                buffer.removeSubrange(0...newlineIdx)
                if line.isEmpty { continue }
                handle(line: line)
            }
        }
    }

    private func handle(line: Data) {
        // Extract "id" upfront for error fallback (may be missing = notification).
        let extractedId = extractRequestId(from: line)

        guard let url = config.endpoint else {
            emitError(id: extractedId, code: -32603, message: "Internal bridge error: invalid endpoint URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        if let sid = sessionId {
            request.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = line

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var httpResponse: HTTPURLResponse?
        var transportError: Error?

        let task = session.dataTask(with: request) { data, response, error in
            responseData = data
            httpResponse = response as? HTTPURLResponse
            transportError = error
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let error = transportError {
            emitError(id: extractedId, code: -32000,
                      message: "Cannot reach PDF Content Search: \(error.localizedDescription). Is the app running and API server enabled?")
            return
        }

        guard let resp = httpResponse else {
            emitError(id: extractedId, code: -32603, message: "No HTTP response")
            return
        }

        if let sid = resp.value(forHTTPHeaderField: "Mcp-Session-Id"), !sid.isEmpty {
            sessionId = sid
        }

        // 202 Accepted = notification ack, no body to forward
        if resp.statusCode == 202 {
            return
        }

        if resp.statusCode == 401 {
            emitError(id: extractedId, code: -32001,
                      message: "Authentication failed: invalid API token. Re-run the Claude Desktop setup in PDF Content Search preferences.")
            return
        }

        if resp.statusCode == 404, let sid = sessionId {
            // Session expired — drop cached ID and tell client to re-initialize
            sessionId = nil
            emitError(id: extractedId, code: -32001,
                      message: "MCP session expired (was: \(sid)). Client should send 'initialize' again.")
            return
        }

        guard let data = responseData, !data.isEmpty else {
            if resp.statusCode >= 400 {
                emitError(id: extractedId, code: -32603, message: "HTTP \(resp.statusCode) with empty body")
            }
            return
        }

        // Pass through verbatim + newline terminator.
        var out = data
        out.append(0x0A)
        stdout.write(out)
    }

    private func extractRequestId(from data: Data) -> Any? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let dict = obj as? [String: Any] { return dict["id"] }
        if let arr = obj as? [Any], let first = arr.first as? [String: Any] { return first["id"] }
        return nil
    }

    private func emitError(id: Any?, code: Int, message: String) {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message],
        ]
        if let id = id {
            response["id"] = id
        } else {
            response["id"] = NSNull()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return }
        var out = data
        out.append(0x0A)
        stdout.write(out)
    }

    private func log(_ message: String) {
        if let data = "[pdf-content-search-mcp] \(message)\n".data(using: .utf8) {
            stderr.write(data)
        }
    }
}

do {
    let config = try Config.fromEnvironment()
    Bridge(config: config).run()
} catch BridgeError.missingToken {
    FileHandle.standardError.write(Data("PDF_CS_TOKEN environment variable is required.\n".utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("Failed to start: \(error)\n".utf8))
    exit(1)
}
