# Stage 11 Data Lifecycle Acceptance

## Status

**Stage 11 PARTIAL — Awaiting Reviewer Gate**

## Scope and Evidence Audit — 当前总范围索引

**Stage 11 Scope and Evidence Audit Candidate — Awaiting Reviewer Gate** 仅表示本轮审计产物待审。Reviewer 已接受下述 Runtime 子关卡：Ledger `1/1`、单次 Existing focused `12/12`、Full UI `18/18 PASS`，全部 underlying exits `0`、summary/tests parsers `0/0`；不据此宣布总 Stage 完成。

完整 requirement → implementation → assertion → artifact → identity → limitation 映射见 [Stage 11 Scope Evidence Matrix](STAGE11_SCOPE_EVIDENCE_MATRIX.md)。确定的实现缺口：Settings currency/display preferences、last-cleanup time UI/AX、unified privacy-safe OSLog。集中决策还包括 Settings cache stale/offline 的准确语义、空 session offline 被映射为 missing 的呈现，以及旧 Export Release 26 ms 的同源复用限制（共享 Backup validator 已改变）。既有 Unit 的95项相关源全部匹配；Restore Release相关Foundation/Test匹配；旧Export计时保留为历史PASS，不冒充当前完整validator链的精确同源性能证据。

本轮全部 Test/Build/Performance/UI/BFT：`NOT RUN — DOCUMENTATION AND READ-ONLY AUDIT ROUND`。复用项明确 `NOT RUN — ACCEPTED EVIDENCE AFTER RELEVANT SOURCE-IDENTITY VERIFICATION`。仅审计及三份文档，没有产品/测试修复，没有App、Provider、真实Keychain/Cache/Store操作。人工VoiceOver、keyboard-only、appearance/contrast、chart interaction、security-scoped/signed-sandbox/offline观察仍独立未验证，不由18/18替代；不得把Stage11明确缺口任意挪到Stage12。

本轮 [ExecutionReport](/private/tmp/Aureus-Stage11-SCOPE-EVIDENCE-AUDIT-01-h3ILCY/ExecutionReport.md) 记录实际全文阅读、安全116项基线、相关证据身份与最终117项文件审计。以下历史内容保留原始轮次语境：PID59940首次断连根因仍 `UNKNOWN`，历史Mandatory Read和numeric-exit缺口不追溯改写。Stages12–14继续 `NO-GO`。

## App Connection Diagnostic Closure 03 — 当前运行时证据

Evidence root：`/private/tmp/Aureus-Stage11-APP-CONNECTION-DIAGNOSTIC-CLOSURE-03-jKe2QJ`；完整 [ExecutionReport.md](/private/tmp/Aureus-Stage11-APP-CONNECTION-DIAGNOSTIC-CLOSURE-03-jKe2QJ/ExecutionReport.md)。主 Executor 按序实际阅读五份正文至 EOF，核对本机 help 与 xctestrun，并审阅规定 UI Test 完整语义段；未冒称整个 UI Test 本轮 READ TO EOF。其余 Product/Foundation/Unit、设计与治理约束为 Hash-only continuity。

本轮基线为 KNimB7/FinalInventory.json，自身 SHA-256 `a614f3c63f2a673c2602998c420387c031b0c8288b904b9f4b6e20c6a5309f02`。预期值取 `inventory[].sha256`，不是旧比较字段 `expected`。116 项安全路径与实际集合、普通文件类型、无 symlink 组件及全部 Hash 通过。四项产品使用 bEN0A5 冻结路径，三个 executable arm64、Bundle IDs 匹配，App/Runner strict codesign `0/0`，local ad hoc；无 build/re-sign。

唯一 pre-Gate command correction：新 wrapper 删除 `-test-iterations 1`。最终 argv 无 iteration/retry/repetition 参数，仅 `test-without-building`、准确 xctestrun、macOS arm64、parallel disabled、maximum concurrent destination 1、独立 result 与 exact selectors。每 Gate 一次，stdout/stderr 直接入日志，wait 后即时保存 underlying numeric exit、wrapper/child PID 和 UTC；不用 tee。

| Gate | canonical 结果 | 退出与执行 | 时间与 bundle |
|---|---|---|---|
| A Ledger Dynamic | `Passed`；definitions/executions `1/1`；outcomes `1/0/0`；expected failures `0` | exit `0`；methods/workflows `1/1`；wrapper/child `74956/74958` | UTC `10:44:59Z–10:49:59Z`；canonical `294.814 s`；`LedgerDynamicDiagnostic.xcresult` |
| B Existing focused | `Passed`；definitions/executions `12/12`；outcomes `12/0/0`；expected failures `0` | exit `0`；methods/workflows `12/12`；wrapper/child `75253/75255` | UTC `10:51:08Z–11:13:36Z`；canonical `1342.750 s`；`ExistingFocusedRegression.xcresult` |
| C Full AureusUITests | `Passed`；definitions/executions `18/18`；outcomes `18/0/0`；expected failures `0` | exit `0`；methods/workflows `18/18`；wrapper/child `76624/76626` | UTC `11:14:35Z–11:39:28Z`；canonical `1487.969 s`；`FullAureusUITests.xcresult` |

日期均为 2026-09-05；bundle 均位于本轮 evidence root，均含 `Info.plist`，summary/tests 顺序 parsers `0/0`。B 的十二项与请求 exact selectors 一致，C 的十八个 canonical Test Case 与当前源码定义完全一致且全部 `Passed`。A/B/C 的 Ledger 方法分别完整通过；未将计划内覆盖写成一次执行，也未拼接 aggregate。

历史 category clear → `ledger.filter.tag` 及后续 container/date/currency、invalid-date、summary 在本轮完整方法中通过；历史 PID 59940 失联在本轮规定执行中未复现，首次原因仍 `UNKNOWN`。本轮没有后续 pre-launch 传播。Gate B 运行时一次观察到另一短暂 xcodebuild PID 75385，立即准确 PID 复核时其与父进程已退出，用途 `UNKNOWN`；不读取参数、不终止、不作根因推断。各 Gate 前后没有未解决的相关冲突；本轮 App/Runner 正常退出，无额外清理请求。

原 KNimB7 Ledger bundle 从实际目录顺序解析：完整 `unknown/0-test`、exit `64`、methods/workflows `0/0`、parsers `0/0`，保持参数校验失败/NOT PASS，不改称 incomplete。更早 bEN0A5 Targeted `1/1 PASS` 与 Existing 完整 `0/12/0 Failed`、numeric exit `NOT VERIFIED`、Mandatory Read 缺口均保留。OMbBhJ 未运行记录不变。新证据不追溯修复历史。

Unit/Performance：`NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION`，Focused `134/168`、Affected `167/205`、Full `460/531`，Restore Release `25/49` / 10,000 rows `43 ms`，Export Release `29/31` / 10,000 rows `26 ms`。Clean/BFT：`NOT RUN — ACCEPTED BUILD / REUSED EXACT FROZEN SIGNED PRODUCT`。独立 External Restore Targeted：`NOT RUN — ACCEPTED CURRENT-SOURCE 1/1 PASS AFTER EXACT SOURCE/PRODUCT VERIFICATION`，其 B/C 中实际执行另计。

Source/business repair、business/infrastructure retry、incomplete re-observation、automatic repetition/retry、parser-only reread 均 `0`。仅调用既有 synthetic/sanitized UI 流程；Local-mode 仍为 temporary-store 隔离验证，不涉及真实用户 Production Store。mock provider/credential/cache fixture 有实际操作，未伪报为零；未遥测的全进程 live counters 为 `NOT VERIFIED`。Executor 未发起 live Provider/Credential/Keychain/Market Cache 操作，Provider requests `NOT RUN`。Twelve Data persistent writes `Disabled`，retention rights `BLOCKED`，external retention/scheduling/cloud `NOT IMPLEMENTED / NOT AUTHORIZED`，Stages 12–14 `NO-GO`。

测试期间完整 116 项与路径集合、四项产品均保持一致；所有 invocation 结束后仅更新 README 与本文件，其余 114 项不变，无新增/删除/重命名。安全清单排除 `.git`、`.secrets`、`default.profraw` payload；未读取附件、AX dump 或真实用户数据。最终清单、Markdown/privacy 审计及完整 Hash 见报告。Stage 11 总 Gate 仍等待 Reviewer，不生成下一轮 Prompt。

## 前轮状态（02 原始失败保留）

**Stage 11-APP-CONNECTION-DIAGNOSTIC-CLOSURE-02 PARTIAL — Awaiting Reviewer Gate**

## App Connection Diagnostic Closure 02 — 命令参数校验停止

本轮 evidence root：`/private/tmp/Aureus-Stage11-APP-CONNECTION-DIAGNOSTIC-CLOSURE-02-KNimB7`；完整 [ExecutionReport.md](/private/tmp/Aureus-Stage11-APP-CONNECTION-DIAGNOSTIC-CLOSURE-02-KNimB7/ExecutionReport.md)。主 Executor 按序实际审阅全部 14 项指定正文至 EOF；其余设计/架构/Foundation 为 Hash-only inheritance，不标记本轮全文阅读。历史 Mandatory Read 缺口不能追溯修复。

治理基线 `RepositoryPost.sha256` 自身 SHA-256 为 `857b9685d9a90f97645ef348f2badba8d974d5d6ec7f4323720a384bbe04ad71`，116 条安全普通文件路径、实际集合及全部 Hash 匹配；逐组件拒绝 symlink，遍历前排除 `.git`、`.secrets`、`default.profraw`。四项冻结产品与指定 Hash 匹配，三个 executable 为 arm64，Bundle IDs 匹配，App/Runner strict codesign `0/0`，local ad hoc。未重新 build/sign。

启动前未发现 Aureus、XCTest Runner 或 xcodebuild 冲突；系统 WorkflowKit `BackgroundShortcutRunner` 不是本测试 Runner。未终止任何进程，未使用历史 PID 62705 的退出授权。Gate A 自然退出后也无准确产品/测试 invocation 残留。

| Gate | 实际状态 | 完整执行元数据 |
|---|---|---|
| A Ledger Dynamic | FAIL — command argument validation；canonical `unknown`，不是业务 failure | 唯一 `test-without-building` invocation；wrapper PID `72689`，xcodebuild PID `72691`；UTC `2026-09-05T10:17:16Z` → `10:17:17Z`；underlying exit `64`；definitions/executions `0/0`，methods started/workflows reached `0/0`，outcomes `0/0/0`，expected failures `0`；canonical interval `0 s`；`LedgerDynamicDiagnostic.xcresult` 含 Info.plist，summary/tests parsers `0/0` |
| B Existing focused | NOT RUN | A 未通过，未启动 invocation；expected 12/12 不作实际计数；result、exit、duration、parsers N/A |
| C Full UI | NOT RUN | B 未通过，未启动 invocation；expected 18/18 不作实际计数；result、exit、duration、parsers N/A |

Gate A exact selector：`AureusUITests/AureusUITests/testLedgerDynamicCashFlowTransferInvestmentEditAndDelete`。实际命令保留用户要求的 `-test-iterations 1`；Xcode 返回 `xcodebuild: error: Must specify -test-iterations with more than 1 iteration.`。wrapper 在 wait 返回后立即保存数字退出码并以同值退出，未用 tee 或外层状态替代。该参数校验失败发生于业务前；不能声称 Ledger 已执行、历史失联“未复现”或“已修复”，首次失联根因仍 `UNKNOWN`。未擅自删除参数或增加迭代，repair/retry/infrastructure retry/incomplete re-observation/automatic retry 均 `0`；parser-only reread `0`。

从实际 bEN0A5 四份历史 bundle 顺序重新解析，全部 parser exit `0`：Clean/BFT succeeded（各四项既存 warning）；Targeted `1/1 PASS`；Existing 完整 `0/12/0 Failed`。历史 Existing numeric exit 仍 `NOT VERIFIED`，后续十一项 pre-launch 传播与首次 Ledger 业务中失联保持区分。OMbBhJ A/B/C 全部 `NOT RUN` 的历史不变。

Unit/Performance 本轮 `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION`：Focused `134/168`、Affected `167/205`、Full `460/531`；Restore Release `25/49`、10,000 rows `43 ms`；Export Release `29/31`、10,000 rows `26 ms`。Clean/BFT 为 `NOT RUN — ACCEPTED BUILD / REUSED EXACT FROZEN SIGNED PRODUCT`；独立 External Restore Targeted 为 `NOT RUN — ACCEPTED CURRENT-SOURCE 1/1 PASS AFTER EXACT SOURCE/PRODUCT VERIFICATION`。均不替代当前 Gate。

本轮未启动业务 App/fixture，Executor 发起 live Provider/Credential/Keychain/Market Cache 操作为 `0`，Provider requests `NOT RUN`；不宣称全系统或其他进程遥测为零。Local-mode 历史 UI 仅为 temporary-store 隔离证据，不是真实用户 Production Store 验证。Twelve Data persistent writes `Disabled`；Provider retention rights `BLOCKED`；external retention/scheduling/cloud `NOT IMPLEMENTED / NOT AUTHORIZED`；Stages 12–14 `NO-GO`。

文档前完整 116 项和四项产品复核无变化；仅两份授权文档新增本轮事实，保留治理说明与历史失败。无 Repository 新增/删除/重命名，不读取受限目录、default.profraw payload、附件或真实用户数据。最终清单及限定 Markdown/privacy 审计见本轮报告。

## 前轮状态（历史保留）

**Stage 11-APP-CONNECTION-DIAGNOSTIC-CLOSURE-01 PARTIAL — Awaiting Reviewer Gate**

## App Connection Diagnostic Closure — 本轮启动前停止

本轮 evidence root：`/private/tmp/Aureus-Stage11-APP-CONNECTION-DIAGNOSTIC-CLOSURE-01-OMbBhJ`。主 Executor 按指定顺序实际接收并审阅 32 项完整正文至 EOF；逐项记录见 [MandatoryRead.md](/private/tmp/Aureus-Stage11-APP-CONNECTION-DIAGNOSTIC-CLOSURE-01-OMbBhJ/MandatoryRead.md)，不以此追溯修复上一轮 `/dev/null` 阅读缺口。

清单自身 SHA-256 `1693bbe926693b38876398d53ff798ad6c8db210a359a3afc4ab54d38e7440e6`、116 个普通文件及四项冻结产品 Hash 全匹配；路径集合、普通文件类型、symlink 组件和受限目录排除检查通过。三个 executable 均 arm64，Bundle ID 正确；App/Runner strict codesign exit `0/0`，local ad hoc、无 TeamIdentifier，不冒充发行签名。

