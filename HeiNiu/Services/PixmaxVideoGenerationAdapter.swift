/// PixMax 画布生视频适配器：素材上传、审核、节点提交、轮询与下载。

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PixMax 当前内置模型目录与素材组合规则。
enum PixmaxModelCatalog {
    struct Spec: Sendable {
        var capability: VideoModelCapability
        var allowedReferenceModes: [String]
    }

    static let aspectRatios = ["auto", "16:9", "9:16", "1:1", "4:3", "3:4", "21:9"]

    static let specs: [Spec] = [
        make("PIXDANCE_2_FAST", ["480P", "720P"], Array(4...15), true, "referToVideo", ["referToVideo", "imageToVideo"]),
        make("PIXDANCE_2", ["480P", "720P", "1080P"], Array(4...15), true, "referToVideo", ["referToVideo", "imageToVideo"]),
        make("SEEDANCE_1_5", ["480P", "720P", "1080P"], Array(4...12), true, "imageToVideo", ["imageToVideo"]),
        make("KLING_V3_OMNI", ["720P", "1080P"], Array(3...15), true, "referToVideo", ["referToVideo", "imageToVideo", "imageRefer"]),
        make("KLING_V3", ["720P", "1080P"], Array(3...15), false, "imageToVideo", ["imageToVideo"]),
        make("KLING_O1", ["720P", "1080P"], [5, 10], true, "referToVideo", ["referToVideo", "imageToVideo", "imageRefer"]),
        make("KLING_2_6", ["720P", "1080P"], [5, 10], true, "imageToVideo", ["imageToVideo"]),
        make("PIXVERSE_V6", ["360P", "540P", "720P", "1080P"], [5, 8, 10, 15], true, "imageToVideo", ["imageToVideo"]),
        make("VEO31", ["720P", "1080P", "4K"], [4, 6, 8], true, "imageToVideo", ["imageToVideo"]),
        make("VEO31_FAST", ["720P", "1080P", "4K"], [4, 6, 8], true, "imageToVideo", ["imageToVideo"]),
        make("VEO31_PREVIEW", ["720P", "1080P", "4K"], [4, 6, 8], true, "imageToVideo", ["imageToVideo", "imageRefer"]),
        make("HAILUO_23", ["768P", "1080P"], [6, 10], false, "imageToVideo", ["imageToVideo"]),
        make("HAILUO_02", ["768P", "1080P"], [6, 10], false, "imageToVideo", ["imageToVideo"]),
        make("VIDU_Q3_PRO", ["720P", "1080P"], Array(1...16), true, "imageToVideo", ["imageToVideo", "imageRefer"]),
        make("VIDU_Q2_PRO", ["720P", "1080P"], Array(0...10), true, "referToVideo", ["referToVideo", "imageToVideo", "imageRefer"]),
        make("VIDU_Q3_MIX", ["720P", "1080P"], Array(1...16), true, "imageRefer", ["imageRefer"]),
        make("WAN2_6", ["720P", "1080P"], Array(2...15), true, "referToVideo", ["referToVideo", "imageToVideo"]),
        make("SORA_2_PRO", ["720P", "1080P"], [4, 8, 12], true, "imageRefer", ["imageRefer"]),
        make("SORA_2", ["720P"], [4, 8, 12], true, "imageRefer", ["imageRefer"]),
    ]

    static var capabilities: [VideoModelCapability] { specs.map(\.capability) }

    static func spec(for model: String) -> Spec? { specs.first { $0.capability.model == model } }

    private static func make(
        _ model: String,
        _ resolutions: [String],
        _ durations: [Int],
        _ audio: Bool,
        _ defaultReferenceMode: String,
        _ modes: [String]
    ) -> Spec {
        let supportsMultimodal = modes.contains("referToVideo")
        return Spec(
            capability: VideoModelCapability(
                model: model,
                displayName: model,
                aspectRatios: aspectRatios,
                resolutions: resolutions,
                durations: durations,
                supportsAudioGeneration: audio,
                maximumReferenceImages: 9,
                maximumReferenceVideos: supportsMultimodal ? 3 : 0,
                maximumReferenceAudios: supportsMultimodal ? 3 : 0,
                referenceMode: defaultReferenceMode
            ),
            allowedReferenceModes: modes
        )
    }
}

