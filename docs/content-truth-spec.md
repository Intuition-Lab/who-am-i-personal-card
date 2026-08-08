# Who Am I 内容真实性规范与验收矩阵

状态：Beta 实施规范

基线：`codex/self-contained-package` @ `dcfedc1cb61ffa51d3080d4568ed26ce7bce9786`

适用范围：Card、Spotlight / Now、Rewind、Identity / Memory Sky、Connector、Report、Evidence、Search / Ask、Correct / Share

不在范围：视觉重设计、云端公开主页、未授权的数据外发

## 1. 产品内容承诺

Who Am I 展示的是当前 `activeModel` 在当前授权范围内的内容。产品必须让用户始终看得出一段内容属于以下哪一种：

1. 用户自己填写的内容；
2. 本机真实记录到的内容；
3. Personal Model 基于多条记录形成的推断；
4. 产品基于已有内容生成的总结或建议；
5. Runtime、Connector 或授权系统提供的权威状态。

产品不承诺“知道用户的一切”，也不把一次活动、关键词规则或固定模板写成用户的稳定身份。没有足够数据时，诚实的空状态属于产品内容，不得回退到 Cecilia、Lin、上一个本机 Profile 或任何演示文案。

同一套 UI 切换 `activeModel` 时，Card、Now、Rewind、Identity、Connector、Report、Evidence、Search、Ask 和 Correct 的内容必须整体切换。任何模型相关字段都必须携带或继承当前会话的 `modelId`，不得从请求体或 Query 临时覆盖。

## 2. 内容类型与统一元数据

### 2.1 五类内容

| 机器值 | 中文标签 | 定义 | 可否当作事实陈述 |
| --- | --- | --- | --- |
| `authoritative` | 系统状态 | Runtime、授权、Connector、安装或用户 Profile 存储直接给出的状态 | 只能陈述该系统状态，不能外推用户身份 |
| `observed` | 已记录 | 来自 Persome activity、memory 或 capture 的可追溯观察 | 只能陈述“记录显示”，不能把观察解释成人格 |
| `inferred` | 模型推断 | Root、Face、模式、画像等由多条记录归纳出的理解 | 必须显示置信度、时间范围和 Evidence；不得用绝对语气 |
| `generated` | 生成内容 | 信件、摘要、建议、回答等依据已有内容生成的表达 | 必须显示生成时间、方法和依据；不是新事实 |
| `user-entered` | 你填写的 | 姓名、handle、自我介绍、tagline、Correction 等由用户明确输入 | 可作为用户声明显示，但不得伪装成模型推断 |

“观察”不是“真相”，“推断”不是“定义”，“生成”不是“发生过”。中文 UI 至少要在详情或内容旁展示上述短标签。

### 2.2 所有可解释内容的最小元数据

下面字段可作为 Snapshot、Search、Ask、Evidence、Report 的向后兼容可选字段；缺少字段时 UI 必须降级为更保守的展示，而不是自行补全。

```json
{
  "contentType": "observed",
  "sourceRefs": ["local-model:memory:entry-id"],
  "timeRange": {
    "start": "2026-08-01T00:00:00+08:00",
    "end": "2026-08-08T23:59:59+08:00"
  },
  "generatedAt": "2026-08-09T09:30:00+08:00",
  "confidence": 0.78,
  "method": "persome.behavior_patterns",
  "availability": "available"
}
```

约束：

- `sourceRefs` 中的每个引用必须绑定当前 `modelId`。
- `timeRange` 表示内容依据覆盖的时间，不是 UI 打开的时间。
- `generatedAt` 表示推断或生成内容的计算时间；原始观察使用 `capturedAt` / `occurredAt`。
- `confidence` 只用于 `inferred`；没有可解释的计算方法时省略，不得写固定高分。
- `method` 使用稳定、可审计的来源名，例如 `persome.behavior_patterns`、`persome.search`、`connector.event-report`、`product.rule-summary.v1`。
- `availability` 取 `available`、`derived-only`、`source-unavailable`、`permission-denied`、`stale`。
- 对 `generated` 内容，Evidence 证明的是“生成所依据的材料”，不是证明生成文案本身为事实。

## 3. 逐页内容契约

### 3.1 Personal Card

用户承诺：这张卡代表当前 Personal Model 和用户主动声明的身份；它不是一张由演示数据填满的静态名片。

