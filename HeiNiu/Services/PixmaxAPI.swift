/// PixMax 原生认证、会话验证与画布基础接口。

import CryptoKit
import Foundation
import Security

/// PixMax 原生接口错误；敏感响应头和临时 OSS 凭据不会进入错误文本。
enum PixmaxError: LocalizedError, Sendable {
    case invalidBaseURL
    case unauthorized
    case network(String)
    case http(Int, String)
    case api(String, String)
    case invalidResponse(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "PixMax Base URL 只允许 pixmax.ai 或 pixmax.cn 的 HTTPS 子域"
        case .unauthorized:
            "PixMax 登录态已失效，请重新登录"
        case .network(let message):
            "PixMax 网络异常：\(message)"
        case .http(let code, let message):
            "PixMax 接口 HTTP \(code)：\(message.prefix(240))"
        case .api(let code, let message):
            "PixMax 接口失败：\(message.prefix(240))（\(code)）"
        case .invalidResponse(let message):
            "PixMax 响应格式异常：\(message)"
        case .unsupported(let message):
            message
        }
    }

    var isAuthenticationFailure: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    var isTransientGatewayFailure: Bool {
        switch self {
        case .network:
            true
        case .http(let code, _):
            [429, 500, 502, 503, 504].contains(code)
        default:
            false
        }
    }
}

/// PixMax 登录方式。
enum PixmaxLoginMode: String, CaseIterable, Identifiable, Sendable {
    case personal
    case team

    var id: String { rawValue }
    var title: String { self == .personal ? "个人版" : "团队版" }
}

/// 个人版站点。
enum PixmaxSite: String, CaseIterable, Identifiable, Sendable {
    case international
    case china

    var id: String { rawValue }
    var title: String { self == .international ? "国际版 (.ai)" : "中国版 (.cn)" }
    var baseURL: String { self == .international ? "https://console.pixmax.ai" : "https://app.pixmax.cn" }
}

/// 登录成功后用于判断账号切换的非敏感身份摘要。
struct PixmaxUserIdentity: Hashable, Sendable {
    var stableID: String
    var summary: String
}

/// 已验证或创建的个人项目与画布。
struct PixmaxWorkspace: Hashable, Sendable {
    var projectUUID: String
    var fileUUID: String
    var wasCreated: Bool
}

/// 登录接口结果；只在内存中携带 Cookie，调用方应立即写入钥匙串。
struct PixmaxLoginResult: Sendable {
    var cookie: String
    var identity: PixmaxUserIdentity
}

/// PixMax 当前登录身份可见的积分信息。
struct PixmaxCreditSummary: Hashable, Sendable {
    var totalBalance: Double?
    var availableQuota: Double?
    var quotaMode: String
    var userTier: String

    /// 团队子账号必须使用子账号额度，避免误显示企业主账号总积分。
    func displayValue(isTeamAccount: Bool) -> String {
        if isTeamAccount {
            if quotaMode.uppercased() == "UNLIMITED" { return "不限额" }
            return Self.formatted(availableQuota)
        }
        return Self.formatted(totalBalance)
    }

    private static func formatted(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.grouping(.automatic).precision(.fractionLength(0...2)))
    }
}

/// PixMax 当前登录身份的一条生成消费记录。
struct PixmaxGenerationRecord: Identifiable, Hashable, Sendable {
    var id: String { taskUUID }
    var taskUUID: String
    var modelName: String
    var createTime: String
    var status: String
    var creditCost: Double?

    var statusTitle: String {
        switch status.uppercased() {
        case "COMPLETED", "COMPLETE", "SUCCESS": "已完成"
        case "CANCELLED", "CANCELED", "ABORTED": "已取消"
        case "RUNNING", "GENERATING", "QUEUE", "QUEUED": "进行中"
        case "FAILED", "FAIL": "失败"
        default: status.isEmpty ? "未知" : status
        }
    }

    var creditCostTitle: String {
        guard let creditCost else { return "--" }
        return creditCost.formatted(.number.grouping(.automatic).precision(.fractionLength(0...2)))
    }

    var createTimeTitle: String {
        if let milliseconds = Double(createTime), milliseconds > 0 {
            let seconds = milliseconds > 10_000_000_000 ? milliseconds / 1_000 : milliseconds
            return Date(timeIntervalSince1970: seconds).formatted(
                .dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            )
        }
        if let date = ISO8601DateFormatter().date(from: createTime) {
            return date.formatted(
                .dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            )
        }
        return createTime.isEmpty ? "--" : createTime
    }
}

