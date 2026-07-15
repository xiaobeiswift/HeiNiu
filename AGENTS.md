# 黑妞短剧 · 长久记忆（AGENTS）

面向后续在本仓库协作的 AI / 开发者。更完整的结构化文档见 DocC：

`HeiNiu/HeiNiu.docc/`（Xcode：**Product → Build Documentation** / ⌃⇧⌘D）

## 产品

- 名称：**黑妞短剧**
- Bundle ID：`cn.codable.heiniu`
- 平台：macOS 15+，SwiftUI，中文 UI
- 协议：MIT

## 架构要点

- 入口：`HeiNiuApp` 注入 `SettingsStore` + `HeiNiuAgentStore`
- 侧栏：工作台（黑妞/学习/剧本/分镜/资产）+ 配置（设置/技能/MCP）
- 密钥只进钥匙串；配置进 Application Support JSON
- 解码一律容错（`decodeIfPresent` + 默认值）

## 概念分离（勿混淆）

| 概念 | 触发 | 管理 |
|------|------|------|
| 对话模式 | `/goal` `/plan`… | 系统内置 |
| 技能 | `$outline`… | 配置 → 技能 |
| 插件 | — | 配置 → 技能 → 插件 |
| MCP | 黑妞策略禁用/自动/手动 | 配置 → MCP 清单 |

- 归属插件的技能 **不** 出现在独立技能列表
- 知识库在黑妞编辑页配置，不在聊天工具条放入口

## 聊天输入

- 只保留附件按钮
- `/` 命令 · `@` 提及 · `$`/`¥` 技能 · `#` 插入会话
- 全界面拖放 + 文件名 chip（无绝对路径）

## 数据路径

`~/Library/Application Support/HeiNiu/`

- `settings.json` / `agents.json` / `conversations.json`
- `knowledge.json` + `Knowledge/<id>/`
- `skills.json` / `plugins.json`

## 文档注释规范

- 使用 DocC：`///` 中文
- 类型、重要属性、公开方法均应有说明
- 可用 ``TypeName`` 交叉引用
- 长久记忆文章写在 `HeiNiu.docc/*.md`，根目录 `AGENTS.md` 为索引摘要
- 在线文档通过 GitHub Actions 发布 Pages（见 `.github/workflows/docs.yml`）
- 本地不要提交生成的 `docs/` 静态站（体积大，已 gitignore）

## 明确不做（当前阶段）

- 学习 / 剧本 / 分镜 / 资产库完整业务流水线
- App Store 沙盒上架
- 把 API Key 写入明文 JSON