| 字段 / 区域 | 类型 | 数据源 | 时间与更新 | Evidence / 置信度 | 空状态与错误状态 |
| --- | --- | --- | --- | --- | --- |
| `model.id` | `authoritative` | Owner Profile / Provider；非 MCP | Profile 创建时生成，切换模型时更新 | 不展示为内容；用于隔离 | 无有效模型时不渲染 Card，进入设置态 |
| 姓名、handle | `user-entered`，旧模型迁移时为 `authoritative` | `OwnerProfileStore` 或受信任的既有 Profile；非 MCP | 用户保存或迁移时更新 | 标注“你填写的”；无需行为证据 | 未填写时要求创建；不得使用仓库默认人物 |
| member number、since year、glyph | `authoritative` | 产品 Profile 本机生成；非 MCP | Profile 创建后稳定 | 不得解释为人格 | 生成失败则阻止 Profile 提交 |
| tagline、自我介绍 | `user-entered` | Profile 编辑；非 MCP | 用户保存时更新 | 标注“你填写的” | 没有输入时显示编辑引导，不使用英文人格默认句 |
| memory count | `authoritative` | MCP `list_memories` | 每次 Snapshot 或手动刷新 | 只说明文件/条目数量，不说明模型质量 | Runtime 不可用时显示“暂时无法读取”，不得显示 0 |
| Root | `inferred` | MCP `behavior_patterns.root` | 模型构建完成或刷新后更新；必须带依据时间范围 | 必须至少一个可解析 Evidence，显示置信度或证据量 | 数据不足时：“还没有足够证据形成稳定理解。” |
| Faces | `inferred` | MCP `behavior_patterns.faces` | 模型刷新后更新 | 每个 Face 需独立 Evidence、观察数和置信度 | 无 Face 时显示形成中，不生成通用人格标签 |
| 更新时间 | `authoritative` | Runtime Snapshot / memory updated time | 与当前 Snapshot 一致 | 无 | 时间未知时写“更新时间未知”，不用 “as of now” |

当前基线中的 `Building a model of myself`、`A Personal Model that stays on this Mac.` 和 `A Personal Model already on this Mac.` 只是通用占位内容。正式策略是：

- 不把它们当作用户 tagline 或 Identity；
- 新 Profile 使用空值加编辑提示；
- 若为了 Schema 兼容必须保留非空字符串，Provider 可使用中性状态文案“Personal Model 正在形成”，同时以 `authoritative` / `method=product.setup-state` 标记，UI 不把它显示成用户自我介绍。

### 3.2 Spotlight / Now

用户承诺：Spotlight 帮用户回到最近真实发生、当前仍相关或基于近期活动值得继续的上下文；它不是日历，也不预测必然会发生的事情。

| 字段 / 区域 | 类型 | 数据源 | 时间与更新 | Evidence / 置信度 | 空状态与错误状态 |
| --- | --- | --- | --- | --- | --- |
| 过去 | `observed` | MCP `recent_activity`、`current_context` | 最近 14 天，打开/刷新时更新 | 必须引用活动或 memory receipt | 无记录时隐藏该项 |
| 现在 | `observed` 或 `inferred` | `current_context` 优先，近期 activity 次之 | 当前上下文或最近一次活动 | `observed` 需来源；跨活动归纳则标记 `inferred` | 当前不可读时：“还没有可继续的最近上下文。” |
| 延续建议 | `generated` | 基于近期活动的生成器；不是日历 | 展示依据时间范围与生成时间 | 必须至少一个 `sourceRef`；不显示虚假精确置信度 | 无可靠来源时整项隐藏 |
| Search 入口 | 操作，不是内容 | 当前会话 `activeModel` | 即时 | 结果规则见 3.8 | Runtime 不可用时保留重试入口 |

必须删除或降级当前 `futureEvents` 的固定 `09:30`、`14:00`、`18:30`。除非未来接入真实日历且用户授权，否则：

- UI 名称从“未来”降级为“延续建议”；
- 不显示具体日期和时间；
- 使用“基于最近 24 小时活动”之类的来源说明；
- 建议不得写成承诺或已安排任务。

推荐文案：

- 标题：`延续建议`
- 来源：`基于最近 24 小时已记录活动`
- 空状态：`最近的记录还不足以给出有依据的延续建议。`

### 3.3 Rewind

用户承诺：Rewind 只回放实际记录到的活动和可追溯的模型理解；产品可以生成摘要，但不能补写不存在的事件、精确时长或生活判断。