/// PixMax 服务商卡片展示的账号概览。
struct PixmaxAccountOverview: Hashable, Sendable {
    var credit: PixmaxCreditSummary
    var recentGenerations: [PixmaxGenerationRecord]
}

/// URLSession 驱动的 PixMax JSON 客户端。
struct PixmaxAPIClient: @unchecked Sendable {
    let baseURL: URL
    let cookie: String
    let session: URLSession

    init(baseURL: String, cookie: String, session: URLSession = .shared) throws {
        self.baseURL = try Self.validatedBaseURL(baseURL)
        self.cookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    /// 只接受 PixMax 官方 HTTPS 域名及其子域。
    static func validatedBaseURL(_ value: String) throws -> URL {
        guard var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              ["pixmax.ai", "pixmax.cn"].contains(where: { host == $0 || host.hasSuffix(".\($0)") })
        else { throw PixmaxError.invalidBaseURL }
        guard components.user == nil, components.password == nil else { throw PixmaxError.invalidBaseURL }
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw PixmaxError.invalidBaseURL }
        return url
    }

    func userInfo() async throws -> [String: Any] {
        try await post("/user/api/user/info", payload: [:])
    }

    /// 读取当前登录身份的积分和最近生成消费记录。
    func accountOverview(pageSize: Int = 8) async throws -> PixmaxAccountOverview {
        let creditResponse = try await get("/user/api/credit/balance")
        let historyResponse = try await post("/user/api/credit/consumptions", payload: [
            "pageIndex": 1,
            "pageSize": min(20, max(1, pageSize)),
            "needTotalCount": true,
            "orderDirection": "DESC",
        ])
        let creditData = (creditResponse["data"] as? [String: Any]) ?? [:]
        let credit = PixmaxCreditSummary(
            totalBalance: Self.double(creditData, keys: ["totalBalance"]),
            availableQuota: Self.double(creditData, keys: ["availableQuota"]),
            quotaMode: Self.string(creditData, keys: ["quotaMode"]),
            userTier: Self.string(creditData, keys: ["userTier"])
        )
        let records = ((historyResponse["data"] as? [Any]) ?? [])
            .compactMap { $0 as? [String: Any] }
            .compactMap(Self.generationRecord)
        return PixmaxAccountOverview(credit: credit, recentGenerations: records)
    }

    func projectCreate(name: String) async throws -> String {
        let response = try await post("/user/api/project/createOrUpdate", payload: [
            "name": name,
            "projectType": "PERSONAL",
        ])
        guard let uuid = Self.extractUUID(response["data"]) else {
            throw PixmaxError.invalidResponse("创建项目后缺少 projectUuid")
        }
        return uuid
    }

    func fileCreate(projectUUID: String) async throws -> String {
        let response = try await post("/user/api/project/file/create", payload: [
            "projectUuid": projectUUID,
            "name": "Frame 1",
            "type": "FILE",
        ])
        guard let uuid = Self.extractUUID(response["data"]) else {
            throw PixmaxError.invalidResponse("创建画布后缺少 fileUuid")
        }
        return uuid
    }

    func canvas(fileUUID: String) async throws -> [String: Any] {
        try await post("/user/api/canvas/get", payload: ["fileUuid": fileUUID])
    }

