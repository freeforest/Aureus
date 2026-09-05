# Stage 11 完整范围与证据矩阵

**Stage 11 Scope and Evidence Audit Candidate — Awaiting Reviewer Gate**

2026-09-05，只读源码/既有证据审计。Reviewer 已接受 External Backup Restore UI Runtime 子关卡；**Stage 11 总 Gate 仍为 PARTIAL**。本 Candidate 仅指审计产物待审，不表示产品完成。未实施下述建议，未运行任何 Test/Build/Performance/UI/BFT，未启动 App。

## 1. 阅读、来源与判定规则

冻结来源简称及行号基于本轮修改前版本（这些来源未修改）：

- **S**：[V1_SCOPE](V1_SCOPE.md)，§3 Settings line 43；§4 Ledger lines 63–71；§4 Operational lines 117–132；§7 Stage ownership line 193。
- **A**：[V1_ARCHITECTURE](V1_ARCHITECTURE.md)，A-004 lines 183–198；A-005 lines 229–240；A-006 lines 266–275；A-009 lines 397–421；A-010 lines 469–527；A-014 lines 656–698；A-015 lines 700–730；A-016 lines 738–773。
- **G**：[AGENTS](../AGENTS.md)，Product Hard Constraints、Data Privacy、User-owned Git、Reviewer/Executor；[设计汇总](../Aureus_Wealth_Terminal_项目设计汇总.md) §§15、18、19、20；[研究证据](V1_RESEARCH_EVIDENCE.md) §13 是出处连续性，不是运行时证明。
- **S6**：[Stage 6 acceptance](STAGE6_MARKET_DATA_ACCEPTANCE.md) §§1.1、3.2、4、5、6；[retention decision](STAGE6_TWELVE_DATA_RETENTION_DECISION.md) §§1.1、2、7。历史 live 观察只对当时的 endpoint/MIC/credential 有效，不推导当前 entitlement。

主 Executor 按序全文审阅用户指定十份正文，长文件截断处补读；源码/测试按完整相关语义阅读并接受只读子代理映射，不冒称全仓 READ TO EOF。实际记录与安全清单见本轮 [ExecutionReport](/private/tmp/Aureus-Stage11-SCOPE-EVIDENCE-AUDIT-01-h3ILCY/ExecutionReport.md)。

矩阵的实现状态为 `IMPLEMENTED / NOT IMPLEMENTED / PARTIAL`；自动化状态为 `VERIFIED / NOT VERIFIED`，其中 VERIFIED **只指列出的既有断言与相关源身份支持**。本轮执行状态统一为 `NOT RUN — DOCUMENTATION AND READ-ONLY AUDIT ROUND`；证据复用统一为 `NOT RUN — ACCEPTED EVIDENCE AFTER RELEVANT SOURCE-IDENTITY VERIFICATION`。人工观察列统一 `NOT RUN / NOT VERIFIED`，除明确标为历史观察的 S6，不能由自动化替代。

## 2. Artifact 与 relevant identity 索引

