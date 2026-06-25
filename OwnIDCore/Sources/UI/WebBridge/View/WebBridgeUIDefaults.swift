import Foundation
import UIKit

/// Default constants and helpers used by WebBridge UI hosting.
///
/// The embedded HTML bootstraps the OwnID web SDK, reports JavaScript load/exception failures through `ownid://`
/// callback URLs, and is loaded with the operation-resolved base URL by `WebBridgeWebView`.
internal enum WebBridgeUIDefaults {
    /// Default background for the SDK-managed WebView container and safe-area regions.
    static let backgroundColor: UIColor = .white

    /// Default fallback base URL for the OwnID WebView page.
    static let webViewURL = "https://webview.ownid.com"

    private static let webViewHTMLTemplate = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <title></title>
          <link id="webapp-icon" rel="icon" type="image/png" href="https://cdn.prod.website-files.com/63e207687d9e033189f3c3f1/643fe358bb66c2a656709593_OwnID%20icon.png">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
           .spinner {--ownid-spinner-overlay-bg-color: #fff;--ownid-spinner-bg-color: rgba(133, 133, 133, .3);--ownid-spinner-bg-opasity: 1;--ownid-spinner-color: #858585;--ownid-spinner-size: 40px;position: absolute;z-index: 1;width: 100%;height: 100%;background-color: var(--ownid-spinner-overlay-bg-color);top: 0;left: 0;display: flex;justify-content: center;align-items: center;}.spinner svg {position: absolute;width: var(--ownid-spinner-size);height: var(--ownid-spinner-size);overflow: visible;}.spinner .bg {stroke: var(--ownid-spinner-bg-color);opacity: var(--ownid-spinner-bg-opasity);}.spinner .sp {stroke-linecap: round;stroke: var(--ownid-spinner-color);animation: animation 2s cubic-bezier(0.61, 0.24, 0.44, 0.79) infinite;}.spinner .bg, .spinner .sp {fill: none;stroke-width: 15px;}.spinner .sp-svg {animation: rotate 2s cubic-bezier(0.61, 0.24, 0.44, 0.79) infinite;}@keyframes animation {0% {stroke-dasharray: 1 270;stroke-dashoffset: 70;}50% {stroke-dasharray: 80 270;stroke-dashoffset: 220;}100% {stroke-dasharray: 1 270;stroke-dashoffset: 70;}}@keyframes rotate {100% {transform: rotate(720deg);}}
          </style>
          <script type="text/javascript">
            window.gigya = {};
            window.OWNID_NATIVE_WEBVIEW = true;
            window.ownid = async (...a) => ((window.ownid.q = window.ownid.q || []).push(a), {error: null, data: null});
            function onJSException(ex) { document.location.href = 'ownid://on-js-exception?ex=' + encodeURIComponent(ex); }
            function onJSLoadError() { document.location.href = 'ownid://on-js-load-error'; }
            setTimeout(function () { if (!window.ownid?.sdk) onJSLoadError(); }, 10000);
            window.onerror = (errorMsg) => onJSException(errorMsg);
            var interval = setInterval(() => { if (window.ownid?.sdk) { clearInterval(interval); window.onerror = () => {}; } }, 500);
          </script>
        </head>
        <body>
        <div class="spinner">
          <svg viewBox="0 0 100 100"><circle class="bg" r="42.5" cx="50" cy="50"></circle></svg>
          <svg class="sp-svg" viewBox="0 0 100 100"><circle class="sp" r="42.5" cx="50" cy="50"></circle></svg>
        </div>
        <script src="OWNID-CDN-URL" type="text/javascript" onerror="onJSLoadError()"></script>
        <script>ownid('start', { language: window.navigator.languages || 'en', animation: false });</script>
        </body>
        </html>
        """

    /// Returns HTML with `OWNID-CDN-URL` resolved from the current configuration.
    ///
    /// Uses `rootURL/sdk/{appID}` when `rootURL` is configured. Otherwise resolves the default CDN host by
    /// environment and region.
    internal static func html(for configuration: any OwnIDConfiguration) -> String {
        let cdnURL: String
        if let rootURL = configuration.rootURL, let baseURL = URL(string: rootURL) {
            cdnURL = baseURL.appendingPathComponent("sdk").appendingPathComponent(configuration.appID).absoluteString
        } else {
            cdnURL =
                "https://cdn\(configuration.toStringPrefix()).ownid\(configuration.region.toStringSuffix()).com/sdk/\(configuration.appID)"
        }

        return webViewHTMLTemplate.replacingOccurrences(of: "OWNID-CDN-URL", with: cdnURL)
    }

    /// URL scheme used by JavaScript callbacks emitted from the default HTML template.
    internal static let ownIdScheme = "ownid"
    /// Host value for JavaScript exception callback URLs.
    internal static let jsExceptionHost = "on-js-exception"
    /// Host value for JavaScript load-error callback URLs.
    internal static let jsLoadErrorHost = "on-js-load-error"
}
