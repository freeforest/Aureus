# Stage12 Hardening Plan

## W1实际进度：2026-09-11有限人工基线

本次执行 Prompt 12-NATIVE-MANUAL-BASELINE-01，证据为 [W1 ExecutionReport](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-NATIVE-MANUAL-BASELINE-01-Iaul8w/ExecutionReport.md)。Stage11 PASS保持；Stage12 **PARTIAL — Awaiting Reviewer Gate**，Stages13–14 NO-GO。下文入场规划中的“本轮NOT RUN”保留为入场文档轮当时记录；本节单列W1实际进度，不改写历史。

运行前123项匹配E-ENTRY，规范化SHA256 `ee6126c5170a9fe724dff1bdf6a63d7cacdf7c2487812b0fd61fa85224c1f5f6`。E-LC源App及本轮完整副本各179项manifest匹配，strict codesign分别exit0、arm64、local ad-hoc。两次预定LaunchServices启动均open exit0，实际PID46727、47515；确切副本路径及temporary/UI-testing、demo、audit和en/US参数均核验。用户分别正常Quit，两PID已不存在；App自身数字退出码NOT VERIFIED。无第三次启动、构建、Runner、Unit/XCUI、Release或性能运行。

| 检查范围 | 本轮实际证据 | 未闭合部分 |
|---|---|---|
| 初始Settings字段、VoiceOver、Tab/Shift-Tab | 用户对首张卡反馈“没问题”，USER REPORTED；后续完整清单反馈“均无问题”“均已完成核验” | 没有逐字段朗读转录、完整keyboard-only动作轨迹或独立人工质量复核；不能扩大为八类人工QA完成 |
| Wealth偏好/草稿、Cache Apply/取消/Reset与永久数据可见隔离 | 第一会话用户整体报告无问题 | 具体净值、Goals名称、非默认偏好值未分别留档；不等同Store哈希或全部清理路径验证 |
| CSV与内外Backup/Restore、取消与确认 | 用户报告均完成；后明确自报手动删除CSV/备份 | 指定CSV缺失、Backups目录为空已核验；未取得导出哈希或恢复前哈希，原件保留及前后字节不变性NOT VERIFIED。不能认定App导出失败，也不能把缺失文件当已验证产物 |
| Markets图表、Accessible Data、当前显示可读性 | 用户对完整操作清单整体反馈无问题 | 主题/窗口/显示条件及逐交互结果未单列；不是帧率、首帧、其他主题或真实offline证据 |
| 第二temporary graph | 后续用户明确授权Agent有限UI检查；仅观察到Synthetic Demo与初始Dashboard数据 | 偏好默认、缓存重新seed、CSV/probe无残留及backup inventory未完成检查。原会话非默认偏好未具体记录；新图完整隔离结论NOT VERIFIED |

流程与工具偏差：用户改为要求完整清单后，逐卡记录改为整体反馈；外部备份导出后的暂停点未取得实际前置哈希，用户清理文件导致原始产物缺失。第二图新增有限UI授权不替代人工QA；连接工具自动输出完整Dashboard AX文本，超出“不采集完整AX树”的约定，Executor立即停止，没有进一步导航、截图或数据操作。该偏差保留，不能追溯消除；没有另存完整AX树至工程目录。

W1仍未完整闭合。用户反馈与工具观察分列，未发现可据现有证据确认的产品缺陷，但证据不足不能写成全部PASS。security-scope释放计数、受控offline/timeout/missing/stale、六项性能、OSLog系统交付/留存/人工脱敏、其他显示条件、完整第二图检查与必要人工细项继续开放。旧Unit597、Release31/28ms、BFT、原20项UI及D-03有限证据均为inherited / NOT RUN in W1；不合并历史FullUI Failed与独立1/1。本轮仅更新本计划，其他122项冻结，不进入W2–W5。

## W1限定补证：2026-09-11导出字节身份与新图对照

本次 Prompt 12-W1-ARTIFACT-AND-GRAPH-CLOSURE-01 的新证据见 [ExecutionReport](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-W1-ARTIFACT-AND-GRAPH-CLOSURE-01-dxzPBT/ExecutionReport.md)。Stage11 PASS保持；W1及Stage12仍 **PARTIAL — Awaiting Reviewer Gate**，Stages13–14 NO-GO。Reviewer有限接受上轮第一会话USER REPORTED反馈；旧CSV/备份缺失、用户自报删除、旧第二图未完成和旧完整AX输出偏差全部保留。本次产物不恢复旧证据，也不追溯填补旧哈希。

本轮123项起点全部匹配E-W1，规范化SHA256 `f0fdcf1244c67c781d6bb4753b1559646264df753f1c0559b5a5595146db996b`。同一已接受local ad-hoc App源/副本完整179项manifest及strict签名通过；两次启动准确副本，temporary/UI-testing＋demo＋audit及en/US参数核验。open均exit0，App PID49377与51041分别经用户正常Quit和准确PID不存在确认结束；App数字退出码NOT VERIFIED。运行期间123项不变，结束后仅追加本节。

