import SwiftUI
import WebKit
import Network
import Combine

/// The school's mobile portal in a web view — the iOS equivalent of the Android MainActivity.
struct PortalView: View {
    let school: School
    @EnvironmentObject private var store: SchoolStore
    @StateObject private var model = PortalModel()
    @State private var confirmChange = false

    var body: some View {
        VStack(spacing: 0) {
            // iPhones have no hardware back button, so the bar provides Back plus a way to switch school.
            HStack {
                Button { model.webView.goBack() } label: {
                    Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                }
                .disabled(!model.canGoBack)
                Spacer()
                Text(school.name).font(.headline).lineLimit(1)
                Spacer()
                Menu {
                    Button { model.retry() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    Link(destination: SchoolStore.privacyURL) { Label("Privacy Policy", systemImage: "hand.raised") }
                    Button(role: .destructive) { confirmChange = true } label: {
                        Label("Change School", systemImage: "building.2")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()

            ZStack {
                WebView(webView: model.webView)
                if model.preparing || model.isLoading {
                    ProgressView()
                }
                if let error = model.loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                        Text("Couldn't open the school portal").font(.headline)
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { model.retry() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                }
            }
        }
        .task {
            await store.loadSchools()
            await model.start(school: store.selected ?? school)
        }
        .alert("Change School?", isPresented: $confirmChange) {
            Button("Change", role: .destructive) {
                Task {
                    await model.signOut()
                    store.clearSelection()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be signed out of \(school.name).")
        }
        .sheet(item: $model.sharedFile) { file in
            ShareSheet(url: file.url)
        }
    }
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class PortalModel: NSObject, ObservableObject {
    let webView: WKWebView

    @Published private(set) var canGoBack = false
    @Published private(set) var isLoading = false
    @Published private(set) var preparing = true
    @Published private(set) var loadError: String?
    @Published var sharedFile: SharedFile?

    private var startURL: URL?
    private let monitor = NWPathMonitor()
    private var wasOffline = false
    private var pendingDownloads: [ObjectIdentifier: URL] = [:]

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)
        webView.publisher(for: \.isLoading).assign(to: &$isLoading)
    }

    deinit {
        monitor.cancel()
    }

    func start(school: School) async {
        guard startURL == nil, var components = URLComponents(string: school.loginUrl) else { return }
        if let token = await PushToken.fetch(for: school) {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "fcm", value: token)]
        }
        guard let url = components.url else { return }
        startURL = url
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        preparing = false
        startNetworkMonitor()
    }

    func retry() {
        loadError = nil
        if webView.url == nil, let startURL {
            webView.load(URLRequest(url: startURL, cachePolicy: .reloadIgnoringLocalCacheData))
        } else {
            webView.reload()
        }
    }

    /// Schools share the curtina.in domain, so drop the session before switching.
    func signOut() async {
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                       modifiedSince: .distantPast)
    }

    // Reload when the connection comes back, like the Android network callback.
    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "PortalModel.network"))
    }

    private func networkChanged(online: Bool) {
        if online && wasOffline { retry() }
        wasOffline = !online
    }

    private func handleFailure(_ error: Error) {
        let nsError = error as NSError
        // Cancelled loads (a link tapped mid-load) and download hand-offs (WebKit error 102) aren't failures.
        if nsError.code == NSURLErrorCancelled || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102) {
            return
        }
        loadError = error.localizedDescription
    }

    private func present(_ alert: UIAlertController, otherwise fallback: () -> Void) {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        guard let top else { return fallback() }
        top.present(alert, animated: true)
    }

    private static func mapsURL(fromGeo url: URL) -> URL? {
        // geo:lat,lng?q=place → Apple Maps (iOS has no geo: handler).
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems?.first { $0.name == "q" }?.value ?? components?.path ?? ""
        var maps = URLComponents(string: "https://maps.apple.com/")
        maps?.queryItems = [URLQueryItem(name: "q", value: query)]
        return maps?.url
    }
}

extension PortalModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
        let scheme = url.scheme?.lowercased() ?? ""

        if scheme == "geo" {
            if let maps = Self.mapsURL(fromGeo: url) { UIApplication.shared.open(maps) }
            return decisionHandler(.cancel)
        }
        // Map links and tel:, mailto:, whatsapp: etc. open in their own apps.
        if url.absoluteString.hasPrefix("https://maps") || !["http", "https", "about", "blob", "data"].contains(scheme) {
            UIApplication.shared.open(url)
            return decisionHandler(.cancel)
        }
        if navigationAction.shouldPerformDownload {
            return decisionHandler(.download)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition") ?? ""
        if disposition.lowercased().hasPrefix("attachment") || !navigationResponse.canShowMIMEType {
            return decisionHandler(.download)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadError = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }
}

extension PortalModel: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(suggestedFilename)
        pendingDownloads[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    // Android saves to Downloads; on iOS hand the file to the share sheet ("Save to Files", WhatsApp, Print…).
    func downloadDidFinish(_ download: WKDownload) {
        if let url = pendingDownloads.removeValue(forKey: ObjectIdentifier(download)) {
            sharedFile = SharedFile(url: url)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        pendingDownloads.removeValue(forKey: ObjectIdentifier(download))
    }
}

extension PortalModel: WKUIDelegate {
    // target="_blank" / window.open: load in the same view, like Android.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // Camera/microphone for the page; iOS still asks the user once using the Info.plist text.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    // WKWebView ignores alert()/confirm()/prompt() unless the app shows them.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, otherwise: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text)
        })
        present(alert) { completionHandler(nil) }
    }
}

struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