| ID | 准确 artifact / 接受来源 | 本轮身份核验、复用范围及限制 |
|---|---|---|
| E-UI | `/private/tmp/Aureus-Stage11-APP-CONNECTION-DIAGNOSTIC-CLOSURE-03-jKe2QJ/`：`LedgerDynamicDiagnostic.xcresult`、`ExistingFocusedRegression.xcresult`、`FullAureusUITests.xcresult` | Reviewer 接受 `1/1`、`12/12`、`18/18 PASS`，exits `0`、parsers `0/0`。本轮目录/Info.plist存在，116项当前源全匹配，四项产品Hash匹配；不机械重复解析，不读附件。`ACCEPTED EVIDENCE`，仅实际断言。 |
| E-U | `/private/tmp/Aureus-Stage11-SETTINGS-EXTERNAL-BACKUP-RESTORE-UI-01-A9c0OF/`：`FocusedUnit-Final.xcresult`、`AffectedRegression-Final.xcresult`、`FullAureusTests-Final.xcresult` | 已接受 definitions/dynamic executions `134/168`、`167/205`、`460/531 PASS`。对应 `final-source-inventory.sha256` 中 Product、Unit、Project 95/95匹配；三个目录与Info.plist存在。复用对应套件，不将definition数误当dynamic outcomes。 |
| E-RP | `/private/tmp/Aureus-Stage11-EXTERNAL-BACKUP-RESTORE-VALIDATION-CLOSURE-01-skIX9p/ReleaseExternalRestorePerformance.xcresult` | 已接受25/49、10,000-row `43 ms`；Foundation/相关Unit源匹配。历史清单95项中5项Settings/composition后续变化不属于该isolated workload。`ACCEPTED EVIDENCE`，不是整个旧App composition同源或跨机器保证。 |
| E-EP | `/private/tmp/Aureus-Stage11-SETTINGS-EXTERNAL-BACKUP-EXPORT-UI-01-ayEbIL/ReleaseExternalExportPerformance-Final.xcresult` | 已接受29/31、10,000-row `26 ms`真实历史不变；但直接依赖 `PermanentBackup.swift` 后续变化，**HISTORICAL ONLY**，当前完整验证链的独立Release计时 `NOT VERIFIED`。E-U当前Debug Export覆盖不能替代Release。 |
| E-B | `/private/tmp/Aureus-Stage11-EXTERNAL-RESTORE-DIRECTORY-PANEL-CLOSURE-01-bEN0A5/`：`CleanDebugBuild.xcresult`、`BuildForTesting.xcresult`、`TargetedExternalRestoreUI.xcresult` | Reviewer已接受构建与独立1/1；最新E-UI使用该冻结signed产品。本轮不build/sign、不把BFT当UI执行；签名类别历史为local ad hoc，不是发行签名。 |
| E-S6 | S6的Core Entry Reviewer接受记录与限定live matrix | 当前Service/Keychain/Cache/Unit源由E-U相关95项身份支持synthetic回归；旧live与凭据配置事实为`HISTORICAL ONLY`，不能声称现时真实Keychain/Provider已复验。retention `BLOCKED`独立保留。 |

基线 `jKe2QJ/FinalInventory.json` 自身SHA-256：`13769352e001def05e84080904b52cc6cd7c6055b22637251a7d6228aab55726`。使用 `inventory[].sha256`，不是历史 `expected`；路径安全/普通文件/无symlink、实际116集合与Hash全部通过。Unit清单自身SHA `8d19965641b385be3f952dccc41fd090c4423e141d3901d2f9ce64d0fe1b2b69`；Restore清单 `77fa5c0ae27c845c0d8461ef4c7f3efa72fc7ff4d048e72410f3b5fe4ba5abf6`；Export清单 `f02f3943564cccb79332201c3a83c551141a49ad29357765759c2924f0371674`。后面三项为本轮计算的来源身份，不冒充用户提供的签名证明。

### 源码导航简称

以下表中“文件简称:行号/符号”是精确源码定位，箭头表示调用关系；不是仅凭identifier搜索定案。

| 简称 | 实现 / 测试路径 |
|---|---|
| SV / SM / LM | [SettingsView](../Aureus/Features/Settings/SettingsView.swift) / [SettingsFeatureModel](../Aureus/Features/Settings/SettingsFeatureModel.swift) / [SettingsDataLifecycleModel](../Aureus/Features/Settings/SettingsDataLifecycleModel.swift) |
| AD / RP / AM | [AppDependencies](../Aureus/App/AppDependencies.swift) / [RuntimePaths](../Aureus/App/RuntimePaths.swift) / [AppModel](../Aureus/App/AppModel.swift) |
| BK / RS / ER / EX / MS | [PermanentBackup](../Aureus/Persistence/Backup/PermanentBackup.swift) / [PermanentRestore](../Aureus/Persistence/Backup/PermanentRestore.swift) / [PermanentExternalRestore](../Aureus/Persistence/Backup/PermanentExternalRestore.swift) / [PermanentBackupExport](../Aureus/Persistence/Backup/PermanentBackupExport.swift) / [PermanentMigrationSafety](../Aureus/Persistence/Backup/PermanentMigrationSafety.swift) |
| CS / DS | [MarketCacheStore](../Aureus/Persistence/MarketCache/MarketCacheStore.swift) / [MarketDataService](../Aureus/Services/MarketDataService.swift) |
| BT / RT / ERT / ET / MT / LT | [PermanentBackupTests](../AureusTests/PermanentBackupTests.swift) / [PermanentRestoreTests](../AureusTests/PermanentRestoreTests.swift) / [PermanentExternalRestoreTests](../AureusTests/PermanentExternalRestoreTests.swift) / [PermanentBackupExportTests](../AureusTests/PermanentBackupExportTests.swift) / [PermanentMigrationSafetyTests](../AureusTests/PermanentMigrationSafetyTests.swift) / [SettingsDataLifecycleTests](../AureusTests/SettingsDataLifecycleTests.swift) |
| CT / DT / KT / UI | [MarketCacheInfrastructureTests](../AureusTests/MarketCacheInfrastructureTests.swift) / [MarketDataInfrastructureTests](../AureusTests/MarketDataInfrastructureTests.swift) / [KeychainAndFXInfrastructureTests](../AureusTests/KeychainAndFXInfrastructureTests.swift) / [AureusUITests](../AureusUITests/AureusUITests.swift) |