| 本轮限定检查 | 新证据与结果 | 边界 |
|---|---|---|
| CSV原件保留 | 新图导入指定synthetic输入后导出5971 bytes，SHA256 `39b910f019fe3dfde50a505f70d47ea366b1073f97ba47b7703f37440df8bcd4`；恢复前后及最终一致 | 仅准确自有输出的普通文件、size与Hash；不代表旧轮文件曾存在 |
| 外部备份字节身份 | 唯一generation含aureus.sqlite 417792 bytes与manifest.json 213 bytes；两个硬暂停点保存前后SHA256，最终复核均一致 | 无数据库解码、运行Store读取或独立security-scope计数 |
| 有限外部恢复 | 用户提供图中有恢复Completed，随后原两个Goals仍在、Export Probe不在列表、有效备份2；原始文件Hash不变 | Cancel后Probe保持未明确归属，仍NOT VERIFIED，未重做恢复 |
| 第一图明确对照 | 用户提供图显示USD、grouping Off、Graph Probe存在、CSV Expense存在、有效备份2 | 有限人工提交证据，无Agent截图/AX采集 |
| 第二图G1–G7 | 用户明确反馈“G1–G7均符合”：CNY/On、两个Probe不存在、CSV Expense不存在、backup0、cache2条/768bytes/默认512MiB、原两个Goals仍在 | USER REPORTED，对照本轮第一图；不冒称旧第二图完成或Production Store验证 |

全部新synthetic原件和App保留至Reviewer验收。无CUA、AX采集、截图采集、构建、Unit/XCUI、Release、性能、Provider或OSLog运行；未重复VoiceOver、图表或内部恢复。继承Unit597、Release31/28ms、BFT、D-03有限static/Unit与原20项UI均NOT RUN in this round，旧FullUI Failed与独立en/US1/1不合并。取消保持细项、security-scope释放计数、受控offline/timeout/missing/stale、六项性能、OSLog交付/留存/人工脱敏、其他显示条件与尚缺的人工质量细项继续开放；不进入W2–W5。

## 当前授权与入口

2026-09-11，Reviewer 通过 Prompt 12-ENTRY-AND-HARDENING-PLAN-01 裁决 **Stage11 总 Gate PASS**，授权 Stage12 入场文档与规划。Stage12 总 Gate 尚未通过；**Stages13–14 NO-GO**。本文件是待后续授权的验收方案，不是运行指令或已批准的实现工作包。本轮所有构建、测试、App、人工 QA、性能与日志观察均 NOT RUN，运行/修复/重试预算为0。

来源优先级遵循当前用户裁决与[根治理](../AGENTS.md)；适用冻结来源为 [V1 Scope](V1_SCOPE.md) 的质量边界、Stage Mapping、Scope Change Control，以及 [A-014/A-015/A-016](V1_ARCHITECTURE.md)。本次裁决明确：A-016 八类人工 QA 属于 Stage12 **必需验收**，不是可选建议或已通过项。发现 Stage11 功能或安全缺陷仍须登记，取得明确修复授权；Stage11 PASS 不覆盖缺陷。

入口为 [E-FINAL 报告](/Users/freeforest/Aureus_Engineering_Evidence/Stage11-FINAL-EVIDENCE-CLOSEOUT-01-vFX7aM/ExecutionReport.md)及 [FinalInventory](/Users/freeforest/Aureus_Engineering_Evidence/Stage11-FINAL-EVIDENCE-CLOSEOUT-01-vFX7aM/FinalInventory.json)。本轮实际核验122项；清单自身 SHA256 为 `0b7e6951ec0da79cb128f0b7b4c8748fcc5f9ef854c9bcdffaf5bc8670cd1266`，规范化 SHA256 为 `f6e4f06ca9cc0dce67851b22968044e04e782aeb88adaf8dd4ae1675e4de6cd1`。最终仅三文档更新并新增本计划；运行相关119项冻结。

| 继承来源 | ACCEPTED EVIDENCE；本轮 NOT RUN | 不能推出的结论 |
|---|---|---|
| [E-CC](/Users/freeforest/Aureus_Engineering_Evidence/Stage11-CONSOLIDATED-CLOSURE-01-ZnXAET/ExecutionReport.md) | Full Unit 491 definitions /597 executions，597/0/0；Release Export 29/31，31/0/0；10,000-row export＋committed validation 28 ms；相关 BFT 限定通过 | 28 ms 不是 p95，也不是启动、Dashboard、Ledger或图表性能 |
| E-CC | 原20个 UI 方法有限 Passed；原 Full UI 永久为20/1/0 Failed | 不与后续1/1拼成新的 Full UI21/21 |
| [E-LC](/Users/freeforest/Aureus_Engineering_Evidence/Stage11-CACHE-AUDIT-LOCALE-CONTRACT-01-Fv0v66/ExecutionReport.md) | en/US 独立 cache audit 1/1 PASS，17条完整唯一 label检查 | 不是任意locale、VoiceOver质量或多语言验证；具体进程Locale getter未实测 |
| [E-OSL-RB](/Users/freeforest/Aureus_Engineering_Evidence/Stage11-OSLOG-EVIDENCE-REBASELINE-01-DS0fIa/ExecutionReport.md) | D-03限定 static/Unit；同一Full的十一组子集，不是独立Focused | 不证明OSLog系统交付、留存及人工脱敏 |

