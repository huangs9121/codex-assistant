# Codex 助手

面向 Codex 日常使用的开源辅助工具合集。这个仓库用于集中维护菜单栏工具、自动化脚本和后续可复用的小型辅助功能。

## 当前工具

### Codex Quota

原生 macOS 菜单栏 App，用电池样式持续显示 Codex 剩余额度。

- 每 15 秒从本机自动读取最新额度快照
- 三种显示样式：原生电池、数字徽章、分段电池
- 左侧标识支持 `Codex` 文字、OpenAI Logo 或隐藏
- 可选在菜单栏显示紧凑重置倒计时（`D` / `H`）
- 信息区显示更新时间、下次重置、当前套餐和套餐到期；Pro 套餐来自最新本地额度快照，到期时间无法安全匹配时显示 `--`
- 支持 GitHub 新版本提醒和开机启动
- 仅支持 arm64（Apple Silicon）和 macOS 13 及以上

开机启动默认关闭；启用前建议先将 App 放入 `/Applications`。

## 安装

同事可从 [GitHub Releases](https://github.com/huangs9121/codex-assistant/releases) 下载 `Codex Quota-arm64.zip`，解压后将 `Codex Quota.app` 拖入 `/Applications`。首次运行如果被 macOS 拦截，可在 Finder 中右键 App 后选择“打开”。

当前发布使用 ad-hoc 签名且未经 Apple 公证，Gatekeeper 出现安全提醒属于预期情况。请只从本仓库下载。

## 更新策略

App 启动和持续运行期间按策略检查 GitHub 公开 Release：成功后至少间隔 24 小时，失败后至少间隔 1 小时重试。检查只向 GitHub 公开 API 发出 `GET` 请求；发现新版本时仅提示并打开 Release 页面，不会自动下载或安装。

## 隐私

- `~/.codex/sessions` 和 `~/.codex/auth.json` 仅在本机读取，不修改、不上传。
- auth 文件仅用于只读解析 JWT payload 中匹配当前套餐的到期信息；App 不记录 token、账号信息或其他 claims。
- 唯一网络访问是上述 GitHub 公开 Release 更新检查，不发送 GitHub token、Codex token 或设备信息。

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