## 3. Settings、Cache、Credential 与离线矩阵

| ID / 冻结来源与Stage ownership | 要求 → 实现与调用关系 | 测试名称及实际断言 | 实现 / 自动化 / artifact | 人工与限制、最小下一步 |
|---|---|---|---|---|
| S11-01；S43/123/193，A669；Stage11 | Settings currency/display preferences。SV55 body→SM整类型无此状态/store；AD71仅注入Markets/Portfolio局部偏好 | 通用Settings无对应断言；MarketsTerminalTests.preferences验证identifier/UIchoices，不能替代通用currency/display | `NOT IMPLEMENTED / NOT VERIFIED`；无artifact | 人工NOT RUN；D-01决定最小选项，不改CNY估值权威 |
| S11-02；A266–275、S20–24；Stage3/5金融权威，Stage11偏好必须保持 | Money/FX原币+转换值；[LedgerCSV](../Aureus/Domain/Ledger/LedgerCSV.swift):77 header保留原币/FX/provenance，preview→typed posting；偏好不得重写历史 | [LedgerCSVTests](../AureusTests/LedgerCSVTests.swift):28 transfer/USD roundtrip；UI.testWealthCNYUSDLiabilityCRUDAndDynamicTotals:1966与Ledger完整summary覆盖CNY/USD | `IMPLEMENTED / VERIFIED`（所列断言）；E-U/E-UI | 人工NOT RUN；没有获准改统一估值币种或自动FX |
| S11-03；A492–527，S124/193；Stage6→11 | 512MiB默认/范围/90→80水位、TTL/LRU；[CachePolicyConfiguration](../Aureus/Persistence/MarketCache/CachePolicyConfiguration.swift)→CS.cleanup/store/updateMaximum；AM.runMarketCacheMaintenance与AD.launch cleanup | CT.cleanupPriority:259断言优先淘汰、≤80%；cleanupScheduleBookkeeping:340断言各schedule独立；capacityReductionRollback:490失败后容量/行数/result不变 | `IMPLEMENTED / VERIFIED`；E-U | 人工NOT RUN；不能以配置存在证明每个真实长时调度点已观察 |
| S11-04；A519–527，S124；Stage6→11 | SV.cacheSection→SM.removeExpired/resetCache/applyMaximum→CS对应事务/reset；reset只准确cache DB及sidecars | CT.providerPurgeAndReset:318、allCleanupPathsArePermanentlyIsolated:527比Permanent URL/Hash/schema/records/snapshots；UI.testStage6SettingsCredentialEntitlementAndCacheLifecycle:2180确认Remove/Reset终态 | `IMPLEMENTED / VERIFIED`；E-U/E-UI | 人工NOT RUN；UI未断言capacity Apply全部选项，不夸大UI覆盖 |
| S11-05；A521；Stage11 | Settings bytes/cap/percentage/entries/oldest/provider breakdown：CS.statistics419→SM.refresh207→SV327–380 | UI同Settings方法只断言summary存在；CT统计/容量断言，不证明所有字段AX读出 | `IMPLEMENTED / NOT VERIFIED`（所有字段端到端AX）；字段计算E-U，有限UI E-UI | 人工NOT RUN；oldest以epoch文本显示且被summary的children-ignore省略，易读性/AX须限定补证 |
| S11-06；A521；Stage11 | last cleanup result/time：CS.record745持久化last_cleanup_ms→statistics419→SM207；SV336/344只消费result，无lastCleanupAt | CT现有result/schedule断言非timestamp；无exact时间/reopen/失败保持/reset-nil或时间AX断言 | 存储`IMPLEMENTED`、展示`NOT IMPLEMENTED`；时间自动化`NOT VERIFIED` | D-02补最小展示/AX与时间断言；nil是无可用记录，不等于从未清理 |
| S11-07；A521；Stage11 | Settings cache stale/offline状态：CS.statistics118与DS.session statistics无该状态，SV292–380未显示；SM.validation offline error不是cache状态 | 无此Settings状态断言；Markets freshness不能替代“Settings displays” | `NOT IMPLEMENTED / NOT VERIFIED`；`DECISION REQUIRED` | D-04确定条目freshness或最近操作状态，不能虚构全局网络探测 |
| S11-08；A469–486、S93–103；Stage6→11 | TD bounded session-only；AD70新session→DS各query→TransientMarketSessionStore；clear/disconnect/rotation/entitlement清除；偏好仅identifier/UIchoice | DT.sessionOnlyServiceRouting:2277重复调用只各一次、5 entries、disk sentinel不变；sessionStaleFallbackBoundaries:2326 credential error清session；UI Settings clear/Markets reconstruction | `IMPLEMENTED / VERIFIED`；E-U/E-UI，rights仍BLOCKED | 人工NOT RUN；mock transport有实际调用，不能称全系统0 |
| S11-09；A484/510/522，S129；Stage6/7→11 | offline/timeout有旧session：DS.latestQuote411与historicalBars467保留时间并标stale；FX referenceRate633独立cache策略；MarketsView316/400显示freshness/fetched | DT.sessionStaleFallbackBoundaries断言旧price/quality.offline/stale，invalid credential不fallback；KT.fxStaleOffline:263旧rate相同/stale，miss抛missing | `IMPLEMENTED / VERIFIED`（synthetic有限分支）；E-U | 手工offline NOT RUN；不延伸为当前live entitlement或真实离线观察 |
| S11-10；A484/421，S129；Stage6/7→11 | relaunch空session不造值已实现；但DS.search400–407 offline无旧值→missing→MarketsFeatureModel.apply509/disclosure549→“Requested session data is missing.”，覆盖View277默认Offline文案 | DT.sessionStaleFallbackBoundaries末尾明确expect `.missing`；无fresh-session model/UI断言保证明确Offline文本 | `PARTIAL / NOT VERIFIED`（明确Offline呈现）；E-U仅证明现有missing行为 | D-05保留offline原因的有限错误/呈现候选；不是本轮新runtime FAIL |
| S11-11；A397–414/668，S128；Stage6→11 | SecureField SV147→SM.save58（defer清输入）→DS.ProviderCredentialCoordinator849→[KeychainCredentialStore](../Aureus/Security/KeychainCredentialStore.swift):34；service/account、ThisDeviceOnly、无同步 | KT.nativeKeychainLifecycle:122以随机synthetic service真实SecItem save/read/rotate/delete；[ProviderBoundaryTests](../AureusTests/ProviderBoundaryTests.swift):86 policy + InMemory断言；UI Settings输入清空/配置标签 | `IMPLEMENTED / VERIFIED`（synthetic native及mock UX）；E-U/E-UI | 真实用户Keychain/权限人工NOT RUN；UI “Configured in Keychain”不是其mock真的访问Keychain |
| S11-12；A409–421；Stage6→11 | explicit Validate/Disconnect/Delete；SM→coordinator.revoke882先provider.disconnect再session clear、provider cache purge、key delete；capability按endpoint而非typed Plan | KT.credentialCoordinatorLifecycle:144 validates typedmissing、清provider保留FX；UI Settings validation synthetic states/两次确认删除；DT负责transport barrier相关回归 | `IMPLEMENTED / VERIFIED`（所列synthetic断言）；E-U/E-UI/E-S6 | 真实Plan/MIC/freshness仍按历史S6限定，不能要求本轮live再验 |