产品身份仅按上述已接受来源继承，**本轮没有重新核验二进制或签名**。未来运行前须验证实际完整App/Runner、配置、源身份及隔离，不能仅凭历史路径启动。旧Dlr35W保持 HISTORICAL ONLY — 据报告通过，原始证据已丢失；历史失败、取消、UNKNOWN、读取顺序和提前文档更新偏差不追溯更改。长期工程证据不自动属于公开发布材料。

## 要求—证据—剩余动作矩阵

下表运行状态全部为本轮 NOT RUN；“已有”是继承或源码定义，不是本轮实跑。

| 要求/冻结来源 | 当前状态与已有覆盖 | 缺失证据 | 验证动作与工作包 | 依赖与完成标准 |
|---|---|---|---|---|
| VoiceOver；A-016 UI/accessibility | cache audit完整label已接受 | 朗读质量、顺序、语义、变化通知 | W1，用户听读缓存/财富/错误/确认窗口 | 当前桌面与signed产品隔离确认；逐检查点用户记录，无阻断缺陷 |
| keyboard-only；A-016 | 导航/CRUD测试定义及原20项有限通过 | 无鼠标完整路径、焦点归还/陷阱 | W1，Tab/Shift-Tab、Return/Escape完成流程 | 记录起止焦点及取消/提交结果；必需路径可完成 |
| security-scoped panels；A-014/015/016 | Settings lease接线及原生panel UI定义 | 用户可理解、取消与权限释放实际体验 | W1，synthetic CSV/导出/外部恢复 | 仅新操作自有路径；scope取消/成功、无额外权限异常 |
| backup/restore confirmation；A-015/016 | 内外恢复、安全备份、rollback Unit与UI有限证据 | 警告可理解、取消无变更、确认恢复体验 | W1，先备份、加synthetic probe、取消再确认 | 旧值/恢复值/安全备份可追溯；异常立即停，不能用重试掩盖 |
| offline behavior；A-016 | Service/Markets错误传播Unit；Settings明确Not checked | 用户观察offline/timeout/missing及stale的实际UI；HARNESS MISSING | W2冻结受控synthetic失败入口；W1补完人工观察 | 不切真实网络/Provider；timeout不等于offline；无虚构成功数据 |
| chart interaction；A-016 | 本地WebView、JS交互与Markets UI定义 | pan/zoom/crosshair/tooltip人工质量 | W1，synthetic search→history→chart与原生fallback | 数据对齐、交互/焦点可用；ready不是首帧性能证据 |
| appearance/contrast；A-016 | 主题/文字与状态源码，有限AX覆盖 | 明暗/对比度/缩放可读性人工观察 | W1，当前获准显示条件下逐页/图表/弹窗 | 条件逐项记录；不可见信息/仅颜色状态需报缺陷 |
| signed sandbox；A-014/015/016 | signed BFT与历史synthetic UI | 当前人工session的隔离、panel与异常体验 | W1，已核验signed产品＋temporary graph | 不访问真实domain；无未解释权限/路径行为 |
| 六项候选性能；A-016 | 相关功能、Export单次28ms；候选专用harness缺失 | 下节机器/样本/边界/指标结果 | W2冻结协议及单独授权harness，W3测量 | 先冻结歧义；全部原始样本及失败保留，阈值由Reviewer决定 |
| OSLog；A-014与D-03有限合同 | 三枚举、private模板、disabled/recording/severity/smoke | 系统交付/留存/人工脱敏 NOT VERIFIED | W4，隔离环境内仅固定枚举的最小前向观察方案 | 新环境/观察权限单独批准；不读私人或历史日志，明确未证明部分 |
| 变更后回归；A-016、Scope Stage12 | 已接受源对应Unit/UI/Export | Stage12变更影响与最终同源跨功能证据 | W5，风险选择后最终跨功能验收 | 不用历史通过遮盖新缺陷；完整退出码/参数节点/产品身份 |
| 产品/数据边界；A-014/015、根治理 | temporary memory-only、CNY/FX、两Store隔离 | 每次新运行的隔离和变更范围证明 | W1–W5共同前置与退出审计 | 不触真实数据/secret；Permanent sentinel、源/产物与授权一致 |

## 工作包顺序与建议预算

这是建议，必须由后续明确授权冻结文件范围、产品、selector、样本和预算后才执行。本轮不创建任务、不预约运行。