/// PixMax 原生生视频适配器。
struct PixmaxVideoGenerationAdapter: VideoGenerationAdapter {
    let descriptor = MediaAdapterDescriptor(
        id: VideoProvider.pixmaxAdapterID,
        displayName: "PixMax 画布生视频",
        summary: "使用原生 URLSession 登录态、OSS 上传和 PixMax 画布节点生成视频。",
        endpointHint: "/assets/* · /canvas/node/batch · /generate/*",
        configurationFields: [
            MediaAdapterFieldDescriptor(id: "prompt", title: "提示词", help: "可用图片1、视频1、音频1引用按连线顺序编号的素材。", example: "图片1中的人物走入视频1的场景", isRequired: true),
            MediaAdapterFieldDescriptor(id: "model", title: "模型", help: "只能从内置模型目录选择。", example: "PIXDANCE_2_FAST", isRequired: true),
            MediaAdapterFieldDescriptor(id: "resolution", title: "分辨率", help: "按模型能力选择。", example: "720P", isRequired: true),
            MediaAdapterFieldDescriptor(id: "references", title: "参考素材", help: "最多 9 图、3 视频、3 音频；具体组合受模型限制。", example: "运行时媒体输入", isRequired: true),
        ],
        supportedSizes: Array(Set(PixmaxModelCatalog.capabilities.flatMap(\.resolutions))).sorted(),
        supportedDurations: Array(Set(PixmaxModelCatalog.capabilities.flatMap(\.durations))).sorted(),
        supportsReferenceImage: true,
        supportsReferenceVideo: true,
        supportsReferenceAudio: true,
        maximumReferenceImages: 9,
        maximumReferenceVideos: 3,
        maximumReferenceAudios: 3,
        supportsAudioGeneration: true,
        modelCapabilities: PixmaxModelCatalog.capabilities,
        usageNotes: [
            "不启动或控制任何浏览器；Cookie 仅从钥匙串读取。",
            "素材只上传实际连线文件，并先做远端哈希去重和合规检查。",
            "生成轮询每秒一次且不设总时限；停止运行会停止本地等待。",
        ]
    )

    private let session: URLSession
    private let gate: PixmaxProviderSubmissionGate

    init(session: URLSession = .shared, gate: PixmaxProviderSubmissionGate = .shared) {
        self.session = session
        self.gate = gate
    }

    func generate(
        request: VideoGenerationRequest,
        provider: VideoProvider,
        apiKey: String,
        outputDirectory: URL,
        progress: @escaping @Sendable (MediaGenerationProgress) async -> Void
    ) async throws -> MediaArtifact {
        guard provider.kind == .pixmax, provider.adapterID == VideoProvider.pixmaxAdapterID else {
            throw PixmaxError.unsupported("当前服务商不是 PixMax 原生适配器")
        }
        guard provider.isEnabled else { throw PixmaxError.unsupported("PixMax 服务商尚未启用") }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            PixmaxSessionManager.shared.reportAuthenticationFailure(providerID: provider.id, allowReprompt: true)
            throw PixmaxError.unauthorized
        }
        let spec = try validate(request)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let client = try PixmaxAPIClient(baseURL: provider.effectiveBaseURL, cookie: apiKey, session: session)

        do {
            await progress(MediaGenerationProgress(fraction: 0.01, message: "正在验证 PixMax 登录态"))
            _ = try await client.userInfo()
        } catch let error as PixmaxError {
            if error.isAuthenticationFailure {
                PixmaxSessionManager.shared.reportAuthenticationFailure(providerID: provider.id, allowReprompt: true)
            }
            throw error
        }

        let workspace = try await PixmaxSessionManager.shared.workspace(
            for: provider,
            cookie: apiKey,
            client: client
        )
        let images = try request.referenceImageURLs.enumerated().map { index, url in
            let prepared = try normalizeImageIfNeeded(url, outputDirectory: outputDirectory)
            return PixmaxMedia(type: .image, ordinal: index + 1, fileURL: prepared)
        }
        let videos = request.referenceVideoURLs.enumerated().map {
            PixmaxMedia(type: .video, ordinal: $0.offset + 1, fileURL: $0.element)
        }
        let audios = request.referenceAudioURLs.enumerated().map {
            PixmaxMedia(type: .audio, ordinal: $0.offset + 1, fileURL: $0.element)
        }
        let media = images + videos + audios
        guard !media.isEmpty else { throw PixmaxError.unsupported("PixMax 生视频至少需要一个参考素材") }

        await gate.acquire(provider.id)
        let nodeUUID: String
        do {
            nodeUUID = try await prepareAndSubmit(
                request: request,
                spec: spec,
                provider: provider,
                client: client,
                fileUUID: workspace.fileUUID,
                media: media,
                progress: progress
            )
            await gate.release(provider.id)
        } catch {
            await gate.release(provider.id)
            if let pixmax = error as? PixmaxError, pixmax.isAuthenticationFailure {
                PixmaxSessionManager.shared.reportAuthenticationFailure(providerID: provider.id, allowReprompt: true)
            }
            throw error
        }