启动前准确进程检查发现 PID `62705`，PPID `1`，来自 `/private/tmp/Aureus-Stage11-BACKUP-FOUNDATION-01-CgeiqO/UnsignedDerivedData/Build/Products/Debug/Aureus.app/Contents/MacOS/Aureus`。它不是本轮冻结产品；其当前用途/运行归属未确认。执行前置条件为 `BLOCKED`，未终止或操作此进程，未启动 Gate A。没有真实 Automation/Accessibility 权限提示证据，不称为 `USER TAKEOVER REQUIRED`。

| Gate | 本轮状态 | 执行元数据 |
|---|---|---|
| A Ledger Dynamic diagnostic | NOT RUN | invocation 0；业务执行 0；exit/counts/duration/result/Info.plist/parsers 不适用，未生成 bundle |
| B Existing focused 12/12 | NOT RUN | A 未通过；invocation 0；未构造 aggregate |
| C Full AureusUITests 18/18 | NOT RUN | B 未通过；invocation 0；未使用历史结果替代 |

执行 wrapper 已通过 `apply_patch` 创建在 evidence root，设计为直接日志重定向、同进程立即捕获数字退出码并保存独立 marker；但没有运行任何 Gate wrapper，所以没有新 exit-code marker，也没有本轮实际退出码证据。Source/business repair、business retry、infrastructure retry、incomplete re-observation、build/sign 均为 `0`。

四个历史实际 bundle 重新顺序 canonical parsing 成功，Info.plist 均存在：Clean/BFT succeeded；Targeted `1/1`、`1/0/0 PASS`；Existing `12/12`、`0/12/0 FAIL`。历史 Existing 数字退出码仍为 `NOT VERIFIED`。Ledger 首项约 178 秒业务执行后在清除筛选后的 `ledger.filter.tag` 查询失去 PID `59940` 连接；后续十一项在 `launchApp` 的 pre-launch residual-panel 查询处连锁失败。首次断连原因仍为 `UNKNOWN`，不能归因于 Restore、Provider 或 QoS warning。本轮未执行，不能称为“本轮未复现”或“根因已修复”。

Unit/Performance 均为 `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION`：Focused `134/168 PASS`、Affected `167/205 PASS`、Full `460/531 PASS`、External Restore Release `25/49 PASS`（10,000 rows，43 ms）、External Export Release `29/31 PASS`（10,000 rows，26 ms）。Clean/BFT 为 `NOT RUN — ACCEPTED BUILD / REUSED EXACT FROZEN SIGNED PRODUCT`；独立 External Restore Targeted 为 `NOT RUN — ACCEPTED CURRENT-SOURCE 1/1 PASS AFTER EXACT SOURCE/PRODUCT VERIFICATION`。继承的 Local-mode 隔离验证仅针对 XCTest temporary store，不涉及真实用户 Production Store。

停止后、文档更新前 116 项源码及四项产品复核仍全匹配。仅允许两份文档变化，源码、测试、Project、Package、Migration、Entitlements 不变。完整自包含 [ExecutionReport.md](/private/tmp/Aureus-Stage11-APP-CONNECTION-DIAGNOSTIC-CLOSURE-01-OMbBhJ/ExecutionReport.md) 记录逐项 AC、完整 Hash 和审计边界。

Provider requests `NOT RUN`；Twelve Data/Frankfurter/Provider transport、Credential/Keychain/Market Cache live access 为 `0`；persistent writes `Disabled`；retention rights `BLOCKED`；Stages 12–14 `NO-GO`。本轮在启动前停止，不决定 Stage 11 Gate，不生成下一轮 Prompt。以下历史内容原样保留。

## External Backup Export Foundation round

Prompt 11-EXTERNAL-BACKUP-EXPORT-FOUNDATION-01 adds an explicitly invoked, no-UI external export foundation. It accepts only a generation that passes the existing configured internal Backup-root validation, then exports the byte-identical `aureus.sqlite` and `manifest.json` pair into an operation-scoped caller-injected destination. The destination must be an existing writable absolute file directory, must resolve without symbolic links, and must not overlap the Repository, internal Backup root, Permanent database location, or Market Cache location. The service neither stores the destination nor creates a security-scoped bookmark.

Export uses a unique direct-child staging directory, copies only the two generation files, runs the authoritative streaming SHA-256, byte-count, SQLite query-only quick-check, foreign-key, schema, manifest, file-type, symlink, and exact-artifact validation, then commits by same-filesystem atomic move and validates the committed generation again. Collision never overwrites. Failure cleanup is limited to the operation-owned staging directory; unrelated destination siblings and existing external generations remain untouched. External retention/pruning is not implemented or run, while internal five-generation retention and internal Restore's direct-child root restriction remain unchanged.

The exported artifact is not a ZIP, compressed archive, encrypted wrapper, or new manifest format. It contains no third metadata file and makes no application-layer encryption claim. Settings external file UI, `NSOpenPanel`/`NSSavePanel`, security-scoped access/bookmarks, destination persistence, external Restore/import, raw SQLite import, cloud export, scheduled export, and Stages 12–14 remain outside this round.

Current evidence root: `/private/tmp/Aureus-Stage11-EXTERNAL-BACKUP-EXPORT-FOUNDATION-01-1ngtiQ`.

| Verification | Result | Evidence |
|---|---|---|
| Historical UI/build evidence | `NOT RUN — ACCEPTED HISTORICAL CURRENT-SOURCE EVIDENCE` | Read-only canonical parsing confirmed prior Native CSV `1/1`, Existing focused `10/10`, and full `AureusUITests` `16/16` PASS plus successful Clean Build/BFT; these results were not rerun or counted as this round's UI evidence |
| Initial signed Focused Unit | `INFRASTRUCTURE FAILURE` | Shell exit `65`; complete `FocusedUnit-Signed.xcresult`; `Info.plist` present; summary/tests parser exits `0/0`; `57` definitions / `59` executions; App Sandbox denied the known `/private/tmp/AureusTests/<UUID>` roots, so `0` business tests passed and this result is not a business PASS |
| Final Focused Unit | `PASS` | Exact suites `PermanentBackupExportTests` and `PermanentBackupTests`; stable unsigned isolated-host route; shell exit `0`; `57` definitions / `59` dynamic executions; `57` passed / `0` failed / `0` skipped; result interval `9.238 s`; complete `FocusedUnit-Unsigned-Final3.xcresult`; `Info.plist` present; summary/tests parser exits `0/0` |
| Affected regression | `PASS` | Exact suites `PermanentBackupExportTests`, `PermanentBackupTests`, `PermanentRestoreTests`, `PermanentMigrationSafetyTests`, `SettingsDataLifecycleTests`, and `PersistenceTests`; shell exit `0`; `130` definitions / `140` dynamic executions; `130/0/0`; result interval `42.203 s`; complete `AffectedRegression-Unsigned.xcresult`; `Info.plist` present; parser exits `0/0` |
| Full Unit | `PASS` | Exact selector `AureusTests`; shell exit `0`; `423` definitions / `466` dynamic executions; `423/0/0`; result interval `84.172 s`; complete `FullAureusTests-Unsigned.xcresult`; `Info.plist` present; parser exits `0/0` |
| Release Export suite | `PASS` | Exact suite `PermanentBackupExportTests`; Release-oriented testability-enabled isolated host; shell exit `0`; `29` definitions / `31` dynamic executions; `29/0/0`; complete `ReleaseExportPerformance-Unsigned.xcresult`; `Info.plist` present; parser exits `0/0`; total result interval `132.010 s`, including build |
| Release workload | `PASS` | `STAGE11_EXTERNAL_BACKUP_EXPORT_PERF rows=10000 export_validate_ms=25 exported_files=2 provider_requests=0 cache_reads=0 credential_reads=0` |
| Clean Debug arm64 Build | `PASS` | Shell exit `0`; status succeeded; errors `0`; four existing `PortfolioView` deprecation warnings; duration `29.344 s`; complete `CleanDebugBuild.xcresult`; `Info.plist` present; build parser exit `0` |
| Fresh signed arm64 BFT | `PASS` | Shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four existing warnings; duration `39.588 s`; complete `BuildForTesting.xcresult`; `Info.plist` present; build parser exit `0`; App and Runner strict codesign exits `0` |
| UI tests | `NOT RUN — NOT AUTHORIZED IN EXTERNAL BACKUP EXPORT FOUNDATION ROUND` | BFT and the accepted prior `16/16` UI bundle are not this round's UI runtime execution |

The stable unsigned route was authorized only after the complete signed result proved the established App Sandbox test-root policy. Three preserved implementation-diagnostic bundles then exposed, in order, destination canonicalization, staging-name validation, and Market Cache parent protection defects. Each was corrected only in the authorized Export/Backup/Test paths. The final current source was rerun through every required Gate; no failed bundle was merged with a later result or reported as PASS. No parser-triggered test retry occurred.

### External Export provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- Settings external file UI: `NOT RUN`
- External Restore/import: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

## Current External Backup Export Foundation status

**Stage 11 External Backup Export Foundation Candidate — Awaiting Reviewer Gate**

## Settings internal data-lifecycle UI round

The Reviewer accepted Backup Foundation, Restore Foundation, and Migration Safety as `PASS` before authorizing this bounded Settings round. Their manifest, validation, retention, replacement, rollback, recovery-required, migration, schema-version-6, and Provider-isolation contracts remain byte-identical.

Settings now presents one native internal-only data-lifecycle section driven by a separate `SettingsDataLifecycleModel`. Initial load and reconstruction only inventory validated generations under the injected internal Backup root. `Create Backup` is explicit; selecting a visible valid generation enables `Restore Selected Backup`; Restore requires native confirmation, revalidates the candidate, delegates to the existing Restore foundation, and reloads inventory. Ordinary failures and `recoveryRequired` are finite and independently accessible. Invalid or unknown siblings are counted only as ignored diagnostics and are never selectable or deleted. No arbitrary path, raw SQLite, external import/export, `NSOpenPanel`, security-scoped bookmark, automatic schedule, Provider, Credential, Keychain, or Market Cache dependency was added.

`AppDependencies` and `AppShellView` inject the existing `WealthStore`, the environment-specific internal Backup root, normalized app version, and generation identity dependency. Production and Synthetic/temporary roots remain isolated. The Project adds only the Production membership for `SettingsDataLifecycleModel.swift` and the Unit membership for `SettingsDataLifecycleTests.swift`.

### Settings round verification evidence

Final evidence is rooted at `/private/tmp/Aureus-Stage11-SETTINGS-DATA-LIFECYCLE-UI-01-SbVnOZ`.

| Verification | Result | Evidence |
|---|---|---|
| Focused lifecycle/Backup/Restore/Migration Unit | `PASS` | Exact five suites; `101` definitions / `109` dynamic executions; `109` passed, `0` failed, `0` skipped; final unsigned isolated-host shell exit `0`; complete `FocusedUnit-Unsigned-AfterRepair.xcresult`; summary/tests parser exits `0/0`; signed-host permission failure retained separately |
| Full `AureusTests` | `PASS` | `394` definitions / `435` dynamic executions; `435` passed, `0` failed, `0` skipped; final unsigned isolated-host shell exit `0`; complete `FullAureusTests-Unsigned-AfterRepair.xcresult`; parser exits `0/0`; signed-host permission failure retained separately |
| Performance | `NOT RUN — INHERITED AFTER EXACT FOUNDATION SOURCE-HASH VERIFICATION` | Accepted Backup, Restore, and Migration Safety Release workloads remain unchanged; this is not a current-round execution |
| Clean Debug arm64 Build | `PASS` | shell exit `0`; status succeeded; errors `0`; four pre-existing `PortfolioView` warnings; complete `CleanDebugBuild-Final.xcresult`; parser exit `0` |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; status succeeded; errors `0`; four pre-existing warnings; complete `BuildForTesting-Final.xcresult`; parser exit `0`; App and Runner strict codesign exit `0` |
| Targeted Settings UI initial | `FAIL` | `1/1` business execution, `0` passed / `1` failed / `0` skipped; complete `Stage11SettingsTargetedUI.xcresult`; the XCTest identifier shortcut rejected the 149-character confirmation text at `AureusUITests.swift:1336` |
| Targeted Settings UI final | `FAIL` | `1/1` business execution, `0` passed / `1` failed / `0` skipped; complete `Stage11SettingsTargetedUI-Final.xcresult`; Backup creation, Goal probe, inventory reload, selection, and Restore-button lifecycle passed before the exact warning `StaticText` was not found at `AureusUITests.swift:1340` |
| Existing focused regression | `NOT RUN` | Gate prerequisite failed; no business repair or retry authorized after the final Targeted UI execution |
| Full `AureusUITests` | `NOT RUN` | Existing focused Gate was not reached |

The first complete targeted business failure authorized one direct UI-test lifecycle repair: the full confirmation warning moved from XCTest's length-limited identifier subscript to an exact `label ==` predicate without weakening its text. The prompt-required focused Unit, full Unit, Clean Build, BFT, and targeted UI sequence was then repeated on final source. The final targeted failure exhausted the two-business-execution budget, so no third run or second repair was performed. Infrastructure retry and incomplete-result re-observation were both `0`.

### Settings round provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- External Backup/import/export: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

All test records and internal generations were synthetic and isolated under `/private/tmp`. The remaining runtime boundary is the native confirmation dialog's independent exact-label exposure; it is not a Backup, Restore, migration, Persistence, Provider, or test-discovery failure.

## Current Settings UI round status

**Stage 11-SETTINGS-DATA-LIFECYCLE-UI-01 PARTIAL — Awaiting Reviewer Gate**

Stage 10 and the Stage 11 Backup and Restore Foundations have independent Reviewer `PASS` decisions. This document preserves those bounded rounds and records the current no-UI Permanent Migration Safety candidate. It does not declare Stage 11 `PASS`, Restore UI Ready, V1 Ready, Release Ready, or entry to Stages 12–14.

## Scope

The foundation provides:

- a Production internal Backup root at `Application Support/Aureus/Backups/` formed through Foundation container APIs;
- an isolated temporary Backup root at `<injected temporary root>/Backups/`;
- consistent SQLite backup within `WealthStore` actor ownership through GRDB;
- a versioned manifest, complete generation validation, inventory, and valid-only five-generation retention;
- synthetic Unit and Release-oriented performance evidence.

It adds no UI, scheduled/background backup, cloud backup, sync, external file panel, migration hook, import/export, or generic file manager abstraction.

## Backup artifact contract

Each committed generation is a direct child of the configured Backup root and contains exactly:

- `aureus.sqlite`
- `manifest.json`

