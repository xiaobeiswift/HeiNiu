/// PixMax 服务商独立登录态、60 秒心跳与登录弹窗队列。

import Foundation
import Observation

/// 单个 PixMax 服务商的会话状态。
enum PixmaxSessionStatus: Hashable, Sendable {
    case disabled
    case checking
    case authenticated(String)
    case unauthorized
    case networkError(String)

    var title: String {
        switch self {
        case .disabled: "未启用"
        case .checking: "正在检查登录态"
        case .authenticated(let summary): "已登录 · \(summary)"
        case .unauthorized: "登录已失效"
        case .networkError: "网络异常"
        }
    }
}

/// 需要展示原生登录框的服务商。
struct PixmaxLoginPresentation: Identifiable, Hashable {
    var id: UUID { providerID }
    var providerID: UUID
    var automaticallyPresented: Bool
}

/// 按 provider ID 管理心跳；只有 401 或 Unauthorized 才触发登录框。
@Observable
@MainActor
final class PixmaxSessionManager {
    static let shared = PixmaxSessionManager()

    var states: [UUID: PixmaxSessionStatus] = [:]
    var loginPresentation: PixmaxLoginPresentation?
    var accountOverviews: [UUID: PixmaxAccountOverview] = [:]
    var overviewLoading: Set<UUID> = []
    var overviewErrors: [UUID: String] = [:]

    @ObservationIgnored private weak var settings: SettingsStore?
    @ObservationIgnored private var heartbeatTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var promptedInvalidations: Set<UUID> = []
    @ObservationIgnored private var loginQueue: [PixmaxLoginPresentation] = []
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let heartbeatInterval: Duration

    init(session: URLSession = .shared, heartbeatInterval: Duration = .seconds(60)) {
        self.session = session
        self.heartbeatInterval = heartbeatInterval
    }

    deinit {
        for task in heartbeatTasks.values { task.cancel() }
    }

    /// 绑定设置仓库，并立即为全部已启用 PixMax 服务商启动心跳。
    func attach(settings: SettingsStore) {
        self.settings = settings
        reconcile()
    }

    /// 根据当前服务商启用状态增删心跳任务。
    func reconcile() {
        guard let settings else { return }
        let pixmaxProviders = settings.videoProviders.filter { $0.kind == .pixmax }
        let existingIDs = Set(pixmaxProviders.map(\.id))
        for (id, task) in heartbeatTasks where !existingIDs.contains(id) {
            task.cancel()
            heartbeatTasks[id] = nil
            states[id] = nil
            accountOverviews[id] = nil
            overviewLoading.remove(id)
            overviewErrors[id] = nil
            promptedInvalidations.remove(id)
            removeQueuedLogin(id)
        }
        for provider in pixmaxProviders {
            if provider.isEnabled {
                if heartbeatTasks[provider.id] == nil { startHeartbeat(providerID: provider.id) }
            } else {
                heartbeatTasks[provider.id]?.cancel()
                heartbeatTasks[provider.id] = nil
                states[provider.id] = .disabled
                accountOverviews[provider.id] = nil
                overviewLoading.remove(provider.id)
                overviewErrors[provider.id] = nil
                promptedInvalidations.remove(provider.id)
                removeQueuedLogin(provider.id)
            }
        }
    }

    /// 用户手动打开登录框；与失效周期的一次性自动弹窗互不冲突。
    func requestLogin(providerID: UUID) {
        enqueueLogin(providerID: providerID, automatic: false, force: true)
    }

    /// 登录框关闭后继续展示队列中的下一个账号。
    func dismissLogin(providerID: UUID) {
        if loginPresentation?.providerID == providerID { loginPresentation = nil }
        presentNextLoginIfNeeded()
    }

    /// 生成前或适配器收到 Unauthorized 时报告失效。
    func reportAuthenticationFailure(providerID: UUID, allowReprompt: Bool = false) {
        states[providerID] = .unauthorized
        accountOverviews[providerID] = nil
        overviewLoading.remove(providerID)
        overviewErrors[providerID] = nil
        enqueueLogin(providerID: providerID, automatic: true, force: allowReprompt)
    }

    /// 启用/停用一个 PixMax 服务商；停用会立即取消心跳。
    func setEnabled(_ enabled: Bool, providerID: UUID) {
        guard let settings, var provider = settings.videoProvider(id: providerID), provider.kind == .pixmax else { return }
        provider.adapterSettings["enabled"] = enabled ? "true" : "false"
        settings.updateVideoProvider(provider)
        if enabled {
            promptedInvalidations.remove(providerID)
        }
        reconcile()
    }

