# 黑妞（自定义 AI 角色）

类似 Gemini Gem / Custom GPT：人设、模型绑定、知识库与对话。

## 数据模型

- ``HeiNiuAgent``：角色定义  
- ``HeiNiuConversation`` / ``ChatTurn``：会话与消息  
- ``KnowledgeItem``：知识库条目  

## 仓库

``HeiNiuAgentStore`` 负责 CRUD、对话发送、知识库导入与技能/插件持久化。

## UI

- ``HeiNiuHomeView``：左侧角色列表 + 右侧聊天  
- ``HeiNiuChatView``：对话、附件、触发面板、上下文占用  
- ``HeiNiuAgentEditorView``：左侧导航编辑页  

## MCP 策略

``AgentMCPMode``：

- `disabled`：不使用 MCP  
- `automatic`：使用全局已启用服务器  
- `manual`：仅用 `enabledMCPServerIDs`  
