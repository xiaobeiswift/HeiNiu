# 黑妞短剧 · 长久记忆（AGENTS）

面向后续在本仓库协作的 AI / 开发者。更完整的结构化文档见 `HeiNiu/HeiNiu.docc/`。

## 产品

- 名称：**黑妞短剧**
- Bundle ID：`cn.codable.heiniu`
- 平台：macOS 15+，SwiftUI，中文 UI
- 协议：MIT
- 定位：短剧知识资料、提示词与模型服务配置工作台，不包含项目或自定义聊天智能体

## 架构要点

- 入口：`HeiNiuApp` 注入 `SettingsStore` 与 `KnowledgeStore`
- 侧栏：工作台（知识库 / 剧本 / 分镜 / 资产库）+ 设置
- 当前不包含项目管理或创作流水线；剧本、分镜和资产库仍为占位模块
- 密钥只进钥匙串；配置进 Application Support JSON
- 解码一律容错（`decodeIfPresent` + 默认值）

## 数据路径

`~/Library/Application Support/HeiNiu/`

- `settings.json`
- `KnowledgeBase/knowledge.sqlite`
- `KnowledgeBase/Files/<documentID>/...`

`KnowledgeBase/` 是当前全局知识库；不要与历史智能体留下的 `knowledge.json` 和 `Knowledge/` 混淆，后两者仍不读取或写入。

知识库使用 SQLite 保存集合、文档、标签、分块与 Float32 向量，原文件复制到 `KnowledgeBase/Files/`。嵌入接口支持标准 `/embeddings` 和豆包 `/embeddings/multimodal` 两种请求格式。普通设置备份不含知识内容；知识库通过独立 `.heiniukb` 归档迁移。

历史 `projects.json` 与 `Projects/` 可能继续留在用户数据目录，当前版本不读取、写入或主动删除。

## 文档注释规范

- 使用 DocC：`///` 中文
- 类型、重要属性、公开方法均应有说明
- 长久记忆文章写在 `HeiNiu.docc/*.md`，根目录 `AGENTS.md` 为索引摘要
- 在线文档通过 GitHub Actions 发布 Pages
- 本地不要提交生成的 `docs/` 静态站

## 明确不做

- 自定义 AI 角色、聊天会话、角色专属知识、技能/插件与 MCP 智能体工具
- 项目管理与项目创作流水线
- OCR、网页抓取、文件夹持续同步
- App Store 沙盒上架
- 把 API Key 写入明文 JSON
