/// 生图、生视频源码适配器协议与内置 OpenAI 实现。

import Foundation

/// 适配器暴露给节点检查器的请求字段说明，不包含任何密钥值。
struct MediaAdapterFieldDescriptor: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var help: String
    var example: String
    var isRequired: Bool
}

/// 单个生视频模型的内置能力，避免向服务商提交未知或不兼容的付费任务。
struct VideoModelCapability: Identifiable, Hashable, Sendable {
    var id: String { model }
    var model: String
    var displayName: String
    var aspectRatios: [String]
    var resolutions: [String]
    var durations: [Int]
    var supportsAudioGeneration: Bool
    var maximumReferenceImages: Int
    var maximumReferenceVideos: Int
    var maximumReferenceAudios: Int
    /// PixMax 请求中的 `referModel`；空值表示由素材组合自动选择。
    var referenceMode: String?
}

/// 适配器提供给设置页、节点检查器和帮助页的能力描述。
struct MediaAdapterDescriptor: Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    var summary: String
    var endpointHint: String
    var configurationFields: [MediaAdapterFieldDescriptor]
    var supportedSizes: [String]
    var supportedDurations: [Int]
    var supportsReferenceImage: Bool
    var supportsImageEditing: Bool = false
    var supportsMaskImage: Bool = false
    var supportsReferenceVideo: Bool = false
    var supportsReferenceAudio: Bool = false
    var maximumReferenceImages: Int = 1
    var maximumReferenceVideos: Int = 0
    var maximumReferenceAudios: Int = 0
    var supportsAudioGeneration: Bool = false
    var modelCapabilities: [VideoModelCapability] = []
    var usageNotes: [String]

    /// 按服务商模型标识查询更精确的能力。
    func videoCapability(for model: String) -> VideoModelCapability? {
        modelCapabilities.first { $0.model == model }
    }
}

/// 媒体生成进度事件。
struct MediaGenerationProgress: Hashable, Sendable {
    var fraction: Double?
    var message: String
    var remoteJobID: String?
}

/// 已下载到本地运行目录的媒体产物。
struct MediaArtifact: Hashable, Sendable {
    var fileURL: URL
    var mimeType: String
    var remoteJobID: String?
    var additionalFileURLs: [URL] = []
    var warnings: [String] = []
}

/// 生图适配器的统一请求。
struct ImageGenerationRequest: Hashable, Sendable {
    var prompt: String
    var model: String
    var size: String
    var operation: WorkflowImageOperation = .generate
    var referenceImageURL: URL?
    var maskImageURL: URL?
}

/// 生视频适配器的统一请求。
struct VideoGenerationRequest: Hashable, Sendable {
    var prompt: String
    var model: String
    var aspectRatio: String
    var resolution: String
    var durationSeconds: Int
    var includeAudio: Bool
    var referenceImageURLs: [URL]
    var referenceVideoURLs: [URL]
    var referenceAudioURLs: [URL]

    init(
        prompt: String,
        model: String,
        aspectRatio: String,
        resolution: String,
        durationSeconds: Int,
        includeAudio: Bool,
        referenceImageURLs: [URL] = [],
        referenceVideoURLs: [URL] = [],
        referenceAudioURLs: [URL] = []
    ) {
        self.prompt = prompt
        self.model = model
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.durationSeconds = durationSeconds
        self.includeAudio = includeAudio
        self.referenceImageURLs = referenceImageURLs
        self.referenceVideoURLs = referenceVideoURLs
        self.referenceAudioURLs = referenceAudioURLs
    }

    /// 兼容旧单参考图调用；旧 `size` 映射为分辨率。
    init(
        prompt: String,
        model: String,
        size: String,
        durationSeconds: Int,
        referenceImageURL: URL?
    ) {
        self.init(
            prompt: prompt,
            model: model,
            aspectRatio: "auto",
            resolution: size,
            durationSeconds: durationSeconds,
            includeAudio: false,
            referenceImageURLs: referenceImageURL.map { [$0] } ?? []
        )
    }
}

