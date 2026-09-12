# Stage13 发布候选证据审计

日期：2026-09-12。授权：`13-ENTRY-RC-AUDIT-01`。Executor 仅完成静态与已有证据审阅、限定文档更新；Reviewer 拥有 Stage Gate 和 Release Gate 裁决权。

## 1. 授权与当前状态

用户已确认：

> 确认接受上述未验证风险，按‘用户例外放行、技术证据仍 PARTIAL’进入 Stage13

Stage11 PASS 保持；Stage12 用户例外放行、技术证据仍 PARTIAL；Stage13 已授权入场并提交本轮审计，总 Gate 未通过；Stage14／发布 NO-GO。这是入场例外，不是质量结果重分类或发布许可。此前未执行的 `12-OFFLINE-NATIVE-MANUAL-AND-CANCEL-01` 被替代，本轮不运行其 BFT、App 或人工检查。

本轮限定审阅未发现新的已确认缺陷。此结论不等于产品没有缺陷、全部 V1 能力已完成验收或所有风险已排除。下文把已接受技术证据、已接受入场风险、独立待决策事项分别列出；没有因已知未测项再次阻止入场。

## 2. 当前候选源码身份

候选是 `/Users/freeforest/Aureus_Wealth_Terminal` 当前安全文件集合，不是 Git commit、Tag、RC 版本号或发行包。没有读取 `.git`。

| 身份项 | 本轮核验 |
|---|---|
| 已接受起点 | E-W2 `FinalInventory.json`，123 项 |
| 清单自身 SHA256 | `1186ef3ca14606b77f94e8928fc1f9f45f6d0dd83a87b6102923e4b26e5ee6c6` |
| 123 项规范化 SHA256 | `6bd39d968c398b4ea92decff838f9882ffeb6564e6da59a3503c4051a71148e0` |
| 算法与边界 | 安全 `rg --files`，排除 `.git`、`.secrets`、`default.profraw`，显式加入 `.gitignore`；先核对路径集合及逐组件 lstat，再哈希普通文件。相对路径 UTF-8 字节序；每行小写 SHA256＋两个 ASCII 空格＋相对路径＋LF |
| 当前性 | 起点 123 项逐项匹配；目标审计文档原先不存在。E-W2 `PostUnitInventory.json` 与其最终清单仅计划文档不同，122 项相同，故当前代码/测试/项目输入仍对应已接受的成功 Unit 轮次 |
| 本轮文档变化 | 只新增 README 当前摘要、追加 Stage12 交接、新建本审计。最终 124 项清单与 121 项冻结证明见本轮报告；产品与测试源码没有变化 |

对 E-LC 的 122 项源码清单作定向比较：当前新增 Stage12 计划；三个产品文件 `RuntimePaths.swift`、`AppDependencies.swift`、`SyntheticProviders.swift`，两个 Unit 文件 `GeneralSettingsTests.swift`、`MarketsTerminalTests.swift` 及三个历史收尾文档已变化，其余 114 项相同。旧 signed App 不含新增六场景入口，不能以界面文件没变化推定整个 App 同源。[SourceApplicability.json](/Users/freeforest/Aureus_Engineering_Evidence/Stage13-ENTRY-RC-AUDIT-01-0pTYtQ/SourceApplicability.json)保存比较来源。这里比较源码清单，没有重新哈希或验证旧二进制。

## 3. 证据索引与适用规则

本轮所有运行证据均为 inherited / NOT RUN in this round。静态阅读只说明实现或配置；已接受运行只证明该次输入、产品和检查点；USER REPORTED 不升级成自动化或文件字节证明。