| 字段 / 区域 | 类型 | 数据源 | 时间与更新 | Evidence / 置信度 | 空状态与错误状态 |
| --- | --- | --- | --- | --- | --- |
| 日期列表 | `authoritative` | `recent_activity` 中真实日期 | 默认最近 14 天有记录的日期 | 日期本身无需置信度 | 没有日期：“这段时间还没有可回放的记录。” |
| 事件时间、应用、标题 | `observed` | `recent_activity`、`current_context`，未来可用 capture resolver | 保留原始 occurred time | 每个事件一个 model-bound reference | 时间缺失时显示“时间未知”，不得推算 |
| 使用时长、切换次数 | `observed` 或 `generated` | 只有原始区间完整时才可计算 | 与所选日绑定 | 方法必须可解释；缺段时标注“不完整记录” | 不完整时不显示精确总时长 |
| 日叙事 / portrait | `generated` | 当日事件集合 | 生成时更新，保留所依据日期 | 至少两个来源或明确“仅基于一条记录” | 数据不足时使用中性摘要，不评价用户 |
| Self Reading、reading title、tension | `inferred` | 多条当日或跨日证据 | 显示依据范围 | 必须有 Evidence 和保守语气 | 只有关键词规则时不得展示为人格理解 |
| Daily Letter | `generated` | 当日已记录事件 | 每日最多一个版本，显示生成时间 | 引用当日 Evidence；标签“生成内容” | 当日数据不足时不生成长信，只保留空白说明 |
| Coast frame / 小电视 | `observed` | 经授权的 Coast frame resolver | 与原始 capture 时间一致 | 必须通过当前 viewer + model allowlist | 源删除时显示“原始画面已不可用”，保留派生摘要标签 |

当前 `buildLivePayload` 中通过关键词选择“边界的编辑者”“根因的追问者”“关系里的校准者”等标题，以及“生活被挤薄”等判断，属于规则推断。处理决定：

- Beta 不删除这一视觉区域，但内容必须标记“模型推断”；
- 只有 receipt、时间范围和至少两条独立观察时才展示；
- 关键词规则本身不得产生高置信人格判断；
- 没有足够证据时使用：`今天的记录还不足以形成自我解读。`

### 3.4 Identity / Memory Sky

用户承诺：Identity 展示用户主动声明的身份，以及 Personal Model 基于一段时间形成、可以回溯和纠正的理解。Memory Sky 展示模型关系，不以节点数量制造“了解很多”的错觉。

| 字段 / 区域 | 类型 | 数据源 | 时间与更新 | Evidence / 置信度 | 空状态与错误状态 |
| --- | --- | --- | --- | --- | --- |
| description | `user-entered` | Owner Profile | 用户保存时更新 | 标注“你填写的” | 空时邀请填写一句自我介绍 |
| daily line | `generated` 或 `inferred` | 当日 Rewind 内容 | 依据当日，显示更新时间 | 需当日 Evidence；推断必须有置信度 | 无当日数据：“今天还没有足够记录。” |
| weekly letter | `generated` | 至少 3 个有记录日的 7 日窗口 | 每周或手动刷新；显示覆盖日期 | 每段至少一个来源，整体标记“生成内容” | 不足 3 个活跃日时不展示周信 |
| Root / Faces | `inferred` | MCP `behavior_patterns` | 与 Card 同一 Snapshot | 同 Card，不另造一套解释 | 无数据时显示形成中 |
| Memory Sky 节点和边 | `inferred` | Root / Faces 及其关系 | 模型刷新时更新 | 节点可点开 Evidence；孤立节点要说明证据不足 | 无 Faces 时显示单一 Card 核心和形成提示 |

当前实现把最新一天 `dailyLetter` 的前四行放进 `weeklyLetter`，不符合字段名称。处理决定：

- 在真正 7 日聚合完成前隐藏 Weekly Letter；
- 不得把单日模板改标题后继续冒充周总结；
- 若保留该内容，应回到 Rewind 并命名为 `Daily Letter · 生成内容`。

### 3.5 Connector

用户承诺：Connector 表示某个真实 Agent 客户端是否安装、是否建立了当前模型授权、是否实际读取过内容。安装、连接和使用是三个不同状态。

| 字段 / 区域 | 类型 | 数据源 | 时间与更新 | Evidence / 置信度 | 空状态与错误状态 |
| --- | --- | --- | --- | --- | --- |
| installed / missing | `authoritative` | 本机 target capability probe；非内容 MCP | 打开页或刷新时检测 | 无内容 Evidence | `missing`：`未检测到此 Agent` |
| available | `authoritative` | 已安装但未建立当前模型会话 | 会话创建前 | 无 | `可连接到当前 Personal Model` |
| connected | `authoritative` | `ConnectorSessionService` + 可观察 target | 会话有效期内 | 显示授权范围和过期时间 | 连接失败不得保留绿色 Connected |
| last used | `observed` | 同 model / connector / session 的真实 MCP event | 真实使用事件发生时 | 绑定 connector event receipt | 从未使用时：`已连接，尚未被 Agent 使用` |
| Swipe / Connect All | 用户动作 | 当前可用 Connector | 用户触发时 | 操作结果逐个显示 | 部分失败时不得显示“Agents 已连接” |