    func ensureWorkspace(projectUUID: String?, fileUUID: String?) async throws -> PixmaxWorkspace {
        if let projectUUID, !projectUUID.isEmpty, let fileUUID, !fileUUID.isEmpty {
            do {
                _ = try await canvas(fileUUID: fileUUID)
                return PixmaxWorkspace(projectUUID: projectUUID, fileUUID: fileUUID, wasCreated: false)
            } catch let error as PixmaxError {
                if error.isAuthenticationFailure { throw error }
                // 旧账号画布、已删除画布和失效 revision 都重新创建，不改写远端历史。
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let project = try await projectCreate(name: "黑妞 PixMax \(formatter.string(from: Date()))")
        let file = try await fileCreate(projectUUID: project)
        return PixmaxWorkspace(projectUUID: project, fileUUID: file, wasCreated: true)
    }

    func post(
        _ path: String,
        payload: [String: Any],
        allowedErrorCodes: Set<String> = []
    ) async throws -> [String: Any] {
        try await request(path, method: "POST", payload: payload, allowedErrorCodes: allowedErrorCodes)
    }

    func get(_ path: String) async throws -> [String: Any] {
        try await request(path, method: "GET", payload: nil, allowedErrorCodes: [])
    }

    private func request(
        _ path: String,
        method: String,
        payload: [String: Any]?,
        allowedErrorCodes: Set<String>
    ) async throws -> [String: Any] {
        let url = baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(baseURL.absoluteString + "/", forHTTPHeaderField: "Referer")
        request.setValue("HeiNiu/1.0 URLSession", forHTTPHeaderField: "User-Agent")
        if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if let payload { request.httpBody = try JSONSerialization.data(withJSONObject: payload) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PixmaxError.network(Self.safeNetworkMessage(error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw PixmaxError.invalidResponse("缺少 HTTP 响应")
        }
        if http.statusCode == 401 { throw PixmaxError.unauthorized }
        guard http.statusCode == 200 else {
            throw PixmaxError.http(http.statusCode, Self.safeResponseMessage(data))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PixmaxError.invalidResponse("接口返回非 JSON")
        }
        if object["success"] as? Bool == false {
            let code = Self.string(object, keys: ["errCode", "errorCode", "code"])
            let message = Self.string(object, keys: ["errMsg", "errMessage", "errorMessage", "message"])
            if code.localizedCaseInsensitiveContains("Unauthorized") ||
                message.localizedCaseInsensitiveContains("Unauthorized") {
                throw PixmaxError.unauthorized
            }
            if !allowedErrorCodes.contains(code) {
                throw PixmaxError.api(code.isEmpty ? "Unknown" : code, message.isEmpty ? "未知接口错误" : message)
            }
        }
        return object
    }

    private static func generationRecord(_ dictionary: [String: Any]) -> PixmaxGenerationRecord? {
        let taskUUID = string(dictionary, keys: ["taskUuid", "taskUUID", "uuid", "id"])
        guard !taskUUID.isEmpty else { return nil }
        return PixmaxGenerationRecord(
            taskUUID: taskUUID,
            modelName: string(dictionary, keys: ["modelName", "modelCode", "model"]),
            createTime: string(dictionary, keys: ["createTime", "createdAt", "createTimestamp"]),
            status: string(dictionary, keys: ["status", "taskStatus"]),
            creditCost: double(dictionary, keys: ["totalCost", "creditCost", "cost"])
        )
    }

    static func identity(from response: [String: Any]) throws -> PixmaxUserIdentity {
        let dictionaries = dictionariesDepthFirst(response["data"] ?? response)
        if let subUser = dictionaries.first(where: {
            !string($0, keys: ["subUserUuid", "subUserAccount"]).isEmpty
        }) {
            let subUserUUID = string(subUser, keys: ["subUserUuid", "uuid", "id"])
            let subUserAccount = string(subUser, keys: ["subUserAccount", "account", "phone", "email"])
            let stableID: String
            if !subUserUUID.isEmpty {
                stableID = subUserUUID
            } else if !subUserAccount.isEmpty {
                let digest = SHA256.hash(data: Data(subUserAccount.utf8))
                    .map { String(format: "%02x", $0) }
                    .joined()
                stableID = "sub-\(digest.prefix(24))"
            } else {
                throw PixmaxError.invalidResponse("子账号信息缺少稳定标识")
            }
            let display = string(
                subUser,
                keys: ["subUserAccount", "subUserName", "displayName", "nickname", "account", "phone", "email"]
            )
            return PixmaxUserIdentity(
                stableID: stableID,
                summary: maskedAccountSummary(display.isEmpty ? "企业子账号" : display)
            )
        }
        let idKeys = ["userUuid", "uuid", "userId", "id", "subUserUuid"]
        let summaryKeys = ["nickname", "nickName", "email", "phone", "mobile", "subUserAccount", "account"]
        let stableID = dictionaries.lazy.compactMap { dictionary in string(dictionary, keys: idKeys).nilIfEmpty }.first
        let summary = dictionaries.lazy.compactMap { dictionary in string(dictionary, keys: summaryKeys).nilIfEmpty }.first
        guard let stableID else { throw PixmaxError.invalidResponse("用户信息缺少稳定账号标识") }
        return PixmaxUserIdentity(
            stableID: stableID,
            summary: maskedAccountSummary(summary ?? "账号 \(stableID.prefix(8))")
        )
    }

    /// 登录状态只展示脱敏账号摘要；完整手机号或邮箱不进入设置 JSON。
    private static func maskedAccountSummary(_ value: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.range(of: #"^\d{11}$"#, options: .regularExpression) != nil {
            return "\(clean.prefix(3))****\(clean.suffix(4))"
        }
        if let at = clean.firstIndex(of: "@") {
            let local = clean[..<at]
            let domain = clean[at...]
            return "\(local.prefix(1))***\(domain)"
        }
        return clean
    }

    static func extractUUID(_ value: Any?) -> String? {
        if let string = value as? String { return string.nilIfEmpty }
        guard let dictionary = value as? [String: Any] else { return nil }
        return string(dictionary, keys: ["uuid", "projectUuid", "workspaceId", "fileUuid", "id"]).nilIfEmpty
    }

    static func string(_ dictionary: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
            if let value = dictionary[key] as? NSNumber { return value.stringValue }
        }
        return ""
    }

    static func double(_ dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dictionary[key] as? NSNumber { return value.doubleValue }
            if let value = dictionary[key] as? String, let number = Double(value) { return number }
        }
        return nil
    }

    static func dictionariesDepthFirst(_ value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            return [dictionary] + dictionary.values.flatMap(dictionariesDepthFirst)
        }
        if let array = value as? [Any] { return array.flatMap(dictionariesDepthFirst) }
        return []
    }

    private static func safeNetworkMessage(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "请求超时"
            case .notConnectedToInternet: return "当前没有网络连接"
            case .cannotFindHost, .cannotConnectToHost: return "无法连接 PixMax"
            case .networkConnectionLost: return "网络连接中断"
            default: return "连接失败（\(urlError.code.rawValue)）"
            }
        }
        return "连接失败"
    }

    private static func safeResponseMessage(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "服务返回异常"
        }
        let message = string(object, keys: ["errMsg", "errMessage", "errorMessage", "message"])
        return message.isEmpty ? "服务返回异常" : message
    }
}

