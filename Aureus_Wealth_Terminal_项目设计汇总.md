# Aureus Wealth Terminal

> **A local-first personal wealth intelligence terminal for macOS.**  
> 一个面向个人长期使用的、本地优先、可视化驱动、开源的财富管理与金融市场分析终端。

---

## 1. 项目基本信息

- **项目名称**：Aureus
- **完整名称**：Aureus Wealth Terminal
- **目标平台**：macOS
- **主要使用设备**：MacBook Air M2（24 GB RAM + 1 TB SSD）
- **开发方式**：长期持续迭代
- **开源方式**：GitHub 开源源码；个人财务数据、凭据与其他敏感信息不进入开源仓库
- **核心属性**：
  - Local-first
  - Open-source
  - Single-user
  - Personal / Internal Use Only
  - Non-commercial
  - Visualization-first
  - Personal Wealth Management
  - Market Intelligence
  - Portfolio Analytics
  - Long-term Personal Use

---

## 1.1 Personal Local Mode（2026-08-17）

用户最新明确决定将 Aureus 固定为仅在用户本人 Mac 上运行的单用户、本地、个人/内部、非商业应用：不托管为网络服务，不向第三方展示、共享、转售或再分发 Twelve Data 数据。程序源码可以开源，但 Repository 与开发者不接收 Provider 数据、Credential 或用户财务数据。

该模式不扩大任何 Provider 权利。实际 Plan、endpoint entitlement、rate limit 和 Exchange license 仍然逐项约束请求；Search/catalog 中可见的 symbol 或 MIC 不是价格数据授权证据。

Twelve Data 的 V1 数据处理边界拆分为：

- **Transient Session Use**：仅在当前 App 进程内保留有界内存工作集；App 退出后消失。
- **Persistent Twelve Data Storage**：由产品策略明确禁用，不进入 SQLite、Permanent Store、Snapshot、Backup、Export、日志或文件。
- **User-authored Market Preferences**：只允许保存用户主动选择的最小 symbol/MIC identifier 与 UI 偏好，不保存 Provider description、Quote、OHLCV、Split、Dividend、freshness 或 raw response。

---

## 2. 产品定位

Aureus 不定位为传统“记账软件”，而定位为：

> **个人财富智能操作系统 / Personal Wealth Intelligence System**

它希望把以下几类能力统一到一个本地 Mac 应用中：

1. 个人资产与负债管理；
2. 日常记账与现金流管理；
3. 投资组合管理；
4. 全球金融市场行情查看；
5. TradingView 风格的行情可视化；
6. 资产、收益、现金流等长期历史数据可视化；
7. 个人财富分析与长期目标规划；
8. 开源代码与个人私有财务数据严格隔离。

可以把 Aureus 理解为一个个人版本的：

> **Bloomberg Terminal + TradingView + Wealth Dashboard + Personal Ledger**

---

## 3. 核心设计原则

### 3.1 Local-first

个人财务数据默认保存在本机，并与 GitHub 开源代码仓库严格隔离。

核心目标：

- 不依赖云端才能工作；
- 用户拥有完整数据；
- 支持本地备份与导出；
- 尽量减少敏感财务信息外传；
- 即使未来第三方 API 停止服务，个人历史资产数据仍然完整存在。

---

### 3.2 Visualization-first

Aureus 的核心不是“表格堆数据”，而是：

> **让个人财富状态尽可能被看见。**

包括：

- 总资产曲线；
- 各类资产曲线；
- 收益曲线；
- 现金流趋势；
- 资产配置图；
- 投资收益热力图；
- 消费热力图；
- 股票市场热力图；
- K 线；
- 成交量；
- 技术指标。

整体视觉方向参考：

- TradingView；
- Bloomberg Terminal；
- Apple 原生 macOS 应用；
- 专业投资组合分析软件。

---

### 3.3 Asset Container

财产管理不采用死板的固定账户结构，而采用：