连接按钮只证明授权会话建立，不证明 Agent 已经理解用户，也不自动生成 Report。

### 3.6 Agent Report

用户承诺：Report 是真实 Agent 在当前 Connector Session 中使用 Personal Model 后留下的结果摘要。它不是连接流水账、调试日志或虚构的工作报告。

| 字段 / 区域 | 类型 | 数据源 | 时间与更新 | Evidence / 置信度 | 空状态与错误状态 |
| --- | --- | --- | --- | --- | --- |
| title、connector、updatedAt | `authoritative` | Connector Session + 真实事件 | 事件写入时 | session / grant / model 必须一致 | 无实质事件不创建 Report |
| summary / result | `generated` 或 `observed` | Agent 实际结果和事件语义 | 对本次 session 聚合 | 必须引用真实事件；不得只写事件数量 | 只有 connect 事件：`已连接，尚未产生报告` |
| context types read | `observed` | MCP proxy 的真实 tool event | 每次工具调用 | 显示类型，不默认显示私密正文 | 缺日志时标记未知，不猜测 |
| sections | `generated` | 同 session 事件和 Agent 结果 | Report 生成时 | 每节保留 `sourceRefs` | 生成失败不输出空壳 Report |
| evidence index | `authoritative` | 同 model 的 Evidence refs | Report 生成时 | 每条引用必须能解析或标记 unavailable | 跨模型引用必须 403 |

最低“实质报告”门槛：至少一个真实 Agent 使用事件，且包含 tool、occurredAt、result / summary 或使用的上下文类型。单独的 `connector/connected` 事件不满足门槛。

### 3.7 Evidence

用户承诺：Evidence 解释“这段内容依据什么”，并明确区分直接记录、间接推断和已经丢失的原始来源。Evidence 不使用绿色印章制造未经验证的确定性。

| 字段 / 区域 | 类型 | 数据源 | 时间与更新 | Evidence / 置信度 | 空状态与错误状态 |
| --- | --- | --- | --- | --- | --- |
| reference、modelId | `authoritative` | Provider / EvidenceService | 请求时绑定当前会话 | 前缀必须是当前 `modelId` | 不匹配直接 403，不调用下游 |
| source type | `authoritative` | receipt resolver | 解析时 | `memory`、`activity`、`capture`、`connector-event`、`derived` | 无法判断时为 `derived-only` |
| original time / app / title | `observed` | MCP `resolve_evidence`、`read_receipt` 或受控 capture resolver | 原始记录时间 | 不使用推算时间 | 源缺失时保留“原始来源已不可用” |
| supported claim | `inferred` | 由引用该 Evidence 的内容给出 | 与推断内容绑定 | 标记 direct / indirect | 不得让一个 Evidence 自动支持所有结论 |
| readable content | `observed` 或 `generated` | 原记录或安全摘要 | 解析时 | 明确是否摘要 | 权限不足不下发正文 |

文案规则：

- 有直接来源：`已记录 · 来源可追溯`
- 只有派生内容：`模型推断 · 原始来源未附带`
- 来源曾存在但已删除：`原始来源已不可用，以下仅保留派生摘要`
- 权限不足：`当前授权不能查看这条来源`

当前无 `capturedAt` 时显示“由 Personal Model 验证”会误导，必须改为上述可用性状态。

### 3.8 Search / Ask

用户承诺：Search 在当前 Personal Model 的完整记忆范围内查找相关内容；Ask 只依据当前模型可访问的内容回答，证据不足时明确拒答。

#### Search

| 项目 | 规范 |
| --- | --- |
| 数据源 | 本机 Owner 优先调用 MCP `search`；Fixture / Remote Provider 通过统一 contract |
| 内容类型 | 每条结果保留自身的 `observed` / `inferred` / `generated`，不能统一标成事实 |
| 时间范围 | 请求可带 `since` / `until`；结果展示发生时间或依据时间 |
| Evidence | 每条结果至少一个 model-bound reference；没有引用时标记 `source-unavailable` |
| 排序 | 相关度为主，兼顾新鲜度；去重后返回；不得只扫描当前精简 Snapshot |
| 无结果 | `没有找到有依据的相关记忆。可以换一种说法，或扩大时间范围。` |
| 错误 | `Personal Model 暂时无法搜索。你的现有内容没有被替换。` |

#### Ask