## 4. Import/Export、Backup/Restore、Migration 与 integrity 矩阵

| ID / 来源与Stage | 要求 → 完整主调用链 | 测试名称与断言 | 实现 / 自动化 / artifact | 人工与限制、最小下一步 |
|---|---|---|---|---|
| S11-13；S63–71/125，A674；Stage4→11 | LedgerView.fileImporter64 scoped读取→LedgerFeatureModel.prepareImport265→LedgerCSV.preview105：header/row/duplicate/rule；Confirm277→LedgerPersistence.importLedgerEntries197 queue.write事务 | LedgerCSVTests.atomicImportRollback:298、previewConfirmRace:311、semanticPreviewConfirmRace:331 typed conflict后整批回滚；UI.testLedgerNativeCSVImportPreviewConfirmationAndExport:2136预览规则/确认expense | `IMPLEMENTED / VERIFIED`；E-U/E-UI | 人工panel NOT RUN；只支持Aureus Ledger CSV，不泛化raw SQLite/general import |
| S11-14；S125，A667；Stage4→11 | Ledger model.exportData→LedgerCSV.export87→SwiftUI.fileExporter74默认Aureus-Ledger-V1；存量记录原币FX字段保留 | LedgerCSVTests quoted/UTF8/formula与transfer roundtrip；UI NativeCSV预先不存在、Save后准确默认URL存在、无Ledger Error | `IMPLEMENTED / VERIFIED`；E-U/E-UI | UI断言文件存在不等于逐字段roundtrip，字段证明来自Unit；人工NOT RUN |
| S11-15；A664–666/704，S126；Stage11 | LM.createBackup→WealthStore.createPermanentBackup BK752→BK.create61 actor queue.backup，目标关闭后manifest/digest→staging验证→move→committed验证 | BT.consistentBackupRoundTrip:38读回sentinel；sourceRemainsUnchanged:421；exactArtifactSet:474严格twofiles无WAL/SHM | `IMPLEMENTED / VERIFIED`；E-U、UI internal create | 人工NOT RUN；不称livefile copy、自动定时备份或整个sandbox备份 |
| S11-16；A707–708；Stage11 | BK.validateGeneration176→root/directChild397→唯一contents411→manifest六字段、UTC、SHA/bytes→MS.inspectFile143 query_only quick/FK/schema | BT.manifestFields75/databaseByteCount114/databaseSHA256125/tamperedDatabase136/unexpectedArtifact300；ET.sqliteValidation54完整current schema/IDs | `IMPLEMENTED / VERIFIED`；E-U | 人工NOT RUN；schema6 app invariant检查并非逐行比较所有金融业务值 |
| S11-17；A666/706；Stage11 | BK.inventory284分类valid/invalid/ignored→sort683→prune340删除前再验证、仅超额validated direct children | BT.retainsLatestFive313、deterministicTieBreaker338、failedSixthPreservesFive357、preservesInvalidAndUnknownSiblings397 | `IMPLEMENTED / VERIFIED`；E-U | UI最多观察1→2，五代证明来自Unit而非18/18本身 |
| S11-18；A709–710；Stage11 | LM.restoreSelected confirmed→RS.restorePermanentBackup359，maintenance/live/strict internal candidate→共享core388 | RT.unsafeCandidatesRejected140；ERT.internal path rejection/成功内部恢复:678；LT.unconfirmedRestore495 | `IMPLEMENTED / VERIFIED`；E-U | arbitrary external path不能通过internal API；人工NOT RUN |
| S11-19；A709–710/726；Stage11 | core candidate staging+digest→current inspect→consistent safety并验证→checkpoint/close→atomic replace→migrate/current validate→同actor rebind，全段无await | RT.currentSchemaRestore10、safetyBackupPreserved33、legacyForwardMigration77、noActorReentrancyWindow508；UI internal method1245确认Cancel/Restore/Goals | `IMPLEMENTED / VERIFIED`；E-U/E-UI | current-schema迁移器idempotent，不声称完全不触碰SQLite metadata；人工NOT RUN |
| S11-20；A710/726；Stage11 | core activation失败→rollback revalidate safety/stage/atomic replace/reopen；失败进入recoveryRequired；LM禁用生命周期操作 | RT.migrationFailureRollsBack241、postRestoreInvariantFailureRollsBack281、rollbackFailureIsFinite307；LT.externalRestoreRecoveryPresentation429断言四controls disabled | `IMPLEMENTED / VERIFIED`（限定恢复与model合同）；E-U | 未直接证明recoveryRequired后每一种跨feature CRUD；不得把单个后续Restore拒绝写成全CRUD覆盖 |
| S11-21；A711/667/708；Stage11 | LM.exportSelected345→EX.export94先BK source验证→安全destination265→unique stage只复制两文件→共享validator→atomic move→committed revalidate | ET.validExport10/byteIdentity24/digestAndManifest36；copyFailureCleanup318/stagingValidationFailure337/atomicCommitFailure354/committedRevalidationFailure371 | `IMPLEMENTED / VERIFIED`；E-U/E-UI | E-EP计时仅历史；typed failure不伪成功；人工NOT RUN |
| S11-22；A667/711；Stage11 | EX destination absolute/plain/writable/resolved/protected overlap/collision，operation scope；no external prune | ET.destinationCollision286/unrelatedSiblingPreserved305/noExternalRetention387/internalRetentionUnchanged400（7外代仍7、内5不变） | `IMPLEMENTED / VERIFIED`；E-U | 生产配置AD无硬编码Repository root保护；UI警告不选repo/publicfolder，不能声称自动识别所有任意源码仓库 |
| S11-23；A667/711；Stage11 | SV共享.folder importer→handleExternalExportSelection678 start→await model→defer stop；不存destination | UI ExternalExport1489：一次Escape、空destination/inventory1/Ready；成功twofiles/bytes/result；reconstruction result清除/selection disabled/artifact不变 | `IMPLEMENTED / VERIFIED`（公开UI效果）；E-UI | start/stop次数不是UI全程遥测；手工scope/signedsandbox观察NOT RUN |
| S11-24；A674/709–710；Stage11 | ER.restoreExternalPermanentBackup61→保护root排除→BK.standalone224直接contents不读取parent→同RS core；internal入口不放宽 | ERT schema-zero352仅manifest0→正式API typedmalformedManifest、0copy/replace/safety/ready/source不变；future391 typedschemaMismatch；legacy87支持1…5 | `IMPLEMENTED / VERIFIED`；E-U | parent-bookmark能力不要求；手工真实用户security scope NOT RUN |
| S11-25；A708–710；Stage11 | External仅复制DB为live-parent候选staging，不将generation持久加入internal inventory；安全代才新增；source只读 | ERT success9、independent57、activation rollback610、rollbackFailure652、retention728：source fingerprint不变、stage清空/unknown保留、内5代和safety | `IMPLEMENTED / VERIFIED`；E-U/E-UI | 无history是源码依赖+限定文件/调用断言，不是全系统持久化遥测 |
| S11-26；A667/674/709；Stage11 | SV716选择→SettingsExternalRestoreSecurityLease777→app-owned confirmation；736 beginOperation防重复，await正式API→finish；idle取消/disappear释放 | UI ExternalRestore1675完整两种Cancel、四exact AX节点、Confirm一次、inventory1→2、probeGoal消失/原2恢复、artifact bytes不变；LT.externalRestoreCapabilityAndInvocation297调用数1 | `IMPLEMENTED / VERIFIED`；E-U/E-UI/E-B | lease私有对象未被Model Unit直接测量；人工VoiceOver/keyboard/scope NOT RUN |
| S11-27；A193/705/709，S127；Stage11 | WealthStore.init/migrate→MS.migrate247/classify359：fresh/current无backup，legacy严格migration prefix先backup后migrate；未知/不一致拒绝 | MT.legacyVersions66/legacyBackupAuthority94/missingConfiguration119/backupFailureStopsMigration131；transaction failure346、postvalidation384、reopen412 | `IMPLEMENTED / VERIFIED`；E-U | 保留旧generation后有限失败，不自动选其他backup；不改schema6/六migration IDs |
| S11-28；A183–198/229–240/709；Stage2…11 | DatabaseQueueFactory.open foreign_keys ON；actor queue事务；MS.current inspect required tables/IDs/noREAL；金融计算保持fixedpoint | [PersistenceTests](../AureusTests/PersistenceTests.swift) migration/isolation/storage；CT Permanent完整sentinel比较；RT/ET integrity；Ledger批量race rollback | `IMPLEMENTED / VERIFIED`（已列测试域）；E-U | 本审计不声称穷尽所有损坏形式、真实用户Store或所有金融结果；Release性能仅E-RP当前相关同源 |

