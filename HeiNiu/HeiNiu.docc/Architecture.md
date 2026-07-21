# 架构总览

> 长久记忆：黑妞短剧的模块边界与数据流。

## 分层

```text
HeiNiuApp
  └─ MainView（侧栏导航）
       ├─ 工作台：项目 / 剧本 / 分镜 / 资产库
       └─ 配置：设置
```

### 状态与依赖注入

应用入口创建两个 `@Observable` 主仓库并通过 `.environment` 注入：

- ``SettingsStore``：LLM、生图、生视频服务商、提示词库与备份
- ``ProjectStore``：项目列表与项目流水线状态

视图通过仓库访问状态，不直接维护持久化格式。

### LLM 调用链

1. 流水线步骤选择 ``PromptItem`` 及其服务商和模型
2. ``ProjectPipelineRunner`` 组装系统提示与用户输入
3. ``LLMClientFactory`` 按协议创建 OpenAI 兼容或 Anthropic 客户端
4. 返回文本写入项目的 `pipeline.json`
5. API Key 只从钥匙串读取，不进入配置 JSON

## 设计原则

- **项目驱动**：AI 生成属于明确的项目步骤，不形成开放式聊天会话
- **密钥与配置分离**：配置进 `settings.json`，Key 进 Keychain
- **容错解码**：新增模型字段使用 `decodeIfPresent` 默认值
- **中文 UI**：产品文案与文档注释均使用中文
