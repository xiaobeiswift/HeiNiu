# 黑妞短剧 · 长久记忆（AGENTS）

面向后续在本仓库协作的 AI / 开发者。更完整的结构化文档见 `HeiNiu/HeiNiu.docc/`。

## 产品

- 名称：**黑妞短剧**
- Bundle ID：`cn.codable.heiniu`
- 平台：macOS 15+，SwiftUI，中文 UI
- 协议：MIT
- 定位：短剧项目、知识资料、提示词、模型服务配置与全局节点工作流工作台，不包含自定义聊天智能体

## 架构要点

- 入口：`HeiNiuApp` 注入 `SettingsStore`、`KnowledgeStore`、`WorkflowStore` 与 `ProjectStore`
- 侧栏：工作台（项目 / 知识库 / 工作流）+ 设置
- 工作流仍是独立的全局模板；项目只选择模板、关联一次全局运行，并保存分镜草稿与审核状态
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

工作流定义使用带格式版本的容错 JSON，400ms 防抖原子写入。内置“添加知识库”工作流接受图片文件夹和整理要求，逐图调用支持视觉的 LLM，把原图与生成知识写入全局知识库；嵌入配置完整时自动索引。运行文本与节点状态写入 `run.json`，生成媒体和输入文件夹副本只写入本次运行的 `Assets/`。运行历史不自动清理；普通设置备份不包含工作流或运行媒体。

项目以卡片展示。新建时先填写项目名并选择工作流，再进入统一运行输入页选择文件夹等本次参数；确认开始运行后才创建项目，成功后自动进入分镜审核。重新运行也必须重新确认本次输入。项目文件只保存工作流与运行 ID、状态、分镜草稿、审核意见和警告，不复制工作流定义或媒体。

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
