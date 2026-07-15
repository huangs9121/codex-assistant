# Codex 助手

面向 Codex 日常使用的开源辅助工具合集。这个仓库用于集中维护菜单栏工具、自动化脚本和后续可复用的小型辅助功能。

## 当前工具

### Codex Quota

原生 macOS 菜单栏 App，用电池样式持续显示 Codex 剩余额度。

- 每 15 秒自动读取本机最新额度快照
- 三种显示样式：原生电池、数字徽章、分段电池
- 可隐藏或显示 `Codex` 文字
- 显示快照更新时间和下次重置倒计时
- 支持 Apple Silicon，当前构建目标为 macOS 13 及以上

额度数据仅从当前用户的 `~/.codex/sessions` 读取。App 不调用私有接口，不上传会话内容，也不会修改 Codex 数据。

## 目录结构

```text
apps/codex-quota/   Codex Quota Swift package
docs/               设计与实施文档
outputs/            本机构建产物，不提交 Git
verification/       本机验证截图，不提交 Git
```

## 构建

需要 macOS、Apple Silicon 和 Swift 6：

```bash
cd apps/codex-quota
swift run CodexQuotaCoreTests
./Scripts/build_app.sh
```

构建完成后生成：

```text
outputs/Codex Quota.app
outputs/Codex Quota-arm64.zip
```

## 开源协议

[MIT](LICENSE)