| 项目 | 规范 |
| --- | --- |
| 数据源 | MCP `search` / owner ask 能力；回答前先取得可展示 Evidence |
| 内容类型 | 回答正文为 `generated`；引用内容保留原类型 |
| 回答门槛 | 至少一条与问题直接相关的可解析 Evidence；事实性回答不得仅凭 Profile 占位文案 |
| 不足证据 | `我还没有找到足够依据来回答这个问题。你可以换一种问法，或先让 Personal Model 记录更多内容。` |
| 表达 | 使用“记录显示”“模型目前推断”“基于这些来源”，不用“你就是”“你一定会” |
| 更新 | 显示生成时间；Correct 后下一次 Ask 必须读取新结果 |

历史基线曾只对 Snapshot 做字面包含匹配，Ask 只拼接前两条结果。当前基线已接入本机语义 Search、带 Evidence 的 Ask、证据不足拒答和保守降级；正式内容质量仍以本节和 CQ-001 至 CQ-009 为准。

### 3.9 Correct / Share

#### Correct

用户承诺：Correction 是用户明确写入当前 Personal Model 的纠正；只有写入成功并重新读取验证后，UI 才显示已完成。

| 项目 | 规范 |
| --- | --- |
| 输入类型 | `user-entered` |
| 写入源 | MCP `correct_memory` |
| 绑定 | 当前 `modelId`、当前 owner scope；Authorized / Public 默认不可写 |
| 成功 | `已写入并刷新 Personal Model。`，返回 receipt / affected 状态 |
| 已写入待传播 | `更正已保存，模型理解将在重新构建后更新。` |
| 失败 | `没有写入。请检查 Personal Model 后重试。`；不得先显示成功 |
| 验收 | Search / Ask 不再优先返回被纠正的旧结论；相关 Card / Identity 内容刷新或明确 pending |

#### Share

Beta 只支持本机复制，不支持公共发布。按钮必须叫 `复制 Card`，不能叫 `Share` 或暗示已经生成公开链接。

复制内容必须包含：姓名、handle、用户填写的 tagline（有才显示）、内容更新时间，以及“来自本机 Personal Model”的说明。默认不复制 Root、Faces、Rewind、Evidence、Report 或本机路径。`local/<handle>` 不是公开 URL，不得作为可访问链接分享。

推荐成功文案：`已复制 Card 摘要。没有复制私人记忆或 Evidence。`

## 4. 新模型分阶段内容策略

阶段由“时间 + 可用证据量”共同决定，不能只因为安装满了七天就生成周结论。

### 4.1 阶段 0：0 条记忆

进入条件：Profile 已创建，但 `memoryCount=0`，或 Runtime 已初始化但尚无可读取 activity。

显示：

- 用户填写的姓名、handle、tagline / description；
- Runtime、权限和 Connector 状态；
- 明确的“正在形成”状态与下一步；
- Search / Ask 仍可打开，但诚实返回无依据；
- Connector 可以连接，Report 不生成。

不显示：Root、Faces、Weekly Letter、未来建议、人格标题、精确统计、演示内容。

核心文案：`你的 Card 已创建。Personal Model 还在形成，先从今天开始记录。`

### 4.2 阶段 1：约 1 天

建议门槛：至少 3 个有效活动段或 3 条可解析 memory / activity Evidence。

显示：

- 当天真实事件、应用和可回溯来源；
- 基于当天内容的中性 Daily Summary；
- 有来源的 Search；
- Daily Letter 可选，但必须标记“生成内容”。

不显示：稳定 Root、强人格 Face、Weekly Letter、固定未来时间、跨日生活结论。

核心文案：`Personal Model 已记录今天的一些片段，还不足以形成稳定判断。`

### 4.3 阶段 2：约 7 天

建议门槛：最近 7 天至少 3 个活跃日、10 条可解析 Evidence，且至少 2 类来源或应用。

显示：

- 7 日 Rewind；
- 初步 Face，明确“模型推断”和置信度；
- 真实 7 日范围的 Weekly Letter；
- 有依据的延续建议；
- Correct 后的更新状态。

Root 仍可为空；一周数据不应自动成为“你是谁”的最终答案。

核心文案：`模型开始看到一些重复出现的模式。它们是当前推断，可以查看依据并随时纠正。`

### 4.4 阶段 3：约 30 天

建议门槛：最近 30 天至少 10 个活跃日、30 条可解析 Evidence，多日期、多来源，且行为模式达到 Runtime 的最低置信标准。

显示：

- 有充分 Evidence 的 Root 和 Faces；
- 一个月内变化趋势，而不是只显示静态人格；
- 可比较的周总结和 Correct 传播历史；
- Agent 实际使用后生成的 Reports；
- 更丰富的 Memory Sky，但每个节点仍可解释。

核心文案：`这是 Personal Model 基于最近 30 天形成的当前理解，不是永久定义。`

## 5. 中文文案与语气终稿

### 5.1 语气原则