Generation names use UTC time components plus a random identity and contain no account, Goal, Portfolio, amount, user-path, or other business value. Staging is operation-specific and is atomically moved into its final generation only after complete validation. SQLite WAL/SHM sidecars, Market Cache, Provider data, Credential/Keychain data, UserDefaults, logs, temporary imports, exports, chart assets, and Repository files are excluded.

## Manifest schema

The stable sorted-key JSON manifest has exactly these fields:

| Field | Contract |
|---|---|
| `backupFormatVersion` | Fixed at `1` |
| `appVersion` | Explicitly supplied by the caller |
| `schemaVersion` | Read from the completed backup database |
| `createdAt` | UTC date representation |
| `databaseByteCount` | Exact final database byte count |
| `databaseSHA256` | Lowercase streaming SHA-256 |

The manifest contains no absolute path, record count, financial summary, account, symbol, Goal, Portfolio, Provider, Credential, or device identity. It makes no application-layer encryption claim; V1 relies on macOS and user-storage protection.

## Consistent backup and validation

The source is never copied as a live ordinary file. `WealthStore` passes its owned GRDB source connection to SQLite's consistent backup operation, closes the destination connection, hashes the finalized standalone database in bounded chunks, writes the manifest, validates staging, atomically commits, validates the committed generation again, and only then applies retention.

Validation independently requires:

- a safe direct-child generation path and rejection of symbolic links;
- regular `aureus.sqlite` and `manifest.json` files with no extra artifact or sidecar;
- decodable format-version-1 manifest with exact byte count and SHA-256;
- read-only SQLite open with `PRAGMA query_only = ON`;
- successful `PRAGMA quick_check`;
- zero `PRAGMA foreign_key_check` violations;
- permanent schema metadata matching the manifest without migration.

Finite typed errors distinguish unsafe paths, symbolic links, missing/malformed/unsupported manifests, missing databases, unexpected artifacts, byte-count/hash mismatches, database/integrity failures, foreign-key failures, schema mismatches, consistent-backup failures, and retention failures. Diagnostics do not expose rows, credentials, or user paths.

## Five-generation retention

Only valid generations count toward retention. They are ordered by manifest UTC creation time and then stable generation identity. Pruning starts only after the new committed generation passes a second validation and removes only older, valid, strict-pattern direct children of the configured root until five remain. A failed new generation leaves the existing five valid generations unchanged. Invalid and unknown siblings are diagnosed but neither counted nor automatically deleted.

## Isolation and source integrity

Synthetic tests establish that committed permanent records appear in the backup, later source mutation does not alter an older generation, and backup creation does not mutate the source schema or records. Adjacent Market Cache and key-like sentinels remain unchanged and absent from generations. The implementation has no Provider, Credential, Keychain, or Market Cache dependency.

## Backup Foundation round: Restore and migration boundary

**Restore: NOT IMPLEMENTED / NOT AUTHORIZED IN THIS FOUNDATION ROUND.**

No permanent database replacement, safety restore, rollback, maintenance mode, user-selected restore, old-schema import, pre-migration backup hook, or migration is implemented. Permanent schema version remains `6`; all migration identifiers and the cache schema remain unchanged. Validation does not imply Restore readiness.

This statement is retained as the historical boundary of Prompt 11-BACKUP-FOUNDATION-01. The Reviewer subsequently accepted that Backup Foundation and separately authorized the bounded no-UI Restore Foundation recorded below.

## Verification evidence

Final current-source artifacts are rooted at `/private/tmp/Aureus-Stage11-BACKUP-FOUNDATION-01-CgeiqO`.

| Verification | Result | Evidence |
|---|---|---|
| Focused Unit | `PASS` | Exact suites `PermanentBackupTests` and `PersistenceTests`; `34/34` definitions/executions; `34` passed, `0` failed, `0` skipped; shell exit `0`; complete `FocusedUnit-Final.xcresult`; summary/tests parser exits `0/0` |
| Full `AureusTests` | `PASS` | `327` definitions / `360` dynamic executions; `327` passed, `0` failed, `0` skipped; shell exit `0`; complete `FullAureusTests-Final.xcresult`; summary/tests parser exits `0/0` |
| Release backup suite | `PASS` | `28/28`; the real 10,000-row workload entered and emitted `STAGE11_BACKUP_PERF rows=10000 create_validate_ms=16 provider_requests=0 cache_reads=0 credential_reads=0`; measured create plus validate `16 ms`, below 10 seconds |
| Clean Debug arm64 Build | `PASS` | shell exit `0`; status succeeded; errors `0`; four pre-existing `PortfolioView` deprecation warnings; complete `CleanDebugBuild-Final.xcresult` |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four pre-existing warnings; complete `BuildForTesting-Final.xcresult`; App and Runner strict codesign verification passed |
| UI tests | `NOT RUN — NOT AUTHORIZED IN BACKUP FOUNDATION ROUND` | A signed BFT is build evidence, not UI execution |

The signed Unit host's proven App Sandbox rejection of `/private/tmp/AureusTests/<UUID>` is preserved as infrastructure evidence. The prompt-authorized stable unsigned isolated host ran the same final source, selectors, and assertions for both final Unit gates. Earlier compile, source-candidate, zero-test discovery, and failed diagnostic bundles remain failures or diagnostics and are not counted as PASS. The first Release attempt did not enter the workload because Release omitted testability; the final equivalent Release suite used command-line `ENABLE_TESTABILITY=YES` without changing Project settings.

Every retained result bundle contains `Info.plist`. A final read-only audit preserved sandbox TestReport-cache parser exits `64` for the non-final test bundles and then parsed each same bundle under standard Xcode permissions with exit `0`; no test was rerun for parser recovery. All five final Gate bundles parsed directly with exit `0` in the final evidence path.

## Performance boundary

The Release-oriented suite created at least 10,000 synthetic permanent rows, performed a real consistent backup, streaming SHA-256, manifest generation, SQLite integrity, foreign-key, and schema validation, and verified unchanged source sentinels. The `16 ms` result is current-host evidence only, not a cross-device guarantee. Provider requests, Market Cache reads/mutations, and Credential/Keychain reads were zero.

## Provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Retention: `BLOCKED`
- Stages 12–14: `NO-GO`

All fixtures are synthetic or sanitized. No Repository database, backup generation, Provider payload, Credential, or real financial record was created.

## Known issues and limitations

- Backup creation is not yet wired to Settings or scheduling.
- Restore UI, external import/export, arbitrary/user-selected paths, startup migration hooks, and automatic Restore remain unimplemented and unauthorized.
- Backup artifacts are not claimed to have application-layer encryption.
- Four pre-existing `PortfolioView` string-interpolation deprecation warnings remain; this round added no warning.
- The Mandatory Read prompt named the absent path `Aureus/Domain/Values/TimeValues.swift`; the canonical existing file `Aureus/Domain/Time/TimeValues.swift` was read to EOF, and no path was invented or changed.

## Backup Foundation Reviewer decision

The Reviewer accepted the prior Backup Foundation evidence as `PASS`. The accepted contract remains unchanged: each valid generation contains only `aureus.sqlite` and `manifest.json`, uses streaming SHA-256 and exact byte count, passes SQLite/foreign-key/schema validation, and participates in valid-only five-generation retention. The accepted Backup implementation, `RuntimePaths`, manifest schema, migration source, and schema version `6` remain unchanged in this Restore round.

## Restore Foundation candidate

The internal Restore service accepts only a format-version-1 generation that is a validated direct child of the configured Backup root. Raw SQLite files, arbitrary/external paths, symlinks, live databases, Market Cache files, WAL/SHM sidecars, archives, and future schema versions are rejected before Permanent Store replacement. The selected Backup generation and manifest are never migrated or modified.

Before replacement, the service copies the closed validated candidate into an operation-owned staging file beside the live `aureus.sqlite`, recomputes its streaming byte count and SHA-256, and repeats read-only integrity, foreign-key, and schema validation. It then creates and validates an internal safety generation from the current actor-owned GRDB queue. A safety failure leaves the live queue and database unchanged.

`WealthStore` owns a finite `ready` / `restoring` / `recoveryRequired` maintenance state and a mutable actor-isolated queue. From queue close until a restored or rolled-back queue is rebound, the synchronous actor method contains no suspension point. It checkpoints the live Store, closes the queue, handles only the explicit live database and sidecar paths, and uses same-filesystem atomic replacement without deleting the current database first.

Current-schema candidates reopen without business-data rewriting. Supported legacy schema versions `1...5` run only through the existing `DatabaseMigrations.permanentMigrator()` after replacement; the Backup artifact itself remains untouched. Post-restore validation requires `quick_check`, zero foreign-key violations, permanent schema version `6`, all six existing migration identifiers, required permanent tables, reopen success, and continued reads through the same `WealthStore` actor.

Any open, migration, integrity, foreign-key, schema, or application-invariant failure after replacement triggers rollback from the validated safety generation through a separately revalidated same-filesystem staging file and atomic replacement. Successful rollback rebinds the original Store and returns typed `restoreFailedRollbackSucceeded`. If rollback itself fails, the actor enters `recoveryRequired`, returns typed `rollbackFailed`, retains the safety generation, and performs no automatic alternate-generation loop.

Successful Restore retains the safety generation and then restores valid-only retention to at most five generations. Failed Restore does not prune the safety generation required for recovery. Cleanup is limited to operation-owned, exact staging and sidecar paths whose ownership and parent are verified.

## Restore verification evidence

Final current-source evidence is rooted at `/private/tmp/Aureus-Stage11-RESTORE-FOUNDATION-01-xtAUHU`.

| Verification | Result | Evidence |
|---|---|---|
| Focused Restore/Backup Unit | `PASS` | Exact suites `PermanentRestoreTests`, `PermanentBackupTests`, and `PersistenceTests`; `60` definitions / `64` dynamic executions; `64` passed, `0` failed, `0` skipped; shell exit `0`; complete `FocusedRestoreBackupUnit.xcresult`; summary/tests parser exits `0/0`; result interval `5.701 s` |
| Affected persistence regression | `PASS` | Exact suites `WealthPersistenceTests`, `LedgerPersistenceTests`, `DashboardPersistenceTests`, `PortfolioTerminalTests`, and `GoalPersistenceTests`; `65` definitions / `68` dynamic executions; `68` passed, `0` failed, `0` skipped; shell exit `0`; complete `AffectedPersistenceRegression.xcresult`; parser exits `0/0`; result interval `9.079 s` |
| Full `AureusTests` | `PASS` | `353` definitions / `390` dynamic executions; `390` passed, `0` failed, `0` skipped; shell exit `0`; complete `FullAureusTests.xcresult`; parser exits `0/0`; result interval `47.624 s` |
| Release Restore suite | `PASS` | `26` definitions / `30` dynamic executions; `30` passed, `0` failed, `0` skipped; shell exit `0`; complete `ReleaseRestorePerformance-Final.xcresult`; parser exits `0/0`; real workload emitted `STAGE11_RESTORE_PERF rows=10000 safety_backup_restore_validate_ms=63 migration_applied=0 provider_requests=0 cache_reads=0 credential_reads=0`; result interval `3.062 s` |
| Clean Debug arm64 Build | `PASS` | shell exit `0`; status succeeded; errors `0`; four pre-existing `PortfolioView` deprecation warnings; complete `CleanDebugBuild.xcresult`; build parser exit `0`; result interval `20.964 s` |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four pre-existing warnings; complete `BuildForTesting.xcresult`; build parser exit `0`; result interval `30.261 s`; App and Runner strict codesign verification passed |
| UI tests | `NOT RUN — NOT AUTHORIZED IN RESTORE FOUNDATION ROUND` | Signed BFT is build evidence only and is not UI runtime evidence |

The initial Release-oriented build failed before test execution because default Release omitted testability; its complete exit-65 result is preserved and was not counted as PASS. The corrected equivalent Release product used command-line `ENABLE_TESTABILITY=YES` without changing Project settings. A subsequent method-level selector produced a complete 0-test/unknown result and likewise was not counted as PASS; the same frozen Release product then ran the complete `PermanentRestoreTests` suite, which entered the 10,000-row workload and produced the final evidence above. No business assertion retry, Provider operation, UI execution, or source adaptation was hidden.

## Restore provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- Restore UI and Settings integration: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

All Restore fixtures and databases are synthetic and isolated below the current `/private/tmp` evidence root. No Repository database, Backup generation, Restore staging file, safety database, Provider payload, Credential, or real financial record was created.

## Current candidate

The historical Restore candidate above was independently accepted by the Reviewer as `PASS`. Its safety-backup, same-filesystem atomic replacement, forward-migration, validation, rollback, and `recoveryRequired` contracts remain unchanged.

## Migration state classification

Permanent Store startup and explicit `WealthStore.migrate()` now use one migration-safety authority built from canonical `DatabaseMigrator` applied identifiers, their stored order, and `schema_metadata`:

- a genuinely fresh Store has no applied permanent migration and no unexplained business schema, creates no pre-migration Backup, and migrates to schema `6`;
- a current Store has all six identifiers in order and schema `6`, creates no Backup, and performs an idempotent no-op followed by validation;
- a recognized legacy Store has a strict non-empty v1...v5 identifier prefix and matching schema `1...5`;
- unknown identifiers, gaps, reorderings, future schema, metadata/schema mismatch, non-permanent metadata, unexplained schema-zero business state, and unsafe/symlink Store paths are typed rejections before migration.

## Production composition-root wiring

`AppDependencies.make` supplies the real `WealthStore` construction path with the selected `RuntimePaths.internalBackupDirectoryURL`, a normalized application version, UTC creation instant, random generation identity, and the existing permanent migrator. Temporary and Synthetic dependency graphs use their injected temporary Backup root. No `WealthStore` legacy migration path, including explicit `migrate()`, can silently bypass this gate. Restore candidate migration remains inside its already validated safety-rollback flow and is not wrapped in a duplicate pre-migration generation.

## Pre-migration Backup and failure boundaries

Each recognized v1...v5 Store creates exactly one consistent format-version-1 generation before any pending migration. The committed generation is revalidated for manifest, streaming SHA-256, byte count, SQLite integrity, foreign keys, original schema, and the exact original migration prefix. Its original synthetic records remain readable. Only after that gate passes does the unchanged `DatabaseMigrations.permanentMigrator()` run.

Backup creation, commit, validation, unsafe-root, collision, or filesystem failure prevents migrator invocation and leaves the live legacy Store unchanged. A migration transaction failure preserves the valid pre-migration generation and reports a finite availability state; no automatic Restore, alternate-generation selection, or loop is performed. A post-migration validation failure likewise retains the pre-migration generation and does not report the Store ready.

## Shared post-migration validation