1. **W1：可用原生流程的人工质量基线，建议下一次优先工作包。** 当前已有隔离入口与signed来源，人工证据缺口最直接；先观察VoiceOver、键盘、panels、确认、图表、appearance和sandbox，避免先做性能优化掩盖UX问题。没有复验身份的可用产品时停止，不自动重建。Offline缺乏受控UI入口的部分保持未完成，待W2后返回W1，不宣布整包已通过。
2. **W2：冻结测量口径与受控入口缺口。** Reviewer决定下述性能问题、synthetic offline UI和10k/100k fixtures/测量harness范围。任何建设需要独立代码授权和回归预算，本计划不实施。不得将100k“首屏”问题顺手改成新分页产品需求。
3. **W3：Release性能测量。** 在W2工具/fixtures经过相应回归后，对同一冻结Release产品按批准协议运行一次测量campaign，保留全部采样与安全哨兵；不反复运行至通过。
4. **W4：隐私/OSLog最小观察。** 须先批准独立干净环境和限定观察权限；不在用户日常日志域操作。可先做纸面协议冻结，任何GUI使用与W1/W3/W5串行。
5. **W5：剩余人工项、变更后的针对性回归及最终跨功能验收。** 汇总缺陷来源与授权修复，在最终冻结产品上完成受影响领域、完整Unit和必要完整UI；人工结果和自动化分别列出。若完全无源码变化，Reviewer应按具体未覆盖风险决定是否需要再跑完整suite，不为合成21/21或凑数字重跑Stage11。

| 未来包 | 必要构建建议 | 单次执行建议 | 业务修复/基础设施建议 |
|---|---|---|---|
| W1 | 已核验旧signed产品可复用则0；缺产品先报告 | 一次有值守synthetic人工session，分检查点；offline缺口不试跑生产 | 本包观察不修复；问题另获授权；未知异常不重开session求绿 |
| W2 | 若另获harness代码授权，fresh BFT及隔离副本 | 针对新增harness定义一次验证 | 建议最多一次明确新增代码原因修复；不得变更冻结阈值 |
| W3 | fresh Release/testability配置；保留真实优化 | 一个campaign内预定N个样本，不使用Xcode自动重复/失败重试 | 失败保留，优化/再测需新变更和新授权；基础设施默认0 |
| W4 | 原smoke若产品可核验可复用；否则另批准构建 | 一次固定有限事件＋限定前向观察 | 无配置/权限绕过，无失败重试；缺授权不运行 |
| W5 | 源变化需新unsigned隔离Unit及signed UI产品 | 所需针对性回归＋最终Full Unit/UI各一次，是否重复须说明覆盖差额 | 建议完整业务失败停止；仅明确外因且原进程终止后，另批至多一次基础设施重试 |

每个未来运行均须durable argv/UTC/PID/underlying exit、完整Info.plist、串行canonical解析、definitions/arguments/executions和源产品冻结；失联不代表结束，不重启副本。GUI只能一个session。签名/用户认证由用户决定，Agent不处理凭据、不改系统保护。追加运行需要新增变更、失败或具体未覆盖风险，而非旧结果数字不够整齐。

## 人工QA执行卡（待授权；全部NOT RUN）

共同前置：重新取得当次用户桌面确认，桌面解锁独占、私有内容收起、无其他自动化；认证只由用户处理。另取得**人工参与确认**，不继承历史“确认”。先验证完整signed产品、实际executable与temporary/demo参数；不默认启动production。仅使用当前session自有synthetic数据和目录，随机temporary路径可能在工程证据根外，如实记录类别，不扫描其他目录。VoiceOver或显示条件由用户在另行批准条件下自行准备；不由Agent修改Accessibility/Automation设置。

共同记录格式：检查点ID、UTC、产品/配置Hash、启动隔离布尔值、用户执行步骤、预期、**USER REPORTED**原意结果、未完成项、缺陷与附件授权范围。不记录用户名、真实路径内容或凭据；不默认采集屏幕/全AX。每项以用户观察为准，自动化Passed不能代填。遇私人数据、未知目标路径、权限窗口、隔离不明、操作无法取消、不可恢复状态或新安全缺陷立即停止该路径，保留有限事实交回Reviewer；不尝试真实账户或自动重试。

