# 产品决策（长久记忆）

> 已确认的产品约束。后续改动前请先对照本页。

## 平台与品牌

- 产品名：**黑妞短剧**
- Bundle ID：`cn.codable.heiniu`
- macOS 15+，SwiftUI，中文界面
- 开源协议：MIT

## 产品边界

- 以项目和可追踪的创作步骤为核心
- LLM 只服务于项目流水线和提示词任务
- 不提供自定义 AI 角色、开放式聊天、角色知识库、技能/插件或 MCP 智能体工具
- 「黑妞」仅作为产品品牌名称，不表示应用内智能体

## 服务商

- LLM：OpenAI 兼容（Chat Completions / Responses）与 Anthropic
- 生图 / 生视频：可配置多家服务商
- API Key 存放于钥匙串，不写入普通设置文件

## 数据路径

见 <doc:DataStorage>。
