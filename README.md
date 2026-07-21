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
- LLM 服务商：OpenAI 兼容与 Anthropic，支持模型列表及连接测试
- 提示词库：按剧本、分镜、生图、生视频、角色、场景、物品分类管理
- 生图 / 生视频：配置多家接口、模型和默认参数
- 备份：配置 JSON 导入导出，可选是否包含钥匙串中的 API Key

本项目不包含自定义 AI 角色、聊天会话、角色知识库、技能/插件或 MCP 智能体功能。

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
| API Key | 本机钥匙串（service = `cn.codable.heiniu`） |

旧版本产生的智能体数据文件不会被当前版本读取或写入。

## 工程结构

```text
HeiNiu/
├── HeiNiuApp.swift
├── Design/
├── Models/
├── Services/
└── Views/
    ├── MainView.swift
    ├── Projects/
    └── Settings/
```

## 许可证

[MIT](LICENSE)