| ID | 实际入口/操作 | 检查点与可观察结果 | 人工记录及该项停止条件 |
|---|---|---|---|
| M1 VoiceOver | Settings缓存摘要/oldest/cleanup/provider/TTL，Wealth CNY/USD金额与编辑，Markets Accessible Data，恢复确认 | 字段/单位/UTC/空值/legacy限制读完整；焦点顺序有意义；更新后读值与屏幕一致；不依赖颜色 | 用户逐项听读与理解反馈；缺字/重复/错误值或无法进入表格即登记；17条AX自动化不替代质量 |
| M2 keyboard-only | sidebar→Wealth新建/编辑→Settings容量Apply/Reset确认与取消→返回 | Tab与反向Tab可达；Return/Escape语义正确；提交/取消后焦点合理，无焦点陷阱；草稿/原币不被偏好覆盖 | 记录每条无鼠标路径及焦点归还；键盘无法完成、意外提交或丢草稿停止 |
| M3 security-scoped panels | Ledger原生CSV选择→preview→确认→export；Settings备份选中→Export目录；External Restore选择生成目录 | 仅选新建synthetic目录；取消不产生提交；选定目标正确；成功/取消结束访问lease；不索取无关权限 | 用户记录panel文字/目标类别/取消与结果；不以仅file exists证明可理解或scope释放；scope运行证据不足标NOT VERIFIED |
| M4 backup/restore confirmation | Settings创建内部备份→新增synthetic Goal probe→内部Restore；同一备份Export→外部Restore | 警告明确未加密及替换范围；取消保持probe，确认后恢复备份状态并有安全备份；原导出不被改写；恢复成功后页面重新绑定 | 分开记录取消/确认；用本session前后可见synthetic sentinel佐证，文件完整性依赖获准检查；恢复异常/recovery required停止，不连续恢复试错 |
| M5 offline | 现有Models的Search/History失败映射作预期来源；当前CLI没有受控offline scenario开关 | 无session时offline/timeout/missing区分且无虚构图表；已有stale保留并披露；Settings始终“Network connectivity: Not checked”，空缓存不等于offline | 当前真实UI失败注入 HARNESS MISSING，待W2批准后用户观察；不关闭真实网络、不调用真实Provider；empty local界面不能充当offline完成 |
| M6 charts | Markets synthetic SYN search→选中→显式History refresh→chart/RSI14/Accessible Data | pan/zoom/范围/十字线与tooltip日期OHLCV、量和indicator对齐，原生fallback可读可聚焦；可返回其他页 | 用户逐操作记录卡顿/焦点/错位；桥接ready/renderSummary不能充当画面或帧率；阻塞/错数据停止 |
| M7 appearance/contrast | 上述页面、图表、空/错误/stale和确认窗口；用户批准的明/暗及显示尺寸条件 | 文字、数值、状态与按钮可读；裁切/缩放不隐藏操作；禁仅颜色传达风险；图表与原生页一致 | 条件分别记录而非笼统PASS；未准备的主题/显示条件NOT RUN；不擅改用户系统设置 |
| M8 signed sandbox | 同一signed隔离App完成M2–M4、Clear/Reset后回Wealth | 原生panel可操作且无意外权限；缓存清除永久synthetic记录保持；temporary重启偏好默认；绝不进入production domain | 用户体验与产品路径/参数证据分列；synthetic credential不等于真实Keychain验证；sandbox异常或隔离不明停止 |

实际Settings scope路径为选择后startAccessing、异步workflow结束defer stop；外部恢复持有lease到确认操作结束/取消。上述静态接线只是检查依据，不是用户已观察到释放。现有UI helpers含各自原等待/面板操作，本计划不修改、不复制其等待作为人工PASS条件，也不授权清理未知App。

## 性能协议草案与待冻结问题

来源严格保留A-016 **candidate**性质，基线Apple M2或记录等效机器。后续Reviewer须先冻结口径；不得将下面建议冒充阈值已获批准，也不以单次Export28ms替代。

| 原候选指标 | 拟测边界与现状 | 必须先冻结的问题 |
|---|---|---|
| 10,000 synthetic ledger entries启动：p95≤2.0s | 外部单调时钟从进程启动请求到可交互shell；包含打开/迁移/装载，seed在计时外；现有launch helper无该fixture或计时 | usable shell的可观察标志；是否排除首次迁移；“冷”仅新进程还是冷文件缓存，禁止擅自清OS缓存 |
| 10,000 entries warm Dashboard aggregate：p95≤250ms | 对已准备Store执行真实DashboardService.load，明确返回聚合或界面完成；现有5,000 Goal计时非该工作负载 | 是否包含DB读取/首次snapshot创建/视图更新；预热后是否允许写snapshot；固定业务类型分布 |
| 100,000 entries Ledger首屏warm：p95≤200ms | 真实fetch＋首个可见viewport完成；当前fetchLedgerEntries读取全结果，未发现分页API/首屏harness | first page指可见首屏还是数据库页；可见行数/排序/过滤与是否计全量读取，不能自行增加分页功能 |
| 10,000 bars首次渲染≤1.0s | 真实WebView接收数据到实际首帧可观察完成；JS renderSummary在setData后发出，不是paint指标 | 是否含WKWebView/本地资源初始化；每样本上限还是分位数，原文未写p95；最大现有Markets range仅5,000，10k须另批fixture |
| pan/zoom原文“p95 at or above45fps” | 固定手势轨迹/时长/视口，在10k bars下保留逐帧时间与窗口FPS；现无harness | p95 FPS是高尾，可能不能约束低帧率；Reviewer明确分布对象/窗口/采样算法。不得擅改为p5 FPS或p95 frame time |
| 配置最大容量cleanup≤5s、非主线程、永久数据隔离 | 实际cleanup请求至完成，计数据库清理/结果；另有执行器证据及Permanent URL/hash/schema/sentinel前后 | 默认512MiB还是允许最大4GiB；accounted bytes与实际DB/WAL容量；90%触发/80%目标下如何准备负载；选择TTL/容量/手动哪种，不能关闭既有策略 |

统一草案：记录机器型号/CPU/RAM、macOS/Xcode、架构、Release优化/是否testability、源与产品Hash、屏幕/scale/窗口尺寸、可用存储/电源和竞争负载类别；不导出用户环境或无关进程参数。每个指标建议固定20个timed样本，warm项目先3个不计时预热；启动每次新隔离进程、同构数据，不称OS冷缓存。该数量属于未来一次明确授权campaign的采样，不是失败自动重试；当前预算仍0。

