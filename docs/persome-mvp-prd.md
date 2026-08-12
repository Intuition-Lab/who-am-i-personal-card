# Persome MVP 产品需求文档

> 版本：MVP v1.0 Draft
> 日期：2026-08-12
> 平台：macOS 13+
> 内测规模：100 人
> 当前技术基线：Persome Desktop `0.1.0-beta.4`
> 产品名：Persome
> 核心日常界面：Quick Box / Persome Spotlight
> 核心模型空间：Map / Living Model
> 核心身份对象：Personal Card

---

## 0. MVP 一句话

> Persome 是一个随叫随到的记忆入口：你在 Quick Box 里留下或回忆，背后的 Map 持续形成你的 Personal Card，并让获得授权的 AI 读懂同一个你。

Persome 不是一个新的启动器，也不是另一个需要整理的知识库。

用户启动 Persome、再次点击 Dock 图标、使用全局快捷键或点击菜单栏图标时，最先出现的都是独立 Quick Box。用户点击 `Open app`、日期或 Map 后才展开 Dashboard。Dashboard 首页固定由顶部 Personal Card 与其下同一套 Quick Box 组成。产品真正持续生长的核心是 Map；Personal Card 是 Map 的身份摘要。Map 将星云图、Living Model、Rewind 和 Evidence 收敛成一个动态人格展示空间。Quick Box 向 Map 写入或回忆，Remind 从 Map 浮出线索，Swipe Your Card 把 Map 的授权切片提供给 AI。

---

## 1. 产品核心结构

### 1.1 核心关系：一张 Card，背后一幅 Living Map

Map 是产品的核心模型空间和唯一事实源；Personal Card 是 Map 在当前时刻的浓缩表达、品牌主视觉和对外通行证。两者不能拆成两个产品，也不能把 Card 降级成 Dashboard 中的普通卡片。

Personal Card 代表：

- Map 当前版本的身份摘要；
- 用户进入动态人格图的封面；
- 可以刷给其他 AI 的模型通行证；
- 产品的品牌识别物。

Map 负责：

- 承载用户当前的 Personal Model；
- 收拢记忆、人物、项目、偏好、状态和时间变化；
- 将每条模型理解连接到 Evidence；
- 接收 Jot、行为数据和用户纠正；
- 为 Card、Ask、Remind、Swipe 和 Agent Report 提供同一个数据来源。

Card 正面回答“这是谁”，背面回答“为什么它这样理解我”。

### 1.2 Dashboard 首页：Card 在上，Quick Box 在下

完整 App 主页面只保留两层：

1. 顶部 Personal Card。
2. Card 下方的 Quick Box。

不在两者之间或下方继续堆叠 Remind、Rewind、Swipe、MCP 等模块。它们通过 Quick Box 底部入口进入完整 App 的对应上下文。

```text
                         ┌──────────────────┐
                         │  PERSONAL CARD   │
                         │                  │
                         │      @user       │
                         │                  │
                         └──────────────────┘
                              click to flip

┌──────────────────────────────────────────────────────────┐
│  ┌────────────────────────────────────────────────────┐  │
│  │  Jot something down...                       [ 🎙 ]│  │
│  └────────────────────────────────────────────────────┘  │
│  [ Ask instead ]                                         │
│                                                          │
│  Last 30 days                          less ░▒▓█ more    │
│  ▓ █ ▒ █ ▓ ░ ░   ▒ ▓ █ █ ▓ ░ ░   █ ▓ ▓ █ ▒ ░ ░   ▓ █ ▓ █ │
│  Mon         Sun                                         │
│                                                          │
│  Today  ·  This week  ·  This month  ·  Map              │
│                              [ Settings ]  [ Open app ]  │
└──────────────────────────────────────────────────────────┘
```

启动 App、再次点击 Dock、全局快捷键或菜单栏唤出时，只出现独立 Quick Box，不带 Card。点击 `Open app` 后展开 Dashboard，才出现“Card + Quick Box”的完整首页。Dashboard 使用 Persome 自己的无边框界面，不显示 macOS 红黄绿文档窗口控制点。

### 1.3 中心收敛关系

```text
  被动活动 / Jot / 用户纠正 / Obsidian / Notes
                        │
                        ▼
         ┌─────────────────────────────────┐
         │              MAP                │
         │     动态人格展示 · 唯一事实源     │
         │                                 │
         │  Nebula       Living Model      │
         │  关系结构      当前人格与状态      │
         │                                 │
         │  Rewind       Evidence          │
         │  时间变化      来源与可信度         │
         └───────────────┬─────────────────┘
                         │
       ┌─────────┬───────┼────────┬──────────────┐
       ▼         ▼       ▼        ▼              ▼
 Personal Card  Ask    Remind   Swipe Card    Agent Report
 当前封面与通行证  回忆    主动线索   授权模型切片    AI 使用收据
                                   │
                                   ▼
                             MCP / Connected AI

 Settings 围绕整张 Map 控制数据来源、排除、删除、导出和授权边界。
```