> **Asset Container System**

用户可以创建不同类型的资产“容器 / 卡片 / 页面”。

例如：

- 银行账户；
- 现金；
- 股票账户；
- ETF；
- 基金；
- 保险；
- 债券；
- 房产；
- 其他资产；
- 负债。

每一个资产容器既保存当前状态，也保存历史变化。

---

### 3.4 长期时间序列

Aureus 不只回答：

> “我现在有多少钱？”

还要回答：

> “我的财富是怎样一步一步变成现在这样的？”

因此重要数据都应尽量保留历史快照。

例如：

- 每日总资产；
- 每个账户每日余额；
- 每类资产每日价值；
- 投资组合每日净值；
- 每月收入；
- 每月支出；
- 每月储蓄率；
- 历史资产配置比例。

---

## 4. 应用整体信息架构

当前建议的主导航：

```text
Aureus
│
├── Dashboard      财富总览
├── Wealth         财产管理
├── Markets        全球市场
├── Portfolio      投资组合
├── Analytics      财富与投资分析
├── Ledger         记账与现金流
├── Goals          财富目标
└── Settings       设置
```

---

# 5. Dashboard — 财富驾驶舱

Dashboard 是 Aureus 最重要的入口。

打开软件后首先看到的不是账本，而是个人整体财富状态。

---

## 5.1 总资产

展示：

- Total Assets
- Total Liabilities
- Net Worth
- 本日变化
- 本周变化
- 本月变化
- 年初至今变化
- 历史最高净资产

示例：

```text
Net Worth

¥1,523,820

+2.31% This Month
```

---

## 5.2 总资产历史曲线

支持时间范围：

- 1D
- 1W
- 1M
- 3M
- 1Y
- 3Y
- 5Y
- YTD
- MAX

图表风格尽量接近 TradingView：

- 缩放；
- Hover；
- Crosshair；
- 时间轴；
- 数值轴；
- 区间收益。

---

## 5.3 资产配置

展示不同资产类别占比：

```text
Cash
Stocks
ETF
Funds
Insurance
Real Estate
Other
```

可视化可包括：

- Donut Chart；
- Treemap；
- Allocation Bar；
- 历史配置变化。

---

## 5.4 财富变化热力图

至少规划两类：

### 净资产变化热力图

展示每日净资产增长 / 减少。

### 现金流热力图

展示每日：

- 收入；
- 支出；
- 净现金流。

视觉形式可参考 GitHub Contribution Heatmap。

---

# 6. Wealth — 财产管理

Wealth 是个人资产数据库。

---

## 6.1 Asset Container System

允许新建资产容器。

基础字段可包括：

```text
Name
Type
Institution
Currency
Current Value
Cost Basis
Tags
Notes
Created Date
Updated Date
```

不同类型资产可以拥有不同扩展字段。

---

## 6.2 银行账户

例如：

```text
HSBC HK
Saving Account

Currency: HKD
Balance: HKD 120,000
Interest Rate: 2.5%
```

功能：

- 当前余额；
- 历史余额；
- 利率；
- 币种；
- 银行；
- 账户备注；
- 余额变化曲线。

---

## 6.3 基金 / ETF

字段：

- 名称；
- Ticker / Code；
- 持仓数量；
- 平均成本；
- 当前价格；
- 当前市值；
- 累计收益；
- 收益率；
- 历史收益。

---

## 6.4 股票资产

字段：

- Ticker；
- Shares；
- Average Cost；
- Market Price；
- Market Value；
- Unrealized P/L；
- Realized P/L；
- Currency；
- Broker。

股票资产与 Markets 模块中的实时 / 延迟行情连接。

---

## 6.5 保险

保险作为独立资产容器。

字段可以包括：

```text
Insurance Company
Product
Premium
Payment Frequency
Coverage
Cash Value
Start Date
Maturity Date
Beneficiary
Notes
```

后续可以扩展：

