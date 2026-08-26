import SwiftUI
import WebKit

struct MarketChartWebView: NSViewRepresentable {
    let payload: MarketChartPayload
    let reduceMotion: Bool
    let onMessage: @MainActor (MarketChartInboundMessage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMessage: onMessage)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "aureusChart")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityLabel("Interactive market chart. Use the Accessible Data view for tabular values.")
        context.coordinator.webView = webView
        loadLocalPage(in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.pendingPayload = payload
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.applyIfReady()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "aureusChart")
        coordinator.webView = nil
        coordinator.pendingPayload = nil
    }

    private func loadLocalPage(in webView: WKWebView, coordinator: Coordinator) {
        guard let pageURL = Bundle.main.url(
            forResource: "market-chart",
            withExtension: "html",
            subdirectory: "ThirdParty/LightweightCharts/5.2.0"
        ) else {
            onMessage(.rendererError(category: "rendererFailure"))
            return
        }
        coordinator.allowedDirectory = pageURL.deletingLastPathComponent().standardizedFileURL
        webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        var allowedDirectory: URL?
        var pendingPayload: MarketChartPayload?
        var reduceMotion = false
        private var isReady = false
        private let onMessage: @MainActor (MarketChartInboundMessage) -> Void

        init(onMessage: @escaping @MainActor (MarketChartInboundMessage) -> Void) {
            self.onMessage = onMessage
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "aureusChart" else { return }
            do {
                let decoded = try MarketChartInboundMessage.decode(message.body)
                if decoded == .ready {
                    isReady = true
                    applyIfReady()
                }
                onMessage(decoded)
            } catch {
                onMessage(.rendererError(category: "invalidPayload"))
            }
        }

        func applyIfReady() {
            guard isReady, let webView, let pendingPayload else { return }
            do {
                let object = try MarketChartPayload.encodedObject(pendingPayload)
                let shouldReduceMotion = reduceMotion
                Task { @MainActor [weak self, weak webView] in
                    guard let webView else { return }
                    do {
                        _ = try await webView.callAsyncJavaScript(
                            "return window.AureusChart.applyPayload(payload, reduceMotion)",
                            arguments: ["payload": object, "reduceMotion": shouldReduceMotion],
                            in: nil,
                            contentWorld: .page
                        )
                    } catch {
                        self?.onMessage(.rendererError(category: "rendererFailure"))
                    }
                }
            } catch {
                onMessage(.rendererError(category: "invalidPayload"))
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.scheme == "about" {
                decisionHandler(.allow)
                return
            }
            guard url.isFileURL,
                  let allowedDirectory,
                  url.standardizedFileURL.path.hasPrefix(allowedDirectory.path + "/") else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? { nil }
    }
}