### 1.4 用户可见的信息架构

Dashboard 只是完整 App 的展开外壳，不再额外设计一套与 Card / Map 重复的“数据驾驶舱”页面。用户可见结构只有：

1. **Quick Box**：Jot、Ask、Correct、语音、热力图和六个出口；可以独立全局唤出。
2. **Dashboard 首页**：Personal Card 在上，Quick Box 在下。
3. **完整 App / Map**：产品核心；Nebula 星云图 + Living Model + Rewind + Evidence + Remind。
4. **完整 App / Swipe Your Card**：从 Map 生成授权切片；包含 Connected AI、MCP 和 Report。
5. **完整 App / Settings**：控制 Map 能接收什么、保留什么、向谁开放什么。

Rewind、Memory Sky 和 My Model 不再分别占用一级导航。它们是 Map 内观察同一个 Personal Model 的不同方式。

### 1.5 模块收敛规则

- **Card** 不保存另一份身份数据，只渲染 Map 的当前摘要。
- **Spotlight / Jot** 写入 Map；**Ask / Correct** 读取或修改 Map。
- **Remind** 是 Map 主动挑出的三条线索，不建立独立提醒数据库。
- **Rewind** 是 Map 的时间视角，不跳转到另一套详情系统。
- **Evidence** 是 Map 的来源边和可信度，不做孤立的技术页面。
- **Swipe Your Card** 是 Map 的授权投影，不复制整份模型。
- **Agent Report** 将 AI 的真实读取轨迹写回 Map，成为可审计的使用记录。
- **Settings** 只控制 Map 的数据边界和授权边界，不重复提供一个 My Model 页面。

产品结构可以压缩成一句话：

> 三个入口，两块界面，一个核心 Map。

---

## 2. 产品定位

### 2.1 不选择的赛道

Persome 不进入 Alfred、Recast/同类极致效率工具和命令启动器赛道。

原因：

- 该赛道成熟，用户迁移成本高。
- “快速打开和执行”不是 Persome 的独特资产。
- 全局输入框只是低摩擦入口，不是产品本身。
- Persome 的差异化来自持续生长的个人记忆、可验证的 Personal Model 和跨 AI 复用。

### 2.2 产品形态

- 对外统一使用 **Persome**。
- 分发为独立 `Persome.dmg`。
- 安装后是原生 `Persome.app`，不是 HTML 页面。
- App 有 Dock 图标、菜单栏常驻图标和全局快捷键。
- 用户不需要知道 Persome Runtime、Node、MCP server 等底层运行方式。
- MCP 对普通用户的产品表达是 **Swipe Your Card / Connected AI**。

### 2.3 目标用户

核心用户：

- 同时使用 ChatGPT、Claude、Codex、Cursor、Gemini 等多个 AI。
- 已有 Apple Notes、Obsidian、Notion 或大量本地文件。
- 信息分散，知道长期记忆有价值，但不愿维护另一套知识库。
- 希望 AI 认识同一个自己，并且要求理解有依据、可纠正、可删除。

### 2.4 核心价值顺序

1. **自生长**：Card 会跟着用户继续长，不是一次性画像。
2. **零操作**：不用标签和文件夹，记录和行为自动结构化。
3. **全 AI 可读**：刷一次 Card，授权 AI 可以读取同一份模型。
4. **可回忆、可验证**：结论能回到当天和原始 Evidence。
5. **本地可控**：权限、纠正、删除和导出由用户掌握。

对外主张：

> It grows with you. Every AI can remember.

中文：

> 它自己长大，让每个 AI 都记得你。

---

## 3. MVP 目标与非目标

### 3.1 MVP 目标

MVP 必须证明四件事：

1. 用户安装后无需整理，Card 会从本机 Personal Model 自动形成。
2. 用户可以用 Jot 主动留下一句话，也可以用 Ask 回忆过去。
3. 用户能通过 Map 内的星云图、Living Model、Rewind 和 Evidence 验证模型为什么这样理解自己。
4. 用户能通过 Swipe Your Card 把同一份模型安全地提供给 Claude、GPT/Codex 或其他 MCP Agent。

### 3.2 MVP 非目标

- 不做通用命令启动器。
- 不做团队知识库。
- 不做外部行动 Agent，不替用户发消息、付款、发布或下单。
- 不要求用户管理标签、双链、文件夹和知识图谱。
- 不在 MVP 同时建设新的 Skills 输出层，先验证 MCP。
- 不在 MVP 正式交付 iPhone 和 Apple Watch，只保留架构入口。
- 不用“效率评分”评价用户。

---

## 4. 三个入口、两块界面

### 4.1 三个入口

1. **全局快捷键**：日常主入口。建议默认 `⌘ ⇧ Space`，用户可修改；从任何 App 唤出 Quick Box。
2. **Dock 图标**：与直接启动一致，先唤出独立 Quick Box；用户选择 `Open app` 后才展开 Dashboard。
3. **菜单栏常驻图标**：随时可见，是“Persome 一直在运行”的系统级证据；左键唤出 Quick Box，右键打开状态菜单。

