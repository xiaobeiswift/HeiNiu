/// PixMax 个人版 / 团队版原生登录框。

import SwiftUI

struct PixmaxLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @Environment(PixmaxSessionManager.self) private var sessions

    let providerID: UUID
    let automaticallyPresented: Bool

    @State private var mode: PixmaxLoginMode = .personal
    @State private var site: PixmaxSite = .international
    @State private var account = ""
    @State private var password = ""
    @State private var teamLinkOrUUID = ""
    @State private var cookie = ""
    @State private var showsCookieImport = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var provider: VideoProvider? { settings.videoProvider(id: providerID) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(automaticallyPresented ? "PixMax 登录已失效" : "登录 PixMax")
                        .font(.title2.weight(.semibold))
                    Text(provider?.name ?? "PixMax")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Button("取消") { close() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
            }
            .padding(20)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("账号类型", selection: $mode) {
                        ForEach(PixmaxLoginMode.allCases) { item in Text(item.title).tag(item) }
                    }
                    .pickerStyle(.segmented)

                    if mode == .personal {
                        personalFields
                    } else {
                        teamFields
                    }

                    DisclosureGroup("高级：导入完整 Cookie", isExpanded: $showsCookieImport) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextEditor(text: $cookie)
                                .font(.caption.monospaced())
                                .frame(minHeight: 90)
                                .padding(6)
                                .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.stroke))
                            Text("Cookie 必须先通过 /user/info 验证，验证成功后才会写入钥匙串。")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textTertiary)
                            Button("验证并导入 Cookie") { submitCookie() }
                                .buttonStyle(.bordered)
                                .disabled(isWorking || cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.top, 8)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(AppTheme.danger)
                            .textSelection(.enabled)
                    }

                    Label("登录全程使用 URLSession，不会打开或控制浏览器。密码只用于本次 RSA 加密请求，永不保存。", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(20)
            }

            Divider()
            HStack {
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button(mode == .personal ? "登录个人版" : "登录团队版") { submitPassword() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .foregroundStyle(.black)
                    .disabled(isWorking || !canSubmitPassword)
            }
            .padding(16)
        }
        .frame(width: 540, height: 600)
        .onAppear {
            if provider?.effectiveBaseURL.contains("pixmax.cn") == true { site = .china }
            if provider?.adapterSettings["loginMode"] == PixmaxLoginMode.team.rawValue { mode = .team }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private var personalFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("站点", selection: $site) {
                ForEach(PixmaxSite.allCases) { item in Text(item.title).tag(item) }
            }
            TextField(site == .international ? "邮箱" : "手机号或邮箱", text: $account)
                .textFieldStyle(.roundedBorder)
            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)
            Text("首版不支持依赖 Turnstile 的短信或邮件验证码登录。")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var teamFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("团队链接或 mainUserUuid")
                .font(.callout.weight(.medium))
            TextField("粘贴企业子账号登录页地址栏中的完整链接", text: $teamLinkOrUUID)
                .textFieldStyle(.roundedBorder)
            Text("企业子账号")
                .font(.callout.weight(.medium))
            TextField("输入登录页显示的子账号", text: $account)
                .textFieldStyle(.roundedBorder)
            Text("登录密码")
                .font(.callout.weight(.medium))
            SecureField("输入子账号密码", text: $password)
                .textFieldStyle(.roundedBorder)
            Text("会先验证企业主账号身份，再执行子账号登录；生成仍使用 PERSONAL 项目画布。")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var canSubmitPassword: Bool {
        !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        (mode == .personal || !teamLinkOrUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func submitPassword() {
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            defer { isWorking = false; password = "" }
            do {
                if mode == .personal {
                    try await sessions.loginPersonal(providerID: providerID, site: site, account: account, password: password)
                } else {
                    try await sessions.loginTeam(
                        providerID: providerID,
                        teamLinkOrUUID: teamLinkOrUUID,
                        account: account,
                        password: password
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submitCookie() {
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let baseURL: String
                if mode == .personal {
                    baseURL = site.baseURL
                } else if let provider {
                    baseURL = provider.effectiveBaseURL
                } else {
                    throw PixmaxError.invalidResponse("服务商已删除")
                }
                try await sessions.importCookie(providerID: providerID, baseURL: baseURL, cookie: cookie, mode: mode)
                cookie = ""
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func close() {
        sessions.dismissLogin(providerID: providerID)
        dismiss()
    }
}