Backup, Restore, and Migration Safety share one authoritative permanent-database validator. Current-schema validation requires `PRAGMA quick_check == ok`, zero foreign-key violations, schema version `6`, all six identifiers in order, all required permanent tables, successful reads, and no `REAL` financial-authority column. `DatabaseMigrations.swift`, its six identifiers, schema version `6`, Backup manifest fields and retention semantics, and Restore ordering/rollback/recovery behavior remain unchanged.

## Retention and idempotence

Only fully committed and validated generations participate in valid-only five-generation retention. Invalid or unknown siblings remain uncounted and undeleted. A first legacy open creates one generation; reopening or explicitly migrating the now-current Store creates none. Fresh and repeated current Store operations likewise create none. Concurrent construction is serialized so it cannot create a second pre-migration generation.

## Migration Safety verification evidence

Final current-source evidence is rooted at `/private/tmp/Aureus-Stage11-MIGRATION-SAFETY-01-jSZ2Ys`.

| Verification | Result | Evidence |
|---|---|---|
| Focused migration/Backup/Restore Unit | `PASS` | Exact suites `PermanentMigrationSafetyTests`, `PermanentBackupTests`, `PermanentRestoreTests`, `PersistenceTests`, and `PortfolioTerminalTests`; `108` definitions / `116` dynamic executions; `116` passed, `0` failed, `0` skipped; shell exit `0`; complete `FocusedMigrationBackupRestoreUnit-Final.xcresult`; summary/tests parser exits `0/0`; result interval `17.835 s` |
| Affected persistence regression | `PASS` | Exact eight suites; `146` definitions / `157` dynamic executions; `157` passed, `0` failed, `0` skipped; shell exit `0`; complete `AffectedPersistenceRegression.xcresult`; parser exits `0/0`; result interval `13.563 s` |
| Full `AureusTests` | `PASS` | `380` definitions / `421` dynamic executions; `421` passed, `0` failed, `0` skipped; shell exit `0`; complete `FullAureusTests.xcresult`; parser exits `0/0`; result interval `49.070 s` |
| Release migration-safety suite | `PASS` | `27` definitions / `31` dynamic executions; `31` passed, `0` failed, `0` skipped; shell exit `0`; complete `ReleaseMigrationSafetyPerformance.xcresult`; parser exits `0/0`; the 10,000-row workload emitted `STAGE11_MIGRATION_SAFETY_PERF rows=10000 start_schema=1 backup_migrate_validate_ms=35 provider_requests=0 cache_reads=0 credential_reads=0` |
| Clean Debug arm64 Build | `PASS` | shell exit `0`; status succeeded; errors `0`; four pre-existing `PortfolioView` deprecation warnings; complete `CleanDebugBuild.xcresult`; build parser exit `0`; result interval `20.253 s` |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four pre-existing warnings; complete `BuildForTesting.xcresult`; build parser exit `0`; result interval `30.446 s`; App and Runner strict codesign verification passed |
| UI tests | `NOT RUN — NOT AUTHORIZED IN MIGRATION SAFETY ROUND` | BFT is build evidence only; Settings Backup/Restore UI, Existing focused UI, and full `AureusUITests` were not executed |

The initial signed focused Unit result is preserved as an infrastructure failure: its complete bundle discovered all `108` definitions but App Sandbox denied the known `/private/tmp/AureusTests/<UUID>` test roots. The authorized stable unsigned isolated-host route then exposed two direct test-adaptation failures, which were retained; final current source reran the affected Gate and passed. Sandbox TestReport-cache parser attempts returned `64`; the same complete bundles parsed read-only under standard Xcode permissions with exit `0`. No parser recovery reran tests and no failed result was counted as PASS.

## Migration Safety provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- Settings UI and external file flow: `NOT RUN / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

All migration fixtures and databases are synthetic and isolated below the current `/private/tmp` evidence root. No Repository database, Backup generation, migration staging file, Provider payload, Credential, or real financial record was created.

## Current Migration Safety candidate

**Stage 11 Migration Safety Candidate — Awaiting Reviewer Gate**

## Restore confirmation native Accessibility round

Prompt 11-RESTORE-CONFIRMATION-AX-01 replaced only the Restore-specific system-managed `confirmationDialog` with an application-owned native SwiftUI sheet. The existing Delete Key, Disconnect, and Reset Market Cache confirmation dialogs remain unchanged. The sheet exposes four independent visible nodes: `settings.dataLifecycle.restore.dialog.heading`, `settings.dataLifecycle.restore.dialog.warning`, `settings.dataLifecycle.restore.cancel`, and `settings.dataLifecycle.restore.confirm`. The warning's visible text, Accessibility label, and UI-test exact string are identical. Cancel only dismisses the sheet; Confirm dismisses it and invokes the existing confirmed Restore path exactly once. No Foundation, lifecycle model, App wiring, Project, Package, Migration, Entitlement, external-file flow, or Provider path changed.

### Current-round verification

Current evidence is rooted at `/private/tmp/Aureus-Stage11-RESTORE-CONFIRMATION-AX-01-Gn6kSi`.

| Verification | Result | Evidence |
|---|---|---|
| Focused Unit | `NOT RUN — INHERITED AFTER EXACT MODEL/FOUNDATION/UNIT SOURCE-HASH VERIFICATION` | Accepted current-source evidence remains `101` definitions / `109` dynamic executions PASS |
| Full Unit | `NOT RUN — INHERITED AFTER EXACT MODEL/FOUNDATION/UNIT SOURCE-HASH VERIFICATION` | Accepted current-source evidence remains `394` definitions / `435` dynamic executions PASS |
| Performance | `NOT RUN — INHERITED AFTER EXACT BACKUP/RESTORE/MIGRATION-SAFETY SOURCE-HASH VERIFICATION` | Backup, Restore, and Migration Safety authorities remained byte-identical |
| Clean Debug arm64 Build | `PASS` | Final shell exit `0`; status succeeded; errors `0`; four pre-existing `PortfolioView` warnings and no new warning; complete `CleanDebugBuild-Final.xcresult`; `Info.plist` present; build parser exit `0`; result interval `33.283 s` |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four pre-existing warnings; complete `BuildForTesting.xcresult`; `Info.plist` present; build parser exit `0`; result interval `34.694 s`; App and Runner strict codesign verification passed |
| Targeted Settings UI | `PASS` | Exact selector `testStage11SettingsInternalBackupRestoreLifecycleAndIsolation`; `1/1` definition/execution and one business execution; `1` passed / `0` failed / `0` skipped; shell exit `0`; complete `Stage11RestoreConfirmationTargetedUI.xcresult`; `Info.plist` present; initial sandbox TestReport parser exits `64/64`, same-bundle standard-permission parser exits `0/0`; method duration `107.337 s` |
| Existing focused regression | `INCOMPLETE RESULT — NOT PASS` | Exact ten selectors used the same frozen product. The command session was externally interrupted and `ExistingFocusedRegression.xcresult` contains only `Data`/`Staging` without `Info.plist`; before interruption, complete business assertions failed in `testLedgerDynamicCashFlowTransferInvestmentEditAndDelete` at line `1968`, `testLedgerNativeCSVImportPreviewConfirmationAndExport` at line `2439`, and `testStage8PortfolioSyntheticCRUDHoldingsSnapshotAndIsolation` at line `235`. Because completed business failures exist, the result is ineligible for incomplete-result re-observation and is not reported as a canonical aggregate PASS or FAIL count. |
| Full `AureusUITests` | `NOT RUN` | Existing focused did not pass; ordered Gate prerequisite was not met |

The targeted runtime proved the exact heading and warning, the independently enabled Cancel and Confirm controls, Cancel dismissal of all four sheet nodes with inventory still at one and status still Ready, re-open and fresh element queries, one Confirm click, inventory growth to two valid generations, `Restore Completed`, absence of recovery-required/error state, disappearance of the probe Goal, restoration of both original Synthetic Goals, Settings reconstruction, and Production root isolation. Provider, Credential, Keychain, and Market Cache operations remained zero in the test's tail.

The initial Clean command used conflicting architecture specification and exited `70` before compilation; that configuration artifact is preserved as `CleanDebugBuild.xcresult` and is not counted as PASS. The corrected final Clean and BFT used final source. UI infrastructure retry, targeted business repair/retry, and parser-triggered test retry were all `0`. The externally interrupted Existing focused result consumed no re-observation because its completed business failures make it ineligible under the prompt.

### Current-round provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- External file flow: `NOT RUN`
- Stages 12–14: `NO-GO`

No Restore, Backup, safety, database, DerivedData, or xcresult artifact was written into the Repository. The remaining Gate boundary is the incomplete and business-failing Existing focused regression; Full UI is therefore not current-round evidence.

## Current Restore confirmation round status

**Stage 11-RESTORE-CONFIRMATION-AX-01 PARTIAL — Awaiting Reviewer Gate**

## Existing UI independent re-observation round

Prompt 11-EXISTING-UI-REOBSERVATION-01 made no Product, Test, Project, Package, Migration, Entitlement, Target, Scheme, or fixture change. It reused the exact frozen current-source signed UI product after all required source and product hashes matched. The prior `ExistingFocusedRegression.xcresult` remains preserved and classified as `INCOMPLETE RESULT — NOT PASS / NOT VERIFIED`: it has no `Info.plist`, no canonical definitions/executions, and no canonical passed/failed/skipped aggregate. Its console observations were not combined into a result or used as a business-failure count.

Current evidence is rooted at `/private/tmp/Aureus-Stage11-EXISTING-UI-REOBSERVATION-01-APiInh`.

| Verification | Result | Evidence |
|---|---|---|
| Targeted Settings UI | `NOT RUN — ACCEPTED CURRENT-SOURCE 1/1 PASS AFTER EXACT SOURCE/PRODUCT VERIFICATION` | The accepted complete targeted bundle and the frozen App, Runner, UI Test executable, and xctestrun identities matched |
| Focused Unit | `NOT RUN — INHERITED AFTER EXACT MODEL/FOUNDATION/UNIT SOURCE-HASH VERIFICATION` | Accepted `101` definitions / `109` dynamic executions PASS |
| Full Unit | `NOT RUN — INHERITED AFTER EXACT MODEL/FOUNDATION/UNIT SOURCE-HASH VERIFICATION` | Accepted `394` definitions / `435` dynamic executions PASS |
| Performance | `NOT RUN — INHERITED AFTER EXACT BACKUP/RESTORE/MIGRATION-SAFETY SOURCE-HASH VERIFICATION` | Backup, Restore, and Migration Safety authorities remained byte-identical |
| Clean Build | `NOT RUN — ACCEPTED CURRENT-SOURCE BUILD AFTER EXACT SOURCE/PRODUCT VERIFICATION` | No rebuild was authorized or performed |
| BFT | `NOT RUN — REUSED EXACT FROZEN CURRENT-SOURCE PRODUCT` | No rebuild or re-sign was authorized or performed |
| Ledger Dynamic independent selector | `PASS` | Exact selector `testLedgerDynamicCashFlowTransferInvestmentEditAndDelete`; shell exit `0`; `1/1` definition/execution and one business execution; `1` passed / `0` failed / `0` skipped; complete `LedgerDynamic.xcresult`; `Info.plist` present; initial sandbox parser exits `64/64`, same-bundle standard-permission parser exits `0/0`; method duration `229.752 s`; result interval `248.094 s` |
| Native CSV independent selector | `INCOMPLETE RESULT — NOT PASS / NOT VERIFIED` | Exact selector `testLedgerNativeCSVImportPreviewConfirmationAndExport`; shell exit `1` during sandboxed Xcode log/destination initialization before the business method; the new `NativeCSV.xcresult` contains only `Data`/`Staging`, has no `Info.plist`, and cannot provide a canonical result; same-bundle summary/tests parser exits were `64/64` because `Info.plist` is absent. It did not satisfy the complete zero-business bootstrap retry condition or the externally interrupted incomplete-result re-observation condition, so it was not rerun. |
| Portfolio independent selector | `PASS` | Exact selector `testStage8PortfolioSyntheticCRUDHoldingsSnapshotAndIsolation`; shell exit `0`; `1/1` definition/execution and one business execution; `1` passed / `0` failed / `0` skipped; complete `Portfolio.xcresult`; `Info.plist` present; summary/tests parser exits `0/0`; method duration `71.099 s`; result interval `72.300 s` |
| Diagnostic matrix | `PARTIAL` | Ledger Dynamic and Portfolio independently passed, but Native CSV did not produce a canonical result; independent results were not combined into a false aggregate |
| Existing focused regression | `NOT RUN` | Gate A did not close; ordered prerequisite was not met |
| Full `AureusUITests` | `NOT RUN` | Existing focused `10/10` was not run and could not satisfy the prerequisite |

No business retry, business repair, UI infrastructure retry, or incomplete-result re-observation was used. The Native CSV invocation is preserved as an incomplete infrastructure result and is not represented as a business failure or PASS. Provider requests remained `NOT RUN`; Twelve Data operations, Frankfurter live operations, Provider transports, Credential reads, Keychain metadata reads, and Market Cache reads/mutations remained `0`. Twelve Data persistent writes remain `Disabled`, Provider retention rights remain `BLOCKED`, external file implementation remains `NOT RUN`, and Stages 12–14 remain `NO-GO`.

## Current existing UI re-observation status

**Stage 11-EXISTING-UI-REOBSERVATION-01 PARTIAL — Awaiting Reviewer Gate**

## Native CSV standard-permission closure round

Prompt 11-NATIVE-CSV-UI-CLOSURE-01 changed no Product, Unit Test, UI Test, Project, Package, Migration, Entitlement, Target, Scheme, fixture, Backup, Restore, or Migration Safety behavior. The round used the exact frozen signed current-source App, Runner, UI Test executable, and xctestrun. Unlike the preceding sandboxed attempt, the new invocation started directly in the explicitly authorized standard Xcode permission environment.

Current evidence is rooted at `/private/tmp/Aureus-Stage11-NATIVE-CSV-UI-CLOSURE-01-Yey8Vo`.