菜单栏状态菜单包含：Open Persome、Jot、Ask、Today、Pause capture、Data & Permissions、Connected AI、Quit。

### 4.2 第一块界面：Quick Box

Quick Box 是用户每天实际操作的主界面，不展示完整 Card，也不复制完整 App。

- 打开后输入框立即获得焦点。
- 默认 Jot；可显式切换 Ask。
- 纠正与 Ask 共用对话态，不建立独立纠正页。
- 支持文字和语音；语音优先在本地转写，并先回填为可编辑文本。
- 空态显示最近 30 天活动热力图。
- 热力图回答“Persome 有没有工作”，不要求用户主动提问或查看日志。
- Quick Box 提供 `Settings` 和 `Open app` 两个出口。
- Today、This week、This month 和 Map 都进入完整 App 的同一 Map，只改变时间焦点。
- `Esc` 或再次按快捷键关闭。
- 高频唤出不播放位移动画，也不等待 Card 动画。

### 4.3 第二块界面：Dashboard

完整 App 承载四件低频但高信任价值的事：

1. **看见自己并立即输入**：主页面顶部是 Personal Card，下方是完整 Quick Box。
2. **验证模型**：Map 按日、周、月、年和长期星云展示模型怎样形成与变化，并承载 Remind。
3. **交给 AI**：Swipe Your Card 管理 MCP、Connected AI 和 Agent Report。
4. **控制边界**：Settings 管理数据来源、模型内容、Connected AI、删除和导出。

从 Quick Box 进入完整 App 时必须保留用户意图：

- `Today`：打开 Map / Rewind 的今天。
- `This week`：打开 Map / Rewind 的本周。
- `This month`：打开 Map / Rewind 的本月。
- `Map`：打开 Map 默认的 Living Model 星云状态。
- `Settings`：直接打开信任配置。
- `Open app`：展开 Dashboard，并打开“Card + Quick Box”首页。

Settings 不是设置项堆放处，而是信任落地的面板，只回答两个问题：

- **数据从哪来**：哪些 App 被观察、哪些明确排除、接入哪些外部数据源、MCP 开放给谁。
- **模型现在理解成了什么**：可以查看、纠正、删除、撤回和整份导出。

用户操作由此闭合：决定给什么 → 看 Map 怎样理解 → 随时纠正或删除 → 查看 AI 拿去做了什么 → 随时撤回授权。

---

## 5. Personal Card

### 5.1 Card 正面

展示：

- 用户 handle / display name
- Personal Model 身份
- Card 编号
- 生成月份
- 一句话身份表达
- 当前材质和 glyph

交互：

- 点击翻面。
- 拖动产生轻量 3D 视差。
- 键盘聚焦后 Enter 翻面。
- Card 不承担输入；输入始终在独立 Quick Box 中完成。

### 5.2 Card 背面

展示当前模型的微型 Map：

- ROOT 中心点
- FACE 亮星
- 记忆数量
- 当前模型最近一次变化
- `Expand Map`

点击 ROOT 或亮星显示：

- 当前理解
- 来源摘要
- 出处
- 改写
- 分享

### 5.3 Card 生长状态

Card 必须真实反映模型状态：

- New：刚创建，模型为空。
- Forming：正在积累。
- Growing：有新数据进入。
- Updated：用户纠正后已更新。
- Paused：捕获暂停。
- Limited：权限不足。

禁止在新用户或模型不可用时显示 Cecilia、Lin 或任何其他人的 Card。

### 5.4 Card 与其他模块的关系

- Map 通过星云结构、Living Model 和 Rewind 解释 Card 如何形成和变化。
- Remind 从 Card 的模型中浮出近期线索。
- Swipe Your Card 将当前 Card 的授权切片提供给 AI。
- Agent Report 记录 AI 怎样使用了这张 Card。

---

## 6. Persome Spotlight

Persome Spotlight 就是 Quick Box。它通过全局快捷键或菜单栏独立唤出；在完整 App 主页面中固定放在 Card 下方，并保持同一套状态和交互。

### 6.1 两个可控状态与疑问句识别

Spotlight 只有两个状态：

1. **Jot**：默认，记录一句话。
2. **Ask**：回忆、提问和纠正。

默认是 Jot。输入明显疑问句（问号或明确的中英文疑问结构）时，Spotlight 自动切换到 Ask，并显示 `Question detected · switched to Ask`。用户可以一键选择 `Keep as jot` 撤回识别；不自动提交、不在后台静默保存，也不对模糊陈述猜测意图。

切换：

- Jot 点击 `Ask instead`。
- Ask 点击 `Back to jotting`。
- 支持 `⌘ /` 切换。
- 每次新唤起默认 Jot；未提交草稿可在短时间内恢复。

### 6.2 Jot 空态