        let finalNode = try await pollGeneration(client: client, nodeUUID: nodeUUID, progress: progress)
        let resultAssets = (finalNode["resultAssets"] as? [[String: Any]]) ?? []
        guard !resultAssets.isEmpty else { throw PixmaxError.invalidResponse("生成完成但缺少 resultAssets") }
        await progress(MediaGenerationProgress(fraction: 0.98, message: "正在下载 PixMax 视频", remoteJobID: nodeUUID))
        var files: [URL] = []
        for (index, asset) in resultAssets.enumerated() {
            try Task.checkCancellation()
            let assetUUID = PixmaxAPIClient.string(asset, keys: ["assetsUuid", "assetUuid", "uuid"])
            guard !assetUUID.isEmpty else { continue }
            let target = outputDirectory.appendingPathComponent("pixmax-\(nodeUUID)-\(index + 1).mp4")
            try await downloadAsset(client: client, asset: asset, assetUUID: assetUUID, target: target)
            files.append(target)
        }
        guard let primary = files.first else { throw MediaGenerationError.missingArtifact }
        await progress(MediaGenerationProgress(fraction: 1, message: "PixMax 视频已保存", remoteJobID: nodeUUID))
        await PixmaxSessionManager.shared.refreshAccountOverview(providerID: provider.id)
        let extras = Array(files.dropFirst())
        return MediaArtifact(
            fileURL: primary,
            mimeType: "video/mp4",
            remoteJobID: nodeUUID,
            additionalFileURLs: extras,
            warnings: extras.isEmpty ? [] : ["PixMax 返回了 \(files.count) 个结果；额外视频已保存在本次 Assets 目录。"]
        )
    }

    private func validate(_ request: VideoGenerationRequest) throws -> PixmaxModelCatalog.Spec {
        guard let spec = PixmaxModelCatalog.spec(for: request.model) else {
            throw PixmaxError.unsupported("PixMax 未知模型：\(request.model)")
        }
        let capability = spec.capability
        guard capability.aspectRatios.contains(request.aspectRatio) else {
            throw PixmaxError.unsupported("模型 \(request.model) 不支持画幅 \(request.aspectRatio)")
        }
        guard capability.resolutions.contains(request.resolution) else {
            throw PixmaxError.unsupported("模型 \(request.model) 不支持分辨率 \(request.resolution)")
        }
        guard capability.durations.contains(request.durationSeconds) else {
            throw PixmaxError.unsupported("模型 \(request.model) 不支持 \(request.durationSeconds) 秒时长")
        }
        guard !request.includeAudio || capability.supportsAudioGeneration else {
            throw PixmaxError.unsupported("模型 \(request.model) 不支持生成音频")
        }
        guard request.referenceImageURLs.count <= capability.maximumReferenceImages,
              request.referenceVideoURLs.count <= 3,
              request.referenceAudioURLs.count <= 3
        else { throw PixmaxError.unsupported("参考素材超过 PixMax 的 9 图 / 3 视频 / 3 音频上限") }
        if (!request.referenceVideoURLs.isEmpty || !request.referenceAudioURLs.isEmpty),
           !spec.allowedReferenceModes.contains("referToVideo") {
            throw PixmaxError.unsupported("模型 \(request.model) 不支持当前视频或音频参考组合")
        }
        return spec
    }

    private func prepareAndSubmit(
        request: VideoGenerationRequest,
        spec: PixmaxModelCatalog.Spec,
        provider: VideoProvider,
        client: PixmaxAPIClient,
        fileUUID: String,
        media: [PixmaxMedia],
        progress: @escaping @Sendable (MediaGenerationProgress) async -> Void
    ) async throws -> String {
        var revision = try await canvasRevision(client: client, fileUUID: fileUUID)
        var references: [(PixmaxMedia, String)] = []
        for (index, item) in media.enumerated() {
            try Task.checkCancellation()
            await progress(MediaGenerationProgress(
                fraction: 0.08 + Double(index) / Double(max(1, media.count)) * 0.35,
                message: "正在处理\(item.slotLabel)"
            ))
            let asset = try await ensureAsset(client: client, media: item)
            let nodeUUID = UUID().uuidString
            let create = [try baseNode(media: item, asset: asset, nodeUUID: nodeUUID)]
            revision = try await writeNodes(
                client: client,
                fileUUID: fileUUID,
                revision: revision,
                create: create
            )
            references.append((item, nodeUUID))
        }

        let referMode: String
        if media.contains(where: { $0.type != .image }) && spec.allowedReferenceModes.contains("referToVideo") {
            referMode = "referToVideo"
        } else {
            referMode = spec.capability.referenceMode ?? spec.allowedReferenceModes[0]
        }
        let finalPrompt = mentionPrompt(request.prompt, references: references)
        let params: [String: Any] = [
            "model": request.model,
            "prompt": finalPrompt,
            "resolution": request.resolution,
            "aspectRatio": request.aspectRatio == "auto" ? "" : request.aspectRatio,
            "duration": String(request.durationSeconds),
            "referModel": referMode,
            "includeAudio": request.includeAudio ? "true" : "false",
            "count": "1",
        ]
        let nodeUUID = UUID().uuidString
        let metadata = try jsonString([
            "data": [
                "status": "idle", "label": "", "url": "", "assetsId": "",
                "verifyStatus": "NONE", "poster": "", "params": params, "errMsg": "",
            ],
            "position": ["x": 984, "y": 388],
            "measured": ["width": 360, "height": 200],
        ])
        let generateNode: [String: Any] = [
            "uuid": nodeUUID,
            "type": "GENERATE_VIDEO",
            "prevNodeUuids": references.map(\.1),
            "defaultAssetUuid": "",
            "params": params,
            "metaData": metadata,
        ]
        _ = try await writeNodes(
            client: client,
            fileUUID: fileUUID,
            revision: revision,
            create: [generateNode]
        )
        let interval = min(20, max(0, Int(provider.adapterSettings["submissionInterval"] ?? "0") ?? 0))
        await gate.waitForSubmissionInterval(provider.id, seconds: interval)
        try Task.checkCancellation()
        await progress(MediaGenerationProgress(fraction: 0.55, message: "正在提交 PixMax 任务", remoteJobID: nodeUUID))
        do {
            _ = try await client.post("/user/api/generate/batch", payload: ["nodeUuids": [nodeUUID]])
            await gate.markSubmitted(provider.id)
        } catch let error as PixmaxError {
            if case .api(let code, _) = error, code.contains("Credit.Insufficient.Balance") {
                throw PixmaxError.unsupported("PixMax 余额不足，请充值或切换账号")
            }
            throw error
        }
        return nodeUUID
    }

    private func canvasRevision(client: PixmaxAPIClient, fileUUID: String) async throws -> String {
        let response = try await client.canvas(fileUUID: fileUUID)
        return (response["data"] as? [String: Any])?["revision"] as? String ?? ""
    }

    private func writeNodes(
        client: PixmaxAPIClient,
        fileUUID: String,
        revision: String,
        create: [[String: Any]]
    ) async throws -> String {
        var current = revision
        for attempt in 1...3 {
            do {
                let response = try await client.post("/user/api/canvas/node/batch", payload: [
                    "fileUuid": fileUUID,
                    "baseRevision": current,
                    "create": create,
                    "update": [],
                    "delete": [],
                ])
                return (response["data"] as? [String: Any])?["revision"] as? String ?? current
            } catch let error as PixmaxError {
                let text = error.localizedDescription
                guard attempt < 3,
                      text.contains("Canvas.Revision.Conflict") || text.localizedCaseInsensitiveContains("revision")
                else { throw error }
                current = try await canvasRevision(client: client, fileUUID: fileUUID)
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        throw PixmaxError.invalidResponse("画布 revision 连续冲突")
    }

    private func ensureAsset(client: PixmaxAPIClient, media: PixmaxMedia) async throws -> PixmaxAsset {
        let data = try Data(contentsOf: media.fileURL)
        let hash = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let check = try await client.post(
            "/user/api/assets/check",
            payload: ["fileHash": hash],
            allowedErrorCodes: ["Common.NotFound"]
        )
        if check["success"] as? Bool != false,
           let existing = check["data"] as? [String: Any],
           !PixmaxAPIClient.string(existing, keys: ["assetsUuid", "assetUuid"]).isEmpty {
            do {
                return try await verifyAsset(client: client, asset: PixmaxAsset(dictionary: existing), label: media.slotLabel)
            } catch let error as PixmaxError {
                let detail = error.localizedDescription
                guard detail.contains("AssetLibrary.Asset.NotOwner") ||
                        detail.contains("AssetLibrary.Asset.NotFound") ||
                        detail.localizedCaseInsensitiveContains("does not belong to current user")
                else { throw error }
                // 同哈希资产属于旧账号时跳过复用，继续申请本账号 OSS 上传。
            }
        }

        let mime = mimeType(for: media)
        let authorize = try await client.post("/user/api/assets/oss/authorize", payload: [
            "fileName": media.fileURL.lastPathComponent,
            "fileSize": data.count,
            "contentType": mime,
        ])
        guard let authorization = authorize["data"] as? [String: Any],
              let sessionID = authorization["sessionId"] as? String
        else { throw PixmaxError.invalidResponse("OSS 授权缺少 sessionId") }
        try await ossPut(authorization: authorization, data: data, fallbackContentType: mime)

        let deadline = Date().addingTimeInterval(180)
        var uploaded: PixmaxAsset?
        while Date() < deadline {
            try Task.checkCancellation()
            let response = try await client.post("/user/api/assets/oss/check", payload: ["sessionId": sessionID])
            let result = response["data"] as? [String: Any] ?? [:]
            let status = (result["status"] as? String ?? "").uppercased()
            if status == "COMPLETED", let asset = result["asset"] as? [String: Any] {
                uploaded = PixmaxAsset(dictionary: asset)
                break
            }
            if ["FAILED", "ERROR"].contains(status) { throw PixmaxError.unsupported("\(media.slotLabel) OSS 处理失败") }
            try await Task.sleep(for: .seconds(2))
        }
        guard let uploaded else { throw PixmaxError.unsupported("\(media.slotLabel) OSS 处理超时") }
        return try await verifyAsset(client: client, asset: uploaded, label: media.slotLabel)
    }

    private func verifyAsset(client: PixmaxAPIClient, asset: PixmaxAsset, label: String) async throws -> PixmaxAsset {
        guard !asset.uuid.isEmpty else { throw PixmaxError.invalidResponse("素材缺少 assetUuid") }
        let deadline = Date().addingTimeInterval(180)
        var result = asset
        while Date() < deadline {
            try Task.checkCancellation()
            do {
                let response = try await client.post(
                    "/user/api/assetLibrary/compliance/check",
                    payload: ["assetUuid": asset.uuid]
                )
                let data = response["data"] as? [String: Any] ?? [:]
                let status = (data["complianceStatus"] as? String ?? "").uppercased()
                if status == "ACTIVE" {
                    result.merge(data)
                    break
                }
                if ["FAILED", "BLOCKED", "REJECTED"].contains(status) {
                    throw PixmaxError.unsupported("\(label) 素材审核失败（\(status)）")
                }
            } catch let error as PixmaxError {
                if case .api(let code, _) = error,
                   code.localizedCaseInsensitiveContains("frequent") || code.localizedCaseInsensitiveContains("rate") {
                    try await Task.sleep(for: .seconds(5))
                    continue
                }
                throw error
            }
            try await Task.sleep(for: .seconds(2))
        }
        guard result.complianceStatus.uppercased() == "ACTIVE" else {
            throw PixmaxError.unsupported("\(label) 素材审核超时")
        }
        if result.ossDomain.isEmpty || result.webURL.isEmpty {
            let links = try await client.post("/user/api/assets/getAssetsLink", payload: ["assetUuids": [result.uuid]])
            if let dictionary = firstAssetDictionary(in: links, matching: result.uuid) { result.merge(dictionary) }
        }
        return result
    }

    private func ossPut(authorization: [String: Any], data: Data, fallbackContentType: String) async throws {
        let objectKey = PixmaxAPIClient.string(authorization, keys: ["objectKey"])
        let bucket = PixmaxAPIClient.string(authorization, keys: ["bucketName"])
        let endpoint = PixmaxAPIClient.string(authorization, keys: ["endpoint"])
        let accessKeyID = PixmaxAPIClient.string(authorization, keys: ["accessKeyId"])
        let secret = PixmaxAPIClient.string(authorization, keys: ["accessKeySecret"])
        let token = PixmaxAPIClient.string(authorization, keys: ["securityToken"])
        guard !objectKey.isEmpty, !bucket.isEmpty, !endpoint.isEmpty,
              !accessKeyID.isEmpty, !secret.isEmpty, !token.isEmpty
        else { throw PixmaxError.invalidResponse("OSS 授权字段不完整") }
        let callback: [String: String] = [
            "callbackUrl": PixmaxAPIClient.string(authorization, keys: ["callbackUrl"]),
            "callbackBody": PixmaxAPIClient.string(authorization, keys: ["callbackBody"]),
            "callbackBodyType": PixmaxAPIClient.string(authorization, keys: ["callbackBodyType"]).nilIfEmpty ?? "application/x-www-form-urlencoded",
        ]
        let callbackData = try JSONSerialization.data(withJSONObject: callback, options: [.sortedKeys])
        let callbackHeader = callbackData.base64EncodedString()
        let contentType = PixmaxAPIClient.string(authorization, keys: ["contentType"]).nilIfEmpty ?? fallbackContentType
        try Task.checkCancellation()
        let date = await ossServerDate(bucket: bucket, endpoint: endpoint)
        let canonicalHeaders = "x-oss-callback:\(callbackHeader)\n" + "x-oss-security-token:\(token)\n"
        let canonicalResource = "/\(bucket)/\(objectKey)"
        let stringToSign = "PUT\n\n\(contentType)\n\(date)\n\(canonicalHeaders)\(canonicalResource)"
        let signature = Data(HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: SymmetricKey(data: Data(secret.utf8))
        )).base64EncodedString()

        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(bucket).\(endpoint)"
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#")
        components.percentEncodedPath = "/" + (objectKey.addingPercentEncoding(withAllowedCharacters: allowed) ?? objectKey)
        guard let url = components.url else { throw PixmaxError.invalidResponse("OSS 上传地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 600
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-oss-security-token")
        request.setValue(callbackHeader, forHTTPHeaderField: "x-oss-callback")
        request.setValue("OSS \(accessKeyID):\(signature)", forHTTPHeaderField: "Authorization")
        request.setValue(date, forHTTPHeaderField: "Date")
        request.httpBody = data
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PixmaxError.network("OSS 上传失败")
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PixmaxError.http((response as? HTTPURLResponse)?.statusCode ?? 0, "OSS 上传或回调失败")
        }
    }

    private func baseNode(media: PixmaxMedia, asset: PixmaxAsset, nodeUUID: String) throws -> [String: Any] {
        var data: [String: Any] = [
            "label": media.fileURL.lastPathComponent,
            "assetsId": asset.uuid,
            "url": asset.absoluteWebURL,
            "verifyStatus": "ACTIVE",
        ]
        if !asset.thumbnailWebURL.isEmpty { data["thumbnailUrl"] = asset.absoluteURL(asset.thumbnailWebURL) }
        if media.type == .video, !asset.previewWebURL.isEmpty { data["poster"] = asset.absoluteURL(asset.previewWebURL) }
        let metadata = try jsonString([
            "data": data,
            "position": ["x": 600, "y": 400],
            "measured": ["width": 242, "height": 133],
        ])
        return [
            "uuid": nodeUUID,
            "type": media.type.nodeType,
            "defaultAssetUuid": asset.uuid,
            "metaData": metadata,
        ]
    }

    private func mentionPrompt(_ prompt: String, references: [(PixmaxMedia, String)]) -> String {
        var result = prompt
        var prefixes: [String] = []
        for (index, item) in references.enumerated() {
            let media = item.0
            let placeholder = "__HEINIU_PIXMAX_\(index)__"
            let token = "%%@[\(media.fileURL.lastPathComponent)][\(media.type.rawValue)][\(index)](\(item.1))%%"
            let stem = media.slotLabel
            let components = stem.reduce(into: "") { partial, character in
                if character.isNumber { partial += "\\s*\(character)" }
                else { partial += NSRegularExpression.escapedPattern(for: String(character)) }
            }
            let pattern = "(?:[@＠]\\s*)?\(components)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                let count = regex.numberOfMatches(in: result, range: range)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: placeholder)
                if count == 0 { prefixes.append(placeholder) }
            } else {
                prefixes.append(placeholder)
            }
            result = result.replacingOccurrences(of: placeholder, with: token)
            prefixes = prefixes.map { $0.replacingOccurrences(of: placeholder, with: token) }
        }
        return prefixes.joined() + result
    }

    private func pollGeneration(
        client: PixmaxAPIClient,
        nodeUUID: String,
        progress: @escaping @Sendable (MediaGenerationProgress) async -> Void
    ) async throws -> [String: Any] {
        var transientStartedAt: Date?
        let started = Date()
        while true {
            try await Task.sleep(for: .seconds(1))
            try Task.checkCancellation()
            let response: [String: Any]
            do {
                response = try await client.post("/user/api/generate/progress", payload: ["nodeUuids": [nodeUUID]])
                transientStartedAt = nil
            } catch let error as PixmaxError where error.isTransientGatewayFailure {
                let first = transientStartedAt ?? Date()
                transientStartedAt = first
                guard Date().timeIntervalSince(first) < 60 else { throw error }
                await progress(MediaGenerationProgress(fraction: 0.65, message: "等待 PixMax 网关恢复", remoteJobID: nodeUUID))
                continue
            }
            guard let node = progressNode(response, nodeUUID: nodeUUID) else { continue }
            let status = (node["status"] as? String ?? "").uppercased()
            if status == "COMPLETE" { return node }
            if ["FAILED", "ABORTED", "ERROR"].contains(status) {
                let message = PixmaxAPIClient.string(node, keys: ["errMsg", "providerErrorMsg", "errorMessage"])
                throw PixmaxError.unsupported("PixMax 生成失败：\(message.isEmpty ? status : message)")
            }
            let fraction = status == "QUEUE" ? 0.60 : min(0.95, 0.65 + Date().timeIntervalSince(started) / 600)
            await progress(MediaGenerationProgress(
                fraction: fraction,
                message: status == "QUEUE" ? "PixMax 排队中" : "PixMax 生成中",
                remoteJobID: nodeUUID
            ))
        }
    }

    private func progressNode(_ response: [String: Any], nodeUUID: String) -> [String: Any]? {
        let data = response["data"]
        if let list = data as? [[String: Any]] { return list.first { $0["nodeUuid"] as? String == nodeUUID } }
        if let dictionary = data as? [String: Any] {
            if dictionary["nodeUuid"] as? String == nodeUUID { return dictionary }
            for key in ["nodes", "list"] {
                if let list = dictionary[key] as? [[String: Any]],
                   let match = list.first(where: { $0["nodeUuid"] as? String == nodeUUID }) { return match }
            }
        }
        return nil
    }

    private func downloadAsset(
        client: PixmaxAPIClient,
        asset: [String: Any],
        assetUUID: String,
        target: URL
    ) async throws {
        let fallbackDomain = PixmaxAPIClient.string(asset, keys: ["ossDomain"])
        let fallbackPath = PixmaxAPIClient.string(asset, keys: ["webUrl", "downloadUrl", "videoUrl", "url"])
        var remoteURL = absoluteMediaURL(path: fallbackPath, domain: fallbackDomain)
        while remoteURL == nil {
            try Task.checkCancellation()
            let response = try await client.post("/user/api/assets/getAssetsLink", payload: ["assetUuids": [assetUUID]])
            if let item = firstAssetDictionary(in: response, matching: assetUUID) {
                remoteURL = absoluteMediaURL(
                    path: PixmaxAPIClient.string(item, keys: ["downloadUrl", "videoUrl", "mediaUrl", "fileUrl", "url", "webUrl"]),
                    domain: PixmaxAPIClient.string(item, keys: ["ossDomain", "domain", "cdnDomain"])
                )
            }
            if remoteURL == nil { try await Task.sleep(for: .seconds(1)) }
        }
        guard let remoteURL else { throw MediaGenerationError.missingArtifact }
        let temporary: URL
        let response: URLResponse
        do {
            (temporary, response) = try await session.download(from: remoteURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PixmaxError.network("视频下载失败")
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PixmaxError.http((response as? HTTPURLResponse)?.statusCode ?? 0, "视频下载失败")
        }
        try FileManager.default.moveItem(at: temporary, to: target)
    }

    private func firstAssetDictionary(in value: Any, matching uuid: String) -> [String: Any]? {
        for dictionary in PixmaxAPIClient.dictionariesDepthFirst(value) {
            let candidate = PixmaxAPIClient.string(dictionary, keys: ["assetsUuid", "assetUuid", "uuid"])
            if candidate == uuid { return dictionary }
        }
        return PixmaxAPIClient.dictionariesDepthFirst(value).first {
            !PixmaxAPIClient.string($0, keys: ["webUrl", "downloadUrl", "videoUrl", "url"]).isEmpty
        }
    }

    private func absoluteMediaURL(path: String, domain: String) -> URL? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("//") { return URL(string: "https:" + path) }
        if let url = URL(string: path), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return url }
        let base = domain.isEmpty ? "https://pixmax-prod.oss-accelerate.aliyuncs.com" : domain
        return URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func normalizeImageIfNeeded(_ sourceURL: URL, outputDirectory: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw PixmaxError.unsupported("无法读取参考图片：\(sourceURL.lastPathComponent)") }
        if (300...6000).contains(width), (300...6000).contains(height) { return sourceURL }
        var scale = max(300 / Double(max(width, 1)), 300 / Double(max(height, 1)), 1)
        if max(Double(width) * scale, Double(height) * scale) > 6000 {
            scale = min(6000 / Double(max(width, 1)), 6000 / Double(max(height, 1)))
        }
        let newWidth = max(1, Int((Double(width) * scale).rounded()))
        let newHeight = max(1, Int((Double(height) * scale).rounded()))
        guard (300...6000).contains(newWidth), (300...6000).contains(newHeight),
              let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw PixmaxError.unsupported("参考图片无法缩放到 PixMax 要求的 300–6000px") }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        guard let resized = context.makeImage() else { throw PixmaxError.invalidResponse("图片缩放失败") }
        let target = outputDirectory.appendingPathComponent("pixmax-normalized-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PixmaxError.invalidResponse("无法创建 PNG 副本")
        }
        CGImageDestinationAddImage(destination, resized, nil)
        guard CGImageDestinationFinalize(destination) else { throw PixmaxError.invalidResponse("PNG 副本写入失败") }
        return target
    }

    private func mimeType(for media: PixmaxMedia) -> String {
        let ext = media.fileURL.pathExtension.lowercased()
        let values: [String: String] = [
            "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp",
            "bmp": "image/bmp", "gif": "image/gif", "mp4": "video/mp4", "mov": "video/quicktime",
            "webm": "video/webm", "mkv": "video/x-matroska", "avi": "video/x-msvideo",
            "mp3": "audio/mpeg", "wav": "audio/wav", "m4a": "audio/mp4", "aac": "audio/aac",
            "ogg": "audio/ogg", "flac": "audio/flac",
        ]
        return values[ext] ?? "application/octet-stream"
    }

    private func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else { throw PixmaxError.invalidResponse("节点 metadata 编码失败") }
        return text
    }

    private static func httpDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: Date())
    }

    private func ossServerDate(bucket: String, endpoint: String) async -> String {
        guard let url = URL(string: "https://\(bucket).\(endpoint)") else { return Self.httpDate() }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        if let (_, response) = try? await session.data(for: request),
           let value = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Date"),
           !value.isEmpty {
            return value
        }
        return Self.httpDate()
    }
}

