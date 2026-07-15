# 技能与插件

## 概念分离

- **对话模式**（`/goal` 等）：系统内置工作方式，见 ``BuiltInChatModes``  
- **技能**（`$outline` 等）：可配置能力包，见 ``HeiNiuSkill``  
- **插件**：技能容器，见 ``HeiNiuPlugin``  

## 展示规则

- 「技能」页只显示 **未归属插件** 的独立技能  
- 插件内技能 **只在插件卡片中列出**，避免两边重复  
- 插件禁用后，其技能在聊天中不可用  

## 范围

``SkillScope``：

- `builtIn`：内置  
- `personal`：个人（可删）  

## UI

侧栏 **配置 → 技能** → ``SkillsSettingsView``：顶栏插件/技能，再分内置/个人。
