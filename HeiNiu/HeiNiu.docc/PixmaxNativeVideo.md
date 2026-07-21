# PixMax 原生生视频

> 长久记忆：PixMax 的无浏览器登录、会话心跳、画布提交与多模态输入边界。

## 原生会话

``PixmaxAuthenticator`` 使用 `URLSession` 完成国际版/中国版个人密码登录、企业子账号登录和 Cookie 导入验证。密码在本机通过 Security.framework 按 PixMax 前端规则执行 RSA PKCS#1 v1.5 加密，仅用于当次请求。成功响应的 Cookie 经 `/user/api/user/info` 验证后只写入 `video-provider-<uuid>` 钥匙串项。

整条链路不运行 Python，不启动 Chrome、Safari、Playwright 或 CDP，也不使用 WebKit 及浏览器 Cookie。Base URL 仅接受 HTTPS 的 `pixmax.ai`、`pixmax.cn` 及其子域。

``PixmaxSessionManager`` 为每个已启用的 PixMax 服务商管理独立状态。启用、应用启动和登录成功时立即检查，之后每 60 秒请求一次 `/user/api/user/info`。只有 HTTP 401 或 PixMax Unauthorized 会进入登录失效队列；断网、超时和 5xx 仅显示网络异常。同一次失效只自动弹出一次，关闭开关会立即取消心跳。

已登录的服务商卡片会读取 `/user/api/credit/balance` 和 `/user/api/credit/consumptions`，展示积分以及最近生成任务。团队版只展示当前子账号的 `availableQuota` 或不限额状态，不混用企业主账号的 `totalBalance`。

## 画布与生成

``PixmaxVideoGenerationAdapter`` 将素材去重、阿里云 OSS V1 HMAC-SHA1 签名上传、合规检查、画布节点批量写入、生成轮询和成片下载全部编译进应用。不提供浏览器 OSS 兜底，也不持久化 OSS 临时密钥。上传、审核、画布写入和付费提交按服务商串行。

生视频节点保留 `referenceImage` 端口 ID，并支持最多 9 张图片、3 段视频和 3 段音频。``WorkflowConnection`` 的 `targetOrder` 决定“图片1…9 / 视频1…3 / 音频1…3”编号。提示词中的别名会替换为 PixMax mention token，未提及的已连接素材会自动前置。

内置模型目录是只读的。画幅、分辨率、时长、音频开关和参考素材组合必须在实际付费提交前通过模型能力校验。生成会每秒轮询并响应任务取消；网关临时错误有 60 秒宽限。完成时下载全部 `resultAssets`，主视频进入节点输出，额外结果留在同次 `Assets/` 并写入运行警告。