## 5. Privacy、隔离与人工质量边界

| ID / 来源与Stage | 实现与调用关系 | 断言与artifact | 实现 / 自动化 | 限制与最小下一步 |
|---|---|---|---|---|
| S11-29；G Data Privacy、A668/673/708；Stage6→11 | Production Keychain authority，manual .secrets不作runtime源；BK/EX只允许db+manifest；Settings warning明确私密备份 | BT.manifestPrivacy/adjacentIsolation，RT.resultAndErrorPrivacy550，ET.sanitizedResultAndErrors451；E-U | `IMPLEMENTED / VERIFIED`（有限result/artifact）；本轮live NOT RUN | 不访问.secret连metadata也未访问；不能由无输出推断全系统无秘密 |
| S11-30；S193、A670/675/712；Stage11 | Product Swift无OSLog/Logger/NSLog/print authority；不能把无主动日志等同已实现统一日志 | 无OSLog私密插值/事件sink断言、无该runtime artifact | `NOT IMPLEMENTED / NOT VERIFIED` | D-03有限事件方案待裁决；不建遥测/日志文件/远程上传 |
| S11-31；A563–568/675；Stage7→11 | MarketChartWebView70/85有限error映射→MarketChartInboundMessage.decode198 whitelist→bundled JS；CSP connect-src none，无console输出命中 | MarketsTerminalTests.inboundMessages171拒绝raw freeform error；E-U；Unit性能print与第三方诊断分开 | `IMPLEMENTED / VERIFIED`（桥接有限契约）；不是OSLog实现 | vendor仅受限符号扫描，不能保证系统WebKit永不诊断；Ledger本地error UI自由文本不能传进未来日志 |
| S11-32；A677/711；Stage11 | SV580 disclosure不加应用层加密，external warnings636/640要求私密受控存储；无ZIP/encryption实现 | UI ExternalExport/Restore exact warning断言；E-UI，BT manifest字段无encryption伪声明 | `IMPLEMENTED / VERIFIED`（披露）；人工NOT RUN | sandbox/macOS保护不是Aureus独立加密；无新增加密授权 |
| S11-33；A195/671、S129/131/193；Stage2…11 | LaunchConfiguration.current demo/ui-testing/temp→RP.temporary；AD.make selects InMemoryCredential/SyntheticProviders与memory prefs；真实local graph路径独立 | UI ExternalRestore尾部Local-mode空Goals/inventory0、无自动panel，Export artifact仍同；LT.temporaryCompositionRootIsolation646；E-U/E-UI | `IMPLEMENTED / VERIFIED`（temporary-store隔离） | 测试变量production仍隔离store，**不是实际用户Production Store验证**；不做全进程live计数推断 |
| S11-34；A773、S130/194；Stage12人工/全局hardening（Stage11明确缺口仍留本Stage） | 现有native AX节点与chart fallback不等于人工使用质量 | E-UI18/18只证明实际自动化断言；manual artifact未取得 | `PARTIAL / NOT VERIFIED`；人工`NOT RUN` | VoiceOver/keyboard-only/contrast/appearance/chart interaction/真实sandbox-panel-offline人工观察需后续授权；不在本轮启动 |