/// 控制同一 PixMax 服务商的上传、审核、画布写入和提交串行执行。
actor PixmaxProviderSubmissionGate {
    static let shared = PixmaxProviderSubmissionGate()

    private var locked: Set<UUID> = []
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    private var lastSubmission: [UUID: Date] = [:]

    func acquire(_ providerID: UUID) async {
        if !locked.contains(providerID) {
            locked.insert(providerID)
            return
        }
        await withCheckedContinuation { continuation in
            waiters[providerID, default: []].append(continuation)
        }
    }

    func release(_ providerID: UUID) {
        if var queue = waiters[providerID], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[providerID] = queue
            next.resume()
        } else {
            locked.remove(providerID)
            waiters[providerID] = nil
        }
    }

    func waitForSubmissionInterval(_ providerID: UUID, seconds: Int) async {
        guard seconds > 0, let previous = lastSubmission[providerID] else { return }
        let remaining = Double(seconds) - Date().timeIntervalSince(previous)
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
    }

    func markSubmitted(_ providerID: UUID) { lastSubmission[providerID] = Date() }
}

private struct PixmaxMedia {
    enum MediaType: String {
        case image, video, audio

        var nodeType: String {
            switch self {
            case .image: "BASE_IMAGE"
            case .video: "BASE_VIDEO"
            case .audio: "BASE_AUDIO"
            }
        }
    }

