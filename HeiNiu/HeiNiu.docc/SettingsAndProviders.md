# 设置与服务商

## 设置页

``SettingsView`` 顶部分段：

服务商 · 提示词 · 生图 · 生视频 · 备份  

## LLM 服务商

- ``LLMProvider`` + ``ProviderProtocolType``  
- OpenAI 兼容模式：``OpenAICompatibleAPIMode``（Chat Completions / Responses）  
- ``ProvidersSettingsView``：默认折叠；右侧菜单「编辑 / 删除」  
- 「获取模型列表」：`SettingsStore.fetchModels(for:)`  

## 提示词库

- 分类：``PromptCategory``  
- 条目：``PromptItem``（每类多条）  
- 默认模板：``DefaultPrompts``  

## 生图 / 生视频

- ``ImageProvider`` / ``VideoProvider`` 多家配置  
- 文案模板在提示词库对应分类，不在接口页重复维护  