1. 克制：不说“最懂你”“真实的你”“你一定会”。
2. 具体：说明数据来自哪里、覆盖多久、何时更新。
3. 可纠正：推断旁边始终有 Evidence 或 Correct 入口。
4. 不拟人化权威：可以说“模型目前推断”，不说“我确认你就是”。
5. 不把缺失写成失败：数据少时说明形成阶段和下一步。
6. 不把系统状态写成人格：Connected、memory count、安装时间不等于了解程度。
7. 中英文一致：操作按钮优先中文；`Evidence`、`Personal Model` 可作为产品术语保留。

### 5.2 状态文案

| 场景 | 终稿 |
| --- | --- |
| 模型形成中 | `Personal Model 正在形成。记录越完整，理解才会逐渐变得具体。` |
| 0 记忆 | `还没有可展示的记忆。完成权限设置并使用电脑一段时间后再回来。` |
| Root 空 | `还没有足够证据形成稳定理解。` |
| Faces 空 | `模型还没有观察到重复出现、可以验证的模式。` |
| Now 空 | `还没有可继续的最近上下文。` |
| Rewind 空 | `这段时间还没有可回放的记录。` |
| Identity 空 | `模型还不了解到足以描述你。你可以先填写一句自我介绍。` |
| Connector missing | `未检测到此 Agent。安装后可以连接当前 Personal Model。` |
| Connector connected unused | `已连接，尚未被 Agent 使用。` |
| Report 空 | `Agent 真正使用这张 Card 后，报告才会出现在这里。` |
| Evidence 直接来源 | `已记录 · 来源可追溯` |
| Evidence 派生 | `模型推断 · 原始来源未附带` |
| Evidence 丢失 | `原始来源已不可用，以下仅保留派生摘要。` |
| Search 无结果 | `没有找到有依据的相关记忆。可以换一种说法，或扩大时间范围。` |
| Ask 拒答 | `我还没有找到足够依据来回答这个问题。` |
| Correct 成功 | `已写入并刷新 Personal Model。` |
| Correct 待传播 | `更正已保存，模型理解将在重新构建后更新。` |
| Copy 成功 | `已复制 Card 摘要。没有复制私人记忆或 Evidence。` |
| Runtime 不可用 | `Personal Model 暂时无法连接。你的已有 Card 和记忆没有被替换。` |
| 权限缺失 | `还需要本机权限才能继续记录。打开设置后可以回来重试。` |

## 6. 内容质量验收矩阵

所有场景使用合成 fixture，不使用真实个人数据。每个场景至少覆盖 Cecilia → Lin → Cecilia 或两个独立 owner 环境中的一种隔离检查。