- 已缴保费；
- 累计现金价值；
- IRR；
- 保单时间轴。

---

## 6.6 房产与其他资产

未来允许扩展：

- 房产；
- 黄金；
- 私募；
- 债券；
- 收藏品；
- 其他可估值资产。

---

# 7. Markets — 全球金融市场终端

Markets 是独立的市场行情模块。

目标体验：

> 类似简化版 TradingView + Finviz Heatmap。

---

## 7.1 全球市场首页

支持市场：

- 美国；
- 香港；
- 中国；
- 日本；
- 主要全球指数；
- ETF；
- 后续可扩展 Crypto。

---

## 7.2 行情周期

至少支持：

- 当日；
- 周；
- 月；
- 季；
- 年；
- YTD。

---

## 7.3 市场热力图

展示股票市场整体涨跌。

每个股票方块可以根据：

- 市值；
- 行业；
- 涨跌幅；

进行视觉编码。

支持：

```text
1D
1W
1M
3M
YTD
1Y
```

后续可增加：

- Sector Heatmap；
- Industry Heatmap；
- Portfolio Heatmap；
- Watchlist Heatmap。

---

# 8. 单股票详情页

点击任意股票后进入独立详情页面。

---

## 8.1 股票基本信息

展示：

```text
Company Name
Ticker
Current Price
Daily Change
Daily Change %
Market Cap
Exchange
Currency
```

---

## 8.2 TradingView 风格 K 线

核心要求：

- Candlestick；
- Volume；
- Zoom；
- Pan；
- Crosshair；
- Tooltip；
- 时间范围切换。

周期可逐步支持：

```text
1D
5D
1M
3M
6M
1Y
5Y
MAX
```

---

## 8.3 技术指标

第一阶段优先：

- MA；
- EMA；
- RSI；
- MACD；
- Bollinger Bands；
- Volume。

后续：

- ATR；
- Fibonacci；
- Volume Profile；
- 更多自定义指标。

---

# 9. Portfolio — 投资组合管理

Portfolio 与 Wealth 中的投资资产相连接。

---

## 9.1 当前持仓

展示：

```text
Ticker
Shares
Avg Cost
Current Price
Market Value
P/L
P/L %
Weight
```

---

## 9.2 Portfolio Performance

展示：

- Portfolio NAV；
- 累计收益；
- 年度收益；
- 月度收益；
- Benchmark Comparison。

可比较：

- NASDAQ-100；
- S&P 500；
- 其他自定义 Benchmark。

---

## 9.3 投资组合可视化

包括：

- Portfolio Value Curve；
- Asset Allocation；
- Sector Allocation；
- Geographic Allocation；
- Return Heatmap；
- Monthly Return Matrix；
- Drawdown Chart。

---

# 10. Analytics — 财富与投资分析

Analytics 负责将已有数据转化为决策信息。

---

## 10.1 投资收益指标

逐步支持：

- Total Return；
- Annualized Return；
- CAGR；
- Time-Weighted Return；
- Money-Weighted Return / XIRR。

---

## 10.2 风险指标

逐步支持：

- Volatility；
- Sharpe Ratio；
- Sortino Ratio；
- Maximum Drawdown；
- Beta；
- Alpha。

---

## 10.3 财富分析

例如：

- 净资产增长率；
- 月度储蓄率；
- 年度储蓄率；
- 投资资产占比；
- 流动资产占比；
- 现金缓冲月数；
- 资产集中度；
- 负债率。

---

# 11. Ledger — 记账与现金流

传统记账仍然保留，但不是 Aureus 的唯一核心。

---

## 11.1 Transaction

每条交易至少包含：

```text
Date
Amount
Currency
Type
Category
Account
Asset Container
Merchant
Tags
Note
```

交易类型：

- Income；
- Expense；
- Transfer；
- Investment Buy；
- Investment Sell；
- Dividend；
- Interest；
- Fee。

---

## 11.2 分类

支持：