p95建议nearest-rank：升序数组第ceil(0.95×N)个；N=20为第19个，同时保存全部原始值/min/max。预热与timed标签分开。失败、超时、缺测保留，不能删掉再补样本、只挑最快或把失败当0；必要采样未完成则不出完整PASS。对没有p95定义的指标先等Reviewer回答。测量工具开销、时间源、单位、起止事件与seed/validation是否计入须写入协议。

fixtures必须是批准的synthetic ledger/price/bars，不使用真实导出或Twelve Data持久内容；创建前核验目标空目录和容量：payload、SQLite/WAL、备份/结果及余量，不足停止，不清理历史数据。cleanup不得用2条legacy/768bytes或.testing(1000)替代配置上限；并保存Permanent哨兵，actor声明不等于已测“off main actor”。计时外验证行数、数据分布、Store身份和结果正确性，防止快速空结果。

## 已定位的验证入口

以下是源码定义目录，**不是执行命令**。所有入口本轮NOT RUN；未来必须发现实际产品/配置、隔离后才能组成argv。没有列出的harness不凭猜测发明启动参数。

| 精确入口 | 状态/实际语义 |
|---|---|
| `AureusTests` | EXISTING DEFINITION（Unit target）；ACCEPTED EVIDENCE E-CC 491/597；当前不重跑 |
| `AureusTests/PermanentBackupExportTests/stage11ExternalBackupExportPerformance` | EXISTING DEFINITION；10,000 synthetic账户行，export及committed artifact validation计时，原断言10秒；ACCEPTED EVIDENCE Release suite29/31、28ms；不是ledger性能 |
| `AureusTests/DashboardDomainTests/goalProjectionPerformance` | EXISTING DEFINITION；5,000 Goal投影/净值条件计时，非10k Ledger warm aggregate；A-016专用HARNESS MISSING |
| `AureusTests/MarketsTerminalTests/emptySessionSearchFailure`、`emptySessionHistoryFailure`（同suite） | EXISTING DEFINITION；每项offline/timeout/missing公开Model路径及有界终态；继承Full覆盖，不是人工offline UI |
| `AureusTests/MarketCacheInfrastructureTests/allCleanupPathsArePermanentlyIsolated` | EXISTING DEFINITION；参数化cleanup、Permanent hash/schema/sentinel/业务记录保持；非最大容量5秒/线程测量 |
| `AureusTests/DataLifecycleDiagnosticsTests`：`disabledAndRecording`、`severity`、`privateTemplates`、`osLogSmoke` | EXISTING DEFINITION；有限sink、severity参数、源码private模板和固定成功枚举smoke；系统交付/留存仍NOT VERIFIED |
| `AureusUITests/AureusUITests/testStage11SettingsCacheAuditFieldsCapacityAndReset` | EXISTING DEFINITION；ACCEPTED EVIDENCE独立en/US1/1、17检查；其余locale不泛化 |
| `AureusUITests/AureusUITests/testStage11GeneralPreferencesAffectWealthWithoutChangingValuation`、`testStage11SettingsCacheStatusTracksSessionAndClear`（同class） | EXISTING DEFINITION；偏好消费、session真实search填充/clear；历史原20项有限Passed，不是本轮运行 |
| `AureusUITests/AureusUITests/testStage11SettingsInternalBackupRestoreLifecycleAndIsolation` | EXISTING DEFINITION；M4内部备份/取消/恢复/隔离操作来源 |
| `AureusUITests/AureusUITests/testStage11SettingsExternalBackupExportToUserSelectedFolderAndIsolation`、`testStage11SettingsExternalBackupRestoreFromUserSelectedGenerationAndIsolation`（同class） | EXISTING DEFINITION；M3/M4目录选择、原生确认与synthetic目标隔离 |
| `AureusUITests/AureusUITests/testLedgerNativeCSVImportPreviewConfirmationAndExport` | EXISTING DEFINITION；synthetic CSV、原生Open/Save、preview/确认来源；不代表用户体验 |
| `AureusUITests/AureusUITests/testStage7MarketsSyntheticSearchWatchlistChartAccessibilityAndClear` | EXISTING DEFINITION；M1/M6 Search、chart、Accessible Data、clear来源；无10k首帧或FPS计时 |
| `AureusUITests/AureusUITests/testWealthCNYUSDLiabilityCRUDAndDynamicTotals` | EXISTING DEFINITION；CNY/USD/FX及负债CRUD来源；人工键盘路径另验 |
| `AureusUITests/AureusUITests/testStage6ProductionCredentialConfigurationObservation` | EXISTING DEFINITION；名称含Production，但源码用ui-testing隔离graph与缺失凭据观察，不是访问真实Keychain授权 |
| A-016 launch10k、Dashboard10k、Ledger100k、chart10k/frame、configured-max cleanup计时 | HARNESS MISSING（未发现符合完整口径的入口）；不得借邻近performance方法冒称已有 |

