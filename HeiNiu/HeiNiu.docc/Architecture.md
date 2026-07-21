# 架构总览

> 长久记忆：黑妞短剧的模块边界与数据流。

## 分层

```text
HeiNiuApp
  └─ MainView（侧栏导航）
       ├─ 工作台：知识库 / 工作流 / 剧本 / 分镜
       └─ 配置：设置
```

### 状态与依赖注入

应用入口创建三个 `@Observable` 主仓库并通过 `.environment` 注入：

- ``SettingsStore``：LLM、生图、生视频服务商、提示词库与备份
- ``KnowledgeStore``：知识集合、资料、索引、检索与独立归档
- ``WorkflowStore``：全局工作流定义、自动保存与完整运行历史

视图通过仓库访问状态，不直接维护持久化格式。

### 知识索引链

1. 导入器抽取 TXT/Markdown/JSON/CSV/字幕、PDF、RTF 或 DOCX 正文，原文件复制到应用数据目录
2. 正文按约 1,000 字符、150 字符重叠切块
3. ``OpenAIEmbeddingClient`` 以每批最多 32 个片段调用标准 `/embeddings`；豆包多模态模式按顺序调用 `/embeddings/multimodal`
4. SQLite 在本机保存 Float32 向量、分块正文和索引状态

### 工作流执行链

1. ``WorkflowNodeCatalog`` 统一提供节点名称、端口、卡片摘要、帮助与校验元数据
2. ``WorkflowValidator`` 检查必填端口、类型、服务配置、普通环路和显式循环结构
3. ``WorkflowExecutor`` 按稳定顺序串行执行可达节点，条件分支跳过未命中出口，循环强制限制在 1–20 次
4. ``WorkflowStore`` 原子保存定义和运行记录；媒体适配器把产物下载到本次运行的 `Assets/`

媒体协议通过 ``ImageGenerationAdapter``、``VideoGenerationAdapter`` 和 ``MediaAdapterRegistry`` 在源码内注册。新增协议只扩展适配器及能力描述，不改变画布节点或调度器。

## 设计原则

- **密钥与配置分离**：配置进 `settings.json`，Key 进 Keychain
- **容错解码**：新增模型字段使用 `decodeIfPresent` 默认值
- **资料独立**：知识库不依赖项目、聊天会话或智能体
- **工作流独立**：工作流是全局模板，不引入项目层或资产库
- **中文 UI**：产品文案与文档注释均使用中文