/// 媒体适配器错误。
enum MediaGenerationError: LocalizedError {
    case invalidURL
    case unsupported(String)
    case invalidResponse(String)
    case http(Int, String)
    case missingArtifact
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidURL: "媒体服务 Base URL 无效"
        case .unsupported(let message): message
        case .invalidResponse(let message): "无法解析媒体响应：\(message)"
        case .http(let code, let body): "媒体接口 HTTP \(code)：\(body.prefix(300))"
        case .missingArtifact: "媒体接口未返回可下载的结果"
        case .timedOut: "媒体任务超过 30 分钟仍未完成"
        }
    }
}

/// 源码内生图协议适配器。
protocol ImageGenerationAdapter: Sendable {
    var descriptor: MediaAdapterDescriptor { get }

    func generate(
        request: ImageGenerationRequest,
        provider: ImageProvider,
        apiKey: String,
        outputDirectory: URL,
        progress: @escaping @Sendable (MediaGenerationProgress) async -> Void
    ) async throws -> MediaArtifact
}

/// 源码内生视频协议适配器。
protocol VideoGenerationAdapter: Sendable {
    var descriptor: MediaAdapterDescriptor { get }

    func generate(
        request: VideoGenerationRequest,
        provider: VideoProvider,
        apiKey: String,
        outputDirectory: URL,
        progress: @escaping @Sendable (MediaGenerationProgress) async -> Void
    ) async throws -> MediaArtifact
}

/// 内置源码适配器注册表。
struct MediaAdapterRegistry: Sendable {
    static let shared = MediaAdapterRegistry(
        imageAdapters: [OpenAIImageGenerationAdapter()],
        videoAdapters: [OpenAIVideoGenerationAdapter(), PixmaxVideoGenerationAdapter()]
    )

    private let imageAdapters: [String: any ImageGenerationAdapter]
    private let videoAdapters: [String: any VideoGenerationAdapter]

    init(
        imageAdapters: [any ImageGenerationAdapter],
        videoAdapters: [any VideoGenerationAdapter]
    ) {
        self.imageAdapters = Dictionary(uniqueKeysWithValues: imageAdapters.map { ($0.descriptor.id, $0) })
        self.videoAdapters = Dictionary(uniqueKeysWithValues: videoAdapters.map { ($0.descriptor.id, $0) })
    }

    /// 查找生图适配器。
    func imageAdapter(id: String) -> (any ImageGenerationAdapter)? { imageAdapters[id] }

    /// 查找生视频适配器。
    func videoAdapter(id: String) -> (any VideoGenerationAdapter)? { videoAdapters[id] }

    /// 全部已注册生图适配器描述。
    var imageDescriptors: [MediaAdapterDescriptor] {
        imageAdapters.values.map(\.descriptor).sorted { $0.displayName < $1.displayName }
    }

    /// 全部已注册生视频适配器描述。
    var videoDescriptors: [MediaAdapterDescriptor] {
        videoAdapters.values.map(\.descriptor).sorted { $0.displayName < $1.displayName }
    }
}

