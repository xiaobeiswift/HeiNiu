/// KeychainHelper 模块。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation
import Security

/// 钥匙串读写工具。
///
/// 使用通用密码项（`kSecClassGenericPassword`），
/// `service` 默认为 Bundle Identifier（回退 `cn.codable.heiniu`）。
///
/// ### 账户命名约定
/// - LLM：`provider-<uuid>`
/// - 生图：`image-provider-<uuid>`
/// - 生视频：`video-provider-<uuid>`
///
/// - Important: 切勿将 API Key 写入 JSON 配置文件。
enum KeychainHelper {
    /// 钥匙串 service 字段。
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "cn.codable.heiniu"
    }

    /// 读取字符串密钥。
    /// - Parameter account: 账户名（如 `provider-...`）。
    /// - Returns: UTF-8 字符串；不存在则 `nil`。
    static func get(account: String) -> String? {
        /// query。
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 写入或更新字符串密钥。
    /// - Parameters:
    ///   - value: 密钥明文。
    ///   - account: 账户名。
    /// - Returns: 是否成功。
    @discardableResult
    /// 写入钥匙串值
    ///
    /// 写入钥匙串值。
    static func set(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)

        /// query。
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        /// attributes。
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return true
        }

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }

        return false
    }

    /// 删除密钥。
    /// - Parameter account: 账户名。
    /// - Returns: 删除成功或不存在时均为 `true`。
    @discardableResult
    /// 删除钥匙串项
    ///
    /// 删除钥匙串项。
    static func delete(account: String) -> Bool {
        /// query。
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