入口源码：[RuntimePaths](../Aureus/App/RuntimePaths.swift)、[AppDependencies](../Aureus/App/AppDependencies.swift)、[UI定义](../AureusUITests/AureusUITests.swift)、[Export测试](../AureusTests/PermanentBackupExportTests.swift)、[Dashboard测试](../AureusTests/DashboardDomainTests.swift)、[Markets测试](../AureusTests/MarketsTerminalTests.swift)、[Cache测试](../AureusTests/MarketCacheInfrastructureTests.swift)、[Diagnostics测试](../AureusTests/DataLifecycleDiagnosticsTests.swift)。

已验证源码启动链为 AureusApp→LaunchConfiguration.current→AppModel.start→AppDependencies.make，由AppRootView.task调用start。支持 `--aureus-ui-testing`、`--aureus-demo`、`--aureus-temporary-store`；任一进入temporary路径，只有demo选择syntheticDemo。UI helper传ui-testing及 `-ApplePersistenceIgnoreState YES -NSQuitAlwaysKeepsWindows NO`，demo按需追加；audit仅ui-testing＋demo＋`--aureus-settings-cache-audit`三者同时生效。不存在任意root、10k/100k、offline-scenario CLI。不得用空参数启动QA。

temporary root由temporaryDirectory/Aureus-Stage2/UUID生成；同graph内存preferences/credential、synthetic provider、disabled diagnostics，与真实Store分离。审计fixture是2条/768 accounted bytes的legacy，不是有效生产offline fallback。en/US测试配置须另获准并核验App/Runner一致，既有UI源码本身没有强制两进程locale。不能写系统持久偏好。

## 隐私/OSLog最小验证方案（未授权运行）

固定来源为 [adapter](../Aureus/Diagnostics/DataLifecycleDiagnostics.swift)：仅operation/outcome/errorCategory枚举，成功info、其他终态error，动态插值private；Production显式OSLog、temporary默认disabled。既有smoke只固定成功事件，severity/错误类别其他组合主要是mapping/static，不能当已采集系统错误日志。

建议W4先由用户/Reviewer批准**独立干净macOS测试账户或等效隔离环境**及有限前向观察能力；不能直接在日常用户域读Console或OSLogStore。环境准备本身需新增授权，不由本计划创建账户/VM或修改权限。核验smoke产品后只触发一次既有固定枚举事件，限定起止时间、确切进程、subsystem `com.aureus.wealthterminal` 和category `data-lifecycle`；观察输出只保留有限事件/level/默认private呈现。禁止扩大为全系统历史日志、打开私有值显示、记录真实业务哨兵或把原Error送日志。

若需证明error level系统路径，现有成功smoke不足，须另批最小test-only入口；不改产品字段/策略。前向看到事件仅证明该环境该次交付及默认显示，不证明所有后端留存、跨重启、所有用户配置或最终不可恢复隐私。留存需求若必须验证，应先由Reviewer冻结时间窗、隔离环境与仅本次事件的限定读取授权；当前仍NOT VERIFIED。不能以“smoke没报错”关闭该项，也不能为获得证据读取既有私人日志。无法提供干净环境/有限查询则停止W4并报告缺证，不默认豁免Stage12隐私验收。

## Stage12出口与报告合同

Reviewer决定Stage12 Gate。出口要求：八类必需人工项有用户来源记录；性能候选口径先冻结后有同源Release原始样本和判定；批准的隐私验证有可追溯结果及明确未证明范围；变更影响回归和最终跨功能结果完整；新发现功能/数据安全问题已授权解决并验证，或明确阻止Gate。未闭合必需项不能靠历史自动化或缩小声明变成PASS。

每包记录来源、修改授权、产品/配置、动作、结果、失败和预算；继承、NOT RUN、NOT VERIFIED、USER REPORTED分开。不重复Stage11文档收尾循环，不生成新的Executor Prompt。本轮计划报告与最终清单位于 [Stage12入场证据](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-ENTRY-AND-HARDENING-PLAN-01-sIcpKm/ExecutionReport.md)。

保持macOS/Apple Silicon、单用户local-only personal/internal non-commercial、visualization-first无AI/LLM；CNY统一计价与USD原值/FX/CNY并存；Permanent/MarketCache隔离及容量/TTL/清理不伤永久记录；synthetic/sanitized only；Twelve Data session-only、persistent writes Disabled、retention rights BLOCKED；真实Credential仅由用户经原生Settings写入应用Keychain。本轮不访问真实domain、Provider、Secret或系统日志，全系统未测量访问数为NOT VERIFIED。

## 2026-09-12 — W2 受控 Search / History 失败入口技术证据

当前授权为 Reviewer 的 `12-OFFLINE-UI-HARNESS-01`：仅实现请求级 synthetic 入口及 Unit 验证，不运行原生 UI 或人工 QA。Stage11 PASS 保持；Stage12 PARTIAL — Awaiting Reviewer Gate；Stages13–14 NO-GO。以上历史“未授权/NOT RUN/HARNESS MISSING”记录保留原时点；本节更新六场景当前技术状态，不追溯改写旧结果。

