import UIKit
import Capacitor
import WebKit
import Speech
import AVFoundation

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Called when the app was launched with a url. Feel free to add additional processing here,
        // but if you want the App API to support tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Called when the app was launched with an activity, including Universal Links.
        // Feel free to add additional processing here, but if you want the App API to support
        // tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

}

private final class WeakNativeSpeechMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: CodexBridgeViewController?

    init(owner: CodexBridgeViewController) {
        self.owner = owner
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        owner?.handleNativeSpeechMessage(message)
    }
}

private final class NativeSpeechController {
    static let messageHandlerName = "codexNativeSpeech"

    private weak var owner: CodexBridgeViewController?
    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var requestId: String?
    private var tapInstalled = false

    init(owner: CodexBridgeViewController) {
        self.owner = owner
    }

    func start(requestId: String, locale: String?) {
        cleanup(sendEnded: false)
        self.requestId = requestId

        requestPermissions { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.requestId == requestId else { return }
                guard granted else {
                    self.send(type: "error", error: "not-allowed")
                    self.cleanup(sendEnded: false)
                    return
                }
                self.beginRecognition(locale: locale)
            }
        }
    }

    func stop(requestId: String, abort: Bool) {
        guard self.requestId == requestId else { return }
        if abort {
            task?.cancel()
        } else {
            request?.endAudio()
            task?.finish()
        }
        cleanup(sendEnded: true)
    }

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        requestSpeechPermission { speechAllowed in
            guard speechAllowed else {
                completion(false)
                return
            }

            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                completion(true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    completion(allowed)
                }
            default:
                completion(false)
            }
        }
    }

    private func requestSpeechPermission(completion: @escaping (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            completion(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                completion(status == .authorized)
            }
        default:
            completion(false)
        }
    }

    private func beginRecognition(locale: String?) {
        guard requestId != nil else { return }

        let speechLocale = locale.flatMap { $0.isEmpty ? nil : Locale(identifier: $0) }
        let recognizer = speechLocale.flatMap(SFSpeechRecognizer.init(locale:)) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            send(type: "error", error: "service-not-allowed")
            cleanup(sendEnded: false)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognizer = recognizer
        self.request = request

        #if !targetEnvironment(macCatalyst)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            send(type: "error", error: "audio-capture")
            cleanup(sendEnded: false)
            return
        }
        #endif

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            send(type: "error", error: "audio-capture")
            cleanup(sendEnded: false)
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        tapInstalled = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, self.requestId != nil else { return }
            if let result {
                self.send(
                    type: "result",
                    transcript: result.bestTranscription.formattedString,
                    final: result.isFinal
                )
                if result.isFinal {
                    self.cleanup(sendEnded: true)
                    return
                }
            }
            if error != nil {
                self.send(type: "error", error: "unknown")
                self.cleanup(sendEnded: false)
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            send(type: "started")
        } catch {
            send(type: "error", error: "audio-capture")
            cleanup(sendEnded: false)
        }
    }

    private func send(
        type: String,
        transcript: String? = nil,
        final: Bool? = nil,
        error: String? = nil
    ) {
        guard let requestId,
              let webView = owner?.bridgedWebView else {
            return
        }

        var payload: [String: Any] = [
            "type": type,
            "requestId": requestId,
        ]
        if let transcript { payload["transcript"] = transcript }
        if let final { payload["final"] = final }
        if let error { payload["error"] = error }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        DispatchQueue.main.async {
            webView.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('codex-native-speech',{detail:\(json)}));",
                completionHandler: nil
            )
        }
    }

    private func cleanup(sendEnded: Bool) {
        let shouldSendEnded = sendEnded && requestId != nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        recognizer = nil

        #if !targetEnvironment(macCatalyst)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        if shouldSendEnded {
            send(type: "ended")
        }
        requestId = nil
    }
}

/// Owns the WebView shell so the remote web page can account for native bars.
/// The web page is hosted remotely, so the values must be applied at runtime.
@objc(CodexBridgeViewController)
class CodexBridgeViewController: CAPBridgeViewController {

    private static let userAgentMarker = "CodexLocalRemoteIOSShell"
    private var lastAppliedTopInset: CGFloat = -1
    private lazy var nativeSpeechMessageHandler = WeakNativeSpeechMessageHandler(owner: self)
    private lazy var nativeSpeechController = NativeSpeechController(owner: self)

    override func webViewConfiguration(for instanceConfiguration: InstanceConfiguration) -> WKWebViewConfiguration {
        let configuration = super.webViewConfiguration(for: instanceConfiguration)
        let current = configuration.applicationNameForUserAgent ?? ""
        if !current.localizedCaseInsensitiveContains(Self.userAgentMarker) {
            configuration.applicationNameForUserAgent = current.isEmpty
                ? Self.userAgentMarker
                : "\(current) \(Self.userAgentMarker)"
        }
        configuration.userContentController.add(
            nativeSpeechMessageHandler,
            name: NativeSpeechController.messageHandlerName
        )
        return configuration
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyNativeLayoutState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // A navigation or reload can replace the document without changing the
        // controller's safe-area inset; force the CSS state into the new page.
        lastAppliedTopInset = -1
        applyNativeLayoutState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyNativeLayoutState()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        applyNativeLayoutState()
    }

    fileprivate func handleNativeSpeechMessage(_ message: WKScriptMessage) {
        guard let raw = message.body as? String,
              let data = raw.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = payload["type"] as? String,
              let requestId = payload["requestId"] as? String,
              !requestId.isEmpty else {
            return
        }

        switch type {
        case "speech-start":
            nativeSpeechController.start(
                requestId: requestId,
                locale: payload["locale"] as? String
            )
        case "speech-stop":
            nativeSpeechController.stop(requestId: requestId, abort: false)
        case "speech-abort":
            nativeSpeechController.stop(requestId: requestId, abort: true)
        default:
            break
        }
    }

    private func applyNativeLayoutState() {
        guard let webView = bridgedWebView else { return }

        let isMacCatalyst = ProcessInfo.processInfo.isMacCatalystApp
        let topInset = isMacCatalyst ? max(view.safeAreaInsets.top, 28) : max(view.safeAreaInsets.top, 0)
        guard abs(topInset - lastAppliedTopInset) > 0.5 else { return }

        let formattedInset = String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(topInset),
        )
        let macCatalystValue = isMacCatalyst ? "true" : "false"
        let script = """
        (() => {
          const root = document.documentElement;
          root.dataset.iosShell = "true";
          root.dataset.macCatalyst = "\(macCatalystValue)";
          root.style.setProperty("--codex-native-top-inset", "\(formattedInset)px");
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard error == nil else { return }
            self?.lastAppliedTopInset = topInset
        }
    }
}
