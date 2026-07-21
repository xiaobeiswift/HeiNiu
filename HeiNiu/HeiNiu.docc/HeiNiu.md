# 黑妞短剧

面向短剧创作者的 macOS 工作台。

@Metadata {
    @TechnologyRoot
}

## 概览

**黑妞短剧**把项目管理、大模型服务商、提示词库、生图和生视频接口收拢到同一应用中，通过项目内的分步流水线生成并保存创作产物。

产品不提供自定义聊天智能体；模型调用由项目流水线根据选中的提示词直接发起。

## 主题

### 产品与架构

- <doc:DocumentationStyle>
- <doc:Architecture>
- <doc:ProductDecisions>
- <doc:DataStorage>
- <doc:SettingsAndProviders>

## 代码地图

| 目录 | 职责 |
|------|------|
| `Models/` | 服务商、项目、流水线、提示词与备份模型 |
| `Services/` | 持久化、钥匙串、LLM 客户端与流水线执行 |
| `Views/` | 主界面、项目流水线与设置 UI |
| `Design/` | 主题色与可复用组件 |

## 文档约定

本工程对外 API 与关键类型使用 DocC 中文文档注释（`///`）。在 Xcode 中选择 **Product → Build Documentation**（⌃⇧⌘D）生成并浏览文档。
