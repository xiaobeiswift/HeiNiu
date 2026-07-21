# 黑妞短剧

面向短剧创作者的 macOS 工作台：管理项目、提示词和模型服务，并按步骤完成短剧创作流水线。

**在线文档（DocC）：**  
https://xiaobeiswift.github.io/HeiNiu/documentation/heiniu/

![macOS](https://img.shields.io/badge/macOS-15%2B-black)
![SwiftUI](https://img.shields.io/badge/SwiftUI-6-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## 功能

- 项目：新建本地项目或挂载外部素材目录
- 创作流水线：导入/粘贴源文本，选择提示词，生成并保存阶段产物
- 全局知识库：集合、标签、文件和笔记，项目可引用集合或单条资料
- 语义检索：支持标准 `/embeddings` 与豆包 `/embeddings/multimodal`，生成结果保留命中来源
- LLM 服务商：OpenAI 兼容与 Anthropic，支持模型列表及连接测试
- 提示词库：按剧本、分镜、生图、生视频、角色、场景、物品分类管理
- 生图 / 生视频：配置多家接口、模型和默认参数
- 备份：不含 API Key 的配置 JSON，以及独立知识库归档

本项目不包含自定义 AI 角色、聊天会话、角色专属记忆、技能/插件或 MCP 智能体功能。知识库是供项目流水线检索引用的全局资料系统，不是聊天智能体。

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
| 项目列表 | `~/Library/Application Support/HeiNiu/projects.json` |
| 项目流水线 | `~/Library/Application Support/HeiNiu/Projects/<projectID>/pipeline.json` |
| 知识库正文、标签、分块和向量 | `~/Library/Application Support/HeiNiu/KnowledgeBase/knowledge.sqlite` |
| 知识库原文件副本 | `~/Library/Application Support/HeiNiu/KnowledgeBase/Files/` |
| API Key | 本机钥匙串（service = `cn.codable.heiniu`） |

旧版本产生的智能体数据文件不会被当前版本读取或写入。

常规设置备份包含嵌入服务商与模型选择，但不包含知识内容或 API Key。知识内容请在知识库页面独立导出 `.heiniukb` 归档；归档内包含 SQLite 快照与原文件副本。

## 工程结构

```text
HeiNiu/
├── HeiNiuApp.swift
├── Design/
├── Models/
├── Services/
└── Views/
    ├── MainView.swift
    ├── Knowledge/
    ├── Projects/
    └── Settings/
```

## 许可证

[MIT](LICENSE)
