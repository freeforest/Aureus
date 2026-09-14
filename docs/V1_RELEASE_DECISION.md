# Aureus 1.0.0 用户例外发布决策

## 2026-09-13 授权与定位

用户明确接受：“剩余人工、性能、日志隐私及最终运行验证未完成的风险，仅完成发布安全与产物检查后，准备正式 V1 的用户例外发布，直接作为正式版本，先使用，后续收集问题再优化、测试与升级。”

Reviewer 接受该路线。发行定位为正式 **1.0.0 / build 1**，不是 Preview、Beta、RC 或 candidate。发布决策为用户例外放行；整体技术证据仍 **PARTIAL**，发布安全与产物检查仍须依实际结果审阅。实际公开上传 **NOT RUN**，由用户自行操作。此决定不豁免新发现的发布安全问题。

## 本轮范围与状态

只改 App Debug/Release MARKETING_VERSION、正式打包命名与公开说明，并新增本记录；build1、业务源码、测试、Scheme、锁定依赖、entitlements 和第三方许可冻结。本轮唯一 Release 构建底层exit0、canonical succeeded/errors0；唯一打包流程exit0，27条内部命令均exit0。正式1.0.0产物准备完成，待Reviewer发布安全与产物复核，未上传。

本轮 App／Unit／UI／人工／性能／系统日志均 **NOT RUN**。旧 Cancel 任务 `Stage14-V1-RESTORE-CANCEL-NATIVE-01-GW0BoK` 被本轮替代，仅有准备和复制核验，未启动会话，Cancel 后 Probe 保留仍 NOT VERIFIED。不恢复旧任务、不改写旧证据。

## 继承证据与已接受风险

历史 Unit 502 definitions / 639 executions、639通过仅为继承证据，不是本轮1.0.0二进制运行结果。F1六场景及stale/Clear为有限 USER REPORTED；既有流程偏差和历史失败保持。Stage11 PASS、Stage12用户例外放行且技术PARTIAL、Stage13 PASS及Stage14本地候选准备PASS均保留其原适用范围。

用户已接受剩余人工（含Cancel/Probe、security-scope释放计数、VoiceOver、keyboard和显示条件）、六项性能口径/测量、OSLog交付/留存/人工脱敏、最终同源App运行及真实下载首次放行未完成的风险；不把未测写成故障或技术PASS，也不设为本轮追加补测要求。旧阶段横幅仍为遗留文案，未修复。

## 产品与公开边界

官方Apple Silicon、macOS14最低部署目标不代表全机型实测；本地ad-hoc、无Developer ID、未公证。MIT不授予Provider数据/凭据权利。CNY默认与USD原额/FX/CNY并存、Permanent/Cache隔离、容量/TTL/清理、无AI/LLM、Twelve Data session-only和持久写入Disabled均不变。真实Credential仍仅经原生Settings进入应用Keychain。

公开资产仅DMG、白名单源码ZIP和SHA256SUMS；内部证据、决策文件和完整日志不公开。源码ZIP审阅不等于Git历史审计；用户自行公开现有仓库时负责检查历史。备份不由Aureus独立加密，不应只保留App内唯一副本。普通使用无需QA参数，见[公开指南](../PUBLIC_README.md)。

## 实际工程证据

本轮长期目录：[ExecutionReport](/Users/freeforest/Aureus_Engineering_Evidence/Stage14-V1-USER-EXCEPTION-RELEASE-PREP-01-GHF56V/ExecutionReport.md)。110项公开白名单与BuildSource对应，原始Release完整21项；许可加入及ad-hoc签名后完整30项，Staging/DMG内/InstallCheck完全相同，strict验签通过，恰为原三个true entitlement。Charts六文件匹配、GRDB隐私资源有效；只读挂载已卸载。ZIP路径集、解包字节/模式及SHA256SUMS检查通过。四条canonical插值警告及一条原日志AppIntents提示保留，未修复。

公开产物为 `Aureus-1.0.0-macos-arm64.dmg`（7409263 bytes，SHA256 `3da9611f5653b2ab3c0619c5f9bea81673c46018dc6dd9b41cfb4f862dc5c43f`）、`Aureus-1.0.0-source.zip`（507270 bytes，SHA256 `d307b6e91c670b33ea7e1bf946a240f217a57dd6b22259438151f02b839205e5`）及同目录SHA256SUMS。完整身份及最终范围以本轮报告和清单为准，不以主executable替代bundle核验。未运行App，安装复制检查不等于安装后启动通过。