| Verification | Result | Evidence |
|---|---|---|
| Settings lifecycle targeted UI | `NOT RUN — ACCEPTED CURRENT-SOURCE 1/1 PASS AFTER EXACT SOURCE/PRODUCT VERIFICATION` | Complete historical result remained current after exact source and product verification |
| Ledger Dynamic independent UI | `NOT RUN — ACCEPTED CURRENT-SOURCE 1/1 PASS AFTER EXACT SOURCE/PRODUCT VERIFICATION` | Complete historical result remained current |
| Portfolio independent UI | `NOT RUN — ACCEPTED CURRENT-SOURCE 1/1 PASS AFTER EXACT SOURCE/PRODUCT VERIFICATION` | Complete historical result remained current |
| Focused Unit | `NOT RUN — INHERITED AFTER EXACT MODEL/FOUNDATION/UNIT SOURCE-HASH VERIFICATION` | Accepted `101` definitions / `109` dynamic executions PASS |
| Full Unit | `NOT RUN — INHERITED AFTER EXACT MODEL/FOUNDATION/UNIT SOURCE-HASH VERIFICATION` | Accepted `394` definitions / `435` dynamic executions PASS |
| Performance | `NOT RUN — INHERITED AFTER EXACT BACKUP/RESTORE/MIGRATION-SAFETY SOURCE-HASH VERIFICATION` | Frozen authorities remained byte-identical |
| Clean Build | `NOT RUN — ACCEPTED CURRENT-SOURCE BUILD AFTER EXACT SOURCE/PRODUCT VERIFICATION` | Rebuild was not authorized or performed |
| Signed BFT | `NOT RUN — REUSED EXACT FROZEN CURRENT-SOURCE PRODUCT` | Rebuild and re-sign were not authorized or performed |
| Native CSV Gate | `FAIL` | Exact selector `testLedgerNativeCSVImportPreviewConfirmationAndExport`; shell exit `65`; canonical definitions/executions `1/1`; one business execution; passed/failed/skipped `0/1/0`; method duration `64.016 s`; result interval `76.266 s`; complete `NativeCSV-Standard.xcresult`; `Info.plist` present; standard-permission summary/tests parser exits `0/0`; failure source `AureusUITests.swift:2482` |
| Existing focused regression | `NOT RUN` | Native CSV Gate did not pass; ordered prerequisite was not met |
| Full `AureusUITests` | `NOT RUN` | Existing focused `10/10` was not run and could not satisfy the prerequisite |

The Native CSV business method successfully entered the existing synthetic file-selection flow, produced and verified the import preview, confirmed the import, verified the imported synthetic expense, invoked export, and opened the native Save Panel. It then produced the complete assertion failure `Save Panel did not expose its current filename field`. This is a canonical business failure rather than a Runner, Automation, testmanagerd, bootstrap, discovery, or parser failure. No business repair, business retry, infrastructure retry, or incomplete-result re-observation was authorized or used.

The preceding sandboxed Native CSV directory remains preserved as `INCOMPLETE RESULT — NOT PASS / NOT VERIFIED`. Its short staging diagnostics identify a pre-business `com.apple.testmanagerd.control` sandbox restriction and Runner PID `0`; it was not modified, completed, deleted, combined, or substituted for the current complete result.

Provider requests remained `NOT RUN`; Twelve Data operations, Frankfurter live operations, Provider transports, Credential reads, Keychain metadata reads, and Market Cache reads/mutations remained `0`. Twelve Data persistent writes remain `Disabled`, Provider retention rights remain `BLOCKED`, external file implementation remains `NOT RUN`, and Stages 12–14 remain `NO-GO`.

## Current Native CSV closure status

**Stage 11-NATIVE-CSV-UI-CLOSURE-01 PARTIAL — Awaiting Reviewer Gate**

## Native CSV public-default-filename Save Panel round

Prompt 11-NATIVE-CSV-SAVE-PANEL-01 changed only the authorized UI test before formal Gate execution. The repaired Native CSV helper preserves the Product's public `defaultFilename: "Aureus-Ledger-V1"` contract, verifies that `Aureus-Ledger-V1.csv` does not exist before export, follows the existing Go To Folder flow, re-queries the active Save Panel after that sheet closes, requires the current `OKButton` to exist and be enabled, clicks it exactly once, waits for the Save Panel to disappear, and verifies the exact exported file. Product and Test references to Apple's internal `saveAsNameTextField` are now zero. No Product Swift, Unit test, Project, Package, Migration, Entitlement, Target, Scheme, fixture, Backup, Restore, Migration Safety, Settings, Goals, Portfolio, Markets, or Analytics behavior changed.

Current evidence is rooted at `/private/tmp/Aureus-Stage11-NATIVE-CSV-SAVE-PANEL-01-R7vbvB`.

| Verification | Result | Evidence |
|---|---|---|
| Focused Unit | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Domain, Persistence, FeatureModel, and Unit sources remained frozen |
| Full Unit | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted current-source Unit evidence remained applicable |
| Performance | `NOT RUN — INHERITED AFTER EXACT FOUNDATION SOURCE-HASH VERIFICATION` | Backup, Restore, and Migration Safety authorities remained frozen |
| Clean Debug arm64 Build | `PASS` | Shell exit `0`; result `Succeeded`; errors `0`; four existing `PortfolioView` deprecation warnings; duration `31.783 s`; complete `CleanDebugBuild.xcresult`; `Info.plist` present; final build parser exit `0` |
| Fresh signed arm64 BFT | `PASS` | Shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four existing warnings; duration `34.641 s`; complete `BuildForTesting.xcresult`; `Info.plist` present; build parser exit `0`; App and Runner strict codesign exit `0` |
| Native CSV targeted UI | `PASS` | Exact selector `testLedgerNativeCSVImportPreviewConfirmationAndExport`; shell exit `0`; definitions/executions `1/1`; one business execution; passed/failed/skipped `1/0/0`; method duration `55.340 s`; result interval `63.758 s`; complete `NativeCSVTargetedUI.xcresult`; `Info.plist` present; summary/tests parser exits `0/0` |
| Existing focused regression | `PASS` | Ten exact selectors in one serial invocation; shell exit `0`; definitions/executions `10/10`; ten business executions; passed/failed/skipped `10/0/0`; result interval `1033.251 s`; complete `ExistingFocusedRegression.xcresult`; `Info.plist` present; summary/tests parser exits `0/0` |
| Full `AureusUITests` | `PASS` | Exact selector `AureusUITests`; shell exit `0`; definitions/executions `16/16`; sixteen business executions; passed/failed/skipped `16/0/0`; all sixteen canonical Test Case nodes `Passed`; method aggregate `1165.334 s`; result interval `1178.296 s`; complete `FullAureusUITests.xcresult`; `Info.plist` present; tests parser exit `0`; summary parser initial concurrent-cache exit `64`, same-bundle sequential read-only reparse exit `0` |

All UI invocations used one frozen signed product with parallel testing disabled and maximum concurrent destination `1`. The final product identities are App `6af5d12fd5c49c2de82c6bc0a09024efae07a4d1c223fa4fb3ffff38bda94d66`, Runner `253d63c1ca59775d09a518862becf045df5decc3d7a8e78034807575aece58b8`, UI Test executable `1c57bd87815675a7bccd14f8af4ff73db9edb293dd7b6022475aae6ec1e6b98c`, and xctestrun `6c48af20976451375d9329674d1ad2dc9b0f0c2051931f1f245bdb7c62dc7c43`. Their hashes remained unchanged across all three UI Gates. The same-bundle parser re-read did not rerun any test.

The preceding complete Native CSV Save Panel assertion failure and the earlier incomplete sandboxed Native CSV result remain historical facts; neither was modified, merged, downgraded, or substituted. This round used exactly one pre-Gate UI-test repair. After formal Gate execution began, business repair, business retry, infrastructure retry, and incomplete-result re-observation were all `0`.

Provider requests remained `NOT RUN`; Twelve Data operations, Frankfurter operations, Provider transports, Credential reads, Keychain metadata reads, and Market Cache reads/mutations remained `0`. Twelve Data persistent writes remain `Disabled`, Provider retention rights remain `BLOCKED`, external file implementation remains `NOT RUN`, and Stages 12–14 remain `NO-GO`.

## Current Data Lifecycle UI runtime status

**Stage 11 Data Lifecycle UI Runtime Candidate — Awaiting Reviewer Gate**

## Settings external Backup Export UI round

Prompt 11-SETTINGS-EXTERNAL-BACKUP-EXPORT-UI-01 connects the accepted no-UI external Export foundation to the existing Settings data-lifecycle model and view. The Production composition root supplies the real Permanent, internal Backup, and Market Cache paths without deriving a source-checkout path. Settings uses SwiftUI `.fileImporter` with `.folder`, starts security-scoped access immediately after selection, holds it across the asynchronous export, and stops it on every completed path. The model retains no destination URL, filename history, or bookmark. The visible External Backup warning and its AX label are identical; the heading, warning, Export button, and result are independent nodes. External Restore/import, scheduling, cloud export, external retention, ZIP/compression, and application-layer encryption remain unimplemented.

Current evidence is rooted at `/private/tmp/Aureus-Stage11-SETTINGS-EXTERNAL-BACKUP-EXPORT-UI-01-ayEbIL`.

| Verification | Result | Evidence |
|---|---|---|
| Focused Unit | `PASS` | Final-source stable unsigned isolated-host route; exact suites `SettingsDataLifecycleTests`, `PermanentBackupExportTests`, and `PermanentBackupTests`; shell exit `0`; `77` definitions / `79` dynamic executions; `77` passed / `0` failed / `0` skipped; complete `FocusedUnit-Final.xcresult`; `Info.plist` present; summary/tests parsers `0/0`; result interval `41.920 s` |
| Affected regression | `PASS` | Six exact suites; shell exit `0`; `136` definitions / `146` dynamic executions; `136/0/0`; complete `AffectedRegression-Final.xcresult`; `Info.plist` present; parsers `0/0`; result interval `7.435 s` |
| Full Unit | `PASS` | Exact selector `AureusTests`; shell exit `0`; `429` definitions / `472` dynamic executions; `429/0/0`; complete `FullAureusTests-Final.xcresult`; `Info.plist` present; parsers `0/0`; result interval `50.519 s` |
| Release External Export | `PASS` | Exact suite `PermanentBackupExportTests`; shell exit `0`; `29` definitions / `31` dynamic executions; `29/0/0`; complete `ReleaseExternalExportPerformance-Final.xcresult`; `Info.plist` present; parsers `0/0`; actual line `STAGE11_EXTERNAL_BACKUP_EXPORT_PERF rows=10000 export_validate_ms=26 exported_files=2 provider_requests=0 cache_reads=0 credential_reads=0` |
| Clean Debug arm64 Build | `PASS` | Shell exit `0`; status succeeded; errors `0`; four existing `PortfolioView` warnings and no new warning; complete `CleanDebugBuild-Final.xcresult`; `Info.plist` present; build parser `0`; duration `28.487 s` |
| Fresh signed arm64 BFT | `PASS` | Shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four existing warnings; complete `BuildForTesting-Final.xcresult`; `Info.plist` present; build parser `0`; duration `34.369 s`; App/Runner strict codesign exit `0` |
| Targeted Settings External Export UI, initial | `FAIL` | Exact selector `testStage11SettingsExternalBackupExportToUserSelectedFolderAndIsolation`; shell exit `65`; definitions/executions `1/1`; one business execution; `0/1/0`; complete `TargetedExternalExportUI.xcresult`; `Info.plist` present; parsers `0/0`; failure at old source line `1550` after the native directory panel opened but the panel-scoped typed `Cancel` query did not match |
| Targeted Settings External Export UI, final | `FAIL` | Same exact selector on rebuilt final source/product; shell exit `65`; definitions/executions `1/1`; one business execution; `0/1/0`; complete `TargetedExternalExportUI-Final.xcresult`; `Info.plist` present; parsers `0/0`; result interval `50.953 s`; failure `AureusUITests.swift:1549` because the native panel's public visible-label `Cancel` control remained unqueryable through a type-independent application-wide query |
| Existing focused regression | `NOT RUN` | Gate G did not pass; the ordered prerequisite for the eleven exact selectors was not met |
| Full `AureusUITests` | `NOT RUN` | Existing focused `11/11` was not run and could not satisfy the prerequisite for current inventory `17/17` |

The first signed Focused Unit bundle is retained as an infrastructure result: it discovered all `77` definitions, but the known App Sandbox policy denied `/private/tmp/AureusTests/<UUID>` before `57` Backup/Export tests could use their synthetic roots. The authorized stable unsigned isolated-host route then produced the complete final-source Unit evidence above. This route is infrastructure handling, not a business retry. Gate G used exactly one authorized direct UI-test lifecycle repair, two business executions total, no infrastructure retry, and no incomplete-result re-observation. The final failure occurred before Cancel, Choose, artifact creation, reconstruction, and Production-isolation tail assertions; those runtime portions remain `NOT VERIFIED` in this round. Historical external Export foundation and prior `16/16` UI evidence were not substituted for the newly affected UI Gate.

### Current-round provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- External Restore/import: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Scheduling/cloud export: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

All Unit, performance, build, BFT, and UI artifacts remain below the current `/private/tmp` evidence root. No database, external generation, security-scoped bookmark, DerivedData, or xcresult was written into the Repository.

## Current Settings external Export UI status

**Stage 11-SETTINGS-EXTERNAL-BACKUP-EXPORT-UI-01 PARTIAL — Awaiting Reviewer Gate**

## External Backup Export panel Escape-cancel round

Prompt 11-EXTERNAL-BACKUP-EXPORT-PANEL-CANCEL-01 changes only `AureusUITests.swift` before formal execution. The targeted flow no longer queries the system-owned directory panel `Cancel` node by identifier, label, element type, count, enabled, hittable, or click state. It proves that the native panel appears, sends exactly one public macOS/XCTest `Escape` action, waits for dismissal, and verifies zero Cancel side effects before reopening a new panel and retaining the existing public `PathTextField` / `OKButton` success path. Production Swift, Unit tests, Project, Package, migrations, entitlements, targets, scheme, and synthetic fixtures remain unchanged.

Current evidence root: `/private/tmp/Aureus-Stage11-EXTERNAL-BACKUP-EXPORT-PANEL-CANCEL-01-KuDiH0`.

