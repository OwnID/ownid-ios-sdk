import Foundation
import Testing
import WebKit

// Support-only: WebBridge fixture adapters and failure cleanup.
@MainActor
@Suite(.serialized)
struct WebBridgeTestSupportTests {
    @Test func `Missing JavaScript completion times out and accepts a late callback safely`() async throws {
        let webView = DeferredJavaScriptWebView(frame: .zero, configuration: WKWebViewConfiguration())
        defer { tearDownWebBridgeTestWebView(webView) }

        do {
            try await evaluateWebBridgeTestJavaScript("'value'", in: webView, seconds: 0)
            Issue.record("Expected JavaScript evaluation to time out")
        } catch TestTimeoutError.timedOut(let phase) {
            #expect(phase == "WebBridge JavaScript evaluation")
        }

        let completion = try #require(webView.completion)
        completion("late value", nil)
        webView.completion = nil
    }

    @Test func `Navigation process termination fails the pending load`() async throws {
        let webView = makeWebBridgeTestWebView()
        defer { tearDownWebBridgeTestWebView(webView) }
        let probe = WebBridgeTestNavigationProbe()
        probe.webViewWebContentProcessDidTerminate(webView)

        do {
            try await probe.waitForFinish()
            Issue.record("Expected navigation to fail after process termination")
        } catch {
            #expect(String(describing: error).contains("web content process terminated"))
        }
    }

    @Test func `Missing navigation completion times out and accepts a late finish safely`() async throws {
        let webView = makeWebBridgeTestWebView()
        defer { tearDownWebBridgeTestWebView(webView) }
        let probe = WebBridgeTestNavigationProbe()

        do {
            try await probe.waitForFinish("missing navigation", seconds: 0)
            Issue.record("Expected navigation to time out")
        } catch TestTimeoutError.timedOut(let phase) {
            #expect(phase == "missing navigation")
        }
        probe.webView(webView, didFinish: nil)
    }

    @Test func `Page host provides visible bounds and removes its view hierarchy at teardown`() {
        let webView = makeWebBridgeTestWebView()
        defer { tearDownWebBridgeTestWebView(webView) }
        let host = WebBridgeTestWebViewHost(webView)
        defer { host.tearDown() }

        #expect(webView.window === host.window)
        #expect(!host.window.isHidden)
        #expect(!webView.bounds.isEmpty)

        host.tearDown()

        #expect(webView.window == nil)
        #expect(webView.superview == nil)
        #expect(host.window.isHidden)
        #expect(host.window.rootViewController == nil)
    }
}

@MainActor
private final class DeferredJavaScriptWebView: WKWebView {
    var completion: (@MainActor @Sendable (Any?, (any Error)?) -> Void)?

    override func evaluateJavaScript(
        _ javaScriptString: String,
        completionHandler: (@MainActor @Sendable (Any?, (any Error)?) -> Void)? = nil
    ) {
        completion = completionHandler
    }
}
