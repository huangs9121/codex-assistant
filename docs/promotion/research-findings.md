# 推广与命名调研结论（2026-08）

> 调研范围：macOS 独立工具推广打法、Codex/Claude 生态周边工具命名与传播、小红书独立开发者生态、
> 目标人群「用 Mac 玩 AI 的人（主力 Codex，后续扩展其他工具）」。

## 一、竞争格局：额度监控是红海，操控是蓝海

菜单栏 AI 额度监控类产品已高度拥挤：

- **[CodexBar](https://github.com/steipete/CodexBar/)**（Peter Steinberger，知名开发者）：已支持 **69 家供应商**（Codex/OpenAI/Claude/Cursor/Gemini…），有官网 codexbar.app，Reddit 热议
- **[ManaBar](https://github.com/elvishasleft/manabar)**（一名）与 **[ManaBar](https://github.com/andylimlabs/manabar)**（又一名，MMO 法力条可视化）——「法力条」意象已被占用两次
- ClaudeMeter、ClaudeBar、ClaudeUsageBar、CC Usage Bar……

**结论：我们是这个品类里唯一「能动手」的**——CodexBar 们只能「看」额度，我们有手势触发、全局快捷键、⚡️立即触发、滚轮反转，是「看 + 操控」。定位与命名都必须 owning「操控」而非「监控」。

## 二、渠道打法（调研支持的修订）

| 渠道 | 调研结论 | 对我们的修订 |
|---|---|---|
| 小红书 | 5 万+ 独立开发者聚集，#独立开发者 话题 700 万次讨论，独立开发内容同比 +146%；**官方点名最大误区是「笔记写成产品日志」**（repo/bug/开发日志吸引不了普通用户）；CapWords 案例：场景化种草 → 用户自发传播 | 主阵地不变；笔记全部改为**场景合集体**（如「程序员必装的 5 个 Mac 神器」），功能点藏在场景里；参加官方独立开发大赛、带话题蹭平台流量 |
| Product Hunt | 对 indie 的价值在下降（社区共识「PH is not for Indie Hackers anymore」） | 降级为可选项；若上，作为发版周的一环而非核心 |
| Reddit / Indie Hackers / X build-in-public | 诚实的 build-in-public 帖带来的注册是 PH 的 **3-8 倍**（r/buildinpublic 共识） | 发版前 1-2 周就开始在 X/IH 发 build-in-public（手势动图是最好的素材）；r/ClaudeCode、r/OpenaiCodex 是精准社区（CodexBar 就是在这些社区火起来的） |
| Hacker News | Show HN 对开源 mac 工具仍有效（多条同类工具 HN 讨论） | 开源仓库 + Show HN 一帖，标题讲「系统级鼠标手势」而非额度 |
| 对标路径 | CodexBar 靠 r/ClaudeCode、r/OpenaiCodex 口碑起量 | 直接复用已被验证的社区路径 |

## 三、命名规律（调研结论）

1. **Brandable > Descriptive**：描述性名字难以注册商标、难做品牌资产；独特名字才有保护性（TrademarkEngine、NameSilo 结论一致）
2. **生态内 X-Bar 命名空间已挤满**：CodexBar / TokenBar（另一独立开发者在用）/ ManaBar×2 / ClaudeBar / SwiftBar / Bartender——**避开 Bar 后缀、避开监控类语义**
3. 不能绑死 Codex：后续要扩展 Claude/Gemini 等（CodexBar 已把「多供应商监控」占住，我们绑 Codex 反而自缩赛道）
4. 「Codex 额度」搜索流量靠 tagline / README / 笔记关键词承接，不靠名字

## 四、对人群的洞察

「用 Mac **玩** AI」——「玩」字是钥匙：这群人有玩家文化 overlap（折腾、mod、连招、法力条）。
玩家 UI 语言（combo 连招 / cast 施法 / mana 法力）是与他们沟通的最短路径。
我们的双段 8 方向手势在他们的语境里就叫**连招（combo）**；触发快捷键就叫**施法/出招**。

## 五、命名方案（第三轮，基于以上全部）

| 候选 | 立意 | 优势 | 风险 |
|---|---|---|---|
| **Kombo** | 连招（玩家文化）：双段手势=连招，8 方向=出招表；Shottr 式变形拼写 | 直击「玩 AI」人群；与监控类产品完全区隔；独特性/可注册性拉满 | 常见词变体，部分人会问为什么拼成 K |
| **Flint** | 火石：一点就着（⚡️立即触发）；燧人氏的中文梗可做小红书话题 | Brandable 最优、独特性验证过；与具体 AI 工具解耦，扩展无碍 | 语义需一句话解释，联想门槛略高 |
| **Flick** | 一挥即发：标准手势术语 | 国际化好念；手势卖点直给 | 与 Flickr 联想干扰；监控属性没盖住 |

定位语（通用）：**Kombo/Flint — AI 玩家的 Mac 操控台：额度看得见，招式出得来。**
（英文：The action deck for people who play with AI on Mac.）

## 六、已排除

AgentBar（agent 泛滥且产品尚无真 AI）、EverBar（平庸）、DrawBar / TokenBar / RightHand（第一轮否）、
CodexBar / ManaBar / TokenBar（已被占用）、Conductor（conductor.build 已是 Claude agents 管理工具）。
