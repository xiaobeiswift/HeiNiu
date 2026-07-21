# 数据存放与迁移

> 长久记忆：文件位置、钥匙串账户与备份行为。

## 本机路径

根目录：`~/Library/Application Support/HeiNiu/`

| 文件 / 目录 | 内容 |
|-------------|------|
| `settings.json` | 服务商、提示词及生图/生视频配置 |
| `KnowledgeBase/knowledge.sqlite` | 集合、标签、正文、分块与 Float32 向量 |
| `KnowledgeBase/Files/<documentID>/...` | 导入原文件的本地副本 |

历史版本可能留下 `projects.json`、`Projects/`、智能体相关文件和 `Knowledge/` 目录；当前版本不再读取或写入这些数据，也不会主动删除。当前知识库使用名称不同的 `KnowledgeBase/` 目录。

## 钥匙串

- service：`cn.codable.heiniu`（或 Bundle ID）
- LLM：`provider-<uuid>`
- 生图：`image-provider-<uuid>`
- 生视频：`video-provider-<uuid>`

API Key 永不写入普通配置 JSON。

## 备份

设置 → 备份支持导出 JSON、合并或替换导入。备份格式版本 3 包含知识库嵌入服务商、模型和接口类型，但不包含 API Key、知识正文、向量或原文件。旧版含 Key 备份仍可兼容导入；新版不再导出 Key。仅拷贝 `settings.json` 不会带走钥匙串密钥。

知识库页面使用独立 `.heiniukb` ZIP 归档，包含版本清单、SQLite 快照和 `Files/`。导入可合并或替换；嵌入模型指纹一致时保留向量，不一致时资料保留并标记为待重建。归档不包含 API Key。

删除集合会保留其资料并将资料移入“未分类”；删除资料会移除正文、分块、向量及对应原文件副本。

## 解码原则

持久化模型优先使用 `decodeIfPresent` 与默认值，避免新增字段导致整文件解码失败或用户配置被清空。
