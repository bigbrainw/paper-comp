import Foundation

struct ModelCatalogEntry: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let shortName: String
    let downloadURL: String
    let fileName: String
    let byteSize: Int64
    let isDefault: Bool
    var usesThinking: Bool
    var mayExceedMemoryOn8GB: Bool
    var nCtx: Int
    var note: String?
    var projectorURL: String?
    var projectorFileName: String?
    var projectorByteSize: Int64?
    var promptFormat: PromptFormat?

    static let gemmaE2BId = "gemma4-e2b-q4"
    static let qwen17BId = "qwen3-1.7b-q4"

    init(
        id: String,
        name: String,
        shortName: String,
        downloadURL: String,
        fileName: String,
        byteSize: Int64,
        isDefault: Bool,
        usesThinking: Bool = false,
        mayExceedMemoryOn8GB: Bool = false,
        nCtx: Int = 4096,
        note: String? = nil,
        projectorURL: String? = nil,
        projectorFileName: String? = nil,
        projectorByteSize: Int64? = nil,
        promptFormat: PromptFormat? = nil
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.downloadURL = downloadURL
        self.fileName = fileName
        self.byteSize = byteSize
        self.isDefault = isDefault
        self.usesThinking = usesThinking
        self.mayExceedMemoryOn8GB = mayExceedMemoryOn8GB
        self.nCtx = nCtx
        self.note = note
        self.projectorURL = projectorURL
        self.projectorFileName = projectorFileName
        self.projectorByteSize = projectorByteSize
        self.promptFormat = promptFormat
    }

    var downloadURLValue: URL { URL(string: downloadURL)! }
    var projectorURLValue: URL? { projectorURL.flatMap(URL.init(string:)) }
    var hasVision: Bool { projectorURL != nil && projectorFileName != nil }

    /// E2B / 1.7B class: fine for terms, weak at teaching.
    var isSmallModel: Bool {
        id == Self.gemmaE2BId || id == Self.qwen17BId
            || id.localizedCaseInsensitiveContains("e2b")
            || id.localizedCaseInsensitiveContains("1.7b")
    }

    var totalByteSize: Int64 { byteSize + (projectorByteSize ?? 0) }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalByteSize, countStyle: .file)
    }

    var formattedProjectorSize: String {
        ByteCountFormatter.string(fromByteCount: projectorByteSize ?? 0, countStyle: .file)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, shortName, downloadURL, fileName, byteSize, isDefault
        case usesThinking, mayExceedMemoryOn8GB, nCtx, note
        case projectorURL, projectorFileName, projectorByteSize, promptFormat
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        shortName = try container.decode(String.self, forKey: .shortName)
        downloadURL = try container.decode(String.self, forKey: .downloadURL)
        fileName = try container.decode(String.self, forKey: .fileName)
        byteSize = try container.decode(Int64.self, forKey: .byteSize)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        usesThinking = try container.decodeIfPresent(Bool.self, forKey: .usesThinking) ?? false
        mayExceedMemoryOn8GB = try container.decodeIfPresent(Bool.self, forKey: .mayExceedMemoryOn8GB) ?? false
        nCtx = try container.decodeIfPresent(Int.self, forKey: .nCtx) ?? 4096
        note = try container.decodeIfPresent(String.self, forKey: .note)
        projectorURL = try container.decodeIfPresent(String.self, forKey: .projectorURL)
        projectorFileName = try container.decodeIfPresent(String.self, forKey: .projectorFileName)
        projectorByteSize = try container.decodeIfPresent(Int64.self, forKey: .projectorByteSize)
        promptFormat = try container.decodeIfPresent(PromptFormat.self, forKey: .promptFormat)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(shortName, forKey: .shortName)
        try container.encode(downloadURL, forKey: .downloadURL)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(byteSize, forKey: .byteSize)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(usesThinking, forKey: .usesThinking)
        try container.encode(mayExceedMemoryOn8GB, forKey: .mayExceedMemoryOn8GB)
        try container.encode(nCtx, forKey: .nCtx)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(projectorURL, forKey: .projectorURL)
        try container.encodeIfPresent(projectorFileName, forKey: .projectorFileName)
        try container.encodeIfPresent(projectorByteSize, forKey: .projectorByteSize)
        try container.encodeIfPresent(promptFormat, forKey: .promptFormat)
    }
}

struct ModelCatalog: Codable, Equatable, Sendable {
    let models: [ModelCatalogEntry]

    static func loadBundled() throws -> ModelCatalog {
        guard let url = Bundle.main.url(forResource: "ModelCatalog", withExtension: "json") else {
            throw ModelCatalogError.missingResource
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ModelCatalog.self, from: data)
    }

    var defaultModel: ModelCatalogEntry? {
        models.first(where: \.isDefault) ?? models.first
    }

    func entry(id: String) -> ModelCatalogEntry? {
        models.first { $0.id == id }
    }
}

enum ModelCatalogError: Error {
    case missingResource
}