| Verification | Result | Evidence |
|---|---|---|
| Focused Unit | `NOT RUN — INHERITED AFTER EXACT PRODUCTION/MODEL/UNIT SOURCE-HASH VERIFICATION` | Accepted `77` definitions / `79` dynamic executions PASS |
| Affected regression | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted `136` definitions / `146` dynamic executions PASS |
| Full Unit | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted `429` definitions / `472` dynamic executions PASS |
| Performance | `NOT RUN — INHERITED AFTER EXACT FOUNDATION SOURCE-HASH VERIFICATION` | Accepted `29` definitions / `31` dynamic executions PASS; 10,000-row export/validate workload `26 ms` |
| Clean Debug arm64 Build, initial | `INFRASTRUCTURE FAILURE` | Shell exit `74`; GRDB checkout's SQLiteLib submodule fetch failed with a transient TLS transport error before source compilation; complete `CleanDebugBuild.xcresult`; `Info.plist` present; not counted as a source/build PASS |
| Clean Debug arm64 Build, infrastructure retry | `PASS` | Shell exit `0`; status `succeeded`; errors `0`; four existing `PortfolioView` deprecation warnings and no new warning; duration `27.136 s`; complete `CleanDebugBuild-InfraRetry.xcresult`; `Info.plist` present; build parser exit `0` |
| Fresh signed arm64 BFT | `PASS` | Shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four existing warnings and no new warning; duration `33.126 s`; complete `BuildForTesting.xcresult`; `Info.plist` present; build parser exit `0`; App/Runner strict codesign exits `0` |
| Gate G targeted External Export UI | `PASS` | Exact selector `testStage11SettingsExternalBackupExportToUserSelectedFolderAndIsolation`; shell exit `0`; definitions/executions `1/1`; one business execution; passed/failed/skipped `1/0/0`; method duration `85.288 s`; result interval `93.639 s`; complete `TargetedExternalExportUI.xcresult`; `Info.plist` present; summary/tests parser exits `0/0` |
| Gate H Existing focused regression | `INCOMPLETE RESULT — NOT PASS / NOT VERIFIED` | One serial invocation requested all eleven exact selectors. The command session was externally interrupted after completed business failures at current-source `AureusUITests.swift:2160` (Ledger Dynamic matching snapshot), `AureusUITests.swift:2679` (Native CSV Save Panel export state), and `AureusUITests.swift:235` (Portfolio summary name). Accurate xcodebuild/App/Runner processes then measured `0`; `ExistingFocusedRegression.xcresult` has no `Info.plist`; no canonical definitions/executions or passed/failed/skipped aggregate exists; summary/tests parsers exit `64/64`; no re-observation is authorized after completed business assertions |
| Gate I full `AureusUITests` | `NOT RUN` | Gate H did not produce the required canonical `11/11 PASS`; current inventory `17/17` was not executed |

Gate G formally proves the complete Cancel and success branches: Cancel leaves the synthetic destination empty, internal inventory at one valid generation, selection usable, status `Ready`, and result/error/recovery/safety/artifact state absent. The subsequent success path completes security-scoped External Export, exposes `External Backup Export Completed`, produces one ordinary non-symlink generation containing only ordinary non-symlink `aureus.sqlite` and `manifest.json`, validates manifest format `1`, schema `6`, and byte count, preserves internal inventory without a safety generation, and passes navigation reconstruction and Production isolation through the Provider-zero tail.

The source file `SettingsDataLifecycleTests.swift` remained frozen at the complete SHA-256 `c1f6d3b7b341e908c0a0445180e785509ba178ed46fbcff239ba41769653dcbf`. Gate G used one targeted business execution and no repair or business retry. Gate H was not rerun, repaired, or combined; the globally authorized incomplete-result re-observation was not used because complete business assertions already existed. Gate I remained `NOT RUN`.

### Escape-cancel round provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- External Restore/import: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Scheduling/cloud export: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

## Current External Backup Export UI runtime status

**Stage 11-EXTERNAL-BACKUP-EXPORT-PANEL-CANCEL-01 PARTIAL — Awaiting Reviewer Gate**

## Existing UI diagnostic closure round

Prompt 11-EXISTING-UI-DIAGNOSTIC-CLOSURE-02 是零源码修改、零重建、零重签名的 evidence-only round。修改前全部规定 Source Identity 精确匹配；测试前的普通文件系统 inventory 包含 `114` 个 ordinary files，并显式排除 `.git/**`、`.secrets/**` 与 `default.profraw` payload。三项独立诊断、Existing focused 与 Full UI 全部串行复用同一个 frozen signed product。上一轮缺少 `Info.plist` 的 `ExistingFocusedRegression.xcresult` 保持 `INCOMPLETE RESULT — NOT PASS / NOT VERIFIED`，其三条 console assertion 线索未被合并或转换成 canonical aggregate。

Current evidence root: `/private/tmp/Aureus-Stage11-EXISTING-UI-DIAGNOSTIC-CLOSURE-02-uRH4fF`.

| Verification | Result | Evidence |
|---|---|---|
| External Export Targeted UI | `NOT RUN — ACCEPTED CURRENT-SOURCE 1/1 PASS AFTER EXACT SOURCE/PRODUCT VERIFICATION` | Accepted bundle `TargetedExternalExportUI.xcresult`; `Info.plist` present; definitions/executions `1/1`; `1/0/0`; canonical result `Passed`; summary/tests parser exits `0/0` |
| Focused Unit | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted `77` definitions / `79` dynamic executions PASS |
| Affected Unit Regression | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted `136` definitions / `146` dynamic executions PASS |
| Full Unit | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted `429` definitions / `472` dynamic executions PASS |
| Performance | `NOT RUN — INHERITED AFTER EXACT FOUNDATION SOURCE-HASH VERIFICATION` | Accepted `29` definitions / `31` dynamic executions PASS; real 10,000-row export/validate workload `26 ms` |
| Clean Build | `NOT RUN — ACCEPTED CURRENT-SOURCE BUILD AFTER EXACT SOURCE/PRODUCT VERIFICATION` | No build was authorized or performed |
| BFT | `NOT RUN — REUSED EXACT FROZEN CURRENT-SOURCE SIGNED PRODUCT` | No rebuild or re-sign was authorized or performed |
| Ledger Dynamic diagnostic | `PASS` | Exact selector `testLedgerDynamicCashFlowTransferInvestmentEditAndDelete`; shell exit `0`; definitions/executions `1/1`; one business execution; `1/0/0`; method duration `230.696 s`; result interval `243.204 s`; complete `LedgerDynamicDiagnostic.xcresult`; `Info.plist` present; summary/tests parser exits `0/0`; picker matching-snapshot failure did not recur |
| Native CSV diagnostic | `PASS` | Exact selector `testLedgerNativeCSVImportPreviewConfirmationAndExport`; shell exit `0`; definitions/executions `1/1`; one business execution; `1/0/0`; method duration `52.287 s`; result interval `54.157 s`; complete `NativeCSVDiagnostic.xcresult`; `Info.plist` present; summary/tests parser exits `0/0`; import, preview, confirmation, Save Panel, `OKButton`, exact default export, and Ledger Error absence passed |
| Portfolio diagnostic | `PASS` | Exact selector `testStage8PortfolioSyntheticCRUDHoldingsSnapshotAndIsolation`; shell exit `0`; definitions/executions `1/1`; one business execution; `1/0/0`; method duration `71.760 s`; result interval `72.916 s`; complete `PortfolioDiagnostic.xcresult`; `Info.plist` present; summary/tests parser exits `0/0`; summary-name, ordering, holdings/snapshot, reload/delete, and Production isolation passed |
| Diagnostic matrix | `PASS` | 三项均各自形成独立完整 `1/1 PASS`；未将三个 bundle相加成伪造 aggregate |
| Existing focused regression | `PASS` | 十一个 exact selectors在单次 serial invocation中执行；shell exit `0`; definitions/executions `11/11`; business executions `11`; passed/failed/skipped `11/0/0`; canonical result `Passed`; result interval `1109.470 s`; complete `ExistingFocusedRegression.xcresult`; `Info.plist` present; summary/tests parser exits `0/0` |
| Full `AureusUITests` | `PASS` | Exact selector `AureusUITests`; shell exit `0`; definitions/executions `17/17`; business executions `17`; passed/failed/skipped `17/0/0`; canonical result `Passed`; all `17` Test Case nodes `Passed`; method aggregate `1262.523 s`; result interval `1274.760 s`; complete `FullAureusUITests.xcresult`; `Info.plist` present; summary/tests parser exits `0/0` |

三项历史 console 线索均未在独立诊断、单次 Existing focused 聚合或 Full UI 中复现。所有 invocation 使用 `-parallel-testing-enabled NO`、maximum concurrent destination `1` 与同一个 frozen product：App SHA-256 `57de6848ec47b9df768adf3a2fab6af0dd48e5935b7701ccbdadf00b7e850a71`，Runner `a0a8835f2b59a28602d6b9a457c3d2edc8a005661641301675049c787cad0fae`，UI Test executable `de158835679de7d511b6d275e70972544aef0677210862c5d3125523e49ca7ce`，xctestrun `0446c244aec3849e52f45dacd7bb08e3af74da5333d2cdce3d7863a6b6fd2bd9`。App/Runner strict codesign复核通过，architecture为 `arm64`，Gate之间未 build、sign或修改产品。Business repair、business retry、UI infrastructure retry 与 incomplete-result re-observation实际用量均为 `0`。

### Diagnostic closure provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- External Restore/import: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Scheduling/cloud export: `NOT IMPLEMENTED / NOT AUTHORIZED`
- External retention: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

测试停止后、文档更新前，系统 `shasum -c` 对全部 `114` 个 pre-inventory ordinary files返回 `OK`，确认 Product/Test/Project及其他 Repository路径在测试期间保持逐字节不变。所有 UI 与 result artifacts 均位于 `/private/tmp`；未向 Repository 写入数据库、Backup/export generation、staging、DerivedData或 xcresult。

## Current Stage 11 UI runtime candidate status

**Stage 11 External Backup Export UI Runtime Candidate — Awaiting Reviewer Gate**

本状态仅是 Executor candidate evidence，不宣布 Stage 11 `PASS`、V1 Ready、Release Ready或 Stage 12授权。

## Validated External Backup Restore Foundation round

Prompt 11-EXTERNAL-BACKUP-RESTORE-FOUNDATION-01 implements an explicit no-UI External Restore entry on the existing `WealthStore` actor. A caller supplies one External generation and operation-scoped configuration. Standalone validation accepts only an absolute file URL whose strict generation name and exact `aureus.sqlite` / `manifest.json` content pass the existing authoritative Backup validator, plus canonical UTC/app-version, format `1`, streaming SHA-256, byte-count, query-only SQLite quick-check, foreign-key, and schema `1...6` checks. Protected internal Backup, Permanent, Market Cache, and caller-supplied roots reject overlap. The internal `validateGeneration(_:in:)` and internal Restore entry remain configured-root direct-child only.

After validation, the External path calls the same Restore core that stages the candidate beside the live database, validates the staged digest and database, creates and validates exactly one safety generation before close, checkpoints and closes the actor-owned queue, atomically replaces the live database, migrates schemas 1...5 through the unchanged permanent migrator, validates schema 6 and application invariants, and rebinds the same actor. Replacement or activation failures reuse the accepted safety rollback; rollback failure enters `recoveryRequired`. External artifacts are not moved, renamed, modified, retained, copied into internal inventory, or persisted as URL/bookmark/history. Candidate/rollback staging cleanup is operation-owned; safety retention remains the existing validated latest-five policy.

Current evidence root: `/private/tmp/Aureus-Stage11-EXTERNAL-BACKUP-RESTORE-FOUNDATION-01-1l01JA`.

| Verification | Result | Evidence |
|---|---|---|
| Historical UI closure | `NOT RUN — ACCEPTED HISTORICAL EVIDENCE ONLY` | Read-only canonical parsing confirmed current-before-change Ledger Dynamic `1/1`, Native CSV `1/1`, Portfolio `1/1`, Existing focused `11/11`, and Full UI `17/17`; Production source changed in this round, so these bundles are not current-source UI evidence |
| Initial Focused compile | `FAIL` | Exact three-suite selector; shell exit `65`; complete `FocusedUnit.xcresult`; `Info.plist` present; definitions/executions `0/0`; compiler required parameterized-test enum visibility; summary/tests parser exits `0/0`; no business execution |
| Second Focused compile | `FAIL` | Same exact selectors; shell exit `65`; complete `FocusedUnit-Final.xcresult`; `Info.plist` present; definitions/executions `0/0`; three GRDB async calls required `await`; summary/tests parser exits `0/0`; no business execution |
| Focused Unit before direct repair | `FAIL` | Exact suites `PermanentExternalRestoreTests`, `PermanentRestoreTests`, and `PermanentBackupTests`; shell exit `65`; complete `FocusedUnit-Current.xcresult`; `Info.plist` present; `78` definitions / `107` dynamic executions; `58/49/0` dynamic outcomes; all `49` new External executions stopped on the same `/private/tmp` URL-string canonicalization rejection while the accepted Backup/Restore suites passed; summary/tests parser exits `0/0` |
| Focused Unit after direct repair | `FAIL` | Same exact suites and final source; shell exit `65`; complete `FocusedUnit-AfterRepair.xcresult`; `Info.plist` present; `78` definitions / `107` dynamic executions; `106/1/0`; canonical result `Failed`; summary/tests parser exits `0/0`; result interval `54.610 s`, test execution `6.432 s` |
| Focused failure boundary | `FAIL` | The sole post-repair failure is `PermanentExternalRestoreTests/unsupportedSchema(version:)` for argument `0`: the fixture's `UPDATE schema_metadata SET version = 0` was rejected by existing `CHECK (version >= 1)` before the External Restore API ran. The future-schema argument and all other dynamic cases passed |
| Affected Regression | `NOT RUN` | Gate C did not pass; ordered prerequisite not met |
| Full Unit | `NOT RUN` | Gate D was not run/passed; ordered prerequisite not met |
| Release Performance | `NOT RUN` | Gate E was not run/passed; the Debug Focused run did execute and pass the same 10,000-row workload at `52 ms`, but it is not Release evidence |
| Clean Debug arm64 Build | `NOT RUN` | Ordered Unit prerequisites did not pass |
| Fresh signed arm64 BFT | `NOT RUN` | Ordered Clean Build prerequisite was not run |
| UI Tests | `NOT RUN — NOT AUTHORIZED IN EXTERNAL BACKUP RESTORE FOUNDATION ROUND` | Historical `17/17` is not substituted for current-source UI evidence; no BFT was produced in this round |

The first business-complete result exposed the `/private/tmp` versus Foundation-standardized `/tmp` string-identity defect. One authorized minimal direct repair removed only the original-versus-standardized string equality while retaining absolute file URL, standardized/resolved path, symlink, type, direct-child, exact-artifact, manifest, digest, SQLite, FK, and schema validation. The required from-Gate-C rerun then produced the single schema-0 fixture failure above. Under the one-repair and second-complete-failure stop rule, no additional test/source repair, business retry, infrastructure retry, or result merging occurred; Gates D–H remain `NOT RUN`.

### External Restore provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- Settings External Restore UI: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Security-scoped runtime: `NOT RUN`
- External retention, scheduling, and cloud Restore: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

## Current External Backup Restore Foundation status

**Stage 11-EXTERNAL-BACKUP-RESTORE-FOUNDATION-01 PARTIAL — Awaiting Reviewer Gate**

