# 黑妞短剧 · 长久记忆（AGENTS）

面向后续在本仓库协作的 AI / 开发者。更完整的结构化文档见 `HeiNiu/HeiNiu.docc/`。

## 产品

- 名称：**黑妞短剧**
- Bundle ID：`cn.codable.heiniu`
- 平台：macOS 15+，SwiftUI，中文 UI
- 协议：MIT
- 定位：短剧项目与 AI 创作流水线工作台，不包含自定义聊天智能体

## 架构要点

- 入口：`HeiNiuApp` 注入 `SettingsStore` 与 `ProjectStore`
- 侧栏：工作台（项目 / 剧本 / 分镜 / 资产库）+ 设置
- 项目流水线直接根据提示词条目调用 LLM，不通过角色或聊天会话
- 密钥只进钥匙串；配置进 Application Support JSON
- 解码一律容错（`decodeIfPresent` + 默认值）

## 数据路径

`~/Library/Application Support/HeiNiu/`

- `settings.json`
- `projects.json`
- `Projects/<id>/pipeline.json`

历史版本可能留下 `agents.json`、`conversations.json`、`knowledge.json`、`skills.json`、`plugins.json` 与 `Knowledge/`；当前版本不再读取或写入这些智能体数据。

## 文档注释规范

- 使用 DocC：`///` 中文
- 类型、重要属性、公开方法均应有说明
- 长久记忆文章写在 `HeiNiu.docc/*.md`，根目录 `AGENTS.md` 为索引摘要
- 在线文档通过 GitHub Actions 发布 Pages
- 本地不要提交生成的 `docs/` 静态站

## 明确不做

- 自定义 AI 角色、聊天会话、角色知识库、技能/插件与 MCP 智能体工具
- App Store 沙盒上架
- 把 API Key 写入明文 JSON
