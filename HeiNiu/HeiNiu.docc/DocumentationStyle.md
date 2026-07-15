# 文档注释规范

> 长久记忆：如何写会被 Xcode DocC 正确展示的中文注释。

## 基本格式

```swift
/// 一句话摘要（会出现在符号列表与页面标题下）。
///
/// 更详细的说明可以多段书写。
///
/// ## 设计原则
/// - 原则 A
/// - 原则 B
///
/// ## 示例
///
/// ```swift
/// let x = Foo()
/// x.bar()
/// ```
///
/// - Parameter name: 参数说明。
/// - Returns: 返回值说明。
/// - Throws: 可能抛出的错误。
/// - Important: 关键警告。
/// - Note: 补充说明。
/// - SeeAlso: ``OtherType/method()``, <doc:Architecture>
```

## 必须写清的内容

对仓库类型、公开方法，尽量包含：

1. **作用**：做什么  
2. **设计原则 / 边界**：不做什么、与谁协作  
3. **示例**：可编译的调用片段  
4. **关联**：`SeeAlso` 指向相关类型或 DocC 文章  

## 位置

- 文档注释必须紧挨声明，且在 `@Observable`、`@MainActor`、`@discardableResult` **之前**。  
- 错误示例：特性夹在注释与 `class` 之间会导致摘要丢失。

## 构建

Xcode：**Product → Build Documentation**（⌃⇧⌘D）