| 代号 | 准确来源与可用范围 |
|---|---|
| E-W2 | [ExecutionReport](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-OFFLINE-UI-HARNESS-01-WmpCMn/ExecutionReport.md)、[FinalInventory](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-OFFLINE-UI-HARNESS-01-WmpCMn/FinalInventory.json)、[UnitResults](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-OFFLINE-UI-HARNESS-01-WmpCMn/UnitResults.json)、[DebugIsolation](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-OFFLINE-UI-HARNESS-01-WmpCMn/DebugIsolation.json)、[FinalProducts](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-OFFLINE-UI-HARNESS-01-WmpCMn/FinalProducts.json)。当前代码的 unsigned BFT / Full Unit 技术证据 |
| E-CC | [UIBusinessResults](/Users/freeforest/Aureus_Engineering_Evidence/Stage11-CONSOLIDATED-CLOSURE-01-ZnXAET/UIBusinessResults.md)及 [报告](/Users/freeforest/Aureus_Engineering_Evidence/Stage11-CONSOLIDATED-CLOSURE-01-ZnXAET/ExecutionReport.md)。历史 Full Unit 491/597、597/0/0；Release Export 29/31、31/0/0；10,000-row export＋committed validation 28 ms；相关 BFT。历史 signed Full UI 21 definitions / 21 executions，20/1/0 Failed，exit65、parsers0/0，绝不是 Full UI PASS |
| E-OBS / E-LC | [直接观察报告](/Users/freeforest/Aureus_Engineering_Evidence/Stage11-CACHE-AUDIT-DIRECT-OBSERVATION-01-eD7IAF/ExecutionReport.md)、[en/US 报告](/Users/freeforest/Aureus_Engineering_Evidence/Stage11-CACHE-AUDIT-LOCALE-CONTRACT-01-Fv0v66/ExecutionReport.md)；由当前 Stage11 矩阵继承。前者 count=1、label 中英语单位/U+0020 与中文单位/U+2006 不一致，单方法 Failed；后者显式 en/US 独立 1/1 Passed、17 条完整唯一 label 检查。两个进程 Locale getter、历史选择机制及历史唯一根因仍未验证 |
| E-W1C | [W1 补证报告](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-W1-ARTIFACT-AND-GRAPH-CLOSURE-01-dxzPBT/ExecutionReport.md)，结合本 Prompt 的 Reviewer 接受：新 CSV、外部备份两文件恢复前/后/最终字节身份有限接受；第二 temporary graph G1–G7 为 USER REPORTED。不是当前新源码的 signed 运行 |
| E-W1 | [旧人工基线报告](/Users/freeforest/Aureus_Engineering_Evidence/Stage12-NATIVE-MANUAL-BASELINE-01-Iaul8w/ExecutionReport.md)及计划所载用户反馈。整体“无问题”仅在实际人工范围内保留；旧 CSV 缺失、Backups 空且用户自报删除，不裁定为 App 导出失败；旧第二图缺证和完整 AX 输出范围偏差保留 |
| Stage11 / D-03 | [范围与证据矩阵](STAGE11_SCOPE_EVIDENCE_MATRIX.md)的 S11-01–34、D-03/D-06、最终 Gate；D-03 [E-OSL-RB 报告](/Users/freeforest/Aureus_Engineering_Evidence/Stage11-OSLOG-EVIDENCE-REBASELINE-01-DS0fIa/ExecutionReport.md)为有限 static/Unit。旧 Dlr35W `/private/tmp` 原件丢失，HISTORICAL ONLY，不能借新包补旧证据 |

本轮未重新解析 xcresult；只读取已接受 JSON、报告和已导出的 Full 测试树。为模块映射从 E-W2 `FullTests.stdout.log` 的 JSON 树得到同包 suite 子集；不是新执行或独立 Focused，也不是逐项 V1 验收数量。

## 4. V1 要求—实现—证据—限制

冻结要求来自 [V1_SCOPE](V1_SCOPE.md) §2–8、[V1_ARCHITECTURE](V1_ARCHITECTURE.md) A-014–017 及 Provider/session-only 约束。以下 definitions/executions 是 E-W2 同一个 Full 包内计数，所有列出的执行节点为 Passed，绝不与历史 UI 数量相加。