- 一级分类；
- 二级分类；
- 自定义分类；
- Tag。

例如：

```text
Food
└── Coffee

Learning
├── Books
└── Software
```

---

## 11.3 CSV 导入 / 导出

优先支持：

- 银行流水；
- 券商流水；
- 手工 CSV；
- Aureus 自有标准格式。

导入后可以进行字段映射。

---

## 11.4 规则分类与历史映射

后续可以根据用户定义的规则或历史映射：

```text
Starbucks
→ Food / Coffee
```

进行自动分类。

第一阶段优先采用：

- Merchant → Category 映射；
- 关键词规则；
- 自定义分类规则；
- 历史人工分类复用。

该功能不依赖 AI / LLM。

---

# 12. Goals — 财富目标

用于长期财富规划。

---

## 12.1 目标资产

例如：

```text
目标：
30 岁净资产 ¥5,000,000
```

系统可以结合：

- 当前资产；
- 每月储蓄；
- 假设收益率；
- 时间；

给出轨迹分析。

---

## 12.2 FIRE

后续支持：

- 年支出；
- Withdrawal Rate；
- FIRE Number；
- 当前完成度；
- 预计达到时间。

---

## 12.3 复利规划

支持：

- Initial Capital；
- Monthly Contribution；
- Expected Return；
- Years；
- Future Value。

---

# 13. 数据可视化体系

Aureus 应建立统一的 Visualization System。

核心图表至少包括：

### 财富

- Net Worth Line Chart
- Asset Class Area Chart
- Asset Allocation Donut
- Treemap
- Cash Flow Bar Chart

### Heatmap

- Net Worth Heatmap
- Expense Heatmap
- Portfolio Return Heatmap
- Market Heatmap
- Monthly Return Matrix

### 股票市场

- Candlestick
- Volume
- MA / EMA
- RSI
- MACD
- Bollinger Bands

### 投资分析

- NAV Curve
- Benchmark Curve
- Drawdown Curve
- Allocation History
- Risk / Return Scatter

---

# 14. 当前推荐技术架构

> 以下属于当前开发方向，具体库与实现仍可在正式编码前进一步冻结。

---

## 14.1 macOS 原生应用

优先考虑：

```text
Swift
+
SwiftUI
```

原因：

- 原生 macOS UI；
- 性能好；
- 适合长期自用；
- 与系统深度集成；
- 对 Apple Silicon 友好。

---

## 14.2 本地数据库

核心数据必须本地持久化。

推荐方向：

```text
SQLite
```

上层可以根据最终 Swift 架构选择合适 ORM / Persistence Layer。

---

## 14.3 Analytics Engine

复杂金融分析可以独立形成分析层。

初期可全部 Swift 实现。

如果后续需要大量 Quant / Data Science 能力，可以引入 Python Analytics Engine。

典型 Python 技术栈：

```text
Python
NumPy
pandas
SciPy
```

核心原则：

> UI 与金融计算逻辑解耦。

---

# 15. 市场数据架构

市场数据不直接与 UI 强耦合。

推荐：

```text
Market Data Provider
        │
        ▼
Data Adapter
        │
        ▼
Transient Session Store / Authorized Local Cache
        │
        ▼
Market Data Service
        │
        ├── Markets
        ├── Stock Detail
        ├── Portfolio
        └── Analytics
```

---

## 15.1 免费国际股市数据

项目目标明确：

> **优先接入免费或具有可用免费额度的国际股票数据源。**

Stage 1 曾讨论过的候选包括：

- Yahoo Finance / yfinance；
- Alpha Vantage；
- Stooq；
- 后续其他可替换 Provider。

V1 Primary Market Data Provider 已冻结为 **Twelve Data（用户 BYOK）**。上述列表保留为历史比较，不建立运行时多 Provider fallback。Twelve Data Production 数据在 Personal Local Mode 下只进入会话内存；这项选择不证明任何具体 endpoint、MIC 或 Exchange entitlement。

