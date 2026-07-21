# 架构总览

> 长久记忆：黑妞短剧的模块边界与数据流。

## 分层

```text
HeiNiuApp
  └─ MainView（侧栏导航）
       ├─ 工作台：项目 / 知识库 / 剧本 / 分镜 / 资产库
       └─ 配置：设置
```

### 状态与依赖注入

应用入口创建三个 `@Observable` 主仓库并通过 `.environment` 注入：

- ``SettingsStore``：LLM、生图、生视频服务商、提示词库与备份
- ``ProjectStore``：项目列表与项目流水线状态
- ``KnowledgeStore``：知识集合、资料、索引、检索与独立归档

视图通过仓库访问状态，不直接维护持久化格式。

### LLM 调用链

1. 流水线步骤选择 ``PromptItem`` 及其服务商和模型
2. 若项目引用知识资料，``KnowledgeStore`` 根据步骤、项目简报、输入与上游产物生成查询并召回片段
3. ``ProjectPipelineRunner`` 把带来源标记的知识上下文与系统提示、用户输入组装为请求
4. ``LLMClientFactory`` 按协议创建 OpenAI 兼容或 Anthropic 客户端
5. 返回文本、知识引用与警告写入项目的 `pipeline.json`
6. API Key 只从钥匙串读取，不进入配置 JSON

### 知识检索链

1. 导入器抽取 TXT/Markdown/JSON/CSV/字幕、PDF、RTF 或 DOCX 正文，原文件复制到应用数据目录
2. 正文按约 1,000 字符、150 字符重叠切块
3. ``OpenAIEmbeddingClient`` 以每批最多 32 个片段调用 OpenAI 兼容 `/embeddings`
4. SQLite 保存 Float32 向量；检索时用余弦相似度排序
5. 每次最多返回 6 段、约 8,000 字符，同一资料最多两段

## 设计原则

- **项目驱动**：AI 生成属于明确的项目步骤，不形成开放式聊天会话
- **密钥与配置分离**：配置进 `settings.json`，Key 进 Keychain
- **容错解码**：新增模型字段使用 `decodeIfPresent` 默认值
- **显式知识范围**：项目未引用资料时完全沿用原有生成逻辑
- **中文 UI**：产品文案与文档注释均使用中文