| ID | 能力 | 输入 / 前置 | 必须观察到 | 失败条件 | 主要负责分支 |
| --- | --- | --- | --- | --- | --- |
| CQ-001 | Search 改写召回 | memory 写“周五和投资人讨论定价”，搜索“融资价格谈判” | MCP 语义 Search 返回该记忆和 Evidence | 只有原词完全相同时才命中 | `codex/content-backend` |
| CQ-002 | Search 去重 | 多个层级返回同一 receipt | 结果只出现一次，保留最佳摘要和来源 | 同一来源重复占满结果 | `codex/content-backend` |
| CQ-003 | Search 时间 | 相同主题分布在两个时间段 | 时间过滤和结果时间正确 | 返回窗口外结果却不说明 | `codex/content-backend` |
| CQ-004 | Search 空状态 | 无相关内容 | 返回空数组和明确 no-result 状态 | 回退 Fixture、Profile 占位或编造结果 | `codex/content-backend` / `codex/native-ui-truth` |
| CQ-005 | Ask 有依据 | 问题有两条相关记忆 | 回答为 generated，列出可点 Evidence | 只返回无引用结论 | `codex/content-backend` |
| CQ-006 | Ask 拒答 | 问题无相关记忆 | 使用拒答终稿，不猜测 | 从 tagline 或无关 Face 外推 | `codex/content-backend` / `codex/native-ui-truth` |
| CQ-007 | Ask 冲突 | 两条来源相互矛盾 | 回答说明冲突并展示双方来源 | 任取一条当成确定事实 | `codex/content-backend` |
| CQ-008 | Correct 写入 | 对旧结论提交 Correction | 返回 receipt / affected / pending 或 verified | 失败时 UI 显示成功 | `codex/evidence-corrections` |
| CQ-009 | Correct 传播 | Correction 后重复 Search / Ask | 新结果优先，旧结论消失或标记已纠正 | 缓存继续返回旧答案且无提示 | `codex/content-backend` + `codex/evidence-corrections` |
| CQ-010 | Rewind 时间真实性 | 活动缺少结束时间 | 不显示推算的精确总时长 | 用默认 1 分钟累加后当作精确统计 | 未完全覆盖 |
| CQ-011 | Rewind 不编造 | 只有一条 Terminal 活动 | 只展示该记录和中性摘要 | 生成生活、关系或休息结论 | `codex/beta-e2e` + `codex/native-ui-truth` |
| CQ-012 | Future 降级 | 无日历授权 | 不显示 09:30 / 14:00 / 18:30；只显示带依据的延续建议或隐藏 | 把模板写成明日日程 | `codex/native-ui-truth`，后端清理未完全覆盖 |
| CQ-013 | Daily / Weekly 边界 | 只有一个活跃日 | 可有标记的 Daily，不出现 Weekly | 单日信件冒充周信 | `codex/native-ui-truth`，真实聚合未覆盖 |
| CQ-014 | Report 实质门槛 | 只有 connected 事件 | Report 列表为空或显示尚未产生 | 生成“1 connector event”报告 | `codex/beta-e2e` |
| CQ-015 | Report 真事件 | Agent 读取 context 并返回结果 | Report 说明做了什么、读了什么类型、结果和 Evidence | 展示原始调用流水账或无结果模板 | `codex/beta-e2e` |
| CQ-016 | Evidence 直接来源 | reference 可由 Runtime resolver 解析 | 显示来源类型、时间、应用、direct 状态 | 只回显 Snapshot 内容却盖“已验证”章 | `codex/evidence-corrections` |
| CQ-017 | Evidence 断链 | 原始 capture 已删除 | 标记 source-unavailable，仍可显示派生摘要 | 伪造 capturedAt 或声称已验证 | `codex/evidence-corrections` / `codex/native-ui-truth` |
| CQ-018 | Evidence 权限 | Viewer 无 evidence scope | 服务端 403，正文不下发 | 只在 UI 隐藏 | 现有 auth + `codex/evidence-corrections` |
| CQ-019 | 跨模型 Search | Cecilia 会话请求体传 Lin ID | 仍只查询 Cecilia 或拒绝覆盖 | 返回 Lin 内容 | 现有 isolation + `codex/beta-e2e` |
| CQ-020 | 跨模型 Evidence | Lin reference 在 Cecilia 会话解析 | 先于下游调用返回 403 | resolver 被调用或返回 Lin 内容 | 现有 isolation + `codex/evidence-corrections` |
| CQ-021 | 切换失效 | Cecilia Report / Evidence 打开时切 Lin | 旧弹层、请求、Connector Session 失效 | Lin UI 仍见 Cecilia receipt | 现有 store / auth + `codex/beta-e2e` |
| CQ-022 | 新用户 0 记忆 | fresh HOME，无 fixture | 只显示创建/形成状态 | 出现 Cecilia、Lin、Root、Face 或模板未来 | 现有 no-demo + `codex/native-ui-truth` |
| CQ-023 | Copy 最小化 | 用户点击复制 Card | 不包含私人 Rewind、Evidence、路径 | 复制本机 URL 或私人内容 | `codex/native-ui-truth`，隐私断言未覆盖 |
| CQ-024 | 错误保留 | Runtime / Search 暂时失败 | 旧 Snapshot 保留并可重试 | 清空 Card 或回退演示数据 | 现有 session + `codex/native-ui-truth` |

发布门槛：CQ-001 至 CQ-024 全部有自动化或可复核的人工证据；任何跨模型泄漏、无依据事实性回答、虚假 Evidence、错误成功态均为 P0。

## 7. 当前实现与开放交付映射

### 7.1 已集成到产品基线的内容能力

| 原交付分支 | 当前基线状态 | 已落地接口 | 后续边界 |
| --- | --- | --- | --- |
| `codex/content-backend` | 已集成 | 本机完整语义 Search、带 Evidence 的 Ask、拒答、内容元数据和 Correct 后刷新 | 继续补真实用户质量评估，不再维护重复 PR #2 |
| `codex/evidence-corrections` | 已集成 | Evidence 来源分型、resolver、断链状态、跨模型约束和 Correct 传播状态 | 不再维护重复 PR #6 |
| `codex/native-ui-truth` | 已集成 | 可选字段兼容解码、搜索/问答状态、内容类型标签、未来降级、诚实 Report / Copy 和无障碍状态 | 不再维护重复 PR #4 |
| `codex/beta-e2e` | 已集成 | deterministic 内容评估、真实 Connector 事件、Report 实质门槛、跨模型和 release gate | CQ-010、CQ-012、CQ-013、CQ-023 仍需专门验收 |

### 7.2 仍开放的并行交付