```text
┌──────────────────────────────────────────────────────────┐
│  Jot something down...                             [ 🎙 ]│
├──────────────────────────────────────────────────────────┤
│  [ Ask instead ]                                         │
│                                                          │
│  Last 30 days                          less ░▒▓█ more    │
│  ▓ █ ▒ █ ▓ ░ ░   ▒ ▓ █ █ ▓ ░ ░   █ ▓ ▓ █ ▒ ░ ░   ▓ █ ▓ █ │
│                                                          │
│  Today · This week · This month · Map                    │
│                              [ Settings ] [ Open app ]   │
└──────────────────────────────────────────────────────────┘
```

热力图：

- 表示当天活跃程度，不表示“有没有记录”。
- 电脑打开不等于整格满色。
- 深浅由前台活跃时间、有效活动段和来源多样性组成。
- 点击日期打开 Map，并直接进入该日期的 Rewind 模式。
- 暂停和数据缺口使用独立标识，不伪装为低活跃。

### 6.3 Jot 输入态

```text
┌──────────────────────────────────────────────────────────┐
│  call with Lin next Wed about pricing              [ 🎙 ]│
│                                          [ ⏎  Save ]     │
└──────────────────────────────────────────────────────────┘
```

规则：

- 输入第一个字符后，热力图和底部入口收起。
- `Enter` 保存；`Shift + Enter` 换行。
- 保存后显示 `Saved · time · Persome`。
- 先保存用户原文，再异步结构化。
- 用户不选择标签、项目或文件夹。
- 离线可写入，恢复后索引。
- 重试不能产生重复记录。

### 6.4 Ask 状态

```text
┌──────────────────────────────────────────────────────────┐
│  what was I working on three days ago?             [ 🎙 ]│
├──────────────────────────────────────────────────────────┤
│  Tuesday afternoon, mostly the pricing doc.              │
│  Two hours in Figma, then a call with Lin.               │
│                                                          │
│  > evidence   14:20 Figma · 15:05 Notion · 16:00 Zoom    │
│                                                          │
│  [ Back to jotting ]                                     │
└──────────────────────────────────────────────────────────┘
```

Ask 支持：

- 关于自己的过去：什么时候、做过什么、讨论过什么。
- 关于当前模型：为什么认为我怎样、依据是什么。
- 模型管理：纠正、删除一段、标记项目结束、导出。

Ask 不支持替用户到外部系统办事。

回答要求：

- 先回答，再给 Evidence。
- Evidence 显示时间、来源和可回到的位置。
- Evidence 不足时明确显示 `Not enough evidence`。
- 记录事实、用户原文、模型推断、生成文本必须区分。
- 产品语言统一用“回忆”，不把自己包装成传统搜索工具。

### 6.5 纠正

纠正属于 Ask，不做独立功能页。

示例：

```text
You: 那个项目我已经停了。

Persome: Updated. Pricing 2.0 marked as ended.
       Before: active project
       After: ended on Aug 12
       Source: your correction · just now
       [ Undo ] [ View in Living Model ]
```

必须展示：

- 改了哪一条
- 修改前
- 修改后
- 用户纠正收据
- Undo

### 6.6 语音

- Jot 与 Ask 均可录音。
- 优先本地转写。
- 转写结果先进入可编辑文本，不自动提交。
- 默认不保存原始音频。
- 麦克风权限与 Screen Recording 分开申请。

---

## 7. Remind

Remind 是 Map 主动浮出记忆的能力，不是独立一级模块，也不是传统待办或日程提醒器。

### 7.1 目标

用户不需要每次都提问，也能看到 Personal Model 认为此刻值得想起的内容。

### 7.2 三类 Remind

| 类型 | 含义 | 示例 |
| --- | --- | --- |
| 过去 | 值得回去的一件事 | “上周你决定先冻结视觉。” |
| 现在 | 可以继续的上下文 | “Personal Card 的 Report 还差 Evidence 收尾。” |
| 接下来 | 基于近期模式的线索 | “你可能想在 Lin 的会议前重新看定价记录。” |

### 7.3 规则

- 接下来的内容是建议，不是已经安排的任务。
- 不展示没有来源的确定时间。
- 每条可以打开 Evidence，或打开 Map 中对应的 Rewind 时间位置。
- 用户可以 `Not relevant`、`Remind later` 或关闭。
- 关闭反馈用于调整模型，不直接删除原始记录。
- Map 的 Today / Week 视图最多显示三条；Quick Box 空态不额外增加 Remind 区块。

---

## 8. Map：星云图 + Living Model —— 动态人格展示图

Map 是 Card 背面的完整展开，也是 Persome 的动态人格展示图。它不是单独的“知识图谱页面”，而是用户查看 Personal Model **现在是什么、为什么形成、怎样变化**的统一空间。

Rewind 不再是独立页面，而是 Map 的时间维度。Memory Sky 不再是独立模块，而是 Map 的星云视图。原 My Model / Identity 不再是独立列表页，而是 Map 的 Living Model 视图。

### 8.1 三个观察模式

