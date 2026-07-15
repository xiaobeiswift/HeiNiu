# 数据存放与迁移

> 长久记忆：文件位置、钥匙串账户、备份行为。

## 本机路径

根目录：

`~/Library/Application Support/HeiNiu/`

| 文件 / 目录 | 内容 |
|-------------|------|
| `settings.json` | 服务商、提示词、生图/生视频、MCP 列表 |
| `agents.json` | 黑妞角色 |
| `conversations.json` | 黑妞对话 |
| `knowledge.json` | 知识库索引 |
| `Knowledge/<agentID>/` | 知识库原文件 |
| `skills.json` | 技能 |
| `plugins.json` | 插件 |

## 钥匙串

- service：`cn.codable.heiniu`（或 Bundle ID）  
- LLM：`provider-<uuid>`  
- 生图：`image-provider-<uuid>`  
- 生视频：`video-provider-<uuid>`  

**API Key 永不写入 JSON。**

## 备份

设置 → 备份：

- 导出 JSON 包，可选是否包含 Key  
- 导入支持 **合并** / **替换全部**  
- 仅拷贝 `settings.json` 不会带走 Key  

## 解码原则

所有持久化模型优先：

```swift
try container.decodeIfPresent(Type.self, forKey: .field) ?? 默认值
```

避免新增字段导致整文件解码失败或用户配置被清空。
