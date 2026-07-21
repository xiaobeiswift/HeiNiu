# 架构总览

> 长久记忆：黑妞短剧的模块边界与数据流。

## 分层

```text
HeiNiuApp
  └─ MainView（侧栏导航）
       ├─ 工作台：知识库 / 剧本 / 分镜 / 资产库
       └─ 配置：设置
```

### 状态与依赖注入

应用入口创建两个 `@Observable` 主仓库并通过 `.environment` 注入：

- ``SettingsStore``：LLM、生图、生视频服务商、提示词库与备份
- ``KnowledgeStore``：知识集合、资料、索引、检索与独立归档

视图通过仓库访问状态，不直接维护持久化格式。

### 知识索引链

1. 导入器抽取 TXT/Markdown/JSON/CSV/字幕、PDF、RTF 或 DOCX 正文，原文件复制到应用数据目录
2. 正文按约 1,000 字符、150 字符重叠切块
3. ``OpenAIEmbeddingClient`` 以每批最多 32 个片段调用标准 `/embeddings`；豆包多模态模式按顺序调用 `/embeddings/multimodal`
4. SQLite 在本机保存 Float32 向量、分块正文和索引状态

## 设计原则

- **密钥与配置分离**：配置进 `settings.json`，Key 进 Keychain
- **容错解码**：新增模型字段使用 `decodeIfPresent` 默认值
- **资料独立**：知识库不依赖项目、聊天会话或智能体
- **中文 UI**：产品文案与文档注释均使用中文