因此建议一开始就建立：

> `MarketDataProvider` 抽象层

避免 Aureus 被某一家 API 锁死。

---

## 15.2 本地缓存与清理策略

本节描述通用、可恢复市场缓存基础设施，以及具有明确持久化权利的数据源。**Twelve Data 在 V1 中是明确例外：Production 持久写入关闭，只允许会话内瞬时处理。** 既有独立 Market Cache 数据库、容量、TTL、LRU、自动/手动清理和 Permanent Store 隔离设计继续保留，但不能被解释为 Twelve Data 的磁盘保存授权。

只有在相应数据源的持久化权利明确时，股票历史行情及其他可恢复市场数据才进入本地磁盘缓存；Twelve Data V1 不适用此路径。

原因：

- 减少 API 请求；
- 避免免费 API Rate Limit；
- 提高 K 线与热力图加载速度；
- 支持离线查看已缓存的市场行情；
- 降低第三方数据源短时不可用对体验的影响。

缓存必须采用**有上限的受控策略**，不能无限增长占用本机磁盘。

至少需要：

- 设置市场数据缓存容量上限；
- 定期检查缓存占用；
- 自动清理过期或低优先级缓存；
- 可按数据类型设置不同 TTL；
- 优先清理可重新从市场 API 获取的数据；
- 在 Settings 中显示当前缓存占用；
- 提供手动“清理缓存”功能；
- 清理后允许按需重新下载市场数据。

缓存清理可以采用 TTL + LRU 等简单策略，具体容量上限与清理周期在实现阶段冻结。

需要严格区分：

```text
可清理
├── 股票行情缓存
├── 指数行情缓存
├── 热力图临时数据
└── 可重新获取的公开市场数据

不可作为缓存自动清理
├── Transaction
├── Asset / Account
├── Holding / Trade
├── Snapshot
├── Goal
├── InsurancePolicy
└── 用户主动创建的历史财富数据
```

> **缓存有上限，但个人财富历史数据库不能因缓存清理而被删除。**

## 15.3 Twelve Data 会话市场数据

Stage 7 的 Twelve Data 行情候选路径使用 actor-owned 的 Transient Session Market Store：64 MiB hard limit、typed TTL、LRU 和相同请求复用；不跨 App launch、不序列化、不进入 SQLite、Backup、Export 或日志。Settings 后续提供 `Clear Session Market Data`。Disconnect、Credential rotation、confirmed entitlement loss 与 termination 都清空该会话数据，且清理能力不能访问 Permanent Store。

当前进程仍有会话数据时，离线状态可以显示带 Provider 时间戳的 stale/offline memory value；App 重启后没有会话数据时必须显示 `Market Data Unavailable Offline`，不得用 Synthetic Provider 冒充 Production 成功。

---

# 16. 图表技术方向

### macOS 原生统计图

可以使用：

```text
Swift Charts
```

适合：

- 总资产；
- 现金流；
- 资产配置；
- 普通折线；
- 柱状图。

---

### 专业金融 K 线

对于 TradingView 风格行情界面，建议采用专门的金融图表层，而不是强行使用普通统计图表。

当前候选方向：

- TradingView Lightweight Charts；
- 自研 Swift / Metal 金融 Chart Engine；
- 其他适合 macOS 的开源 Financial Chart Library。

第一阶段优先采用成熟开源方案。

---

# 17. 数据模型初步划分

建议核心实体：

```text
Account
AssetContainer
Asset
Transaction
Holding
Trade
Price
MarketInstrument
Portfolio
Snapshot
Goal
InsurancePolicy
Category
Tag
Currency
ExchangeRate
```

其中最重要的是：

```text
AssetContainer
Transaction
Snapshot
Price
Holding
```

---

# 18. 多币种

Aureus 的实际使用场景以 **人民币（CNY）与美元（USD）** 为主。

产品层面的默认规则：

