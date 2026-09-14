# Third-Party Notices

This document records third-party components used by Aureus. It does not select or declare a license for Aureus source code.

## GRDB.swift 7.11.1

- Source: <https://github.com/groue/GRDB.swift>
- Pinned version: 7.11.1
- Integrated through Swift Package Manager.
- Applicable license and notices are provided by the upstream package.

The pinned revision is `b83108d10f42680d78f23fe4d4d80fc88dab3212`. Its complete MIT notice below was checked against the local 7.11.1 package and the [upstream LICENSE at that revision](https://raw.githubusercontent.com/groue/GRDB.swift/b83108d10f42680d78f23fe4d4d80fc88dab3212/LICENSE) on 2026-09-12. This is GRDB's notice, not an Aureus copyright claim.

<!-- BEGIN GRDB LICENSE -->
Copyright (C) 2015-2025 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
<!-- END GRDB LICENSE -->

## TradingView Lightweight Charts 5.2.0

- Source: <https://github.com/tradingview/lightweight-charts/releases/tag/v5.2.0>
- Exact version: 5.2.0
- License: Apache-2.0
- Bundled locally for offline chart rendering; no CDN or remote runtime script is used.
- Upstream license: [LICENSE](Aureus/Resources/ThirdParty/LightweightCharts/5.2.0/LICENSE)
- Upstream notice: [NOTICE](Aureus/Resources/ThirdParty/LightweightCharts/5.2.0/NOTICE)
- Acquisition and hashes: [PROVENANCE.md](Aureus/Resources/ThirdParty/LightweightCharts/5.2.0/PROVENANCE.md)

Copyright (c) 2025 TradingView, Inc.

Charts are attributed to TradingView through a native in-app link.

The complete upstream LICENSE and NOTICE are retained byte-for-byte, including their distinct original copyright lines. The vendor JavaScript is unchanged; `market-chart.html` and `aureus-market-chart.js` are Aureus integration files. The source distribution retains the linked license/notice/provenance files. The packaged App additionally carries readable copies in `Contents/Resources/Licenses`, alongside the complete GRDB notice and Aureus MIT license. This document does not relicense third-party components or grant rights to Provider market data.
