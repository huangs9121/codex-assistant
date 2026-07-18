# Codex 助手

面向 Codex 日常使用的开源辅助工具合集。这个仓库用于集中维护菜单栏工具、自动化脚本和后续可复用的小型辅助功能。

## 当前工具

### Codex Quota

原生 macOS 菜单栏 App，不用反复输入 `/status`，随时看到 Codex 剩余额度、重置倒计时和临时 reset 预告。

#### 它解决什么问题

- **查额度太麻烦**：每 15 秒通过本机 Codex 主动查询最新额度，不用打开 Codex、输入 `/status`。
- **重置后显示旧数据**：重置卡生效后直接读取服务端新额度，不再等待下一次对话写入本地日志。
- **读错额度池**：只使用主 `codex` 周额度池，不会被 Spark 等独立模型额度覆盖。
- **不知道什么时候重置**：菜单栏可显示中文重置倒计时；Tibo 发布 reset 预告时发送 macOS 通知，并可打开原始 X 帖子。
- **菜单栏空间不够**：电池、数字徽章、分段电池和纯数字四种样式任选，Codex 文字、OpenAI Logo 也可显示或隐藏。

#### 功能

- 每 15 秒通过本机 Codex 主动查询最新额度；接口不可用时自动回退到本地额度快照
- 根据 macOS 首选语言自动显示简体中文或英文，其他语言回退英文
- 四种显示样式：原生电池、数字徽章、分段电池、纯数字
- 左侧标识支持 `Codex` 文字、OpenAI Logo 或隐藏
- 可选在菜单栏显示中文重置倒计时（例如 `6天`、`12小时`）
- 信息区显示精确到秒的更新时间、下次重置和当前套餐
- 识别到真实额度周期已重置后，在首个 15 秒轮询内发送 macOS 系统通知，并按周期去重
- 自动监控 Tibo reset 预告，发送系统通知并链接到原始 X 帖子；预期时间到达后自动恢复“暂无预告”
- 支持 GitHub 新版本提醒和开机启动
- 按住 Command（⌘）拖动图标，可调整它在菜单栏中的位置
- 仅支持 arm64（Apple Silicon）和 macOS 13 及以上

开机启动默认关闭；启用前建议先将 App 放入 `/Applications`。

## 安装

同事可从 [GitHub Releases](https://github.com/huangs9121/codex-assistant/releases) 下载 `Codex Quota-arm64.zip`，解压后将 `Codex Quota.app` 拖入 `/Applications`。首次运行如果被 macOS 拦截，可在 Finder 中右键 App 后选择“打开”。

当前发布使用 ad-hoc 签名且未经 Apple 公证，Gatekeeper 出现安全提醒属于预期情况。请只从本仓库下载。

## 更新策略

App 启动和持续运行期间按策略检查 GitHub 公开 Release：成功后至少间隔 24 小时，失败后至少间隔 1 小时重试。检查只向 GitHub 公开 API 发出 `GET` 请求；发现新版本时仅提示并打开 Release 页面，不会自动下载或安装。

## 隐私

- App 通过本机安装的 Codex 查询当前限额，不直接读取、复制或保存 Codex token 和账号凭据。
- `~/.codex/sessions` 只作为查询失败时的本地降级数据源，不修改、不上传。
- App 不读取或记录对话内容；其他网络访问仅用于检查 GitHub 公开 Release，以及只读获取 `willcodexquotareset.com` 的 reset 预告。

## 目录结构

```text
apps/codex-quota/   Codex Quota Swift package
docs/               设计与实施文档
outputs/            本机构建产物，不提交 Git
verification/       本机验证截图，不提交 Git
```

## 构建

需要 macOS 13 及以上、Apple Silicon 和 Swift 6。从仓库根目录运行：

```bash
apps/codex-quota/Scripts/build_app.sh
```

构建完成后生成：

```text
outputs/Codex Quota.app
outputs/Codex Quota-arm64.zip
```

构建脚本会运行测试并生成 ad-hoc 签名的 arm64 App 和 ZIP。

## 商标与项目关系

OpenAI Blossom 标识归 OpenAI 所有，使用方式遵循 [OpenAI Brand Guidelines](https://openai.com/brand/)。本项目是非官方开源工具，与 OpenAI 无隶属关系，也不暗示 OpenAI 的认可或背书。

## 开源协议

[MIT](LICENSE)
