# 右键工具总开关与全局排除应用

以下为 2026-09-07 发版前开发验证记录，当时版本保持 1.4.0 / 19。此功能已于 2026-09-08 随 1.4.1 发布；当前状态见 PROJECT_STATE.md，未完成的实机验收仍保留。

## 行为

- 「便捷工具 → 右键快捷操作」顶部增加总开关与全局排除应用入口。
- 总开关默认开启；关闭即移除右键事件监听，规则保留。保存规则与辅助功能权限轮询不会绕过总开关。
- 默认排除 Blender，已核对本机应用标识为 `org.blenderfoundation.blender`。列表可通过系统应用选择器添加应用，也可移除所选项；按应用标识精确匹配且忽略大小写，自动去重。明确清空列表后，重启不补回默认项。
- 全局排除优先于所有右键规则（含立即触发和系统动作），从按下开始放行原始事件；之后拖动、抬起保持原样。也保护尚未获得前台焦点的 Blender 窗口。已开始的手势切换到其他应用时取消，避免对新应用发送快捷键。
- 只作用于右键工具，不改变滚轮反转或修饰键呼出配置。

## 验证证据

- `bash apps/codex-quota/Scripts/build_app.sh`：253 tests passed，release 构建、签名、ZIP 完整性与解压复核通过。日志：`work/rightclick-controls/build.log`。
- `bash apps/codex-quota/Scripts/check_mouse_gesture_controller.sh`：7 项 PASS。直接编译正式控制器，构造但不向桌面发送鼠标事件，检查返回对象仍是原事件、触发门槛、全局开关与焦点切换取消。
- 正式 `MouseGestureSettingsPanelController` 的隔离验证窗口：开关关闭/重开、Blender 默认项、应用选择器重复添加去重、移除、空态、重启保持关闭与空清单，均经过 CUA 点击与界面读取；主界面及排除清单截图已目视核对，无截断或溢出。使用独立测试偏好，没有修改真实规则。验证源：`work/rightclick-controls/UIValidation.swift`；验证 `.app` 已移除。
- 本机安装版已运行；只读读取系统 event tap，右键监听为 enabled，原有另外两个监听也存在。原生 Blender 右键菜单经 CUA 实测弹出并用 Escape 关闭，未修改或保存模型。
- 尚未验证：安装版设置窗口自身的点击（自动操作工具对无窗口菜单栏应用超时）；Blender 连续右键拖动的真实鼠标使用体验。隔离界面与构造事件检查不替代此项。

## 安装与收尾

- 保留 `/Applications/Codex Quota.app` 与 `/Users/openclaw/Projects/codex助手/outputs/Codex Quota.app`；全部文件逐一比对一致，安装签名复核通过。
- 核对运行路径 `/Applications/Codex Quota.app/Contents/MacOS/CodexQuotaApp`，验收时 PID 15752。
- 安装前后 `mouseGestureRules` 的 SHA-256 均为 `cd9045fe53e8942545bb4e9e269c861af9173ab000cd9f66a518268c3fed5029`。
- 原安装归档：`outputs/app-archives.noindex/before-rightclick-controls-20260907.zip`；对应 JSON 记录来源、版本和 SHA-256。已检查 ZIP 完整性及归档内可执行文件与原安装完全一致。
- 临时 `Gesture UI Validation.app`、对应测试偏好和 LaunchServices 注册已移除。工作区扫描仅余正式开发构建；LaunchServices 仅注册正式安装；Spotlight 查询当前返回两个保留入口，没有额外本项目副本。未重建全系统索引。
