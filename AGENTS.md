# 黑妞短剧 · 长久记忆（AGENTS）

面向后续在本仓库协作的 AI / 开发者。更完整的结构化文档见 `HeiNiu/HeiNiu.docc/`。

## 产品

- 名称：**黑妞短剧**
- Bundle ID：`cn.codable.heiniu`
- 平台：macOS 15+，SwiftUI，中文 UI
- 协议：MIT
- 定位：短剧项目、知识资料、提示词、模型服务配置与全局节点工作流工作台，不包含自定义聊天智能体

## 架构要点

- 入口：`HeiNiuApp` 注入 `SettingsStore`、`KnowledgeStore`、`WorkflowStore`、`ProjectStore` 与 `ProjectMediaGenerator`
- 侧栏：工作台（项目 / 知识库 / 工作流）+ 设置
- 工作流仍是独立的全局模板；项目只选择模板、关联一次全局运行，并保存卡片式分镜草稿、媒体相对路径与审核状态
- 剧本与分镜创作由提示词库和工作流承载，不设独立剧本或分镜侧栏模块
- 密钥只进钥匙串；配置进 Application Support JSON
- 解码一律容错（`decodeIfPresent` + 默认值）

## 数据路径

`~/Library/Application Support/HeiNiu/`

- `settings.json`
- `KnowledgeBase/knowledge.sqlite`
- `KnowledgeBase/Files/<documentID>/...`
- `Workflows/workflows.json`
- `Workflows/Runs/<workflowID>/<runID>/run.json`
- `Workflows/Runs/<workflowID>/<runID>/Assets/...`
- `Projects/project-board.json`

`KnowledgeBase/` 是当前全局知识库；不要与历史智能体留下的 `knowledge.json` 和 `Knowledge/` 混淆，后两者仍不读取或写入。

知识库使用 SQLite 保存集合、文档、标签、分块与 Float32 向量，原文件复制到 `KnowledgeBase/Files/`。普通文件导入支持直接保存并预览 JPG、PNG、HEIC 等图片，同时生成可编辑的文件说明，但不执行 OCR 或自动视觉推断；需要自动理解图片时使用内置“添加知识库”工作流。嵌入接口支持标准 `/embeddings` 和豆包 `/embeddings/multimodal` 两种请求格式。普通设置备份不含知识内容；知识库通过独立 `.heiniukb` 归档迁移。

工作流定义使用带格式版本的容错 JSON，400ms 防抖原子写入。只读内置模板有稳定 ID 的“添加知识库”和“汽车内广告分镜”。后者以文章为输入，先语义检索全局创作规则，同一份候选规则同时约束要素提取、分镜规划和审校，再逐项核验规则解析后的人物、产品和车型/座舱知识。不在 Swift 中写死人名、角色映射或某种文档表格格式；只有正文明确声明为规则/强制/优先级/覆盖的资料才能改写文章身份。缺口会把父运行持久化为 `waitingForKnowledge`，按人物→产品→车内场景启动前者补库，再从知识准备节点恢复。运行文本与节点状态写入 `run.json`，生成媒体、输入文件夹副本和 `Assets/KnowledgeReferences/` 参考包只写入本次运行目录。运行历史不自动清理；普通设置备份不包含工作流或运行媒体。

项目以卡片展示。新建时先填写项目名并选择工作流，再进入统一运行输入页选择文件夹等本次参数；文本输入可粘贴或从 TXT、Markdown、RTF、含文本 PDF、DOCX 导入，最多 80,000 字符且不执行 OCR。确认开始运行后才创建项目，成功后自动进入分镜审核。重新运行也必须重新确认本次输入。审核页把旧式整段文本容错拆成单镜头卡片；每张卡片管理最多 9 张混合参考图、一条共用提示词和一个竖屏视频。知识参考元数据会从可编辑提示词移除并映射为 `.knowledge` 图片。用户导入或卡片直接生成的媒体仍写入关联运行的 `Assets/`，项目文件只保存相对路径，不复制媒体或工作流定义。

历史根目录 `projects.json` 以及 `Projects/` 中除 `project-board.json` 外的旧内容仍不读取、写入或主动删除。

## 文档注释规范

- 使用 DocC：`///` 中文
- 类型、重要属性、公开方法均应有说明
- 长久记忆文章写在 `HeiNiu.docc/*.md`，根目录 `AGENTS.md` 为索引摘要
- 在线文档通过 GitHub Actions 发布 Pages
- 本地不要提交生成的 `docs/` 静态站

## 明确不做

- 自定义 AI 角色、聊天会话、角色专属知识、技能/插件与 MCP 智能体工具
- 资产库模块
- 独立剧本与分镜模块
- OCR、网页抓取、文件夹持续同步
- App Store 沙盒上架
- 把 API Key 写入明文 JSON