## 6. 最小补齐候选合同与集中决策

以下均是**建议，未批准、未实施**。不得据此自行扩展范围或将Stage11缺口挪到Stage12。

| 决策/缺口 | 冻结文本已经确定 / 尚未确定 | 最小候选与影响范围 | 建议的必要验证（本轮全部NOT RUN） |
|---|---|---|---|
| D-01 Currency/display | S43确定职责；未确定选项、消费视图、默认值。A266确定CNY估值权威，A240区分显示与canonical CSV | Reviewer选择“新表单默认输入币种”或一个明确显示策略；再选一个有限display选项。Settings窄preference type/store、SM/SV、AD与指定消费视图；UserDefaults只存nonsecret设置、temporary graph memory-only | 默认/未知值fallback、重启持久化、temporary隔离、UI/AX、CNY/USD/FX历史不变、无自动Provider请求。不添加主题/语言/跨设备系统，不改Money/Snapshot公式 |
| D-02 Last cleanup time | A521已要求result/time；CS已持久化UTCInstant。nil包括reset清空metadata，不能叫never cleaned | 仅SV消费lastCleanupAt，有限稳定AX；时间格式与timezone明确，nil“尚无可用清理记录”。可同时纠正oldest epoch可读性，但需授权，不能隐式扩范围 | FixedClock exact time、重开一致、失败不推进、reset nil、SM刷新、UI时间/AX。保持TTL/水位/容量/purge/Permanent隔离不变 |
| D-03 OSLog | A670/675/712明确unified/private/exclusions；未确定事件/level/精确bucket必要性 | 只给现有Backup/Restore/Export/migration/rollback/manual-cleanup终态小型typed adapter；operation/result/errorCategory枚举、必要duration bucket/count。Reviewer决定是否含credential/provider lifecycle。禁止接受任意String/Error/URL/row/payload参数 | synthetic敏感哨兵不进入event，成功/失败/rollback各有限事件，adapter private-by-default静态检查；不读取真实OS logs，不加日志缓存/导出/telemetry/新依赖，不改close-to-rebind顺序 |
| D-04 Settings stale/offline | A521明确Settings展示；尚未定义条目freshness、最近操作状态还是连通性，语义不同 | 决定准确可推导状态及nil/unknown；仅现有数据的有限显示，禁止后台探测或伪网络指示 | mock状态→Settings exact label/AX；不把Provider validation错误当cache整体状态 |
| D-05 Offline empty-session呈现 | A484明确relaunch offline miss为Unavailable Offline；当前`.missing`丢失offline原因 | Reviewer确认服务typed error或model映射最小修正，区分offline/timeout/真missing；可能影响DS、MarketsFeatureModel及Unit/UI | fresh-session mockoffline→明确unavailable、不造值、不Synthetic fallback；旧stale保留timestamp；不新增网络/磁盘TD缓存 |
| D-06 Export Release同源证据 | 26ms旧PASS保留，但其共享validator已变；没有本轮补跑授权 | Reviewer决定接受额外依赖变化论证还是另行授权当前Export suite Release复验；本审计不替Reviewer豁免identity条件 | 确需复验时才按新授权真实10,000-row export+committed validation；不能拿Debug/18UI/Restore43ms替代 |