    /// 清除钥匙串 Cookie 并停用，之后不会由心跳重新弹框。
    func logoutAndDisable(providerID: UUID) {
        guard let settings, var provider = settings.videoProvider(id: providerID) else { return }
        settings.setVideoAPIKey("", for: providerID)
        provider.adapterSettings["enabled"] = "false"
        provider.adapterSettings["identityID"] = nil
        provider.adapterSettings["identitySummary"] = nil
        provider.adapterSettings["workspaceUUID"] = nil
        provider.adapterSettings["fileUUID"] = nil
        settings.updateVideoProvider(provider)
        heartbeatTasks[providerID]?.cancel()
        heartbeatTasks[providerID] = nil
        states[providerID] = .disabled
        accountOverviews[providerID] = nil
        overviewLoading.remove(providerID)
        overviewErrors[providerID] = nil
        promptedInvalidations.remove(providerID)
        removeQueuedLogin(providerID)
    }

    /// 个人版密码登录。
    func loginPersonal(providerID: UUID, site: PixmaxSite, account: String, password: String) async throws {
        let result = try await PixmaxAuthenticator(session: session).personalLogin(site: site, account: account, password: password)
        try await completeLogin(providerID: providerID, baseURL: site.baseURL, mode: .personal, result: result)
    }

    /// 企业子账号登录。
    func loginTeam(providerID: UUID, teamLinkOrUUID: String, account: String, password: String) async throws {
        guard let provider = settings?.videoProvider(id: providerID) else { throw PixmaxError.invalidResponse("服务商已删除") }
        let baseURL = try teamBaseURL(teamLinkOrUUID, fallback: provider.effectiveBaseURL)
        let result = try await PixmaxAuthenticator(session: session).teamLogin(
            baseURL: baseURL,
            teamLinkOrUUID: teamLinkOrUUID,
            account: account,
            password: password
        )
        try await completeLogin(providerID: providerID, baseURL: baseURL, mode: .team, result: result)
    }

    /// 导入 Cookie 前必须通过 `/user/info` 验证。
    func importCookie(
        providerID: UUID,
        baseURL: String,
        cookie: String,
        mode: PixmaxLoginMode = .personal
    ) async throws {
        let result = try await PixmaxAuthenticator(session: session).importCookie(baseURL: baseURL, cookie: cookie)
        try await completeLogin(providerID: providerID, baseURL: baseURL, mode: mode, result: result)
    }

    /// 获取并持久化当前账号画布；适配器生成前也会调用，避免旧画布失效。
    func workspace(
        for provider: VideoProvider,
        cookie: String,
        client suppliedClient: PixmaxAPIClient? = nil
    ) async throws -> PixmaxWorkspace {
        let client = try suppliedClient ?? PixmaxAPIClient(baseURL: provider.effectiveBaseURL, cookie: cookie, session: session)
        let workspace = try await client.ensureWorkspace(
            projectUUID: provider.adapterSettings["workspaceUUID"],
            fileUUID: provider.adapterSettings["fileUUID"]
        )
        if var current = settings?.videoProvider(id: provider.id),
           current.adapterSettings["workspaceUUID"] != workspace.projectUUID ||
           current.adapterSettings["fileUUID"] != workspace.fileUUID {
            current.adapterSettings["workspaceUUID"] = workspace.projectUUID
            current.adapterSettings["fileUUID"] = workspace.fileUUID
            settings?.updateVideoProvider(current)
        }
        return workspace
    }

    /// 立即检查一次；网络错误只更新状态，不触发登录框。
    @discardableResult
    func checkNow(providerID: UUID, automaticPrompt: Bool = true) async -> PixmaxSessionStatus {
        guard let settings,
              let provider = settings.videoProvider(id: providerID),
              provider.kind == .pixmax,
              provider.isEnabled
        else {
            states[providerID] = .disabled
            return .disabled
        }
        let cookie = settings.videoAPIKey(for: providerID)
        guard !cookie.isEmpty else {
            states[providerID] = .unauthorized
            accountOverviews[providerID] = nil
            if automaticPrompt { enqueueLogin(providerID: providerID, automatic: true, force: false) }
            return .unauthorized
        }
        states[providerID] = .checking
        do {
            let client = try PixmaxAPIClient(baseURL: provider.effectiveBaseURL, cookie: cookie, session: session)
            let info = try await client.userInfo()
            let identity = try PixmaxAPIClient.identity(from: info)
            states[providerID] = .authenticated(identity.summary)
            promptedInvalidations.remove(providerID)
            return .authenticated(identity.summary)
        } catch let error as PixmaxError where error.isAuthenticationFailure {
            states[providerID] = .unauthorized
            accountOverviews[providerID] = nil
            if automaticPrompt { enqueueLogin(providerID: providerID, automatic: true, force: false) }
            return .unauthorized
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "连接失败"
            states[providerID] = .networkError(message)
            return .networkError(message)
        }
    }

