# Codex Quota v1.1 功能扩展设计

## 目标

在现有 Codex Quota 菜单栏 App 上增加版本更新提示、三态左侧标识、菜单栏重置倒计时、开机启动和套餐信息，同时保持现有 15 秒本地额度刷新、三种电池样式和 Apple Silicon 分发方式。

本次版本号为 `1.1.0`，Git tag 为 `v1.1.0`。当前旧版不具备更新检查能力，因此用户必须手动安装 v1.1.0 一次；从 v1.1.0 开始，后续 GitHub Release 可以主动提示。

## 菜单栏组合

菜单栏从左到右组合为：

```text
[Codex 文字 / OpenAI Logo / 无] + 电池样式 + 剩余百分比 + [2D / 7H]
```

### 左侧标识

新增 `StatusIdentityMode`：

- `text`：显示 `Codex`，默认值；
- `logo`：显示 17×17pt 官方单色 OpenAI Blossom；
- `hidden`：不显示左侧标识。

从旧偏好迁移时，如果新键不存在：旧 `showsCodexLabel == true` 映射为 `text`，旧值为 `false` 映射为 `hidden`。迁移后写入新键，旧键不再参与渲染。

Logo 使用官方提供的原始比例素材，作为 macOS 模板图适配浅色、深色和菜单栏高亮状态，不增加颜色、特效或变形。Logo 只作为 OpenAI/Codex 服务的状态标识，不作为“Codex 助手”项目主品牌。README 增加 OpenAI 商标归属与非官方项目声明。实现遵循 [OpenAI Brand Guidelines](https://openai.com/brand/)。

### 紧凑重置时间

新增 `showsResetCountdownInStatusBar`，默认 `false`，避免升级后菜单栏突然变长。

- 剩余时间大于等于 24 小时：向下取整显示 `XD`，例如 `2D`；
- 小于 24 小时：向下取整显示 `XH`，例如 `7H`；
- 小于 1 小时或已到期：显示 `0H`；
- 无有效 `resets_at`：显示 `--`。

下拉菜单中的完整中文倒计时始终保留，不受该开关影响。

## 下拉菜单

采用单层平铺结构：

1. 信息区四行：`更新时间`、`下次重置`、`当前套餐`、`套餐到期`；
2. 分隔线；
3. 电池样式区：A/B/C 和真实预览；
4. 左侧标识区：Codex 文字、OpenAI Logo、不显示标识；
5. 分隔线；
6. `显示重置时间`；
7. `开机自动启动`；
8. 分隔线；
9. `检查更新…`，发现新版时改为 `新版本 X.Y.Z 可用…`；
10. `退出`。

样式、标识和重置时间均使用当前自定义整行按钮，点击后立即更新菜单栏和勾选状态，并保持菜单打开。登录项操作失败或需要系统批准时可以弹出系统说明；检查更新和退出允许菜单关闭。

## 套餐与到期时间

### 当前套餐

套餐从与剩余额度相同的最新 `event_msg / token_count / rate_limits.plan_type` 读取，不使用旧登录令牌作为主来源。

规范化映射：

- `prolite`、`pro` → `Pro`；
- `plus` → `Plus`；
- `free` → `Free`；
- `team`、`business`、`enterprise` 使用对应用户可读名称；
- 缺失或未知值 → `--`。

`QuotaSnapshot` 保存所选额度窗口、快照时间、重置时间和规范化套餐。套餐来自同一条 rate-limit 记录，但不依赖 primary/secondary 的选择。

### 套餐到期

额度快照当前不提供订阅到期日期。App 可以只读解析 `~/.codex/auth.json` 中 `tokens.id_token` 的 JWT payload，但不得记录、上传、缓存或展示任何 token、邮箱、账号 ID 或无关 claims。

仅当以下条件全部满足时显示 `yyyy-MM-dd`：

1. `chatgpt_plan_type` 规范化后与最新额度快照套餐一致；
2. `chatgpt_subscription_active_until` 可解析；
3. 到期时间晚于当前时间。

任一条件不满足即显示 `--`。当前本机额度快照为 `prolite → Pro`，旧令牌为 Plus，因此必须显示 `套餐：Pro`、`套餐到期：--`。

## 版本更新提示

本次不使用 Sparkle，也不自动下载或替换 App。当前分发只有 ad-hoc Apple 签名；安全、无打扰的自动安装需要额外维护更新签名，最好同时使用 Developer ID 签名与公证。Sparkle 官方也要求对更新包使用 EdDSA 签名，并建议 Developer ID。[Sparkle Documentation](https://sparkle-project.org/documentation/)

### 检查来源

使用公开接口：

```text
GET https://api.github.com/repos/huangs9121/codex-assistant/releases/latest
```

请求设置明确 `User-Agent`、GitHub JSON Accept header 和超时，不发送 GitHub token、Codex token 或设备信息。公开仓库 latest release 接口允许免认证读取。[GitHub Releases API](https://docs.github.com/en/rest/releases/releases)

### 检查策略

- 启动时，如果上次成功检查距今至少 24 小时，则自动检查；
- App 持续运行时每 24 小时检查；
- 自动失败时静默，最早 1 小时后允许重试；
- 用户点击 `检查更新…` 时忽略节流并给出成功、无更新或失败结果；
- 只接受非 draft、非 prerelease 的 latest release；
- tag 支持 `v1.2.0` 或 `1.2.0`，按数字语义版本比较，不做字符串字典序比较；
- 每个新版本只自动弹窗一次，使用 `lastPromptedVersion` 持久化；
- 弹窗显示版本号和 release body 摘要，按钮为 `前往更新` 与 `稍后`；
- `前往更新` 使用 `NSWorkspace` 打开 release 的 `html_url`；菜单项仍可再次打开该版本。

### 发布流程

构建脚本从一个版本常量生成 `CFBundleShortVersionString` 和递增的 `CFBundleVersion`，不再硬编码散落值。新增发布脚本负责：运行测试、构建并验证 App/ZIP、确认 Git 工作区干净、创建 tag、创建 GitHub Release、上传 `Codex Quota-arm64.zip`。首次建立公开 `v1.1.0` Release。

## 开机自动启动

使用 macOS 13+ `ServiceManagement.SMAppService.mainAppService`，不写入 `~/Library/LaunchAgents`，也不增加辅助进程。Apple 将 `mainAppService` 定义为当前主应用的登录项，并由系统管理注册和授权状态。[Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)

- 默认关闭；
- 菜单勾选由 `SMAppService.status` 实时决定，不用 UserDefaults 冒充系统状态；
- 开启调用 `register()`，关闭调用 `unregister()`；
- `.enabled` 显示勾选；
- `.requiresApproval` 显示 `开机自动启动（需系统确认）`，点击后打开 Login Items 系统设置；
- `.notRegistered` 不勾选；
- `.notFound` 或 API 错误显示明确错误，不声称已开启。

建议用户把 App 放入 `/Applications` 后再启用登录项。构建产物继续保留在项目 `outputs` 供开发验证。

## 代码边界

- `CodexQuotaCore`：扩展 quota/plan 模型、套餐规范化、只读订阅到期解析、语义版本与 GitHub release payload、更新节流策略；
- `CodexQuotaUI`：`StatusIdentityMode`、偏好迁移、紧凑重置格式、Blossom 模板图和完整状态栏组合；
- `CodexQuotaApp`：URLSession 更新请求、更新弹窗、`SMAppService` 状态与操作、菜单装配；
- `Scripts`：版本源、打包元数据和 GitHub Release 发布脚本。

网络更新检查与 15 秒额度扫描使用不同的调度和队列，互不阻塞。所有 AppKit 与菜单状态修改只在 MainActor 执行。

## 错误与隐私

- 额度、套餐或 auth 文件缺失时显示 `--`，App 不崩溃；
- JWT 只做本地展示用途的 payload 解码，不声称验证身份，不输出原文；
- 网络失败不影响额度刷新和菜单操作；
- 自动更新检查失败不抢焦点；手动检查失败提供可操作说明；
- 登录项失败后重新读取系统 status，不留下虚假勾选；
- App 只新增一次对 `api.github.com` 的周期性 GET，不上传会话内容。

## 测试与验收

1. 旧 `showsCodexLabel` 正确迁移到三态标识，新偏好持久化；
2. 文字、官方 Logo、隐藏三态在 A/B/C 样式和有无重置后缀下无裁切；
3. 紧凑倒计时覆盖 2D、23H、0H、已到期和无数据；
4. `prolite` 显示 Pro，未知套餐显示 `--`；
5. 套餐匹配且未来到期才显示日期，Plus/Pro 不匹配、过期、损坏 JWT 均显示 `--`；
6. 语义版本比较覆盖 `1.9.0 < 1.10.0`、相等、旧版本和非法 tag；
7. 自动检查 24 小时节流、失败 1 小时重试、手动强制检查和每版本仅提示一次；
8. GitHub JSON 缺失字段或网络错误不影响 App；
9. 登录项 enabled/notRegistered/requiresApproval/error 状态与菜单一致；
10. 实际菜单中所有平铺项、预览、勾选和菜单保持行为正确；
11. App 从 `/Applications` 副本验证登录启动开关，不污染开发输出；
12. 完整 runner、arm64 Release、App/ZIP 签名、权限、解包和 15 秒生命周期继续通过；
13. `v1.1.0` GitHub Release 为 public，ZIP asset 可访问，App 能识别后续测试 release 但不误判当前版本。

## 明确不做

- 不静默下载、替换或自动安装 App；
- 不接入私有 OpenAI 订阅接口；
- 不把 OpenAI Logo 作为项目 Logo 或暗示官方背书；
- 不支持 Intel 或 universal binary；
- 不在本次申请 Developer ID、签名公证或 App Store 发布。