Map 顶部使用显式分段切换，不新增一级页面：

1. **Nebula**：用星云图查看记忆、人物、项目和主题之间的关系。
2. **Living Model**：查看人格理解、偏好、项目状态、关系和开放事项如何动态变化。
3. **Rewind**：按日、周、月、年回到真实发生过的活动和 Evidence。

三个模式共用同一套节点、时间、Evidence 和纠正数据。切换模式只改变观察方式，不复制数据。

### 8.2 星云图视觉语义

- `ROOT`：长期核心理解，位于中心。
- `FACE`：当前 Card 正面采用的身份表达。
- 星：一段可追溯的记忆或模型理解。
- 星座：项目、人物、偏好、主题、Open Loop 等节点族。
- 线：有 Evidence 支持的可解释关系，不为了视觉效果随意连线。
- 亮度：近期活跃度或证据强度。
- 大小：对当前模型的影响权重。
- 脉冲：新 Evidence、用户纠正或状态变化。
- 虚线：推断关系；实线：记录事实或用户明确确认的关系。

点击任一节点，侧边详情显示：

- 当前理解
- 内容类型：用户原文 / 记录事实 / 模型推断 / 生成内容
- confidence 与 Evidence 数量
- 首次出现、最近变化
- 来源与相关日期
- `Correct`、`Delete`、`Mark ended`、`View history`、`Share`

### 8.3 Living Model：动态人格展示图

Living Model 不是一次性人格测试，也不把用户永久贴上固定标签。它展示模型在真实 Evidence 与用户纠正下持续形成的当前版本。

Living Model 包含：

- ROOT：长期核心理解
- FACE：当前画像和一句话身份表达
- PROJECTS：项目与状态
- PEOPLE：人物与关系
- PREFERENCES：偏好
- OPEN LOOPS：仍在继续的内容
- ENDED：已结束内容
- CHANGE：最近 7/30 天新形成、增强、减弱和被纠正的理解

交互要求：

- 新数据进入时，对应节点轻微生长或改变亮度。
- 用户纠正后立即显示 Before / After，并保留撤销收据。
- 支持 `Then / Now` 对比，解释模型在哪个时间点发生变化。
- 所有结论都能回到 Evidence 或 Rewind 时间位置。
- 没有足够依据的理解显示低置信度，不伪装为人格事实。

### 8.4 Rewind：Map 的时间维度

Rewind 负责“回到真实发生过的过去”。入口包括：

- Spotlight 热力图日期
- Quick Box 的 Today / This week / This month / Map
- Remind 的过去或现在条目
- Evidence 的 `Back to day`
- Map 节点的时间轨迹
- 菜单栏 Today

进入后仍停留在同一 Map 画布，只切换到 Rewind 模式并聚焦对应日期、节点或 Evidence，不跳转到另一套页面。

#### Day

- 当天活动时间轴
- App 与窗口活动段
- 手工 Jot
- 会议、文件和 AI 对话
- 获得权限时的屏幕画面
- 当天总结、今日一句、模型更新
- Evidence

支持拖动时间轴回放、点击活动段定位画面。没有截图权限时回退到真实文本事件，不生成假画面。

#### Week

- 七天活动强度
- 本周主题变化
- 重复模式和明显变化
- 周总结
- ROOT：本周写下的一句话
- 与上周对比

周总结必须标为生成内容，并显示时间范围和 Evidence 数量。

#### Month

- 月历热力图
- 每日活跃度
- 主要 App、主题和项目
- 数据暂停和数据缺口

空白日期不做推断。

#### Year

- 12 个月活动热力图
- 月度主题迁移
- 长期高频主题
- Living Model 阶段变化

不输出“效率分数”。

### 8.5 Map 的闭环交互

- Card 背面展示 mini Map，点击 `Expand Map` 进入完整 Map。
- 点击星云节点可以定位相关 Rewind 片段。
- 从 Rewind 选中一段时间，可以看到它改变了哪些 Living Model 节点。
- Ask、Remind、Agent Report 和 Evidence 都能定位到同一 Map 上下文。
- `Esc` 或 `Back to Card` 回到“Card + Quick Box”主页面，不创建额外导航层级。

---

## 9. Swipe Your Card

Swipe Your Card 是用户理解多 AI 接入的核心交互，不应被替换成普通“连接设置”。

### 9.1 用户价值

> 把同一张 Personal Card 刷给不同 AI，不需要重新介绍自己。

### 9.2 交互流程

1. 用户进入 Swipe Your Card。
2. 页面展示自己的 Card、读卡器和可用 AI。
3. 用户选择 Claude、GPT/Codex 或其他 Agent。
4. 页面说明将开放的能力和数据范围。
5. 用户确认后执行刷卡动画。
6. 后台创建 MCP grant / session。
7. AI 状态变为 `Wearing your card`。
8. AI 第一次真实读取后生成 Agent Report。

### 9.3 刷卡不是全权限

每个 AI 单独选择 scope：

- Identity read
- Recall/search
- Evidence read
- Recent context
- Reports