`codex/native-app-lifecycle`（PR #5）、`codex/apple-signing-notarization`（PR #7）和 `codex/p0-real-runtime-closure`（PR #8）都以同一产品基线为父分支。它们分别处理应用生命周期、Developer ID / 公证，以及真实 Runtime P0 闭环与搜索延迟，不改变本规范的内容类型定义。

最终集成测试仍需覆盖：升级不恢复旧用户 Card、重装不引入演示 Profile、签名后的 App 只连接当前 macOS owner 数据，以及产品锁定的 Runtime 身份与已通过的上游提交完全一致。

### 7.3 集成顺序

1. 先合并本规范 PR #3；它只改变文档。
2. PR #5、#7、#8 按各自 CI 与审查完成情况依次合入 `codex/self-contained-package`，每次合入后都重新同步尚未合并的兄弟分支。
3. 三个交付合齐后运行 CQ-001 至 CQ-024、双 owner、Cecilia → Lin → Cecilia、production no-demo、签名应用和原生截图验收。
4. 所有发布动作继续受 `RELEASE_STATUS=HOLD` 约束；代码合并不自动授权发布。

## 8. P0 / P1 / P2 Backlog

### P0 — 发给首批用户前必须完成

- [x] 语义 Search、Ask Evidence 和拒答闭环；当前基线已有自动化回归。
- [x] Evidence 直接/派生/断链分型和 Correct 传播状态；当前基线已有自动化回归。
- [ ] 固定未来时间删除、Weekly Letter 单日冒充修复、Share 改为 Copy；`codex/native-ui-truth` 部分覆盖，后端模板清理仍需集成时认领。
- [x] 只有真实 Agent 事件才能生成 Report；当前基线已有 Connector E2E 回归。
- [ ] 新用户 0 记忆和 Runtime 错误不显示任何 Demo / 缓存他人内容；已有测试，需在最终 DMG 复验。
- [ ] CQ-001 至 CQ-024 形成最终测试矩阵；`codex/beta-e2e` 部分覆盖，CQ-010、CQ-012、CQ-013、CQ-023 仍需补测。
- [x] 原生页面展示统一的内容类型、时间范围、来源和可用性；当前基线已有兼容解码和状态回归。
- [x] 四个内容交付的 contract 冲突已在产品基线解决，并通过本地产品与 foundation 全量回归；最终 DMG / 发布验收仍由 release gate 单独跟踪。

### P1 — 20 人扩量前完成

- [ ] Profile 编辑、重置本机 Card identity，并说明不会新建另一份 Runtime 数据；当前无人完整覆盖。
- [ ] 真正的 7 日 Weekly Letter 聚合与生成版本管理；当前无人覆盖。
- [ ] Rewind 对缺失时间段的“不完整记录”计算规则；当前无人覆盖。
- [ ] Root / Faces 的证据门槛和阶段 gating 由 Runtime 输出或产品 adapter 统一执行；当前只定义未实现。
- [ ] Copy Card 的隐私单元测试和导出预览；UI 分支部分覆盖，测试无人完整覆盖。
- [ ] Content quality 人工审核表：每位试用用户可标记准确、不准确、无法判断；当前无人覆盖。

### P2 — 100 人之后

- [ ] 经授权的公开 Card 页面和可撤销分享链接；Beta 不承诺。
- [ ] 更多 Connector 的真实 capability probe 和 Report 语义；当前只有 Codex / Claude Code 主路径。
- [ ] 跨设备同步、云账户和多人共用一个 macOS 账户；当前明确排除。
- [ ] Identity 变化趋势、Correction 历史和解释版本对比。
- [ ] 用户可配置生成频率、语气和不希望模型推断的主题。

## 9. 产品审核清单

产品审核时逐项回答“是”才可通过：

- [ ] 用户能一眼区分“你填写的 / 已记录 / 模型推断 / 生成内容 / 系统状态”。
- [ ] 每个推断都能看到覆盖时间、更新时间和 Evidence。
- [ ] 每个生成内容都能看到来源，而不会被当成新事实。
- [ ] 没有日历来源时不出现精确未来时间。
- [ ] 单日内容不叫 Weekly Letter。
- [ ] 连接成功不等于 Agent 已使用，连接事件不生成 Report。
- [ ] Evidence 断链时明确显示 unavailable，不使用“已验证”印章。
- [ ] Search 支持改写召回，Ask 无依据时拒答。
- [ ] Correct 失败不显示成功，成功后 Search / Ask / Card 状态可解释。
- [ ] Share 在 Beta 中只复制最小 Card 摘要，不产生假公开链接。
- [ ] 0 记忆、1 天、7 天、30 天四阶段都诚实且仍有下一步可做。
- [ ] 任意模型切换或权限裁剪后，所有内容和引用仍属于同一 `activeModel`。