| V1 要求 | 已审阅的实际实现与验收来源 | 已接受覆盖 | 仍有限制的部分 |
|---|---|---|---|
| §2/§2.1 产品定位、平台、个人模式、八模块 | [AppShellView](../Aureus/Features/AppShellView.swift)按八个 destination 注入实际 View；[Project](../Aureus.xcodeproj/project.pbxproj) App Debug/Release 为 arm64、macOS14.0、Swift6；根治理/设计的 visualization-first、local-only、单用户 personal/internal/non-commercial、长期无 AI/LLM | E-CC 导航及 Synthetic Demo 方法 Passed；当前 Unit 输入为 arm64 | 配置与页面存在不等于发布验收；不声明 Intel、所有 macOS 版本或商业/托管模式已验证。源码可公开的计划不包含真实数据 |
| §3.1/§3.5 Dashboard | [DashboardDataService.load/refresh](../Aureus/Features/Dashboard/DashboardFeatureModel.swift)读永久 Wealth/Ledger/Goals/完整快照；提供总资产/负债/净值、时间变化、历史高点、allocation/subasset、现金流与两类 heatmap；空 Store 返回空态，不伪造历史；[Stage10 Dashboard integration](STAGE10_GOALS_ACCEPTANCE.md) | E-W2 Dashboard Domain 15/23、Persistence 19/22；E-CC 三个 Dashboard 方法与 Goal 进度/导航方法 Passed | 过去 persisted observations 不代表连续市场历史；旧 signed 界面证据，当前大数据启动/聚合 p95 与完整人工质量未测 |
| §3.1 Wealth 与多币种 | [WealthFeatureModel](../Aureus/Features/Wealth/WealthFeatureModel.swift) reload→aggregate、草稿保存与受保护删除；[FinancialValues](../Aureus/Domain/Money/FinancialValues.swift) Money=Int64 minor units、FX 方向和精度检查；Bank/Cash/Stock/ETF/Fund/Insurance/Other、Liability 等以冻结 Wealth 模型和测试为准 | E-W2 Wealth Domain 5/5、Persistence 9/9，Financial foundations 8/8；E-CC CNY/USD/Liability CRUD 动态总额 Passed | CNY 默认统一估值；USD 原值、应用 FX、CNY 结果必须并存。手工/参考 FX 不是自动实时交易汇率保证；偏好不重写已有金额、FX 或打开草稿 |
| §3.2 Ledger、分类、CSV | [LedgerFeatureModel](../Aureus/Features/Ledger/LedgerFeatureModel.swift) load/filter/CRUD、preview→明确 confirm→原子 import、canonical export；`LedgerDomain.swift`、`LedgerCSV.swift`及 Stage11 矩阵：收入/支出、双边 transfer、投资类、类别/tag、确定性规则和重复检查 | E-W2 Ledger Domain 8/15、Persistence 12/12、CSV 18/24；E-CC 动态现金流/投资/transfer与原生CSV方法 Passed；E-W1C新CSV原件字节身份接受 | UI 方法完成/文件存在不能替代 CSV round-trip 语义；当前候选的原生 panel 人工质量与 scope 释放计数不由 Unit 推定。旧被删除文件的哈希仍缺失 |
| §3.3 Markets、图表、watchlist/heatmap | [Stage7 验收](STAGE7_MARKETS_TERMINAL_ACCEPTANCE.md)及 [MarketsView](../Aureus/Features/Markets/MarketsView.swift)、`MarketsFeatureModel.swift`、`MarketIndicators.swift`：显式 Search/选择/日线刷新、raw MIC、range、candlestick/volume、pan/zoom/crosshair/tooltip、SMA/EMA/RSI/MACD/Bollinger、native Accessible Data、session heatmap；[MarketDataService](../Aureus/Services/MarketDataService.swift) session 查找/typed failure/stale fallback | E-W2 Markets 30/39、Market networking 64/74；E-CC Markets 方法 Passed；W1 实际人工反馈按原记录 USER REPORTED | 四市场是能力披露，不是四市场 endpoint 权利全部通过。当前 UI 日线 1D=Latest Daily Bar，不是 intraday；six-scenario只有 Model Unit，stale 原生入口/人工仍缺；桥接10k bars可编码或 ready不证明首帧/FPS |
| §3.4 Portfolio | [PortfolioFeatureModel](../Aureus/Features/Portfolio/PortfolioFeatureModel.swift)本地 Portfolio/证券关联、activity、NAV 与 session benchmark；[Stage8 合同](STAGE8_PORTFOLIO_ACCEPTANCE.md)：FIFO lot、成本/已实现与未实现、split/oversell校验、v6迁移、完整CNY NAV原子替换，benchmark exact-overlap indexed100 | E-W2 Portfolio Terminal 22/24；E-CC Portfolio CRUD/holdings/snapshot/isolation Passed；Stage8 Reviewer PASS 为历史裁决 | Portfolio quantity 与 Wealth manual mark 的 reconciliation 要披露；benchmark仅显式session请求/精确日期交集，不forward-fill、不冒充TWR或授权证明；新源码没有完整signed跨模块复验 |
| §3.4 Analytics | [AnalyticsFeatureModel](../Aureus/Features/Analytics/AnalyticsFeatureModel.swift)从永久 Portfolio activity/完整 NAV 显式 Calculate；[Stage9 验收](STAGE9_ANALYTICS_ACCEPTANCE.md)登记 Total Return、CAGR、TWR、XIRR、volatility、Sharpe、maximum drawdown、月/年observed returns、checked Decimal、边界/取消状态 | E-W2 Portfolio Analytics Domain15/15、Feature5/5、相关Performance Unit3/3；E-CC Analytics指标/可访问性/隔离方法Passed | 不读Provider计算；缺估值边界/不足数据不是0收益；risk-free为session输入。既有性能Unit不等于A-016六项；旧报告早期PARTIAL与后续Reviewer PASS按日期分别保留 |
| §3.5 Goals、复利、FIRE、储蓄率 | [GoalsFeatureModel](../Aureus/Features/Goals/GoalsFeatureModel.swift)真实 load/create/update/confirmed delete、显式异步计算；[Stage10合同](STAGE10_GOALS_ACCEPTANCE.md) Goal progress、target trajectory、compound、FIRE、saving rate、Dashboard联动；只依赖Wealth/Goals/Ledger | E-W2 Goal Planning15/15、Persistence4/4、Goals Feature6/6、Terminal10/10；E-CC Goals和DashboardGoal方法Passed；W1C两个图固定字段USER REPORTED | USD目标的CNY进度/trajectory不伪造；规划假设session-only，不推荐“安全”提款率；不把历史foundation的未接线时点误判为当前缺陷，也不把静态当前接线当人工验收 |
| §3.5 Settings | [SettingsView](../Aureus/Features/Settings/SettingsView.swift)原生SecureField/偏好、独立session与authorized persistent cache、UTC oldest/cleanup、provider/legacy、Backup/Restore；`GeneralPreferences.swift`与Stage11 S11-05/D-01/D-04 | E-W2 General Settings17/57、Settings Lifecycle28/32；E-CC偏好/cache/session/内部外部backup方法Passed；E-LC独立en/US cache audit1/1、17条exact unique labels | 17条包含initial、legacy、Apply256、Reset、returned全部原合同，不代表任意locale、VoiceOver或当前新产品。Cancel后Probe保持在W1C仍NOT VERIFIED；security-scope释放计数未测 |
| §3.5/§4 迁移、内部与外部 Backup/Restore | [WealthStore初始化](../Aureus/Persistence/Permanent/WealthStore.swift)注入migration safety；[PermanentBackup](../Aureus/Persistence/Backup/PermanentBackup.swift)一致性备份、schema/size/SHA manifest、验证后保留5代；[PermanentExternalRestore](../Aureus/Persistence/Backup/PermanentExternalRestore.swift)拒绝保护目录/不安全候选再进入共享恢复；[Stage11矩阵](STAGE11_SCOPE_EVIDENCE_MATRIX.md)记录 safety backup/staging/验证/rollback/recoveryRequired | E-W2 Backup28/28、Export29/31、Restore26/30、ExternalRestore25/49、MigrationSafety28/32；旧E-CC Release Export29/31、31次执行Passed及28ms；E-W1C恢复前/后/最终两个synthetic文件字节身份接受 | 不读取或恢复运行DB；backup没有应用层加密，面板提示选择用户控制私密加密位置；没有自动阻止所有Repository导出路径的证明，所有recoveryRequired CRUD/人工恢复分支也不全覆盖；不保证用户自删后可恢复 |
| §3.3.1/§4 Permanent / Cache 隔离与清理 | [RuntimePaths](../Aureus/App/RuntimePaths.swift)将Permanent、MarketCache、Backup分开；[CachePolicy](../Aureus/Persistence/MarketCache/CachePolicyConfiguration.swift)默认512MiB、128MiB–4GiB、90%/80%、逐类型TTL；[MarketCacheStore](../Aureus/Persistence/MarketCache/MarketCacheStore.swift)仅持有自己的queue、expire/高水位/自动/手动Reset；AppModel仅对cache维护 | E-W2 BoundedCache15/24、CacheIsolation3/3、General/Settings同包；E-CC/E-LC和W1有限cache观察 | 容量/TTL不构成Twelve Data持久权利；cleanup不能删除永久财富。A-016最大容量≤5s/非主线程性能与真实offline仍未测；temporary新图cache重新seed不是上图Reset失败 |
| §2.1/§3.3 Credential、Provider权限与session-only | [AppDependencies](../Aureus/App/AppDependencies.swift)生产Keychain/TwelveData/Frankfurter与temporary synthetic/memory分支；[KeychainCredentialStore](../Aureus/Security/KeychainCredentialStore.swift)应用service、非同步、ThisDeviceOnly；Settings save→coordinator，清空输入；MarketDataService session存放及generation失效；[Stage6](STAGE6_MARKET_DATA_ACCEPTANCE.md)/[Retention decision](STAGE6_TWELVE_DATA_RETENTION_DECISION.md) | E-W2 Keychain/FX7/7、Provider Credential5/5及Market networking74执行；E-CC credential名字的方法仅其synthetic断言；历史实网范围见§6 | Production Credential只允许用户经原生Settings写入应用Keychain。本轮不访问真实Keychain。Twelve Data V1 session-only、persistent writes Disabled、retention rights BLOCKED不变；catalog/synthetic/用户symbol都不证明实际Plan或endpoint×MIC entitlement |
| §4/A-014/A-016 质量与隐私 | sandbox/user-selected read-write/network-client entitlements；[DataLifecycleDiagnostics](../Aureus/Diagnostics/DataLifecycleDiagnostics.swift)仅有限operation/outcome/errorCategory，动态插值private，temporary disabled；[Stage12计划](STAGE12_HARDENING_PLAN.md)人工/性能/日志协议 | E-W2 Diagnostics4/7；D-03限定static/Unit已接受；W1 USER REPORTED保留 | 不宣称系统日志交付/留存/人工脱敏；signed sandbox人工、VoiceOver、完整keyboard-only、显示条件等只按实测范围。用户接受这些入场风险，不等于满足Stage12全部质量出口 |
| §5/§6/§8 长期排除、非目标与变更控制 | V1_SCOPE明确无AI/LLM；自动交易/broker execution、cloud/social、HFT等V1非目标，crypto/扩币种/嵌入Python等deferred或conditional仍按冻结文本 | 本轮未改产品范围、依赖或业务代码 | 不把非目标缺失列为缺陷；也不借例外移除任何仍要求的V1能力。新功能或权利变化仍需明确决策 |