默认不开放：

- Correction write
- Delete
- Export
- 外部行动

### 9.4 连接状态

- Not installed
- Ready to swipe
- Waiting for approval
- Wearing your card
- Permission limited
- Disconnected
- Error

状态必须来自真实 MCP/客户端状态，不能只播放动画后假设连接成功。

### 9.5 Other Agent

支持其他 MCP 客户端：

- Cursor
- Gemini
- 自定义 MCP client

高级配置可显示本机连接方式，但普通用户默认只看产品语言。

---

## 10. MCP、Agent Report 与 Evidence

### 10.1 MCP 的定位

MCP 是 Persome MVP 的主输出层。

- 用户界面称为 Connected AI / Swipe Your Card。
- 高级设置中可以出现 MCP 名称。
- Skills 是否需要，等 MVP 使用数据验证后再决定。

### 10.2 MCP 调用要求

每次读取必须绑定：

- `modelId`
- `connectorId`
- `sessionId`
- `grantId`
- scope
- Evidence references

### 10.3 Agent Report

当 AI 真正使用 Card 完成一次工作后生成一页 Report。

Report 展示：

- 外部结果摘要
- AI 读取次数
- 使用了哪些模型理解
- 使用了哪些 Evidence
- 时间范围
- 回到当天
- 撤销该 AI 权限

没有真实调用时显示空态：

> Agent 第一次戴上你的卡并完成工作后，会在这里留下一页。

### 10.4 Evidence

Evidence 是所有模块的共同基础，不作为孤立技术页堆给用户。

入口：

- Ask 回答
- Remind
- Card 背面
- Map（Nebula / Living Model / Rewind）
- Agent Report

Evidence 状态：

- Available
- Permission required
- Source missing
- Revoked
- Expired
- Wrong model（必须拒绝）

---

## 11. Settings：信任控制

Settings 管两件事：

1. Persome 可以看什么。
2. Persome 和其他 AI 现在怎样使用这些内容。

### 11.1 数据来源

- 被观察的 App
- 明确排除的 App
- 暂停捕获
- 外部数据源
- 本地文件夹
- 权限状态
- 最近同步和错误

高敏感来源默认关闭或排除。

### 11.2 数据源优先级

| 优先级 | 数据源 |
| --- | --- |
| P0 | 本机活动、Jot、现有 Personal Model |
| P1 | Obsidian |
| P1 | Apple Notes |
| P2 | Calendar、Mail |
| P2 | Notion、本地文件 |

Obsidian MVP 要求：

- 用户选择 vault。
- 不扫描 vault 之外目录。
- 显示文件数、最后同步和排除规则。
- 断开时可以选择保留或删除派生记忆。

### 11.3 模型管理

- 浏览完整模型
- 纠正、删除、归档
- 按时间段删除
- 按来源删除
- 整份导出
- 清空模型（强确认）

### 11.4 Connected AI

- 每个 AI 的 scope
- 最近读取时间
- 最近 Evidence
- 撤销
- 重新授权
- token 轮换

Token/API key 永不完整回显，只允许复制新 token、轮换和撤销。

### 11.5 导出

- JSON 完整导出
- Markdown 可读导出
- 原始 Jot
- 指定时间范围

导出写到用户选择的位置，默认不上传。

---

## 12. 首次安装与初始化

### 12.1 安装

- 用户下载 `Persome.dmg`。
- 拖入 Applications 或双击安装。
- 打开的是原生 App，不是浏览器 HTML。

### 12.2 已有 Personal Model

- 自动检测并连接当前 macOS 账户自己的模型。
- 不重复安装或覆盖数据。
- 直接形成用户自己的 Card。

### 12.3 没有 Personal Model

- Persome 包含固定版本的 Runtime 安装能力。
- 引导用户完成必要权限。
- 新 Card 显示 Forming，不使用演示数据。

### 12.4 权限顺序

按价值逐步申请：

1. 创建本机身份
2. 选择观察范围
3. Accessibility（如必要）
4. Screen Recording（可跳过）
5. 麦克风（首次语音时再申请）
6. 外部数据源（用户主动连接时）

每一步解释：为什么需要、会读取什么、不授权会缺少什么。

---

## 13. 数据模型与真实性

### 13.1 五类内容

必须区分：

1. 用户原文
2. 记录事实
3. Personal Model 推断
4. 生成内容
5. 延续建议

### 13.2 数据流

```text
被动活动 / Jot / Correct / Obsidian / Notes
                       ↓
              原始来源 + 时间 + 权限收据
                       ↓
                去重、切段、结构化
                       ↓
        ┌──────────────────────────────┐
        │             MAP              │
        │ Memory + Claim + Evidence    │
        │ Living Model + Rewind        │
        └──────────────┬───────────────┘
                       ↓
          Card / Ask / Remind / Settings
                       ↓
          Swipe Your Card → MCP → Report
                       │
                       └──── 使用轨迹写回 Map
```

### 13.3 隔离

