# 黑妞短剧

面向短剧创作者的 macOS 工作台：把「服务商、提示词、生图、生视频」收拢到同一处配置，为后续剧本 / 分镜 / 资产生成打底。

> 当前进度：**设置阶段**已可用。学习、剧本、分镜、资产库等业务模块仍在规划中。

![macOS](https://img.shields.io/badge/macOS-15%2B-black)
![SwiftUI](https://img.shields.io/badge/SwiftUI-6-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## 它解决什么问题

做短剧时通常要同时面对：

- 多家大模型 API（OpenAI 兼容、Anthropic…）
- 生图、生视频各自不同的网关与模型
- 大量可复用提示词（大纲、对白、分镜、角色立绘、物品卡…）
- 换电脑后配置难迁移

**黑妞短剧**先把这些配置能力做扎实，再往上长创作流水线。

## 功能一览

### 服务商（LLM）

- 协议：**OpenAI 兼容**、**Anthropic**
- OpenAI 兼容支持两种接口模式：
  - `Chat Completions` → `POST /chat/completions`
  - `Responses` → `POST /responses`
- 可配置名称、Base URL、模型列表、是否支持视觉
- API Key 写入本机钥匙串
- 支持测试连接

### 提示词库

按创作环节分类，**每类可有多条**提示词（新建 / 复制 / 删除）：

| 分类 | 预置示例 |
|------|----------|
| 剧本 | 创作大纲、完整剧本、对白润色、源文本改编 |
| 分镜 | 分镜表、镜头节奏优化 |
| 生图 | 角色立绘、场景概念图、分镜参考图 |
| 生视频 | 镜头视频提示词、风格一致性约束 |
| 角色 | 角色卡提取、外形描述强化 |
| 场景 | 场景卡提取、氛围与光影 |
| 物品 | 物品卡提取、产品外观描述 |

每条可绑定服务商、模型与温度；修改后自动保存。

### 生图 / 生视频

- **生图**：可配置多家 OpenAI Images 兼容服务商（模型、默认尺寸、Key）
- **生视频**：可配置多家服务商（OpenAI 兼容 / 通用 HTTP，画幅、时长、Key）
- 文案模板在「提示词库」对应分类中管理，接口与模板分离

### 备份与迁移

- 导出 JSON 配置包（可选是否包含 API Key）
- 导入支持 **合并** 或 **替换全部**
- 日常配置自动落在本机 Application Support

## 环境要求

- macOS 15.0+
- Xcode 16+（推荐最新稳定版）

## 运行

```bash
git clone https://github.com/xiaobeiswift/HeiNiu.git
cd HeiNiu
open HeiNiu.xcodeproj
```

Xcode 中选择 target **HeiNiu**，⌘R 运行。

命令行编译：

```bash
xcodebuild -project HeiNiu.xcodeproj -scheme HeiNiu -configuration Debug -destination 'platform=macOS' build
```

## 数据存放

| 内容 | 位置 |
|------|------|
| 服务商、提示词、生图/生视频配置 | `~/Library/Application Support/HeiNiu/settings.json` |
| API Key | 本机钥匙串（service = `cn.codable.heiniu`） |

换机时请用应用内 **设置 → 备份**，不要只拷贝 `settings.json`（密钥不会一起带走，除非导出时勾选包含 Key）。

## 工程结构

```
HeiNiu/
├── HeiNiuApp.swift          # 入口
├── Design/                  # 主题与通用 UI 组件
├── Models/                  # LLM / 生图 / 生视频 / 提示词 / 备份
├── Services/                # SettingsStore、Keychain、默认提示词
└── Views/
    ├── MainView.swift       # 侧栏导航
    └── Settings/            # 服务商 · 提示词 · 生图 · 生视频 · 备份
```

## 路线图

- [x] 多协议 LLM 服务商与钥匙串存 Key
- [x] 多分类提示词库
- [x] 多家生图 / 生视频服务商
- [x] 配置导入导出
- [ ] 学习（视频理解 / 转写）
- [ ] 剧本创作与改编
- [ ] 分镜与视频提示词流水线
- [ ] 角色 / 场景 / 物品资产库

## 许可证

[MIT](LICENSE)