## 5. 当前 unsigned 产品与历史二进制的适用性

E-W2 `DebugBFT.xcresult` 首次因本轮新增 Unit 对非 Optional `CivilDate` 使用可选链而编译 Failed/exit65；唯一编译修正后 `DebugBFT-Repair.xcresult` succeeded/exit0、build parser0。旧失败保留，这是已修正的编译事实，不是新发现的产品缺陷。四条 PortfolioView deprecation warning 为上游记录的既有警告，本轮未编译复查。

成功后一次 `FullUnit.xcresult`：497 definitions、36 参数容器、171 Arguments 执行节点、461 非参数执行，共632 executions；632 Passed、failed/skipped/expected failures均0，underlying exit0、signal null，summary/tests parser0/0。新增6 definitions/35 executions Passed；六场景集成6参数与旧 emptySessionSearchFailure/emptySessionHistoryFailure 2/6 同包 Passed；独立 Focused NOT RUN。不是UI结果。

已接受 `FinalProducts.json` / `DebugIsolation.json` 所载身份如下；本轮只核对记录，没有触碰产品内容或重验签名：

| 产品或配置 | 已接受身份 |
|---|---|
| unsigned App Host | E-W2 `DebugUnitDerivedData-Repair/Build/Products/Debug/Aureus.app`，`com.aureus.wealthterminal`，arm64；主executable SHA256 `8bdf5dbdbcf7215c7aa00c97d15d889fddda488aa8be0a5b673720ecc8787dcb`；debug dylib `179acff528309b423658dc01dbda114fef7464ae12a6ab7f6bd65c5cd46fc5f9` |
| Unit bundle | 上述Host `Contents/PlugIns/AureusTests.xctest`，`com.aureus.wealthterminal.tests`，arm64；executable `39ef3989f6f2c226d1d0ecfa38ad791cef59c57a348888b541d4c39f2e28c4a2` |
| 完整清单记录 | Host151项，内含Unit bundle26项；两者有包含关系，不能相加成177个独立产品项。清单含目录、普通文件和内部链接 |
| 原始xctestrun | 同Products下 `Aureus_Aureus_macosx26.5-arm64.xctestrun`，SHA256 `4812b36ad3f552ae98a14c0ded51dd2226235c7fe3145906e5cbeb1dd76440f6` |
| 隔离副本 | 同Products下 `Aureus-Isolated-Unit.xctestrun`，SHA256 `6decda4908f5ba9c837c4a4ed158ebfa16cc193775d5927e25a7be97245cc200`；唯一差异为enabled AureusTests.CommandLineArguments追加 `--aureus-temporary-store`；撤销后递归相同，无环境/路径/UI target注入 |
| 历史宿主观察 | E-W2准确Host PID57446；temporary参数true，demo/UI-testing false；结束由上游CloseoutAudit记录。不是本轮进程观察，也不把xcodebuild退出码当App数字退出码 |