- 全部数据按 `modelId` 分区。
- Connector 按 `modelId + connectorId + sessionId + grantId` 分区。
- Evidence 必须能证明属于当前模型。
- 模型切换后旧 Report、Evidence、Map 上下文和 Connector 会话关闭。
- 生产不注册 Cecilia 或 Lin fixture。

### 13.4 本机边界

- 本机服务只监听 loopback。
- 不直接读写 Runtime 私有数据库。
- 使用固定版本的公开契约集成。
- Runtime 更新只能随 Persome 版本审核。

---

## 14. MVP 功能优先级

### P0：没有就不能内测

- Personal Card 正反面和真实个人初始化
- Card 下方新版 Persome Spotlight
- 显式 Jot / Ask 切换
- Jot 写入、收据、离线队列
- Ask + Evidence
- 纠正 + 修改前后对比
- 最近 30 天活动热力图
- Map：Nebula + Living Model + Rewind Day / Month 基础闭环
- Remind 三条真实线索
- Map 内 Evidence 双向定位
- Swipe Your Card：Claude + GPT/Codex
- MCP grant、scope、撤销
- Agent Report
- Settings：权限、排除、Connected AI
- 自有 Personal Model 自动连接
- 新用户模型初始化
- DMG、签名、公证
- Cecilia/Lin/新用户数据隔离验证

### P1：MVP 发布后第一轮

- Map / Rewind Week 模式
- Map / Rewind Year 模式
- 自动周总结
- Obsidian
- Apple Notes
- 本地语音转写
- Living Model 的删除/历史版本
- 完整导出

### P2：验证后再做

- Calendar、Mail、Notion、本地文件
- iPhone Jot / Ask
- Apple Watch 语音 Jot
- Skills 输出层
- 本地小模型成本优化

---

## 15. 核心验收标准

### A. 安装与身份

- 新用户打开后不会看到任何其他人的 Card。
- 已有 Personal Model 的用户直接连接自己的模型。
- 没有模型的用户可以从 Persome 内完成初始化。

### B. Card 与 Spotlight

- 启动 App、再次点击 Dock、快捷键和菜单栏左键都先显示独立 Spotlight，不提前创建 Dashboard。
- 独立 Spotlight 不带 Card；点击 `Open app` 后才展开 Dashboard。
- Dashboard 首页始终保留 Personal Card，并在其下复用同一套 Spotlight。
- Dashboard 是无边框 Persome 界面，不出现 macOS 红黄绿文档窗口控制点。
- Card 下方紧接新版 Persome Spotlight / Quick Box，不插入其他模块。
- Quick Box 空态完整显示 Ask instead、30 天热力图、Today / This week / This month / Map、Settings 和 Open app。
- Jot 开始输入后热力图与底部入口立即收起，只保留输入、语音和 Save。
- Ask 状态在同一个框内展开回答、Evidence 和 Back to jotting。
- Jot 和 Ask 可以显式切换；明显疑问句会可撤回地切到 Ask，但绝不自动提交。
- 全局快捷键在 Persome 非激活状态可用。

### C. Jot / Ask / Correct

- Jot 一次只保存一条并有收据。
- Ask 回答有 Evidence 或明确不足。
- 纠正显示修改前后并可 Undo。
- Jot 不会被当问题，Ask 不会被默默保存。

### D. Map / Remind

- 热力图深浅对应活动强度。
- 热力图点击后能在 Map / Rewind 中回到正确日期和活动片段。
- Living Model 节点会随新 Evidence 和用户纠正发生可解释变化。
- Rewind 可以显示一个时间段改变了哪些 Living Model 节点。
- Remind 每条有依据，未来线索不冒充安排。
- Evidence 可以定位 Map 节点和回到当天。
- 不存在独立的 Rewind、Memory Sky 或 My Model 一级导航。

### E. Swipe / MCP

- 刷卡成功必须来自真实客户端连接。
- 每个 AI 有独立 scope、session 和撤销状态。
- AI 使用记忆后生成真实 Report。
- 没有实际调用时不生成伪 Report。

### F. 隔离

同一套 UI 执行 Cecilia → Lin → Cecilia 后：

- Card 不串线
- Map（Nebula / Living Model / Rewind）不串线
- Connector 不串线
- Report 不串线
- Evidence 不串线

### G. 发布

- Apple Silicon 和 Intel 可安装。
- Developer ID 签名和 notarization 通过。
- DMG 安装后打开原生 `Persome.app`。
- GitHub Release 与官网按钮指向同一 immutable 资产。

---

## 16. 性能与交互标准

- 常驻 Compact Spotlight 可输入：P50 < 120ms，P95 < 250ms。
- Jot 本地确认：P95 < 300ms。
- Dashboard 首屏：P95 < 1.5s。
- 快捷键唤出不做位移动画。
- 高频切换 100–160ms。
- 模态/抽屉 180–240ms ease-out。
- 按钮按下有 0.97 轻微缩放反馈。
- 支持完整键盘、VoiceOver 和 Reduce Motion。

