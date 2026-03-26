import Foundation
import WebKit

/// A JavaScript function that can be evaluated in a WKWebView.
struct JavascriptFunction {
    let functionString: String

    init(_ function: String) {
        self.functionString = function
    }

    func evaluate(in webView: WKWebView) async throws -> Any? {
        try await webView.evaluateJavaScript(functionString)
    }

    func evaluate(in webView: WKWebView, completion: ((Result<Any?, Error>) -> Void)? = nil) {
        webView.evaluateJavaScript(functionString) { result, error in
            if let error {
                completion?(.failure(error))
            } else {
                completion?(.success(result))
            }
        }
    }
}
