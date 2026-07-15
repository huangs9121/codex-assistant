# Codex 助手项目迁移与开源设计

## 目标

把现有 Codex Quota 菜单栏 App 迁移到 `/Users/openclaw/Projects/codex助手`，保留本地 Git 历史，并把该目录建设成后续承载多个 Codex 辅助功能的公开 monorepo。

## 本地结构

```text
codex助手/
├── apps/codex-quota/     # 当前 Swift 菜单栏 App
├── docs/                 # 设计与实施文档
├── outputs/              # 本地 App/ZIP 产物，不提交 Git
├── README.md
├── LICENSE               # MIT
└── .gitignore
```

现有 `work/CodexQuota/.git` 迁移为新项目根仓库，原提交历史保持不变。Swift package 文件使用 `git mv` 移入 `apps/codex-quota`。现有设计与计划文档移入 `docs/superpowers`；现有 App 和 ZIP 移入根目录 `outputs`。

## 构建与运行

`apps/codex-quota/Scripts/build_app.sh` 现有的两级上溯路径在新结构中正好指向 monorepo 根目录，因此产物继续写入根目录 `outputs`。迁移后必须从新路径重新运行测试、arm64 构建和完整 App/ZIP 打包，并重新启动新路径下的 App，确认旧路径无残留依赖。

## 开源发布

- GitHub 账号：`huangs9121`
- 公开仓库：`codex-assistant`
- 默认分支：`main`
- 开源协议：MIT
- 描述：`Codex 使用辅助工具合集`

README 使用中文说明项目定位、当前功能、构建方式、目录结构和隐私边界。`outputs`、Swift 构建缓存和本机临时验证文件不进入 Git 历史。

## 验收

1. 新目录存在，旧源码、文档和输出目录已迁走，无重复项目副本。
2. Git 历史包含原始提交和迁移提交，工作区干净。
3. 新路径下 62 项测试、arm64 Release 和打包脚本通过。
4. 根目录 `outputs` 仅包含最终 App 与 ZIP，签名、架构和 ZIP 解包验证通过。
5. 最终 App 从新路径运行。
6. GitHub 仓库为 public，`origin` 指向 `huangs9121/codex-assistant`，本地 `main` 与远端同步。
