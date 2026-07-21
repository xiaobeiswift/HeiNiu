# 设置与服务商

## 设置页

``SettingsView`` 顶部分段：

服务商 · 提示词 · 生图 · 生视频 · 备份  

## LLM 服务商

- ``LLMProvider`` + ``ProviderProtocolType``  
- OpenAI 兼容模式：``OpenAICompatibleAPIMode``（Chat Completions / Responses）  
- ``ProvidersSettingsView``：默认折叠；右侧菜单「编辑 / 删除」  
- 「获取模型列表」：`SettingsStore.fetchModels(for:)`  

## 知识库嵌入

- 在服务商设置中选择一个 OpenAI 兼容服务商、接口类型并填写嵌入模型 ID
- 标准文本向量请求发送到 `/embeddings`，豆包图文向量请求发送到 `/embeddings/multimodal`
- 豆包多模态模式使用 `{type: "text", text: "..."}` 输入对象，并按原顺序逐条请求
- “测试嵌入”会显示返回向量维度；更换服务商或模型后，现有资料标记为待重建
- 可重建全部资料，也可在知识库详情中重试单条资料

## 提示词库

- 分类：``PromptCategory``  
- 条目：``PromptItem``（每类多条）  
- 默认模板：``DefaultPrompts``  

## 生图 / 生视频

- ``ImageProvider`` / ``VideoProvider`` 多家配置  
- 文案模板在提示词库对应分类，不在接口页重复维护  
- 服务商保存稳定 `adapterID` 与扩展配置；旧 `kind` 自动映射到内置适配器
- ``MediaAdapterRegistry`` 只注册随应用编译的适配器，不加载外部二进制或 JSON 插件
- 内置 OpenAI Images `/images/generations` 与 `/images/edits`，以及 OpenAI Videos `/videos`；未知适配器保留配置并明确显示不可执行原因