W1 的新 CSV、外部备份两文件恢复前后/最终字节身份，以及有明确第一图状态的第二图 G1–G7 USER REPORTED 对照，已由 Reviewer 有限接受，来源为 [W1限定补证报告](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-W1-ARTIFACT-AND-GRAPH-CLOSURE-01-dxzPBT/ExecutionReport.md)。Cancel 后 Probe 保持仍 NOT VERIFIED，移交后续统一人工验收；security-scope 释放计数、旧文件丢失、旧第二图缺证和完整 AX 输出偏差全部保留。本轮未重复这些人工动作。

新增 `--aureus-market-failure-scenario <value>`，只接受下表六值；必须同时有 `--aureus-ui-testing` 与 `--aureus-demo`，场景参数恰好一次且紧随有效值。缺值、未知值、重复或缺必要参数均禁用，不改变既有模式选择。依赖图另以 syntheticDemo、usesTemporaryStores、非空 temporaryRoot 三项实际边界限制；无效生产组合仅纯判断验证，不创建 Production 图。默认 nil，既有 cache-audit 合同、生产 Keychain/Provider/FX 分支及其他请求保持。没有 stale seed、真实网络切换或持久故障偏好。

本轮证据：[ExecutionReport](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-OFFLINE-UI-HARNESS-01-WmpCMn/ExecutionReport.md)、[canonical及同包子集](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-OFFLINE-UI-HARNESS-01-WmpCMn/UnitResults.json)、[宿主隔离差异](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-OFFLINE-UI-HARNESS-01-WmpCMn/DebugIsolation.json)。首次 unsigned BFT 因新增测试对非 Optional CivilDate 使用可选链而 Failed/exit65；消费唯一编译修正后，新路径 BFT succeeded/exit0、parser0。失败包和首次输入保留；没有业务修复或测试重跑。

单次 Full Unit：497 definitions / 632 executions，632 Passed，failed/skipped/expected failures 均0，underlying exit0，summary/tests parser0/0。36个参数化容器、171个 Arguments 执行节点，加461个非参数执行，未重复计算容器。新增6 definitions /35 executions全部通过；原 emptySessionSearchFailure / emptySessionHistoryFailure 为2/6通过。GeneralSettingsTests 同包17/57，MarketsTerminalTests 同包30/39；独立 Focused NOT RUN。旧 Unit597、Release31/28ms、UI等是历史继承，未作为新源码的运行证明；本轮 Full 包含的既有 performance Unit 不等于 A-016 六项性能测量。

新精确入口：`AureusTests/GeneralSettingsTests/marketFailureArguments`、`invalidMarketFailureArguments`、`marketFailureIsolationGuard`、`ordinaryMarketGraph`（均同 suite）；`AureusTests/MarketsTerminalTests/launchScenarioFailure`（六个参数执行）、`launchScenarioSuccessControl`。状态为 EXISTING DEFINITION / 本轮 Unit VERIFIED；原生 UI NOT RUN。前者从实际 current→make→公开 Model Search/History验证准确状态和原披露；History正常 Search 的1个 session payload允许保留，失败后数量/bytes不变、对应historical key缺失、无图表/指标；非目标请求与默认 synthetic结果一致，永久哨兵/Wealth/Goals/Ledger保持。

### 后续待授权的六场景操作卡（本轮不执行）

共同前提：另行取得明确运行授权、新 signed 同源产品及完整身份核验，重新取得当次桌面/用户参与确认；旧 signed App不能验证新源码。每场景独立 temporary graph，传入 `--aureus-ui-testing --aureus-demo` 和该场景参数；不改真实网络，不接触 Production Credential，不以 cache-audit legacy充当fallback。用户亲自操作，结果标 USER REPORTED，不默认采集截图/AX；认证仅用户本人处理。异常隔离/数据安全/未知权限目标立即停止，不重复失败动作求绿。

| 场景 value | 该图内操作 | 必须观察的结果 |
|---|---|---|
| `search-offline` | 输入 synthetic query `SYN`，显式 Search | `Market Data Unavailable Offline.`；无成功搜索结果、History、伪造图表或指标 |
| `search-timeout` | 输入 `SYN`，显式 Search | `Provider request timed out.`；同上空结果/无图表要求 |
| `search-missing` | 输入 `SYN`，显式 Search | `Requested session data is missing.`；同上空结果/无图表要求 |
| `history-offline` | 正常 Search `SYN`，选择实际返回的 `SYN-CNY.XSYN`，显式刷新 History | Search先成功；刷新才显示 `Market Data Unavailable Offline.`；无新增History/图表/指标 |
| `history-timeout` | 正常 Search、选择返回项、显式刷新 History | Search先成功；刷新才显示 `Provider request timed out.`；同上无新增历史内容 |
| `history-missing` | 正常 Search、选择返回项、显式刷新 History | Search先成功；刷新才显示 `Requested session data is missing.`；同上无新增历史内容 |

每张卡记录具体场景/动作/实际文案及未到达项，不能用某张成功补写其他场景，也不能把 synthetic timeout 当真实联网超时或完整 offline 验收。stale 入口仍 HARNESS MISSING；六场景人工 UI、Cancel细项、其他必需人工质量、性能协议冻结/测量、OSLog系统交付/留存/人工脱敏及 Stage12 最终跨功能验收均继续开放。本轮没有 signed BFT、Release、UI或人工运行，未进入下一工作包。
