# 数据存放与迁移

> 长久记忆：文件位置、钥匙串账户与备份行为。

## 本机路径

根目录：`~/Library/Application Support/HeiNiu/`

| 文件 / 目录 | 内容 |
|-------------|------|
| `settings.json` | 服务商、提示词及生图/生视频配置 |
| `projects.json` | 项目列表 |
| `Projects/<projectID>/pipeline.json` | 项目流水线输入与产物 |

历史版本可能留下智能体相关文件和 `Knowledge/` 目录；当前版本不再读取或写入这些数据。

## 钥匙串

- service：`cn.codable.heiniu`（或 Bundle ID）
- LLM：`provider-<uuid>`
- 生图：`image-provider-<uuid>`
- 生视频：`video-provider-<uuid>`

API Key 永不写入普通配置 JSON。

## 备份

设置 → 备份支持导出 JSON、合并或替换导入，并可选择是否包含 Key。仅拷贝 `settings.json` 不会带走钥匙串密钥。

## 解码原则

持久化模型优先使用 `decodeIfPresent` 与默认值，避免新增字段导致整文件解码失败或用户配置被清空。