---

## 17. 成功指标

### 北极星指标

**每周被用户确认有价值的记忆时刻数。**

包括：

- Ask 得到有依据的回答
- 打开 Evidence
- 回到某一天
- 使用 Remind 继续上下文
- 确认或纠正模型
- AI 通过 MCP 使用 Card 完成工作

### 激活

- 安装完成率
- Personal Model 连接率
- 首次看到自己的 Card 的时间
- 首次非空热力图时间
- 首次 Jot 成功率
- 首次有 Evidence 的 Ask 完成率
- 首次 Swipe 成功率

### 信任

- Evidence 打开率
- 纠正成功率
- 撤销 AI 权限成功率
- 删除/导出成功率
- 数据串线事件：必须为 0

---

## 18. 当前实现到 MVP 的映射

| 当前已有 | MVP 处理 |
| --- | --- |
| Personal Card | 保留在完整 App 主页面顶部，继续逐像素复刻 |
| 原 Spotlight / Now | 替换为新版 Persome Spotlight + Remind |
| 自动识别搜索/问答 | 删除，改显式 Jot / Ask |
| Search / Ask API | 复用为 Ask / 回忆 |
| Correct API | 复用并增加前后 diff 与 Undo |
| Rewind | 合并进 Map 的时间模式，补 Week、Year 和活动强度定义 |
| Memory Sky | 合并进 Map 的 Nebula 模式，并保留 Card 背面的 mini Map |
| Identity | 合并进 Map 的 Living Model 动态人格展示 |
| Connector Swipe | 保留为核心 Swipe Your Card |
| MCP | 保留为 Swipe 背后的授权层 |
| Reports | 保留在 Connected AI 内 |
| Evidence | 保留为所有模块共用基础能力 |
| Setup | 改成 Persome 首次初始化与权限流程 |
| HTML V5 | 只作视觉基线，不作为正式架构 |

当前明确缺失：

- Jot 正式写入接口
- 显式 Jot / Ask 模式状态
- 系统全局快捷键
- 语音转写
- 完整 Settings 信任页
- Obsidian 接入
- Developer ID 签名与公证

---

## 19. 交付排期与分工

### M0：结构确认

- Cecilia：根据本文制作 Card + Persome Spotlight + Remind + Map 原型。
- Joe：审核首页结构、模块关系和关键流程。
- 结构确认后再做视觉细化，不先换掉 Card。

### M1：可交互 Preview

- 保留 Card。
- 替换 Card 下方 Spotlight。
- 加入 Jot / Ask 显式切换与可撤回的疑问句识别。
- 将现有 Ask、Correct、Rewind、Sky 和 Identity 接入统一 Map。
- Remind 收进 Map；Swipe Your Card 从完整 App 进入，不在 Card 与 Quick Box 下方堆模块。

### M2：MVP 功能闭环

- Jot 后端与收据
- 全局快捷键
- 活动热力图
- Swipe / MCP scope
- Agent Report
- Settings 权限与 Connected AI

### M3：发布闭环

- 双模型与新用户测试
- 权限测试
- DMG 安装/升级/卸载
- 签名、公证
- GitHub Release
- 官网下载更新

“次日完成”应定义为 M1 可交互 Preview，不代表 Obsidian、语音、签名和完整 MVP 全部在一天内完成。

---

## 20. 传播与成本

### 传播

- 先打磨“它真的记得、能回到证据、能刷给不同 AI”的体验。
- 官网保留 Card 作为核心视觉。
- Card 下方直接放可交互 Persome Spotlight。
- 演示一条 Jot 如何进入 Card、改变 Living Model、在 Map / Rewind 中被验证，并通过 MCP 被 AI 使用。
- 实时数字只能使用真实、可审计、隐私聚合的数据。

### 成本

当前 token 成本不是最高优先级，但 MVP 必须开始记录：

- 每用户/每日 token
- 每数据源处理成本
- 每次 Ask 成本与延迟
- 后台无效调用率

先做去重、批处理、缓存和无新增数据不调用；用户量上升后再用本地/开源模型处理分类和抽取。

---

## 21. 最终 MVP 判断

Persome MVP 不是“Card + 一堆页面”。

它是一条完整链路：

> Card 表示我是谁；Spotlight 让我留下和回忆；Remind 主动把值得想起的事带回来；Map 用星云图、Living Model 和 Rewind 展示它如何形成与变化；Swipe Your Card 让我把同一个我交给不同 AI；MCP 和 Evidence 保证这次读取真实、可控、不会串线。

如果没有 Card，产品失去核心识别。
如果 Card 下方不是低摩擦 Spotlight，产品没有日常入口。
如果没有 Map / Evidence，Personal Model 不可理解也不可信。
如果 Swipe 只是动画、MCP 没有真实授权，跨 AI 价值不成立。
如果 Jot 和 Ask 仍靠猜测，日常体验不成立。

以上五条是 Persome MVP 的发布底线。