    var type: MediaType
    var ordinal: Int
    var fileURL: URL

    var slotLabel: String {
        switch type {
        case .image: "图片\(ordinal)"
        case .video: "视频\(ordinal)"
        case .audio: "音频\(ordinal)"
        }
    }
}

private struct PixmaxAsset {
    var uuid = ""
    var webURL = ""
    var ossDomain = ""
    var previewWebURL = ""
    var thumbnailWebURL = ""
    var complianceStatus = ""

    init(dictionary: [String: Any]) {
        merge(dictionary)
    }

    mutating func merge(_ dictionary: [String: Any]) {
        uuid = PixmaxAPIClient.string(dictionary, keys: ["assetsUuid", "assetUuid"]).nilIfEmpty ?? uuid
        webURL = PixmaxAPIClient.string(dictionary, keys: ["webUrl"]).nilIfEmpty ?? webURL
        ossDomain = PixmaxAPIClient.string(dictionary, keys: ["ossDomain"]).nilIfEmpty ?? ossDomain
        previewWebURL = PixmaxAPIClient.string(dictionary, keys: ["previewWebUrl"]).nilIfEmpty ?? previewWebURL
        thumbnailWebURL = PixmaxAPIClient.string(dictionary, keys: ["thumbnailWebUrl"]).nilIfEmpty ?? thumbnailWebURL
        complianceStatus = PixmaxAPIClient.string(dictionary, keys: ["complianceStatus"]).nilIfEmpty ?? complianceStatus
    }

    var absoluteWebURL: String { absoluteURL(webURL) }

    func absoluteURL(_ path: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        return ossDomain.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