/// OpenAI Images `/images/generations` 与 `/images/edits` 适配器。
struct OpenAIImageGenerationAdapter: ImageGenerationAdapter {
    let descriptor = MediaAdapterDescriptor(
        id: ImageProvider.openAIAdapterID,
        displayName: "OpenAI Images",
        summary: "支持文生图与单图/遮罩编辑，并保存 Base64 或 URL 结果。",
        endpointHint: "POST /images/generations · POST /images/edits",
        configurationFields: [
            MediaAdapterFieldDescriptor(id: "prompt", title: "提示词", help: "文生图时描述画面；编辑时描述需要保留和修改的内容。", example: "保留人物，把背景改为雨夜霓虹街道", isRequired: true),
            MediaAdapterFieldDescriptor(id: "model", title: "模型", help: "从当前服务商维护的模型列表中选择。", example: "gpt-image-1", isRequired: true),
            MediaAdapterFieldDescriptor(id: "size", title: "尺寸", help: "必须使用适配器能力描述列出的尺寸。", example: "1024x1024", isRequired: true),
            MediaAdapterFieldDescriptor(id: "image", title: "原图", help: "图片编辑模式通过 multipart/form-data 的 image[] 上传。", example: "上游生图节点输出", isRequired: false),
            MediaAdapterFieldDescriptor(id: "mask", title: "遮罩", help: "可选 PNG 遮罩，需与原图同尺寸同格式且包含 alpha 通道。", example: "上游输出的透明遮罩 PNG", isRequired: false),
        ],
        supportedSizes: ImageProvider.availableSizes,
        supportedDurations: [],
        supportsReferenceImage: true,
        supportsImageEditing: true,
        supportsMaskImage: true,
        usageNotes: [
            "文生图使用 JSON 请求发送到 /images/generations。",
            "图片编辑使用 multipart/form-data 上传原图和可选遮罩到 /images/edits。",
            "结果会立即下载到本次运行的 Assets 目录。",
            "遮罩只作为编辑区域指引，模型不一定严格遵循每个像素边界。",
        ]
    )

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generate(
        request: ImageGenerationRequest,
        provider: ImageProvider,
        apiKey: String,
        outputDirectory: URL,
        progress: @escaping @Sendable (MediaGenerationProgress) async -> Void
    ) async throws -> MediaArtifact {
        try Task.checkCancellation()
        let urlRequest = try makeURLRequest(request: request, provider: provider, apiKey: apiKey)
        await progress(MediaGenerationProgress(
            fraction: nil,
            message: request.operation == .edit ? "正在编辑图片" : "正在生成图片"
        ))
        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)
        try Task.checkCancellation()

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["data"] as? [[String: Any]],
              let first = items.first
        else { throw MediaGenerationError.invalidResponse("缺少 data[0]") }

        let imageData: Data
        var mimeType = "image/png"
        if let base64 = first["b64_json"] as? String, let decoded = Data(base64Encoded: base64) {
            imageData = decoded
        } else if let value = first["url"] as? String, let remoteURL = URL(string: value) {
            let (downloaded, downloadResponse) = try await session.data(from: remoteURL)
            try validate(response: downloadResponse, data: downloaded)
            imageData = downloaded
            if let type = (downloadResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") {
                mimeType = type.components(separatedBy: ";").first ?? mimeType
            }
        } else {
            throw MediaGenerationError.missingArtifact
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let ext = fileExtension(for: mimeType, fallback: "png")
        let target = outputDirectory.appendingPathComponent("image-\(UUID().uuidString).\(ext)")
        try imageData.write(to: target, options: .atomic)
        await progress(MediaGenerationProgress(fraction: 1, message: "图片已保存"))
        return MediaArtifact(fileURL: target, mimeType: mimeType)
    }

    private func makeURLRequest(
        request: ImageGenerationRequest,
        provider: ImageProvider,
        apiKey: String
    ) throws -> URLRequest {
        switch request.operation {
        case .generate:
            let url = try endpoint(baseURL: provider.effectiveBaseURL, path: "images/generations")
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = 600
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": request.model,
                "prompt": request.prompt,
                "size": request.size,
                "n": 1,
            ])
            return urlRequest

        case .edit:
            guard let reference = request.referenceImageURL else {
                throw MediaGenerationError.unsupported("图片编辑必须提供原图")
            }
            let url = try endpoint(baseURL: provider.effectiveBaseURL, path: "images/edits")
            let boundary = "HeiNiuBoundary-\(UUID().uuidString)"
            var body = Data()
            appendMultipartField("model", value: request.model, boundary: boundary, to: &body)
            appendMultipartField("prompt", value: request.prompt, boundary: boundary, to: &body)
            appendMultipartField("size", value: request.size, boundary: boundary, to: &body)
            appendMultipartFile(
                "image[]",
                filename: reference.lastPathComponent,
                mimeType: imageMimeType(for: reference),
                data: try Data(contentsOf: reference),
                boundary: boundary,
                to: &body
            )
            if let mask = request.maskImageURL {
                appendMultipartFile(
                    "mask",
                    filename: mask.lastPathComponent,
                    mimeType: imageMimeType(for: mask),
                    data: try Data(contentsOf: mask),
                    boundary: boundary,
                    to: &body
                )
            }
            body.append(Data("--\(boundary)--\r\n".utf8))

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = 600
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = body
            return urlRequest
        }
    }
}