/// 不依赖浏览器的密码登录和 Cookie 导入验证。
struct PixmaxAuthenticator: @unchecked Sendable {
    static let rsaPublicKeyDER = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDrJMmCeIkfaRK2JCvTVGPxd3kpO1MVanc+89XShiOFAWRcXFIx7X+nC5m5Z0bNM3OnP4Cz/Xl9w//Ib12cE9cjj16Hc3eHsUe8ImX5RQugEhpyb8aHECqqjG83RMEjPiBflr+/RnKiyjX6vTlSRc63moCzMB2zXBntmPdpB2yMhwIDAQAB"

    let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieAcceptPolicy = .never
            configuration.httpShouldSetCookies = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func personalLogin(site: PixmaxSite, account: String, password: String) async throws -> PixmaxLoginResult {
        let cleanAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAccount.isEmpty, !password.isEmpty else {
            throw PixmaxError.unsupported("请输入账号和密码")
        }
        let loginType: String
        if site == .international {
            guard cleanAccount.contains("@") else { throw PixmaxError.unsupported("国际版请使用邮箱登录") }
            loginType = "EMAIL"
        } else {
            loginType = cleanAccount.contains("@") ? "EMAIL" : "PHONE"
        }
        return try await passwordLogin(
            baseURL: site.baseURL,
            path: "/user/api/user/password/login",
            payload: [
                "loginType": loginType,
                "account": cleanAccount,
                "password": try Self.encryptPassword(password),
            ]
        )
    }

    func teamLogin(baseURL: String, teamLinkOrUUID: String, account: String, password: String) async throws -> PixmaxLoginResult {
        let mainUserUUID = try Self.extractMainUserUUID(teamLinkOrUUID)
        let cleanAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAccount.isEmpty, !password.isEmpty else {
            throw PixmaxError.unsupported("请输入企业子账号和密码")
        }
        let encrypted = try Self.encryptPassword(password)
        let mainUserInfo: [String: Any]
        do {
            (mainUserInfo, _) = try await unauthenticatedPost(
                baseURL: baseURL,
                path: "/user/api/sub-user/mainUserInfo",
                payload: ["mainUserUuid": mainUserUUID]
            )
        } catch let error as PixmaxError {
            if case .api(let code, _) = error, code == "User.NotFound" {
                throw PixmaxError.unsupported("团队链接或 mainUserUuid 不正确，请粘贴企业子账号登录页地址栏中的完整链接")
            }
            throw error
        }
        let explicitEnterpriseFlags = PixmaxAPIClient.dictionariesDepthFirst(mainUserInfo).compactMap { dictionary -> Bool? in
            if let value = dictionary["enterpriseFlag"] as? Bool { return value }
            if let value = dictionary["enterpriseFlag"] as? NSNumber { return value.boolValue }
            return nil
        }
        if explicitEnterpriseFlags.contains(false) && !explicitEnterpriseFlags.contains(true) {
            throw PixmaxError.unsupported("该 mainUserUuid 不是可用的 PixMax 企业主账号")
        }
        do {
            return try await passwordLogin(
                baseURL: baseURL,
                path: "/user/api/sub-user/login",
                payload: [
                    "mainUserUuid": mainUserUUID,
                    "subUserAccount": cleanAccount,
                    "password": encrypted,
                ]
            )
        } catch let error as PixmaxError {
            if case .api(let code, _) = error,
               code == "User.NotFound" || code == "SubUser.NotFound" {
                throw PixmaxError.unsupported("该企业主账号下没有这个子账号，请核对团队链接与子账号")
            }
            throw error
        }
    }

