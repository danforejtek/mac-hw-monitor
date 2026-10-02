import Foundation

struct OllamaModel: Identifiable, Equatable, Decodable {
    struct Details: Decodable, Equatable {
        let parameter_size: String?
        let quantization_level: String?
        let family: String?
    }
    let name: String
    let size: UInt64
    let size_vram: UInt64?
    let expires_at: String?
    let details: Details?
    var id: String { name }

    /// Fraction of the model resident in GPU memory (Ollama reports CPU offload via size vs size_vram).
    var gpuFraction: Double { size > 0 ? Double(size_vram ?? 0) / Double(size) : 0 }
    var expiresAt: Date? {
        guard let s = expires_at else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

struct OllamaStatus: Equatable {
    var reachable = false
    var version: String?
    var models: [OllamaModel] = []
    var error: String?
}

/// Polls the local Ollama HTTP API (`/api/ps`, `/api/version`).
final class OllamaClient {
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 1.5
        c.timeoutIntervalForResource = 2
        return URLSession(configuration: c)
    }()

    func fetch(baseURL: String) async -> OllamaStatus {
        var status = OllamaStatus()
        guard let base = URL(string: baseURL) else { status.error = "Invalid URL"; return status }
        do {
            let (vData, _) = try await session.data(from: base.appendingPathComponent("api/version"))
            status.version = (try? JSONDecoder().decode([String: String].self, from: vData))?["version"]
            let (pData, _) = try await session.data(from: base.appendingPathComponent("api/ps"))
            struct PS: Decodable { let models: [OllamaModel]? }
            status.models = (try JSONDecoder().decode(PS.self, from: pData)).models ?? []
            status.reachable = true
        } catch {
            status.reachable = false
            status.error = (error as? URLError)?.code == .cannotConnectToHost ? "Not running" : error.localizedDescription
        }
        return status
    }
}
