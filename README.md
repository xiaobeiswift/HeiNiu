# 短剧工作台（HeiNiu）

macOS 短剧创作工作平台。第一阶段完成 **设置** 模块。

## 要求

- macOS 15.0+
- Xcode 16+（推荐 Xcode 26）

## 打开与运行

```bash
open /Volumes/Game/HeiNiu/HeiNiu.xcodeproj
```

在 Xcode 中选择 target **HeiNiu**，运行（⌘R）。

或命令行编译：

```bash
xcodebuild -project HeiNiu.xcodeproj -scheme HeiNiu -configuration Debug build
```

## 第一阶段功能

### 服务商

- 支持 **OpenAI 兼容** 与 **Anthropic** 协议
- 配置名称、Base URL、模型列表、是否支持视觉
- API Key 存入本机钥匙串
- 支持测试连接

### 提示词库

按创作环节分类，**每类可有多条**提示词（可新建 / 复制 / 删除）：

| 分类 | 预置示例 |
|------|----------|
| 剧本 | 创作大纲、完整剧本、对白润色、源文本改编 |
| 分镜 | 分镜表、镜头节奏优化 |
| 生图 | 角色立绘、场景概念图、分镜参考图 |
| 生视频 | 镜头视频提示词、风格一致性约束 |
| 角色 | 角色卡提取、外形描述强化 |
| 场景 | 场景卡提取、氛围与光影 |
| 物品 | 物品卡提取、产品外观描述 |

每条可配置名称、模板、服务商/模型、温度；自动保存。

### 生图服务商

- **可配置多家** OpenAI Images 兼容接口
- 名称 / Base URL / 模型列表 / 默认尺寸 / API Key
- 生图文案模板在「提示词库 → 生图」

### 生视频服务商

- **可配置多家**（OpenAI 兼容 / 通用 HTTP）
- 名称 / Base URL / 模型列表 / 默认画幅 / 默认时长 / API Key
- 生视频文案模板在「提示词库 → 生视频」

## 数据存放

| 内容 | 位置 |
|------|------|
| 服务商、提示词、生图/生视频配置 | `~/Library/Application Support/HeiNiu/settings.json` |
| API Key | 本机钥匙串（service = `cn.codable.heiniu`） |

### 换机迁移

在 **设置 → 备份**：

1. **导出配置…**  
   - 默认不含 API Key（更安全）  
   - 可选「导出时包含 API Key」（文件需妥善保管）
2. 把 JSON 拷到新电脑  
3. **选择配置文件…** 导入  
   - **合并**：按 ID 更新/追加  
   - **替换全部**：覆盖本机配置  

也可手动复制 `settings.json`，但 API Key 不会随之迁移，仍需在新机器填写，或使用「含 Key」导出包。

## 工程结构

```
HeiNiu/
├── HeiNiuApp.swift
├── Models/          # LLMProvider, ImageProvider, PromptTask, PromptConfig
├── Services/        # SettingsStore, KeychainHelper, AppPaths, DefaultPrompts
└── Views/
    ├── MainView.swift
    ├── PlaceholderView.swift
    └── Settings/    # 服务商 / 提示词 / 生图
```

## 后续规划

- 学习 / 剧本 / 分镜 / 资产库业务模块
- 更多协议（Gemini、本机 CLI 等）
- 语音转写（ASR）设置
