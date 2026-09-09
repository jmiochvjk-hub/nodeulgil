import SwiftUI
import WebKit

private let nodeulgilURL = URL(string: "https://jmiochvjk-hub.github.io/nodeulgil/")!

struct ContentView: View {
    @StateObject private var webState = WebViewState()

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            WebView(url: nodeulgilURL, state: webState)
                .ignoresSafeArea(.container, edges: .bottom)

            if webState.isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("불러오는 중")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .safeAreaInset(edge: .top) {
            WebToolbar(state: webState)
        }
    }
}

struct WebToolbar: View {
    @ObservedObject var state: WebViewState

    var body: some View {
        HStack(spacing: 10) {
            Text("pick스케줄")
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Button {
                state.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!state.canGoBack)

            Button {
                state.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

@MainActor
final class WebViewState: ObservableObject {
    weak var webView: WKWebView?
    @Published var isLoading = false
    @Published var canGoBack = false

    func reload() {
        webView?.reload()
    }

    func goBack() {
        guard webView?.canGoBack == true else { return }
        webView?.goBack()
    }

    func update(from webView: WKWebView) {
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: WebViewState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        state.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        state.webView = webView
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: WebViewState

        init(state: WebViewState) {
            self.state = state
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.update(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            state.update(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.update(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.update(from: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            state.update(from: webView)
        }
    }
}
