# 黑妞短剧

面向短剧创作者的 macOS 工作台：管理知识资料、提示词、模型服务配置和全局节点工作流。

**在线文档（DocC）：**  
https://xiaobeiswift.github.io/HeiNiu/documentation/heiniu/

![macOS](https://img.shields.io/badge/macOS-15%2B-black)
![SwiftUI](https://img.shields.io/badge/SwiftUI-6-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## 功能

- 全局知识库：集合、标签、文件和手写笔记
- 本地向量索引：支持标准 `/embeddings` 与豆包 `/embeddings/multimodal`
- LLM 服务商：OpenAI 兼容与 Anthropic，支持模型列表及连接测试
- 提示词库：按剧本、分镜、生图、生视频、角色、场景、物品分类管理
- 生图 / 图片编辑 / 生视频：配置多家接口、模型和默认参数
- 节点工作流：可缩放画布、类型化连线、图片原图/遮罩编辑、条件与显式循环、整图或单节点执行
- 节点内置帮助：卡片摘要、端口提示，以及检查器中的完整中文用法和运行结果
- 运行历史：逐节点状态、流式文本、图片/视频本地产物和手动清理
- 备份：不含 API Key 的配置 JSON，以及独立知识库归档

本项目不包含项目管理、资产库、绑定项目的创作流水线、自定义 AI 角色、聊天会话、技能/插件或 MCP 智能体功能。知识库和工作流都是独立的全局系统。

## 环境要求

- macOS 15.0+
- Xcode 16+

## 运行

```bash
git clone https://github.com/xiaobeiswift/HeiNiu.git
cd HeiNiu
open HeiNiu.xcodeproj
```

命令行编译：

```bash
xcodebuild -project HeiNiu.xcodeproj -scheme HeiNiu -configuration Debug -destination 'platform=macOS' build
```

## 数据存放

| 内容 | 位置 |
|------|------|
| 设置 | `~/Library/Application Support/HeiNiu/settings.json` |
| 知识库正文、标签、分块和向量 | `~/Library/Application Support/HeiNiu/KnowledgeBase/knowledge.sqlite` |
| 知识库原文件副本 | `~/Library/Application Support/HeiNiu/KnowledgeBase/Files/` |
| 工作流定义 | `~/Library/Application Support/HeiNiu/Workflows/workflows.json` |
| 工作流运行历史与媒体 | `~/Library/Application Support/HeiNiu/Workflows/Runs/` |
| API Key | 本机钥匙串（service = `cn.codable.heiniu`） |

旧版本产生的项目、流水线和智能体数据文件不会被当前版本读取或写入。

常规设置备份包含嵌入服务商与模型选择，但不包含知识内容、工作流、运行媒体或 API Key。知识内容请在知识库页面独立导出 `.heiniukb` 归档；归档内包含 SQLite 快照与原文件副本。首版不提供工作流导入导出。

## 工程结构

```text
HeiNiu/
├── HeiNiuApp.swift
├── Design/
├── Models/
├── Services/
└── Views/
    ├── MainView.swift
    ├── WorkflowHomeView.swift
    ├── Knowledge/
    └── Settings/
```

## 许可证

[MIT](LICENSE)
