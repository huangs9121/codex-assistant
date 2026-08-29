# 产品改名候选清单（目标：v1.4.0 落地）

> 背景产品已从「Codex 额度监控」长成「菜单栏额度 + 右键手势 + 全局快捷键 + 滚轮反转」的
> AI 编程效率工具箱，"Codex Quota" 锁死单一功能，且与 OpenAI Codex 有商标邻近风险。
> 定位语（所有候选通用）：**AI 时代 Mac 必备的效率工具箱 / The must-have toolkit for the AI era**。
> 命名策略：名字短而品牌化即可，语义由定位语承担（Raycast / Arc / Linear 路线）。

## 已定决策

- 改名节奏：**先发 v1.3.0（内容已定稿），改名作为 v1.4.0 主打事件**，配合「更名公告」再传播一波。
- 改名红线：**Bundle ID（local.openclaw.codexquota）不动**，保住用户设置、开机启动、辅助功能/输入监听权限。
- 改名范围：显示名（CFBundleName/DisplayName、菜单、界面文案）、GitHub 仓库名（旧链接自动重定向，老客户端更新不断）、自签证书显示名、README/文档/更新链路脚本同步。

## 第一轮候选（被否）

| 名字 | 立意 | 未采用原因 |
|---|---|---|
| DrawBar | Draw=画方向 + Bar=菜单栏/额度条 | 用户觉得没打中「AI 时代必备」 |
| TokenBar | AI 额度语义直给 | 又锁回额度监控 |
| RightHand | 右手/手势 | 重名多 |

## 第二轮候选（待拍板）

| 名字 | 立意 | 优势 | 风险 |
|---|---|---|---|
| **AgentBar** | AI 时代最热词，「替你盯、替你触发」的智能体；为未来接入 AI 能力（自然语言配规则等）预留品牌空间 | 点题「AI 时代必备」最狠，前瞻性最强 | 当前产品尚无真 AI 功能，略显超前；agent 一词被市场滥用 |
| **Flint** | 火石：右键画方向=打火擦出火花，与 ⚡️立即触发天然呼应 | Raycast 式无语义品牌路线，独特性/可注册性最好 | 与 AI 的关联全靠定位语 |
| **EverBar** | ever=始终常驻，「常驻必备」即视感 | 直白稳妥，好念好记 | 略平庸，记忆点一般 |
| **Flick** | 轻扫/一挥（标准手势术语），「一挥即发」 | 国际化好念，手势卖点直给 | 与 Flickr 有联想干扰 |

## 其他备选（未进短名单）

MacPulse（AI 脉搏）、AIHUD（抬头显示）、EraBar（时代点题）、CodeMate（编程伴侣，重名风险）、GlanceBar（一眼额度，手势缺失）

## 拍板后的工程清单（约半天）

1. `build_app.sh`：CFBundleName / DisplayName / ZIP 名 / 证书名引用
2. 代码 33 处：AppText、AutomaticUpdateInstaller、AutomaticUpdatePackage、main.swift（状态栏标题、菜单、关于）
3. `release_github.sh` 与 `check_update_chain.py`：仓库名、产物名断言
4. README 重写 + 更名公告（v1.4.0 release notes 开头声明「原 Codex Quota」）
5. GitHub 仓库改名（`gh repo rename`，保留重定向）
6. 推广物料统一换新名 + 「更名」话题点（小红书适合发「我把它改名了」这类笔记）
