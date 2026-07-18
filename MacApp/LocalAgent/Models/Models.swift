import Foundation

struct AgentTask: Identifiable, Codable, Hashable {
    let id: String
    var userId: String
    var title: String
    var runtimeSessionId: String
    var modelName: String
    var skills: [String]
    var mcpServers: [String]
    var guardrailEnabled: Bool
    var memoryEnabled: Bool
    var pinned: Bool
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case runtimeSessionId = "runtime_session_id"
        case modelName = "model_name"
        case skills
        case mcpServers = "mcp_servers"
        case guardrailEnabled = "guardrail_enabled"
        case memoryEnabled = "memory_enabled"
        case pinned
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ToolEvent: Identifiable, Codable, Hashable {
    var type: String
    var tool: String?
    var input: AnyCodable?
    var toolUseId: String?
    var data: String?

    var id: String {
        if let toolUseId, !toolUseId.isEmpty {
            return "\(type)-\(toolUseId)"
        }
        if let tool, !tool.isEmpty {
            return "\(type)-\(tool)-\(data?.count ?? 0)"
        }
        if let data, !data.isEmpty {
            return "\(type)-\(data.hashValue)"
        }
        return type
    }

    enum CodingKeys: String, CodingKey {
        case type, tool, input, data
        case toolUseId = "toolUseId"
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    let id: String
    var taskId: String
    var role: String
    var content: String
    var images: [String]
    var toolEvents: [ToolEvent]
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case role, content, images
        case toolEvents = "tool_events"
        case createdAt = "created_at"
    }
}

struct AppConfig: Codable {
    var projectName: String
    var skills: [String]
    var mcpServers: [String]
    var models: [String]
    var defaultModel: String
    var defaultSkills: [String]
    var defaultMcpServers: [String]

    enum CodingKeys: String, CodingKey {
        case projectName
        case skills
        case mcpServers = "mcp_servers"
        case models
        case defaultModel = "default_model"
        case defaultSkills = "default_skills"
        case defaultMcpServers = "default_mcp_servers"
    }
}

struct SessionResponse: Codable {
    var userId: String
    enum CodingKeys: String, CodingKey { case userId = "user_id" }
}

struct TasksResponse: Codable {
    var tasks: [AgentTask]
}

struct MessagesResponse: Codable {
    var messages: [ChatMessage]
}

struct FileUploadResult: Codable {
    var ok: Bool
    var fileName: String
    var path: String?
    var s3Key: String?
    var url: String
    var contentType: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case fileName = "file_name"
        case path, url
        case s3Key = "s3_key"
        case contentType = "content_type"
    }
}

struct StreamEvent: Codable {
    var type: String
    var data: String?
    var content: String?
    var images: [String]?
    var toolEvents: [ToolEvent]?
    var tool: String?
    var input: AnyCodable?
    var toolUseId: String?

    enum CodingKeys: String, CodingKey {
        case type, data, content, images, tool, input
        case toolEvents = "tool_events"
        case toolUseId = "toolUseId"
    }
}

/// Minimal JSON value wrapper for tool inputs.
struct AnyCodable: Codable, Hashable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let b as Bool:
            try container.encode(b)
        case let i as Int:
            try container.encode(i)
        case let d as Double:
            try container.encode(d)
        case let s as String:
            try container.encode(s)
        case let arr as [Any]:
            try container.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encode(String(describing: value))
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }

    var displayString: String {
        if let s = value as? String { return s }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return String(describing: value)
    }
}

enum ServerStatus: Equatable {
    case offline
    case starting
    case ready
    case error(String)

    var label: String {
        switch self {
        case .offline: return "Offline"
        case .starting: return "Starting…"
        case .ready: return "Ready"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