E-LC/W1的旧本地ad-hoc signed App主executable `a90b883e221aa668f169edd43fae7d4e820dfd6a624751b21822a71cbfcb2d89`、179项完整bundle与strict签名结果只属于当时产品；主hash相同本身也不能替代整bundle身份。E-CC Release与28ms亦属于历史输入。当前候选同源 signed 运行、Release、最终跨功能和发行产品身份均 NOT VERIFIED；本轮不复制、重建、重签或指定发行物。Project中既有0.1/build1是配置事实，不是本轮选择的RC版本。

## 6. Provider 与第三方资源：能证明到哪里

Stage6验收§1.7记录的2026-08-24实网证据只覆盖当时AAPL/USD/XNGS Search及特定日线（oneDay/adjustment all/outputSize5）History成功。不能扩大到当前Plan、Quote/Split/Dividend、全部MIC、实时性、账单或四市场完整可用。Frankfurter历史观察同样只有其日期和请求范围。公开条款/支持回复仅为2026-08历史时点材料；本轮未联网刷新，不作当前法律许可结论。

| 对应项 | 本地实际依据 | 声明边界 |
|---|---|---|
| GRDB.swift | [Package.resolved](../Aureus.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)唯一pin：7.11.1，revision `b83108d10f42680d78f23fe4d4d80fc88dab3212`；Project exactVersion7.11.1一致；[THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md)有上游出处/许可指引 | 锁定版本与notice对应，不等于发行包已包含完整所需notice/license或已完成法律审查；未读取依赖.git、更新依赖或重新验证缓存 |
| Lightweight Charts | 本地5.2.0，[LICENSE](../Aureus/Resources/ThirdParty/LightweightCharts/5.2.0/LICENSE)、[NOTICE](../Aureus/Resources/ThirdParty/LightweightCharts/5.2.0/NOTICE)、[PROVENANCE](../Aureus/Resources/ThirdParty/LightweightCharts/5.2.0/PROVENANCE.md)齐备；安全清单中原始JS SHA256 `c0992580867c4912cc9385b3c2728315bcc1a76c7f1087dca908430fccdf31d7`与provenance一致 | 本地文件显示Apache2.0/TradingView归属；provenance的npm tar/tag信息是历史获取记录，不是本轮重新下载核验；不把第三方许可证当Aureus源码许可证 |
| 图表集成资源 | `market-chart.html` CSP connect-src none、本地script；`MarketChartWebView` nonPersistent、仅本地导航、拒绝新窗口；MarketsView有“Charts by TradingView”链接；Aureus adapter与vendor文件分列 | 静态资源与归属展示存在；不证明所有运行流量为0、renderer性能或当前candidate发行包资源完整性 |
| Aureus源码许可与发行路线 | V1_ARCHITECTURE A-017对源码许可仍为待用户选择；安全集合无根LICENSE。当前有App sandbox和arm64配置，只有历史本地ad-hoc运行证据 | 开源意向不是已选许可证。分发对象、渠道、签名/公证/安装方式均未由本轮决定；不默认某付费签名方案，也不因未选路线断言产品代码故障 |