- **CNY 为默认基础计价币种（Base Currency）**；
- 人民币资产直接以 CNY 记录；
- 美元资产保留 USD 原始金额；
- 在总资产、净资产、资产配置和长期财富曲线中，美元资产通常按照对应汇率统一折算为人民币；
- 同时保留原币种金额与折算时使用的汇率，避免丢失原始信息。

底层数据应区分：

```text
Original Currency
Original Currency Value
FX Rate
CNY Converted Value
FX Timestamp
```

典型示例：

```text
AAPL Position
Original Value = USD 10,000
USD/CNY = 7.xx
Displayed Portfolio Value = CNY xx,xxx
```

其他币种可以在底层模型中保留扩展能力，但**当前产品与开发优先级只重点考虑 CNY / USD**，不为多种小众币种提前增加复杂度。

---

# 19. 数据安全与开源边界

Aureus 的**源码可以开源，但真实个人财务数据绝不能随项目开源**。

必须从项目结构上明确分离：

```text
Open-source
├── Source Code
├── UI
├── Database Schema / Migration
├── Financial Calculation Logic
├── Market Data Adapter
├── Tests
└── Sanitized / Demo Data

Private
├── 真实资产余额
├── 银行与券商账户信息
├── 交易流水
├── 持仓与成本数据
├── 保险与保单信息
├── 个人目标与财富历史
├── 本地数据库
├── 数据库备份
├── API Key / Token
└── 其他可以识别个人财务状况的数据
```

工程上至少需要：

- Local-only 默认；
- 真实数据库文件加入 `.gitignore`；
- 本地备份目录加入 `.gitignore`；
- API Key、Token、密钥不得硬编码或提交到 Git；
- 使用 macOS Keychain 保存需要保护的凭据；
- GitHub 仓库只提供脱敏 Demo / Fixture 数据；
- 测试不得依赖真实个人数据；
- 不在日志、Crash Report 或 Debug 输出中暴露敏感财务信息；
- 支持手工备份与数据导出；
- 支持 Database Migration；
- 后续根据实际需求评估数据库加密。

> **“项目开源”仅指 Aureus 的程序代码与可公开测试数据开源，不代表用户的任何真实财务数据开源。**

---

# 20. 长期范围边界

Aureus 的长期规划中**不开发 AI / LLM 能力**。

明确不规划：

- Local LLM；
- Cloud LLM；
- AI Financial Assistant；
- AI 自动生成投资建议；
- AI Agent 自动管理资产；
- 基于大模型的交易分类；
- 将个人财务数据库发送给大模型进行分析。

Aureus 的分析能力保持以：

```text
确定性金融计算
+
规则系统
+
统计分析
+
时间序列
+
可视化
```

为核心。

这样可以保持：

- 数据处理逻辑可解释；
- 计算结果可复现；
- 本地隐私边界清晰；
- 长期维护复杂度可控；
- 产品重点始终集中在财富管理、市场数据和金融分析本身。

> **AI 不是“以后再做”的功能，而是当前长期产品范围之外的非目标。**

# 21. 开发阶段

## Phase 0 — Foundation

建立项目基础。

目标：

- SwiftUI macOS App；
- 本地数据库；
- 数据模型；
- Asset Container；
- 手工录入资产；
- Dashboard；
- 总资产计算；
- 总资产历史快照；
- 基础资产曲线；
- CSV Import / Export。

完成后 Aureus 已经可以作为日常个人财产管理软件使用。

---

## Phase 1 — Market Terminal

加入市场行情。

目标：

- MarketDataProvider；
- 免费股票 API；
- 股票搜索；
- Watchlist；
- 市场行情；
- Market Heatmap；
- 股票详情页；
- K 线；
- Volume；
- MA / EMA；
- 对具有明确持久化权利的数据源使用本地历史行情缓存；
- Twelve Data V1 使用会话内行情工作集，不进行 Production 持久写入；
- 缓存容量上限；
- 周期性缓存清理；
- 手动清理缓存入口。

