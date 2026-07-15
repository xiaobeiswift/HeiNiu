# ``HeiNiu``

黑妞短剧：面向短剧创作者的 macOS 工作台。

@Metadata {
    @TechnologyRoot
}

## 概览

**黑妞短剧**把大模型服务商、提示词库、生图/生视频接口、自定义 AI 角色（黑妞）、技能/插件与 MCP 配置收拢到同一应用中，为后续剧本、分镜与资产生成打底。

当前已完成「设置 + 黑妞对话」阶段；学习 / 剧本 / 分镜 / 资产库业务流水线仍在规划中。

## 主题

### 产品与架构

- <doc:DocumentationStyle>

- <doc:Architecture>
- <doc:ProductDecisions>
- <doc:DataStorage>

### 功能模块

- <doc:HeiNiuAgents>
- <doc:SettingsAndProviders>
- <doc:SkillsAndPlugins>
- <doc:ChatComposer>

## 代码地图

| 目录 | 职责 |
|------|------|
| `Models/` | 领域模型（服务商、黑妞、技能、MCP、备份等） |
| `Services/` | 持久化、钥匙串、LLM 客户端、文本抽取 |
| `Views/` | 主界面、黑妞、设置 UI |
| `Design/` | 主题色与可复用组件 |

## 文档约定

本工程所有对外 API 与关键类型使用 **DocC 中文文档注释**（`///`）。

在 Xcode 中选择 **Product → Build Documentation**（⌃⇧⌘D）生成并浏览文档。
