# Fn / 🌐 映射修复（2026-09-08）

用户希望把截图中的 Key 110 映射为单独 Fn，用于听写。

下文记录发版前的修复验证。此功能已于 2026-09-08 随 1.4.1 发布并更新本机；当前版本与发布状态以 PROJECT_STATE.md 为准，微信语音输入的实体按键效果仍待验收。

## 实现

- 目标支持单独 Fn，可直接录制或在原有手动设置下拉框中选择 `Fn / 🌐`；选择 Fn 后隐藏不适用的组合修饰键。
- Fn 来源支持原有单击/双击手势。Fn 目标通过 `flagsChanged` 发送键码 63 的按下和松开；保持期间后续键盘事件携带 Fn，重复事件不重复触发，停止映射会释放 Fn。
- SDK `HIToolbox/Events.h` 的 `kVK_Function=0x3F`、`kVK_ContextualMenu=0x6E` 确认键码；原 `Key 110` 显示为 `Menu`，原始配置值未变。
- 沿用上一任务已确认的表格、按钮与原生弹窗，不另起 UI 风格。增加本地启动参数 `--show-quick-tools`，供更新后直接展示现有设置窗口。

## 当前配置与验证

- 已在真正的 `/Applications/Codex Quota.app` 窗口中操作「手动设置 → Fn / 🌐 → 保存」，确认第 2 行显示 `Menu → Fn / 🌐` 且启用，界面无异常。此检查不是隔离验证应用。
- 配置回读确认：仅用户指定第 2 行补充 Fn 目标；旧 Codex 映射、原始键、行 ID、右键规则、排除应用和其它相关设置保留。
- 项目测试 263 项通过；控制器检查 15 项通过，新增覆盖 Fn 按下、松开、保持、重复事件抑制、停止释放和 Fn 来源手势。
- 构建及签名检查通过，安装文件与开发构建完整清单一致。版本仍为 1.4.0 / 19，未发布。
- 旧安装 ZIP 为 `outputs/app-archives.noindex/before-fn-mapping-20260908.zip`；完整性和内部二进制校验通过，来源及校验值见同名 JSON。
- 本次未创建额外验证应用包；只保留 `/Applications/Codex Quota.app` 与根 `outputs/Codex Quota.app`，Spotlight 当前也只返回两者。

## 听写接收方与验证边界

只读查看本机系统设置：Fn / 🌐 当前设置为「更改输入法」；macOS 听写已开启，快捷键为「按下麦克风键」；本机安装了 ABC 和微信输入法。未修改这些系统设置。

用户已于 2026-09-08 确认目标是微信输入法的语音输入，不是 macOS 系统听写。因此不修改系统听写快捷键或 Fn 的系统设置。不能把 Fn 目标可选、事件检查通过等同于微信语音输入已启动；实体键盘触发与正常结束仍待实测确认。

技术依据：[Apple Fn 事件标志](https://developer.apple.com/documentation/coregraphics/cgeventflags/masksecondaryfn)、[Apple 听写说明](https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac)。Apple 说明听写也可通过麦克风键、已配置快捷键或“编辑 → 开始听写”启动；不能假定任何 Fn 合成事件都等同于听写。