local-only不等于永不联网：明确授权的Provider/FX请求仍是产品能力；session-only不等于备份加密。长期工程证据包含本地路径和诊断记录，不自动属于可公开发布材料。

## 7. 用户已接受的 Stage13 入场风险登记

下列风险共同的接受范围仅是**进入Stage13并完成本次审计**；不是技术PASS、永久豁免或Stage14许可。处置为供Reviewer参考的选项，不是自动安排或默认强制重测清单。后续任何运行、日志、真实环境或修复需新的限定授权。

| ID / 要求来源 | 现有证据 | 缺失证据与可能影响 | 接受范围及后续建议 |
|---|---|---|---|
| R-01 V1§3.3/§4；A-016 offline | 六场景解析/隔离/公开Model路径Unit；旧empty-session方法；旧Markets synthetic UI | 六场景原生人工 NOT RUN；stale受控UI入口 HARNESS MISSING；真实offline不由synthetic注入证明。可能存在状态披露、焦点或错误操作体验缺口 | 已接受入场；Reviewer按拟作声明决定是否另行授权有限观察；不运行已被替代的旧Prompt |
| R-02 A-015/A-016 confirmation/panels | W1C新备份字节身份、确认恢复和G1–G7有限反馈；旧Unit/UI | Cancel后Probe保持、security-scope释放计数 NOT VERIFIED；可能漏掉取消保留/焦点/资源释放问题，不能仅从恢复成功推断 | 已接受入场；保留为后续统一人工或针对具体风险的审阅建议，不重复内部恢复整套W1 |
| R-03 A-014/A-016 signed sandbox/跨功能 | 当前632 Unit与unsigned BFT；历史signed/UI和W1 | 新源码没有同源signed运行及最终跨功能人工证据；组合根变更可能影响运行条件，旧产品不能代表新版本 | 已接受入场；若后续要主张可安装候选可靠性，先由Reviewer确定产品路线和所需同源证据；本轮不构建 |
| R-04 A-016 performance candidate | 旧10k-row Export28ms；现有计算/桥接/Analytics性能相关Unit | 六项口径与测量未闭合：10k ledger启动p95≤2.0s；10k warm Dashboard p95≤250ms；100k Ledger warm首屏p95≤200ms；10k bars首次渲染≤1.0s；pan/zoom原文“p95 at or above45fps”；配置最大容量cleanup≤5s、非主线程及Permanent隔离。机器、计时边界、FPS percentile、最大容量等仍待冻结 | 已接受入场；保留candidate而不自行改阈值。对外不作达标宣称；是否测量及优先哪项由未来具体授权决定，28ms不替代上述指标 |
| R-05 A-014/A-015；D-03 | finite enum/private插值静态及Unit接受，temporary disabled；旧丢失Dlr35W保留 | OSLog系统交付、留存和人工脱敏 NOT VERIFIED；sink成功不能证明系统最终隐私表现 | 已接受入场；如需进一步声明，另行限定仅synthetic日志、采集范围/保留/人工审查授权；不读现有私人系统日志 |
| R-06 A-016其他人工质量 | W1第一会话用户明确整体反馈，保留USER REPORTED；原生图表/Accessible Data及有限UI | 完整VoiceOver质量、keyboard-only条件、具体theme/窗口/contrast/其他显示条件及未到达项没有完整可追溯细项；不能从“均无问题”代填 | 已接受入场；沿用原反馈边界，按目标使用情境决定后续关注点，不全盘作废也不升格 |

