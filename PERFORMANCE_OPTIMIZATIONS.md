# 性能优化总结

## 优化目标
优化配置和模块页面的响应速度，解决页面切换延迟问题。

## 优化内容

### 1. GeneralPage.swift - ModuleSelectionCard

**问题**：
- 每次渲染都为所有模块重新构建复杂的标签字符串
- `moduleLabel()` 函数包含多次字符串拼接和可选值处理

**优化方案**：
- 添加 `@State private var cachedOptions` 缓存计算好的选项数组
- 添加 `@State private var lastMatchesHash` 跟踪模块列表变化
- 使用 `.task(id:)` 修饰符，仅在模块 ID 列表变化时重新计算标签

**效果**：
- 避免每次渲染都重复构建标签字符串
- 只在模块列表实际变化时更新缓存

### 2. GeneralPage.swift - DefaultModuleCard

**问题**：
- `filteredModules` 计算属性每次重绘都调用 `model.moduleStore.getModules().filter`
- 四个级联的 `FixedPopUpPicker` 每次都重新构建选项数组
- `onChange` 回调中多次调用 `.map(\.id)` 和复杂的过滤逻辑

**优化方案**：
- 添加 `@State private var cachedFilteredModules` 缓存过滤结果
- 添加 `@State private var cachedModuleOptions` 缓存选项数组
- 创建 `updateFilteredModules()` 方法，集中处理过滤和缓存更新
- 在所有 `onChange` 回调中调用该方法
- 在 `onAppear` 时初始化缓存

**效果**：
- 消除了计算属性导致的重复过滤操作
- 避免每次渲染都重新构建选项数组
- 级联选择器变化时只触发一次过滤计算

### 3. MacroEditorPage.swift

**问题**：
- 使用 `onAppear` 同步创建 store，可能阻塞 UI 线程

**优化方案**：
- 将 `onAppear` 替换为 `.task`，支持异步初始化
- 在 task 中使用 `guard` 确保只初始化一次

**效果**：
- Store 创建不会阻塞主线程
- 页面切换更加流畅

### 4. ModuleEditorPage.swift

**问题**：
- `onChange` 监听器在每次 model 变化时都无条件触发 `synchronize()`
- 使用 `onAppear` 同步初始化
- 即使值没有实际变化也会触发同步

**优化方案**：
- 添加 `@State` 变量跟踪上一次的版本号
- 在 `onChange` 中先比较版本号，只在实际变化时才调用 `synchronize()`
- 将 `onAppear` 替换为 `.task`，支持异步初始化

**效果**：
- 避免不必要的同步操作
- 减少重复计算和 UI 更新

### 5. ModuleEditorPage.swift - ModuleEditorContent

**问题**：
- `matchText()` 函数在每次渲染时为每个模块重新计算匹配文本
- 包含多次字符串拼接和本地化处理

**优化方案**：
- 添加 `@State private var cachedMatchTexts: [String: String]` 字典缓存
- 使用 `.task(id: store.modules.map(\.id))` 监听模块列表变化
- 只在模块列表变化时重新计算所有匹配文本
- 将计算好的文本传递给 `ModuleListRow`

**效果**：
- 避免每次渲染都重复计算匹配文本
- 列表滚动更加流畅
- 减少 CPU 使用

## 优化技术总结

1. **计算结果缓存**：使用 `@State` 缓存计算密集的结果
2. **精确的变化检测**：使用 `.task(id:)` 或版本号比较，只在数据真正变化时更新
3. **异步初始化**：使用 `.task` 替代 `onAppear` 避免阻塞 UI
4. **批量处理**：将多个小的更新合并为一次大的更新
5. **避免重复计算**：将计算属性改为缓存的状态变量

## 预期效果

- 页面切换响应更加及时
- 下拉菜单展开和选择更加流畅
- 级联选择器交互延迟显著降低
- CPU 使用率降低
- 整体用户体验提升