E-EP差异：`PermanentBackup.swift` 旧 `44ebae07ffbab669f984520c3efe751f5c8ba1a02621ee4fb4c014f66d3c14c3` → 当前 `7bdd0aaa1ab05ee6356f3ed27b7a46ce831d4bbfca851b056c08662718f546a9`。EX.validatedSource240与validateCopiedArtifact307直接调用此authority；不是无关文档/UI变化。旧 `PermanentRestore.swift` 也变化，但仅Backup这一直接依赖已足以限制Export计时同源复用。最新E-U仍支持当前Export业务正确性。

## 7. 结论与边界

当前已实现且具有accepted synthetic/Unit/UI证据的Backup、Restore、Export、migration、CSV、Keychain/cache子合同，不覆盖尚未实现的preferences、cleanup时间展示、OSLog，以及上述状态呈现/证据限制。不能用18/18自动化宣布Stage11完整。

历史PID59940首次断连原因仍 `UNKNOWN`；jKe2QJ规定执行中未复现，不等于根因修复。本轮没有执行，不能说“本轮未复现”。历史完整Failed、unknown/0-test、incomplete、Mandatory Read与numeric-exit缺口原样保留在[Stage11 acceptance](STAGE11_DATA_LIFECYCLE_ACCEPTANCE.md)。

Provider requests `NOT RUN`；本轮无live Credential/Keychain/Market Cache/用户Store操作，不将synthetic fixture能力或未遥测的全系统计数伪报为0。Twelve Data persistent writes `Disabled`；Provider retention rights `BLOCKED`。无scheduling/cloud/external retention/ZIP/compression/application-layer encryption/AI新增要求；Stages12–14 `NO-GO`。未运行Git/gh，未访问.git/.secrets/default.profraw payload。建议均等待Reviewer/用户裁决；报告后STOP，不生成下一轮Prompt。
