# 黑妞短剧

面向短剧创作者的 macOS 工作台。

@Metadata {
    @TechnologyRoot
}

## 概览

**黑妞短剧**把项目分镜审核、全局知识库、大模型服务商、提示词库、生图和生视频接口配置，以及可执行的节点工作流收拢到同一应用中。

项目用于选择全局工作流、启动一次运行并审核生成的分镜稿。知识库用于独立管理、索引和迁移本地资料；工作流用于编排全局模板和保留运行历史。产品不提供资产库或自定义聊天智能体。

## 主题

### 产品与架构

- <doc:DocumentationStyle>
- <doc:Architecture>
- <doc:ProductDecisions>
- <doc:DataStorage>
- <doc:SettingsAndProviders>
- <doc:Workflows>
- <doc:Projects>
- <doc:PixmaxNativeVideo>

## 代码地图

| 目录 | 职责 |
|------|------|
| `Models/` | 项目、服务商、知识库、提示词、工作流与备份模型 |
| `Services/` | 项目持久化、知识索引、工作流执行、钥匙串与接口客户端 |
| `Views/` | 主界面、项目、工作流、知识库与设置 UI |
| `Design/` | 主题色与可复用组件 |

## 文档约定

本工程对外 API 与关键类型使用 DocC 中文文档注释（`///`）。在 Xcode 中选择 **Product → Build Documentation**（⌃⇧⌘D）生成并浏览文档。
