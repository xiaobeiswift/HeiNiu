# 数据存放与迁移

> 长久记忆：文件位置、钥匙串账户与备份行为。

## 本机路径

根目录：`~/Library/Application Support/HeiNiu/`

| 文件 / 目录 | 内容 |
|-------------|------|
| `settings.json` | 服务商、提示词及生图/生视频配置 |
| `KnowledgeBase/knowledge.sqlite` | 集合、标签、正文、分块与 Float32 向量 |
| `KnowledgeBase/Files/<documentID>/...` | 导入原文件的本地副本 |
| `Workflows/workflows.json` | 带格式版本的全局工作流定义 |
| `Workflows/Runs/<workflowID>/<runID>/run.json` | 一次运行的状态、节点文本、警告与错误 |
| `Workflows/Runs/<workflowID>/<runID>/Assets/` | 本次运行复制或下载的图片、视频、音频与输入文件夹 |
| `Projects/project-board.json` | 项目卡片、工作流运行关联、卡片式分镜、媒体相对路径与审核状态 |

历史版本可能留下根目录 `projects.json`、`Projects/` 中的其他旧文件、智能体相关文件和 `Knowledge/` 目录；当前版本只读取 `Projects/project-board.json`，不会读取、改写或主动删除其他历史项目内容。当前知识库使用名称不同的 `KnowledgeBase/` 目录。

## 钥匙串

- service：`cn.codable.heiniu`（或 Bundle ID）
- LLM：`provider-<uuid>`
- 生图：`image-provider-<uuid>`
- 生视频：`video-provider-<uuid>`

API Key 和验证后的 PixMax Cookie 永不写入普通配置 JSON。PixMax 密码不保存。

## 备份

设置 → 备份支持导出 JSON、合并或替换导入。备份格式版本 3 包含知识库嵌入服务商、模型和接口类型，但不包含 API Key、知识正文、向量、原文件、项目、工作流或运行媒体。旧版含 Key 备份仍可兼容导入；新版不再导出 Key。仅拷贝 `settings.json` 不会带走钥匙串密钥。

知识库页面使用独立 `.heiniukb` ZIP 归档，包含版本清单、SQLite 快照和 `Files/`。导入可合并或替换；嵌入模型指纹一致时保留向量，不一致时资料保留并标记为待重建。归档不包含 API Key。

删除集合会保留其资料并将资料移入“未分类”；删除资料会移除正文、分块、向量及对应原文件副本。

工作流定义以 400ms 防抖保存，并通过同目录临时文件替换实现原子写入。运行历史不会自动清理；可删除单次历史、清空某工作流历史，或在确认删除工作流时一并删除。复制工作流只复制定义。

项目看板以带格式版本的容错 JSON 原子保存。镜头参考图和视频只记录指向关联运行 `Assets/` 的相对路径；旧整段分镜在加载时容错迁移为卡片。删除镜头卡片或项目只删除项目 JSON 中的内容与关联，关联的全局工作流运行记录与媒体仍保留。

## 解码原则

持久化模型优先使用 `decodeIfPresent` 与默认值，避免新增字段导致整文件解码失败或用户配置被清空。