This is Executor evidence only. It does not declare Stage 11 `PASS`, V1 Ready, Release Ready, Settings External Restore UI readiness, or Stage 12 authorization.

## External Backup Restore validation closure round

Prompt 11-EXTERNAL-BACKUP-RESTORE-VALIDATION-CLOSURE-01 closes the two validation defects isolated by the preceding Foundation evidence while preserving that round's accepted Restore core. Only `PermanentBackup.swift` and `PermanentExternalRestoreTests.swift` changed before formal verification; this acceptance document and `README.md` changed only after Gates C–H completed.

### Schema-zero and future-schema boundary

The schema-0 test no longer attempts to violate the production database's `CHECK (version >= 1)`. It creates a valid schema-6 External generation, changes only the untrusted External manifest's `schemaVersion` to `0`, leaves the database, digest, and byte count unchanged, and invokes the formal `restoreExternalPermanentBackup` API. The API returns typed `invalidExternalCandidate(.malformedManifest)` before candidate staging, safety Backup, queue close, or replacement. Tracking operations remain at zero, the live synthetic records remain unchanged, maintenance remains `ready`, and the External generation fingerprint remains unchanged.

The separate schema-7 test mutates the synthetic candidate database metadata to `7`, updates the manifest to `7`, recomputes its digest and byte count, and invokes the same formal API. It returns typed `invalidExternalCandidate(.schemaMismatch)` before staging, safety Backup, or replacement. Both rejected operations run exactly once and perform no automatic retry.

### Standalone parent-access closure

`validateStandaloneExternalGeneration` now validates the absolute file URL, its standardized/resolved non-symlink identity, protected-root non-overlap, and then the selected generation itself. It neither derives nor reads the generation's parent directory, does not list that parent, and does not call the root-dependent `validateDirectory(_:in:acceptedName:fileManager:)` path.

The shared authoritative content validator continues to enforce the strict generation-name predicate, plain non-symlink directory, exact `aureus.sqlite` and `manifest.json` children, ordinary non-symlink files, manifest parsing and format/canonical fields, positive byte count, lowercase streaming SHA-256 agreement, query-only SQLite open, quick-check, foreign keys, and manifest/database schema agreement. Internal `validateGeneration(_:in:)` still checks its configured Backup root and `requireDirectChild` before calling the shared validator. External Export final and staging validators still validate the injected destination directory and require direct-child artifacts. `PermanentRestore.swift`, `PermanentExternalRestore.swift`, `WealthStore.swift`, migrations, Project, Package, targets, scheme, and entitlements remain byte-identical.

Current evidence root: `/private/tmp/Aureus-Stage11-EXTERNAL-BACKUP-RESTORE-VALIDATION-CLOSURE-01-skIX9p`.

| Verification | Result | Evidence |
|---|---|---|
| Historical Foundation results | `NOT RUN — READ-ONLY CLASSIFICATION` | `FocusedUnit.xcresult` and `FocusedUnit-Final.xcresult` remain 0-test compile failures; `FocusedUnit-Current.xcresult` remains a complete failed `58/49/0` dynamic result; `FocusedUnit-AfterRepair.xcresult` remains complete `106/1/0` with the schema-0 fixture failure. No historical bundle was modified, merged, or converted to PASS |
| Historical UI closure | `NOT RUN — ACCEPTED HISTORICAL CONTINUITY EVIDENCE` | Read-only verification retained the earlier full `AureusUITests` `17/17 PASS`; Production source changed in this round, so it is not current-source UI evidence |
| Gate C Focused Unit | `PASS` | Unsigned isolated Debug Unit host; exact suites `AureusTests/PermanentExternalRestoreTests`, `AureusTests/PermanentRestoreTests`, `AureusTests/PermanentBackupTests`; shell exit `0`; `79` definitions / `107` dynamic and business executions; passed/failed/skipped `107/0/0`; result interval `46.228 s`, test execution `6.597 s`; complete `FocusedUnit.xcresult`; `Info.plist` present; initial sandbox summary/tests parser exits `64/64`, same-bundle standard Xcode read-only parser exits `0/0`; no test retry |
| Gate D Affected Regression | `PASS` | Unsigned isolated Debug Unit host; exact suites `PermanentExternalRestoreTests`, `PermanentRestoreTests`, `PermanentBackupTests`, `PermanentMigrationSafetyTests`, `PermanentBackupExportTests`, `SettingsDataLifecycleTests`, `PersistenceTests`; shell exit `0`; `161` definitions / `195` dynamic and business executions; `195/0/0`; result interval `47.299 s`, test execution `9.312 s`; complete `AffectedRegression.xcresult`; `Info.plist` present; parsers `0/0`; no retry |
| Gate E Full Unit | `PASS` | Unsigned isolated Debug Unit host; exact selector `AureusTests`; shell exit `0`; `454` definitions / `521` dynamic and business executions; `521/0/0`; result interval `90.712 s`, test execution `52.442 s`; complete `FullAureusTests.xcresult`; `Info.plist` present; parsers `0/0`; no retry |
| Gate F Release External Restore | `PASS` | Release-oriented, `ENABLE_TESTABILITY=YES`, unsigned isolated Unit host; exact selector `AureusTests/PermanentExternalRestoreTests`; shell exit `0`; `25` definitions / `49` dynamic and business executions; `49/0/0`; result interval including build `143.882 s`, test execution `2.390 s`; complete `ReleaseExternalRestorePerformance.xcresult`; `Info.plist` present; parsers `0/0`; no retry |
| Gate F workload | `PASS` | `STAGE11_EXTERNAL_RESTORE_PERF rows=10000 validate_safety_restore_ms=43 migration_applied=0 provider_requests=0 cache_reads=0 credential_reads=0`; actual 10,000-row candidate and current Store workload entered; `43 ms < 10000 ms` |
| Gate G Clean Debug arm64 Build | `PASS` | Exact category `clean build`, Scheme `Aureus`, Debug arm64; shell exit `0`; canonical status `succeeded`; errors `0`; warnings `4`, all pre-existing `PortfolioView.swift` deprecated interpolation warnings; new warnings `0`; duration `28.722 s`; complete `CleanDebugBuild.xcresult`; `Info.plist` present; build parser exit `0`; no retry |
| Gate H fresh signed BFT | `PASS` | Exact category `build-for-testing`, Scheme `Aureus`, Debug arm64, fresh DerivedData; shell exit `0`; `TEST BUILD SUCCEEDED`; canonical status `succeeded`; errors `0`; four existing warnings and zero new warnings; duration `37.608 s`; complete `BuildForTesting.xcresult`; `Info.plist` present; build parser exit `0`; App/Runner strict codesign exits `0`; no retry |
| UI Tests | `NOT RUN — NOT AUTHORIZED IN EXTERNAL BACKUP RESTORE VALIDATION CLOSURE ROUND` | Historical `17/17` was not substituted for a current-source UI run; BFT is build evidence only |

### BFT product identity

- App: `BuildForTestingDerivedData/Build/Products/Debug/Aureus.app/Contents/MacOS/Aureus`; SHA-256 `a6b7780ea573564394fb44a2372d1c5caca50e6034251fd8a2e85d4ae546b781`; Bundle ID `com.aureus.wealthterminal`; `arm64`; local ad hoc / Sign to Run Locally; strict codesign exit `0`.
- Runner: `BuildForTestingDerivedData/Build/Products/Debug/AureusUITests-Runner.app/Contents/MacOS/AureusUITests-Runner`; SHA-256 `102071f122fb6555bb379dbdb3d300387b7726dfc0e8fb2a6db1280b2032b2cf`; Bundle ID `com.aureus.wealthterminal.uitests.xctrunner`; `arm64`; local ad hoc / Sign to Run Locally; strict codesign exit `0`.
- UI Test executable: `BuildForTestingDerivedData/Build/Products/Debug/AureusUITests-Runner.app/Contents/PlugIns/AureusUITests.xctest/Contents/MacOS/AureusUITests`; SHA-256 `6e40f5585d76e6efc3ddb7897523e766d8a5598b071f6aeab487a36d32bb6add`; Bundle ID `com.aureus.wealthterminal.uitests`; `arm64`.
- xctestrun: `BuildForTestingDerivedData/Build/Products/Aureus_Aureus_macosx26.5-arm64.xctestrun`; SHA-256 `0c3e2ce3602148128a452af96946a50c9b401b2586e67c66a917100aff255936`.

### Validation closure provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- Settings External Restore UI: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Security-scoped runtime: `NOT RUN`
- Stages 12–14: `NO-GO`

## Current External Backup Restore Foundation status

**Stage 11 External Backup Restore Foundation Candidate — Awaiting Reviewer Gate**

This remains Executor candidate evidence. The Reviewer still owns the Stage 11 Gate; this status does not declare Stage 11 `PASS`, V1 Ready, Release Ready, Settings External Restore UI readiness, or Stage 12 authorization.

## Settings External Backup Restore UI round

Prompt 11-SETTINGS-EXTERNAL-BACKUP-RESTORE-UI-01 adds the authorized Settings runtime surface over the accepted External Restore Foundation. Production composition injects `PermanentExternalRestoreConfiguration` from the same `RuntimePaths` and reuses the existing actor-owned `WealthStore`. The model exposes a finite `restoringExternalBackup` state, an External Restore capability independent of internal generation selection, one explicit client invocation with independent operation/safety identities, sanitized success/failure presentation, post-success inventory reload, and `recoveryRequired` blocking. Reconstruction clears the transient result and never persists the selected URL, filename, bookmark, history, or security scope.

The Settings view exposes a distinct External Restore heading, exact private-data warning, and `Restore External Backup…` control. One shared SwiftUI `.fileImporter(.folder)` dispatches External Export and External Restore selections without widening either business contract. A transient security-scoped lease starts once for a selected generation, remains held through confirmation and any asynchronous Restore, and releases only on Cancel, completion/failure, or idle view disappearance. The app-owned sheet exposes four independent heading, warning, Cancel, and Confirm Accessibility nodes; Confirm is the only path to the formal External Restore API. No raw SQLite import, bookmark persistence, automatic/startup Restore, external retention, scheduling, cloud Restore, Provider access, or Stage 12 work was added.

Current evidence root: `/private/tmp/Aureus-Stage11-SETTINGS-EXTERNAL-BACKUP-RESTORE-UI-01-A9c0OF`.

| Verification | Result | Evidence |
|---|---|---|
| Historical Foundation/UI evidence | `NOT RUN — READ-ONLY CLASSIFICATION` | Canonical read-only parsing confirmed the accepted External Restore Foundation Unit/Performance/Build evidence, External Export targeted `1/1 PASS`, and preceding Existing focused `11/11` plus Full UI `17/17`; Production/Test source changed in this round, so none was substituted for current-source UI evidence |
| Gate C Focused Unit final | `PASS` | Exact selectors `SettingsDataLifecycleTests`, `PermanentExternalRestoreTests`, `PermanentRestoreTests`, `PermanentBackupExportTests`, `PermanentBackupTests`, and `PersistenceTests`; shell exit `0`; `134` definitions / `168` dynamic executions; business outcomes `134/0/0`; result interval `51.442 s`; complete `FocusedUnit-Final.xcresult`; `Info.plist` present; summary/tests parser exits `0/0`; no retry |
| Gate D Affected Regression final | `PASS` | Exact affected Settings/External Restore/Restore/Backup/Export/Migration/Persistence suites; shell exit `0`; `167` definitions / `205` dynamic executions; `167/0/0`; result interval `54.326 s`; complete `AffectedRegression-Final.xcresult`; `Info.plist` present; parsers `0/0`; no retry |
| Gate E Full Unit final | `PASS` | Exact selector `AureusTests`; shell exit `0`; `460` definitions / `531` dynamic executions; `460/0/0`; result interval `99.309 s`; complete `FullAureusTests-Final.xcresult`; `Info.plist` present; parsers `0/0`; no retry |
| External Restore performance | `NOT RUN — INHERITED AFTER EXACT FOUNDATION SOURCE-HASH VERIFICATION` | Accepted `25` definitions / `49` executions PASS; real 10,000-row validate/safety/Restore workload `43 ms` |
| External Export performance | `NOT RUN — INHERITED AFTER EXACT FOUNDATION SOURCE-HASH VERIFICATION` | Accepted `29` definitions / `31` executions PASS; real 10,000-row export/validate workload `26 ms` |
| Gate F Clean Debug arm64 Build final | `PASS` | Exact category `clean build`, Scheme `Aureus`, Debug arm64; shell exit `0`; canonical status `succeeded`; errors `0`; warnings `4`, all pre-existing `PortfolioView.swift` deprecation warnings; new warnings `0`; duration `29.519 s`; complete `CleanDebugBuild-Final.xcresult`; `Info.plist` present; parser exit `0`; no retry |
| Gate G fresh signed BFT final | `PASS` | Exact category `build-for-testing`, Scheme `Aureus`, Debug arm64, fresh DerivedData; shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four existing warnings and zero new warnings; duration `36.003 s`; complete `BuildForTesting-Final.xcresult`; `Info.plist` present; parser exit `0`; App/Runner strict codesign exits `0`; no retry |
| Gate H Targeted UI initial | `FAIL` | Exact selector `testStage11SettingsExternalBackupRestoreFromUserSelectedGenerationAndIsolation`; complete business execution `1`; definitions/executions `1/1`; `0/1/0`; failure at the first External Export panel presentation because two sibling folder importers competed; retained complete bundle; one authorized direct repair followed |
| Gate H Targeted UI final | `FAIL` | Same exact selector and final frozen product; business execution `1`; definitions/executions `1/1`; canonical `0/1/0`; result `Failed`; method duration `45.083 s`, result interval `56.888 s`; complete `TargetedExternalRestoreUI-Final.xcresult`; `Info.plist` present; summary/tests parser exits `0/0`; `AureusUITests.swift:3042` reported `Directory panel did not expose its Choose control` after the Export panel and Go To Folder path succeeded |
| Gate I Existing focused | `NOT RUN` | Gate H did not produce the required `1/1 PASS`; exact `12/12` aggregate was not invoked |
| Gate J Full `AureusUITests` | `NOT RUN` | Gate I was not run/passed; expected current inventory `18/18` was not invoked |

The first complete Targeted failure authorized exactly one direct repair. The view now owns a single folder importer with an explicit transient operation purpose, and final source reran Gates C–G in order before freezing a fresh signed product. The second and final Targeted business execution proved that the shared importer opens and reaches the External Export Go To Folder lifecycle, then exposed a later public Choose-control query failure. Because the two-business-execution and one-repair budgets were exhausted, no third Targeted run, second repair, infrastructure retry, or incomplete-result re-observation occurred. The failure occurs before the External Restore candidate is selected, so native-panel Cancel, confirmation Cancel, Confirm/Restore, External artifact immutability across Restore, safety generation, Goals reconstruction, navigation reconstruction, and Production-isolation runtime tails are `NOT VERIFIED` in this round and are not inferred from Unit or historical UI evidence.