---

## Phase 2 — Portfolio Intelligence

加入专业投资组合能力。

目标：

- Portfolio；
- Holdings；
- Trade History；
- Cost Basis；
- Benchmark；
- CAGR；
- TWR；
- XIRR；
- Volatility；
- Sharpe；
- Max Drawdown；
- Portfolio Return Heatmap。

---

## Phase 3 — Wealth Intelligence

加入更加完整的个人财富分析。

包括：

- 收支分析；
- 多币种；
- FIRE；
- Wealth Goals；
- Insurance Analytics；
- Historical Asset Allocation；
- Advanced Heatmaps；
- Wealth Forecast。

---


---

# 22. 第一版需要克制的功能

第一版不建议直接开发：

- 自动交易；
- 实盘下单；
- 银行 Open Banking；
- 券商账户自动同步；
- 云端账户系统；
- 社交功能；
- 任何 AI / LLM 财务能力（长期产品范围外）；
- 复杂量化回测平台；
- 高频实时行情。

第一阶段最重要的是把：

```text
资产
+
历史数据
+
交易记录
+
可视化
```

四层建立正确。

---

# 23. GitHub 项目定位

推荐项目描述：

> **Aureus is an open-source, local-first wealth intelligence terminal for macOS, combining personal asset management, portfolio analytics, global market visualization, and long-term financial tracking in one private application.**

中文描述：

> **Aureus 是一个面向 macOS 的开源、本地优先个人财富智能终端，将个人资产管理、投资组合分析、全球市场可视化和长期财富追踪整合在一个应用中。**

---

# 24. Aureus 的核心价值

Aureus 最终不只是回答：

```text
今天花了多少钱？
```

而应该逐渐能够回答：

```text
我现在拥有多少财富？

这些财富分别在哪里？

过去几年我的财富是怎样增长的？

我的现金流是否健康？

我的投资组合承担了什么风险？

哪些资产真正为我创造了收益？

我的资产配置正在发生什么变化？

按照现在的速度，我未来会到哪里？

全球市场现在发生了什么？

我的个人财富与市场变化之间有什么关系？
```

这才是 Aureus 与传统记账软件的核心区别。

---

# 25. 当前已冻结与待冻结事项

## 已冻结

- 项目名：**Aureus**
- 完整名：**Aureus Wealth Terminal**
- macOS 本地应用
- GitHub 开源
- 长期个人使用
- Local-first
- Visualization-first
- 总资产可视化
- 子资产可视化
- 财富 / 收益热力图
- 独立 Markets 页面
- 免费国际股票市场数据
- 市场日 / 周 / 月 / 季 / 年热力图
- 单股 TradingView 风格 K 线
- Asset Container System
- 银行账户
- 基金
- 股票
- 保险等资产类型
- 投资组合分析
- 记账与现金流
- 长期历史财富数据
- 市场数据缓存必须有容量上限
- 市场缓存支持定期 / 自动清理与手动清理
- 个人财富历史数据不受市场缓存清理影响
- 主要币种为 CNY / USD
- CNY 为默认统一计价币种
- 源码开源、真实个人敏感财务数据不开放
- 本地数据库、备份、API Key / Token 等不得提交到 GitHub
- 长期规划明确不开发 AI / LLM 能力

## 待下一阶段冻结

- 最终 Market Data API Provider
- 最终 macOS Chart 技术方案
- Swift 原生分析 vs Swift + Python 混合架构
- SQLite 上层 Persistence 框架
- 第一版数据库 Schema
- 第一版 UI Design System
- MVP 的精确功能边界
- GitHub License
- 数据加密方案
- CNY / USD 汇率数据源
- 市场缓存默认容量上限
- 市场缓存 TTL 与自动清理周期

---

# 26. 项目一句话

> **Aureus — Your private wealth intelligence terminal, built locally and owned forever.**