## 8. 新发现、证据冲突和独立发布决定

本轮没有新的已确认产品缺陷或足以否定123项起点的证据冲突。README与Stage12原文的“Stages13–14 NO-GO”属于各日期历史；本轮新增当前裁决，不全文替换历史。E-CC Failed、E-OBS Failed、E-LC独立Passed可以同时成立；W1C新原件不证明旧已删除原件曾存在。上游首次BFT编译失败及唯一修正均保留，不用修正后结果擦除失败。

尚需用户/Reviewer另行决定的发布事项不是本轮新增产品故障：

| ID | 待决定的具体问题 | 当前处理 |
|---|---|---|
| RD-01 源码许可 | Aureus自有源码采用何种许可证、允许发布哪些自有材料？ | A-017仍待选择；不新增LICENSE，不从vendor Apache许可推定Aureus许可 |
| RD-02 分发路线 | 候选面向本人内部试用还是向外提供？采用什么产品形态、安装渠道及相应签名/验证路线？ | 无本轮选择；不默认付费Developer ID，也不把本地ad-hoc当发行签名或用户安装验收 |
| RD-03 候选标识与声明 | 何时选择正式RC版本/Tag、最终同源产品与可承诺的OS/硬件/功能/质量范围？ | 现在只用安全源码Hash标识；不生成Tag、版本号、包或发行说明承诺。Reviewer另裁Stage13总Gate/Stage14 |
| RD-04 可公开证据 | 哪些经用户筛选与必要人工脱敏的报告/样本可公开，第三方notice如何随所选产物呈现？ | 工程证据默认长期本地保留；没有授权公开或外部协调，不复制旧AX/日志/真实数据 |