### Final frozen UI product

- App: `/private/tmp/Aureus-Stage11-SETTINGS-EXTERNAL-BACKUP-RESTORE-UI-01-A9c0OF/BuildForTestingFinalDerivedData/Build/Products/Debug/Aureus.app/Contents/MacOS/Aureus`; SHA-256 `8bf1a5a2aa0ac6c612d17c73192384e1184709ccd2d79d57e534ebdc3b7353f1`; Bundle ID `com.aureus.wealthterminal`; `arm64`; local ad hoc / Sign to Run Locally; strict codesign exit `0`.
- Runner: `/private/tmp/Aureus-Stage11-SETTINGS-EXTERNAL-BACKUP-RESTORE-UI-01-A9c0OF/BuildForTestingFinalDerivedData/Build/Products/Debug/AureusUITests-Runner.app/Contents/MacOS/AureusUITests-Runner`; SHA-256 `85dbef33f54690a9e7c54a78ec2e4ae2eb4bf1d7fc86e84cf82450249cda899b`; Bundle ID `com.aureus.wealthterminal.uitests.xctrunner`; `arm64`; local ad hoc / Sign to Run Locally; strict codesign exit `0`.
- UI Test executable: `/private/tmp/Aureus-Stage11-SETTINGS-EXTERNAL-BACKUP-RESTORE-UI-01-A9c0OF/BuildForTestingFinalDerivedData/Build/Products/Debug/AureusUITests-Runner.app/Contents/PlugIns/AureusUITests.xctest/Contents/MacOS/AureusUITests`; SHA-256 `39c22c15e676a7710590803bd95e2f3ddb44ba23caa916a03cb035d8332d08fd`; Bundle ID `com.aureus.wealthterminal.uitests`; `arm64`.
- xctestrun: `/private/tmp/Aureus-Stage11-SETTINGS-EXTERNAL-BACKUP-RESTORE-UI-01-A9c0OF/BuildForTestingFinalDerivedData/Build/Products/Aureus_Aureus_macosx26.5-arm64.xctestrun`; SHA-256 `42afdb1426fad2040448289fe62f26597fe2508e8a8920711331eb400bf4d226`.

### Settings External Restore UI provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- External artifact creation through the targeted Restore test: `NOT VERIFIED`
- External retention, scheduling, cloud Restore, raw SQLite import, and automatic/startup Restore: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

## Current Settings External Backup Restore UI status

**Stage 11-SETTINGS-EXTERNAL-BACKUP-RESTORE-UI-01 PARTIAL — Awaiting Reviewer Gate**

This is Executor evidence only. The Reviewer still owns the Stage 11 Gate; it does not declare Stage 11 `PASS`, V1 Ready, Release Ready, or Stage 12 authorization.

## External Restore directory-panel closure round

Prompt 11-EXTERNAL-RESTORE-DIRECTORY-PANEL-CLOSURE-01 的唯一源码修改是 `AureusUITests.swift` 中的 `chooseDirectory`。路径存在、native panel 出现、Command-Shift-G、`PathTextField` 准确输入、有限 Return、`GoToWindow` 消失的原合同保留。Go To 消失后确认当前 native panel 仍存在，执行恰好一次 `app.typeKey(.enter, modifierFlags: [])`。helper 不再查询系统 `OKButton`/Choose/Cancel，也不再以所有 sheet/dialog 消失作为结束条件；调用方继续通过 Export status/artifact 或应用自有 Restore confirmation 节点判断结果。`chooseFile`、`saveFileUsingDefaultFilename`、`currentNativePanel`、`waitForCurrentPanelControl` 及所有业务测试断言保持不变。

本轮 evidence root：`/private/tmp/Aureus-Stage11-EXTERNAL-RESTORE-DIRECTORY-PANEL-CLOSURE-01-bEN0A5`。历史七个 bundle 的 `Info.plist` 和 canonical parsers 均核验成功；上一轮 Targeted initial/final 保持完整 `0/1/0 FAIL`。冻结源 Hash 全部匹配，ordinary files 为 `116`，Project/Scheme/Targets 为 `1/1/3`，arm64、Swift 6、macOS 14.0、GRDB 7.11.1 均保持。正式测试前只有 UI Test 文件变化，文档仅在测试全部结束后更新。

### 当前 Gate evidence

| Gate | 分类 | 完整证据 |
|---|---|---|
| Focused Unit | `NOT RUN — INHERITED AFTER EXACT PRODUCTION/MODEL/UNIT SOURCE-HASH VERIFICATION` | Accepted `134` definitions / `168` dynamic executions PASS |
| Affected Regression | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted `167/205 PASS` |
| Full Unit | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted `460/531 PASS` |
| External Restore Performance | `NOT RUN — INHERITED AFTER EXACT FOUNDATION SOURCE-HASH VERIFICATION` | Accepted `25/49 PASS`，10,000-row workload `43 ms` |
| External Export Performance | `NOT RUN — INHERITED AFTER EXACT FOUNDATION SOURCE-HASH VERIFICATION` | Accepted `29/31 PASS`，10,000-row workload `26 ms` |
| A Clean Build | `PASS` | `clean build`，Scheme Aureus，Debug arm64；direct shell exit `0`；canonical `succeeded`；errors `0`；既存 Portfolio warnings `4`，新增 canonical warnings `0`；duration `33.989 s`；完整 `CleanDebugBuild.xcresult`，`Info.plist` 存在，build parser `0`；无 retry |
| B fresh signed BFT | `PASS` | `build-for-testing`，Scheme Aureus，Debug arm64，fresh DerivedData；direct shell exit `0`；`TEST BUILD SUCCEEDED`，canonical `succeeded`；errors `0`，既存 warnings `4`；duration `37.401 s`；完整 `BuildForTesting.xcresult`，`Info.plist` 存在，build parser `0`，App/Runner strict codesign `0/0`；无 retry |
| C Targeted External Restore UI | `PASS` | `test-without-building`；exact selector `AureusUITests/AureusUITests/testStage11SettingsExternalBackupRestoreFromUserSelectedGenerationAndIsolation`；direct shell exit `0`；definitions/executions `1/1`，business executions `1`，passed/failed/skipped `1/0/0`，expected failures `0`；method `228.097 s`，result interval `240.645 s`；完整 `TargetedExternalRestoreUI.xcresult`，`Info.plist` 存在，summary/tests parsers `0/0`；无 retry |
| D Existing focused | `FAIL` | 单次 serial `test-without-building` 包含下列 12 个 exact selectors；canonical definitions/executions `12/12`，passed/failed/skipped `0/12/0`，expected failures `0`；12 个测试方法已开始，1 个进入应用业务操作，11 个止于公共 pre-launch helper；method duration 合计 `200.925 s`，result interval `214.574 s`；完整 `ExistingFocusedRegression.xcresult`，`Info.plist` 存在，summary/tests parsers `0/0`；direct shell 数字退出码在 command-session interruption 后未能取回，为 `NOT VERIFIED`；无 retry/re-observation |
| E Full AureusUITests | `NOT RUN` | Exact selector `AureusUITests`，expected `18/18`；Gate D 未取得 `12/12 PASS`，无 invocation、shell exit 或结果目录 |

Gate D 的 exact selectors：

```text
AureusUITests/AureusUITests/testStage6SettingsCredentialEntitlementAndCacheLifecycle
AureusUITests/AureusUITests/testWealthCNYUSDLiabilityCRUDAndDynamicTotals
AureusUITests/AureusUITests/testLedgerDynamicCashFlowTransferInvestmentEditAndDelete
AureusUITests/AureusUITests/testLedgerNativeCSVImportPreviewConfirmationAndExport
AureusUITests/AureusUITests/testStage7MarketsSyntheticSearchWatchlistChartAccessibilityAndClear
AureusUITests/AureusUITests/testStage8PortfolioSyntheticCRUDHoldingsSnapshotAndIsolation
AureusUITests/AureusUITests/testStage9AnalyticsSyntheticMetricsAccessibilityAndIsolation
AureusUITests/AureusUITests/testStage10GoalsSyntheticCRUDPlanningAccessibilityAndIsolation
AureusUITests/AureusUITests/testStage10DashboardGoalsProgressAndNavigationIsolation
AureusUITests/AureusUITests/testStage11SettingsInternalBackupRestoreLifecycleAndIsolation
AureusUITests/AureusUITests/testStage11SettingsExternalBackupExportToUserSelectedFolderAndIsolation
AureusUITests/AureusUITests/testStage11SettingsExternalBackupRestoreFromUserSelectedGenerationAndIsolation
```

### Targeted runtime 合同

本轮独立 Targeted `1/1 PASS` 已执行真实 External Export，取得唯一普通 non-symlink generation，其中严格只有普通 non-symlink `aureus.sqlite` 与 `manifest.json`；format `1`、schema `6`、byte count 均符合断言。使用一次 Escape 取消 native Restore panel 后，inventory 仍为 `1`、状态为 Ready、probe Goal 保留、artifact byte snapshot 不变。再次选择后，四个 app-owned confirmation AX 节点的唯一性、完整 exact labels、Cancel/Confirm enabled 均通过；confirmation Cancel 后无 Restore/safety 副作用。第三次选择后 Confirm 只点击一次，正式 Restore 完成，inventory `1→2`，脱敏 result/status 正确，External artifact 不变，probe Goal 消失而原始两个 Synthetic Goals 恢复。

导航重建后 result 不恢复、inventory 仍为 `2`、无自动 panel；随后使用 XCTest 隔离 temporary store 的 Local/Production-mode 重启验证 Goals empty、inventory `0`、无 synthetic records/result/error/recovery/import 节点、无自动 panel、Provider validation 仍为 `Not verified`，External artifact 保持不变。整个流程没有读取真实 Production Store。这些 runtime 证据来自本轮独立 Targeted bundle，不用于替代 Gate D aggregate。

### Gate D failure 与执行记录限制

Gate D 首项 Ledger 在查询 `ledger.filter.tag` 时发生 `Failed to get matching snapshots: Lost connection to the application`，canonical source 为 `AureusUITests.swift:2444`；其 method duration 为 `178.423 s`。同次 invocation 中其余 11 个测试方法随后在 `launchApp` 调用的 `dismissResidualNativePanels` 处遇到同一应用连接错误，source 为 `AureusUITests.swift:3525`，每项约 `2 s`。这是完整的执行期间连接失败结果，不能降级成 incomplete 或 0-business bootstrap；底层连接丢失原因仍为 `NOT VERIFIED`，不据此宣称 Restore/Foundation 或全部业务模块存在数据错误。

工具等待被外部中断，恢复后原 persistent session 返回 `Unknown process id`；准确产品/Runner/xcodebuild 进程均已退出，结果已完成 canonical finalization。因完整 failure 已存在，infrastructure retry 与 incomplete-result re-observation 均不适用，使用量均为 `0`。本轮 repair 共 `1`，在正式 Gate 前完成；正式 Gate 后 repair/business retry 为 `0`。Gate C 与 Gate D 各仅有一次 invocation；Gate E 未启动。未覆盖、修补或合并任何结果。

另需更正前置阅读证据：`MandatoryRead.log` 为 45 个指定路径逐项记录了 `READ TO EOF`，但当时命令将内容重定向到 `/dev/null`。它只证明文件流按序读取完毕，不能证明 Executor 对全部文件的逐项内容审阅；因此 AC-01 为 `NOT VERIFIED`，不以补读追溯修复正式 Gate 的前置证据。

四项 Portfolio interpolation warnings 为既存 canonical build warnings；Build/BFT 日志另有 AppIntents metadata extraction skipped 诊断。Targeted 与 Existing focused tests JSON 各包含一条 XCTest 内部 QoS priority-inversion runtime warning。全部按实际证据保留，不修改冻结 Product。

### 当前 frozen BFT product

所有下列路径均位于 `/private/tmp/Aureus-Stage11-EXTERNAL-RESTORE-DIRECTORY-PANEL-CLOSURE-01-bEN0A5/BuildForTestingDerivedData/Build/Products`；Gate C、D 前后四项 SHA-256 均与基线一致，Gate 之间未 rebuild/sign。

| Product | Path under product root | SHA-256 | Bundle / architecture / signing |
|---|---|---|---|
| App | `Debug/Aureus.app/Contents/MacOS/Aureus` | `0e03f32f8bf87ffac8507973dc9f0df7490f193166117eb10de8180be9e1ecbc` | `com.aureus.wealthterminal` / arm64 / local ad hoc；strict codesign `0` |
| Runner | `Debug/AureusUITests-Runner.app/Contents/MacOS/AureusUITests-Runner` | `5c1b83b3446bc928f6099772b127f0746994bf997103d43753b84ab66fb0b6aa` | `com.aureus.wealthterminal.uitests.xctrunner` / arm64 / local ad hoc；strict codesign `0` |
| UI Test | `Debug/AureusUITests-Runner.app/Contents/PlugIns/AureusUITests.xctest/Contents/MacOS/AureusUITests` | `924ba57d6e8a25aca0734a2956d4ffd1542e516e41372a5a1a968aed5e877b48` | `com.aureus.wealthterminal.uitests` / arm64 |
| xctestrun | `Aureus_Aureus_macosx26.5-arm64.xctestrun` | `42afdb1426fad2040448289fe62f26597fe2508e8a8920711331eb400bf4d226` | 对应同一 macOS arm64 产品 |

### 当前 Provider / Data Boundary

Provider requests 为 `NOT RUN`；Twelve Data operations、Frankfurter operations、Provider transport attempts、Credential reads、Keychain metadata reads、Market Cache live reads/mutations 均为 `0`。Twelve Data persistent writes 保持 `Disabled`，Provider retention rights 保持 `BLOCKED`。External retention、scheduling、cloud Restore 为 `NOT IMPLEMENTED / NOT AUTHORIZED`；Stages 12–14 保持 `NO-GO`。未执行 Git/gh，未访问 `.git/**`、`.secrets/**` 或 `default.profraw` payload，未安装缺失 scanner。

## Current directory-panel closure status

**Stage 11-EXTERNAL-RESTORE-DIRECTORY-PANEL-CLOSURE-01 PARTIAL — Awaiting Reviewer Gate**

Targeted 默认动作及 External Restore runtime 已验证；Existing focused 失败，Full UI 未运行，完整 Stage 11 Gate 仍由 Reviewer 决定。