    /// 获取当前登录身份的积分与最近生成记录；团队会话只展示子账号额度。
    func refreshAccountOverview(providerID: UUID) async {
        guard let settings,
              let provider = settings.videoProvider(id: providerID),
              provider.kind == .pixmax,
              provider.isEnabled
        else { return }
        let cookie = settings.videoAPIKey(for: providerID)
        guard !cookie.isEmpty else { return }
        overviewLoading.insert(providerID)
        overviewErrors[providerID] = nil
        defer { overviewLoading.remove(providerID) }
        do {
            let client = try PixmaxAPIClient(baseURL: provider.effectiveBaseURL, cookie: cookie, session: session)
            accountOverviews[providerID] = try await client.accountOverview()
        } catch let error as PixmaxError where error.isAuthenticationFailure {
            accountOverviews[providerID] = nil
            reportAuthenticationFailure(providerID: providerID)
        } catch {
            overviewErrors[providerID] = (error as? LocalizedError)?.errorDescription ?? "积分与记录刷新失败"
        }
    }

    private func completeLogin(
        providerID: UUID,
        baseURL: String,
        mode: PixmaxLoginMode,
        result: PixmaxLoginResult
    ) async throws {
        guard let settings, var provider = settings.videoProvider(id: providerID) else {
            throw PixmaxError.invalidResponse("服务商已删除")
        }
        let accountChanged = provider.adapterSettings["identityID"] != nil &&
            provider.adapterSettings["identityID"] != result.identity.stableID
        let siteChanged = provider.effectiveBaseURL != baseURL
        if accountChanged || siteChanged {
            provider.adapterSettings["workspaceUUID"] = nil
            provider.adapterSettings["fileUUID"] = nil
        }
        provider.baseURL = baseURL
        provider.adapterID = VideoProvider.pixmaxAdapterID
        provider.models = VideoProvider.pixmaxModels
        provider.adapterSettings["enabled"] = "true"
        provider.adapterSettings["identityID"] = result.identity.stableID
        provider.adapterSettings["identitySummary"] = result.identity.summary
        provider.adapterSettings["loginMode"] = mode.rawValue
        provider.adapterSettings["site"] = baseURL.contains("pixmax.cn") ? PixmaxSite.china.rawValue : PixmaxSite.international.rawValue

        let client = try PixmaxAPIClient(baseURL: baseURL, cookie: result.cookie, session: session)
        let workspace = try await client.ensureWorkspace(
            projectUUID: provider.adapterSettings["workspaceUUID"],
            fileUUID: provider.adapterSettings["fileUUID"]
        )
        provider.adapterSettings["workspaceUUID"] = workspace.projectUUID
        provider.adapterSettings["fileUUID"] = workspace.fileUUID
        settings.setVideoAPIKey(result.cookie, for: providerID)
        settings.updateVideoProvider(provider)
        states[providerID] = .authenticated(result.identity.summary)
        promptedInvalidations.remove(providerID)
        removeQueuedLogin(providerID)
        reconcile()
        await refreshAccountOverview(providerID: providerID)
    }

    private func startHeartbeat(providerID: UUID) {
        heartbeatTasks[providerID]?.cancel()
        heartbeatTasks[providerID] = Task { [weak self] in
            guard let self else { return }
            _ = await self.checkNow(providerID: providerID)
            while !Task.isCancelled {
                do { try await Task.sleep(for: heartbeatInterval) }
                catch { return }
                guard !Task.isCancelled else { return }
                _ = await self.checkNow(providerID: providerID)
            }
        }
    }

    private func enqueueLogin(providerID: UUID, automatic: Bool, force: Bool) {
        if automatic && promptedInvalidations.contains(providerID) && !force { return }
        if automatic { promptedInvalidations.insert(providerID) }
        guard loginPresentation?.providerID != providerID,
              !loginQueue.contains(where: { $0.providerID == providerID })
        else { return }
        let presentation = PixmaxLoginPresentation(providerID: providerID, automaticallyPresented: automatic)
        if loginPresentation == nil {
            loginPresentation = presentation
        } else {
            loginQueue.append(presentation)
        }
    }

    private func removeQueuedLogin(_ providerID: UUID) {
        loginQueue.removeAll { $0.providerID == providerID }
        if loginPresentation?.providerID == providerID {
            loginPresentation = nil
            presentNextLoginIfNeeded()
        }
    }

    private func presentNextLoginIfNeeded() {
        guard loginPresentation == nil, !loginQueue.isEmpty else { return }
        loginPresentation = loginQueue.removeFirst()
    }

    private func teamBaseURL(_ value: String, fallback: String) throws -> String {
        if let url = URL(string: value), let host = url.host?.lowercased() {
            if host == "pixmax.cn" || host.hasSuffix(".pixmax.cn") { return PixmaxSite.china.baseURL }
            if host == "pixmax.ai" || host.hasSuffix(".pixmax.ai") { return PixmaxSite.international.baseURL }
        }
        _ = try PixmaxAuthenticator.extractMainUserUUID(value)
        return try PixmaxAPIClient.validatedBaseURL(fallback).absoluteString
    }
}