/// OpenAI Videos `/videos` 提交、轮询和下载适配器。
struct OpenAIVideoGenerationAdapter: VideoGenerationAdapter {
    let descriptor = MediaAdapterDescriptor(
        id: VideoProvider.openAIAdapterID,
        displayName: "OpenAI Videos",
        summary: "提交视频任务、轮询进度并下载 MP4。",
        endpointHint: "POST /videos · GET /videos/{id}",
        configurationFields: [
            MediaAdapterFieldDescriptor(id: "prompt", title: "提示词", help: "描述镜头、动作、场景、光线和节奏。", example: "人物推门进入，镜头缓慢前移", isRequired: true),
            MediaAdapterFieldDescriptor(id: "model", title: "模型", help: "从当前服务商维护的模型列表中选择。", example: "sora-2", isRequired: true),
            MediaAdapterFieldDescriptor(id: "size", title: "尺寸", help: "必须使用适配器能力描述列出的横竖屏尺寸。", example: "720x1280", isRequired: true),
            MediaAdapterFieldDescriptor(id: "seconds", title: "时长", help: "生成秒数必须来自适配器支持列表。", example: "8", isRequired: true),
            MediaAdapterFieldDescriptor(id: "input_reference", title: "参考图片", help: "可选首帧素材；通过 multipart/form-data 上传。", example: "上游生图节点输出", isRequired: false),
        ],
        supportedSizes: ["720x1280", "1280x720", "1024x1792", "1792x1024", "1080x1920", "1920x1080"],
        supportedDurations: [4, 8, 12, 16, 20],
        supportsReferenceImage: true,
        usageNotes: [
            "参考图片会作为 multipart/form-data 的 input_reference 上传。",
            "任务通常需要数分钟；应用以 10–20 秒间隔轮询。",
            "停止本地运行不会保证远端任务同时取消。",
        ]
    )

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generate(
        request: VideoGenerationRequest,
        provider: VideoProvider,
        apiKey: String,
        outputDirectory: URL,
        progress: @escaping @Sendable (MediaGenerationProgress) async -> Void
    ) async throws -> MediaArtifact {
        try Task.checkCancellation()
        let createURL = try endpoint(baseURL: provider.effectiveBaseURL, path: "videos")
        let boundary = "HeiNiuBoundary-\(UUID().uuidString)"
        var body = Data()
        appendField("model", value: request.model, boundary: boundary, to: &body)
        appendField("prompt", value: request.prompt, boundary: boundary, to: &body)
        appendField("size", value: request.resolution, boundary: boundary, to: &body)
        appendField("seconds", value: String(request.durationSeconds), boundary: boundary, to: &body)
        if let reference = request.referenceImageURLs.first {
            let data = try Data(contentsOf: reference)
            appendFile(
                "input_reference",
                filename: reference.lastPathComponent,
                mimeType: imageMimeType(for: reference),
                data: data,
                boundary: boundary,
                to: &body
            )
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        var create = URLRequest(url: createURL)
        create.httpMethod = "POST"
        create.timeoutInterval = 300
        create.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        create.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        create.httpBody = body

        await progress(MediaGenerationProgress(fraction: 0, message: "正在提交视频任务"))
        let (createData, createResponse) = try await session.data(for: create)
        try validate(response: createResponse, data: createData)
        var state = try parseVideoState(createData)
        let jobID = state.id
        await progress(MediaGenerationProgress(
            fraction: state.progress.map { $0 / 100 },
            message: state.status == "queued" ? "视频任务排队中" : "视频生成中",
            remoteJobID: jobID
        ))

        let deadline = Date().addingTimeInterval(30 * 60)
        var delaySeconds = 10.0
        while state.status == "queued" || state.status == "in_progress" {
            try Task.checkCancellation()
            guard Date() < deadline else { throw MediaGenerationError.timedOut }
            try await Task.sleep(for: .seconds(delaySeconds))
            let statusURL = try endpoint(baseURL: provider.effectiveBaseURL, path: "videos/\(jobID)")
            var statusRequest = URLRequest(url: statusURL)
            statusRequest.timeoutInterval = 60
            statusRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let (statusData, statusResponse) = try await session.data(for: statusRequest)
            try validate(response: statusResponse, data: statusData)
            state = try parseVideoState(statusData)
            await progress(MediaGenerationProgress(
                fraction: state.progress.map { $0 / 100 },
                message: state.status == "queued" ? "视频任务排队中" : "视频生成中",
                remoteJobID: jobID
            ))
            delaySeconds = min(20, delaySeconds * 1.35)
        }

        guard state.status == "completed" else {
            throw MediaGenerationError.invalidResponse(state.error ?? "视频任务状态：\(state.status)")
        }
        try Task.checkCancellation()
        await progress(MediaGenerationProgress(fraction: 0.98, message: "正在下载视频", remoteJobID: jobID))
        let contentURL = try endpoint(baseURL: provider.effectiveBaseURL, path: "videos/\(jobID)/content")
        var contentRequest = URLRequest(url: contentURL)
        contentRequest.timeoutInterval = 300
        contentRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (videoData, contentResponse) = try await session.data(for: contentRequest)
        try validate(response: contentResponse, data: videoData)

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let target = outputDirectory.appendingPathComponent("video-\(UUID().uuidString).mp4")
        try videoData.write(to: target, options: .atomic)
        await progress(MediaGenerationProgress(fraction: 1, message: "视频已保存", remoteJobID: jobID))
        return MediaArtifact(fileURL: target, mimeType: "video/mp4", remoteJobID: jobID)
    }

    private struct VideoState {
        var id: String
        var status: String
        var progress: Double?
        var error: String?
    }

    private func parseVideoState(_ data: Data) throws -> VideoState {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String,
              let status = object["status"] as? String
        else { throw MediaGenerationError.invalidResponse("缺少视频任务 id 或 status") }
        let progress = (object["progress"] as? NSNumber)?.doubleValue
        var errorMessage = object["error"] as? String
        if let error = object["error"] as? [String: Any] {
            errorMessage = error["message"] as? String ?? error["code"] as? String
        }
        return VideoState(id: id, status: status, progress: progress, error: errorMessage)
    }

    private func appendField(_ name: String, value: String, boundary: String, to data: inout Data) {
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        data.append(Data("\(value)\r\n".utf8))
    }

    private func appendFile(
        _ name: String,
        filename: String,
        mimeType: String,
        data fileData: Data,
        boundary: String,
        to data: inout Data
    ) {
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        data.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        data.append(fileData)
        data.append(Data("\r\n".utf8))
    }
}

// MARK: - Shared HTTP helpers

private func appendMultipartField(
    _ name: String,
    value: String,
    boundary: String,
    to data: inout Data
) {
    data.append(Data("--\(boundary)\r\n".utf8))
    data.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
    data.append(Data("\(value)\r\n".utf8))
}

private func appendMultipartFile(
    _ name: String,
    filename: String,
    mimeType: String,
    data fileData: Data,
    boundary: String,
    to data: inout Data
) {
    data.append(Data("--\(boundary)\r\n".utf8))
    data.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
    data.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
    data.append(fileData)
    data.append(Data("\r\n".utf8))
}

private func endpoint(baseURL: String, path: String) throws -> URL {
    let clean = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let url = URL(string: "\(clean)/\(path)") else { throw MediaGenerationError.invalidURL }
    return url
}

private func validate(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else {
        throw MediaGenerationError.invalidResponse("没有 HTTP 响应")
    }
    guard (200..<300).contains(http.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw MediaGenerationError.http(http.statusCode, body)
    }
}

private func fileExtension(for mimeType: String, fallback: String) -> String {
    switch mimeType.lowercased() {
    case "image/jpeg", "image/jpg": "jpg"
    case "image/webp": "webp"
    case "image/gif": "gif"
    default: fallback
    }
}

private func imageMimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg": "image/jpeg"
    case "webp": "image/webp"
    default: "image/png"
    }
}