Provider持久权利不是可由入场例外自行选择的配置：retention rights仍BLOCKED。任何未来扩展都需要独立权利证据与明确产品决定，本轮不安排条款刷新或外部协调。

## 9. 可以与不可以作出的候选声明

| 可支持的限定说法 | 当前不能说 |
|---|---|
| 这是按安全清单识别的macOS/arm64个人local-only候选源码；八模块实现和不同层级的验收证据已逐项映射 | “V1已完成”“Stage13/Release Gate已通过”“所有页面存在所以全部验收通过” |
| 当前代码有一次已接受的Full Unit632/0/0及修正后unsigned BFT证据；本轮未重跑 | “当前signed/Release候选已验证”“旧20项UI＋后来1项=新FullUI21/21 PASS” |
| 受控synthetic Search/History×offline/timeout/missing入口已有技术Unit证据 | “六场景原生人工已通过”“真实网络/全部Provider可用”“stale已验收” |
| CNY为统一估值，原币/FX/转换值区分，永久数据和可回收缓存有独立合同与测试；备份验证有有限证据 | “所有恢复失败场景无风险”“备份由App独立加密”“所有私有日志已确认脱敏” |
| 历史特定Export工作负载实测28ms；W1限定用户反馈和新原件Hash分别保留 | “全局性能达标”“人工八类全通过”“新原件补回了旧丢失证据” |
| Twelve Data V1按session-only处理、persistent writes Disabled；本地第三方版本/notice/provenance有对应 | “当前Plan和全部endpoint×MIC权利已验证”“持久化/商业展示授权已获准”“Aureus源码许可证已选择” |

## 10. 提交 Reviewer 与保留边界

本轮完成的是候选证据审计，不是重做Stage12，也没有取消原产品安全义务。建议Reviewer据上述四类结果裁决Stage13总Gate及未来是否需要发布相关新决定；Executor不自行放行Stage14、不生成下一Prompt、不安排运行。

Build、BFT、Unit、Focused、UI/XCTest、App/Runner、人工QA、Release、性能campaign、真实Provider、Keychain、OSLog、签名/打包/发布全部 NOT RUN。未浏览网页、读取系统日志、截图/AX、真实Store/cache/backup/preferences/Secret或依赖.git。未做全系统访问次数遥测，不能声称全系统私人访问次数为0。

本轮 [ExecutionReport](/Users/freeforest/Aureus_Engineering_Evidence/Stage13-ENTRY-RC-AUDIT-01-0pTYtQ/ExecutionReport.md)、[ReadRecord](/Users/freeforest/Aureus_Engineering_Evidence/Stage13-ENTRY-RC-AUDIT-01-0pTYtQ/ReadRecord.md)、[FinalInventory](/Users/freeforest/Aureus_Engineering_Evidence/Stage13-ENTRY-RC-AUDIT-01-0pTYtQ/FinalInventory.json)保存实际阅读、文档范围/链接检查及最终身份。原有源码、产品和历史证据均不改写或清理。Stage11 PASS；Stage12用户例外放行、技术证据PARTIAL；Stage13本轮提交Reviewer；Stage14／发布NO-GO。