    func importCookie(baseURL: String, cookie: String) async throws -> PixmaxLoginResult {
        let clean = Self.normalizedCookie(cookie)
        guard !clean.isEmpty else { throw PixmaxError.unsupported("请粘贴完整 Cookie") }
        let client = try PixmaxAPIClient(baseURL: baseURL, cookie: clean, session: session)
        let response = try await client.userInfo()
        return PixmaxLoginResult(cookie: clean, identity: try PixmaxAPIClient.identity(from: response))
    }

    private func passwordLogin(baseURL: String, path: String, payload: [String: Any]) async throws -> PixmaxLoginResult {
        let (object, response) = try await unauthenticatedPost(baseURL: baseURL, path: path, payload: payload)
        let cookie = try Self.cookieHeader(from: response)
        let client = try PixmaxAPIClient(baseURL: baseURL, cookie: cookie, session: session)
        let info = try await client.userInfo()
        let identity = try PixmaxAPIClient.identity(from: info)
        _ = object
        return PixmaxLoginResult(cookie: cookie, identity: identity)
    }

    private func unauthenticatedPost(
        baseURL: String,
        path: String,
        payload: [String: Any]
    ) async throws -> ([String: Any], HTTPURLResponse) {
        let base = try PixmaxAPIClient.validatedBaseURL(baseURL)
        let url = base.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(base.absoluteString + "/", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PixmaxError.network("登录请求失败")
        }
        guard let http = response as? HTTPURLResponse else { throw PixmaxError.invalidResponse("登录响应无 HTTP 状态") }
        if http.statusCode == 401 { throw PixmaxError.unauthorized }
        guard http.statusCode == 200 else {
            throw PixmaxError.http(http.statusCode, PixmaxAPIClient.string(
                (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:],
                keys: ["errMsg", "errMessage", "message"]
            ))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PixmaxError.invalidResponse("登录接口返回非 JSON")
        }
        if object["success"] as? Bool == false {
            let code = PixmaxAPIClient.string(object, keys: ["errCode", "errorCode"])
            let message = PixmaxAPIClient.string(object, keys: ["errMsg", "errMessage", "message"])
            throw PixmaxError.api(code.isEmpty ? "Login.Failed" : code, message.isEmpty ? "登录失败" : message)
        }
        return (object, http)
    }

    static func encryptPassword(_ password: String) throws -> String {
        guard let keyData = Data(base64Encoded: rsaPublicKeyDER) else {
            throw PixmaxError.invalidResponse("RSA 公钥不可用")
        }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 1024,
        ]
        var creationError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &creationError) else {
            throw PixmaxError.invalidResponse("无法加载 RSA 公钥")
        }
        guard SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionPKCS1) else {
            throw PixmaxError.unsupported("系统不支持 PixMax RSA 加密规则")
        }
        var encryptionError: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            key,
            .rsaEncryptionPKCS1,
            Data(password.utf8) as CFData,
            &encryptionError
        ) as Data? else {
            throw PixmaxError.unsupported("密码过长或 RSA 加密失败")
        }
        return encrypted.base64EncodedString()
    }

    static func extractMainUserUUID(_ value: String) throws -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if UUID(uuidString: clean) != nil { return clean }
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..<clean.endIndex, in: clean)),
              let range = Range(match.range, in: clean)
        else { throw PixmaxError.unsupported("团队链接中没有有效的 mainUserUuid") }
        return String(clean[range])
    }

    private static func normalizedCookie(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cookieHeader(from response: HTTPURLResponse) throws -> String {
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            fields[String(describing: key)] = String(describing: value)
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: response.url!)
        let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        guard !header.isEmpty else { throw PixmaxError.invalidResponse("登录成功但响应没有 Set-Cookie") }
        return header
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
