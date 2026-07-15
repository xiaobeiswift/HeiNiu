# 架构总览

> 长久记忆：黑妞短剧的模块边界与数据流。

## 分层

```
HeiNiuApp
  └─ MainView（侧栏导航）
       ├─ 工作台：黑妞 / 学习 / 剧本 / 分镜 / 资产库
       └─ 配置：设置 / 技能 / MCP
```

### 状态与依赖注入

应用入口创建两个 `@Observable` 主仓库，并通过 `.environment` 注入：

- ``SettingsStore``：LLM / 生图 / 生视频服务商、提示词库、MCP、备份
- ``HeiNiuAgentStore``：黑妞角色、对话、知识库、技能与插件

视图只读环境对象，不直接访问磁盘路径。

### LLM 调用链

1. 黑妞绑定 ``LLMProvider`` + 模型  
2. ``LLMClientFactory`` 按协议创建客户端  
3. OpenAI 兼容（Chat Completions / Responses）或 Anthropic  
4. API Key 仅来自钥匙串，不进 JSON  

### 聊天上下文组装

发送消息时，``HeiNiuAgentStore/send(package:conversationID:settings:activeSkillIDs:)`` 会组装：

- 系统提示：黑妞指令 + 启用知识库  
- 用户侧：正文 / 命令模板 / 技能模板 + 附件 + 插入会话  
- 上下文占用：``ContextEstimator`` 按字符粗算并分桶展示  

## 设计原则

- **密钥与配置分离**：配置进 `settings.json`，Key 进 Keychain  
- **容错解码**：模型字段新增时用 `decodeIfPresent` 默认值，避免冲掉用户数据  
- **中文 UI**：产品文案与文档注释均使用中文  
- **沙盒关闭**：便于本机 CLI / MCP stdio（不计划上架 App Store 时）  
