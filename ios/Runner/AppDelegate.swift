import UIKit
import Flutter
import QuickLook

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    var pendingFileUrls = [String]()
    var pendingErrorType: String?
    var pendingErrorMessage: String?
    var eventSink: FlutterEventSink?
    var eventChannel: FlutterEventChannel!
    
    var methodChannel: FlutterMethodChannel!
    var backgroundTaskIdentifier: UIBackgroundTaskIdentifier? = nil
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        window = UIWindow()
        window!.rootViewController = FlutterViewController()
        window!.makeKeyAndVisible()
        
        GeneratedPluginRegistrant.register(with: self)
        
        let rootViewController = window!.rootViewController as! FlutterViewController
        let messenger = rootViewController as! FlutterBinaryMessenger
        methodChannel = FlutterMethodChannel(name: "io.flown.airdash/communicator", binaryMessenger: messenger)
        eventChannel = FlutterEventChannel(name: "io.flown.airdash/event_communicator", binaryMessenger: messenger)
        eventChannel.setStreamHandler(self)
        
        methodChannel.setMethodCallHandler { call, result in
            if call.method == "startFileSending" {
                self.backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask()
                result(true)
            } else if call.method == "endFileSending" {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskIdentifier!)
                result(true)
            } else if call.method == "openFile" {
                if let args = call.arguments as? [String: Any], let urls = args["urls"] as? [String] {
                    self.openRawUrls(urls, self.window!.rootViewController!, result)
                } else {
                    result(FlutterError(code: "BAD_ARGS", message: "Wrong argument type", details: nil))
                }
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
        
        if let launchOptions = launchOptions {
            if let url = launchOptions[UIApplication.LaunchOptionsKey.url] as? URL {
                if hasMatchingSchemePrefix(url) {
                    handleUrls()
                }
                return true
            } else if let activityDictionary = launchOptions[UIApplication.LaunchOptionsKey.userActivityDictionary] as? [AnyHashable: Any] {
                for key in activityDictionary.keys {
                    if let userActivity = activityDictionary[key] as? NSUserActivity {
                        if let url = userActivity.webpageURL {
                            if hasMatchingSchemePrefix(url) {
                                handleUrls()
                            }
                            return true
                        }
                    }
                }
            }
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func openRawUrls(_ rawUrls: [String], _ vc: UIViewController, _ result: @escaping FlutterResult) {
        var urls = [URL]()
        for rawUrl in rawUrls {
            let url = URL(string: "file://\(rawUrl)")
            if let url = url {
                urls.append(url)
            } else {
                result(FlutterError(code: "BAD_ARGS", message: "Invalid URL", details: nil))
                break
            }
        }
        let quickLookVC = QuickLookViewController(urls)
        vc.present(quickLookVC, animated: true)
        result(true)
    }
    
    override func applicationDidEnterBackground(_ application: UIApplication) {
        print("Entered background \(UIApplication.shared.backgroundTimeRemaining)")
        Timer.scheduledTimer(withTimeInterval: UIApplication.shared.backgroundTimeRemaining - 5, repeats: false) { timer in
            print("Background update \(UIApplication.shared.backgroundTimeRemaining)")
        }
        return super.applicationDidEnterBackground(application)
    }
    
    override func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if hasMatchingSchemePrefix(url) {
            handleUrls()
            return true
        }
        
        return false
    }
}

extension AppDelegate: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        notifyAboutFiles()
        print("Started event sink listener")
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    func handleUrls() {
        let store = UserDefaults(suiteName: getGroupId())!
        
        if let urls = store.object(forKey: "files") as? [String] {
            pendingFileUrls.append(contentsOf: urls)
            notifyAboutFiles()
        } else {
            pendingErrorType = store.object(forKey: "errorType") as? String ?? "unknownError"
            pendingErrorMessage = store.object(forKey: "errorMessage") as? String ?? "Unknown error"
            notifyAboutFiles()
        }
        store.removeObject(forKey: "files")
        store.removeObject(forKey: "errorType")
        store.removeObject(forKey: "errorMessage")
    }
    
    private func getGroupId() -> String {
        return "group.io.flown.airdashn.appgroup"
    }
    
    public func hasMatchingSchemePrefix(_ url: URL) -> Bool {
        if let bundleId = Bundle.main.bundleIdentifier {
            return url.absoluteString.hasPrefix("ShareMedia-\(bundleId)")
        }
        return false
    }
    
    private func notifyAboutFiles() {
        guard let eventSink = eventSink else { return }
        
        if !pendingFileUrls.isEmpty {
            eventSink(pendingFileUrls)
            pendingFileUrls.removeAll()
        } else if let type = pendingErrorType {
            let message = pendingErrorMessage ?? "Unknown message"
            eventSink(FlutterError(code: type, message: message, details: nil))
            pendingErrorType = nil
            pendingErrorMessage = nil
        }
    }
}

class QuickLookViewController: UIViewController, QLPreviewControllerDataSource {
    
    var urlsOfResources: [URL]
    var shownResource: Bool = false
    
    init(_ resourceURLs: [URL]) {
        self.urlsOfResources = resourceURLs
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        if !shownResource {
            let previewController = QLPreviewController()
            previewController.dataSource = self
            present(previewController, animated: true)
            shownResource = true
        } else {
            self.dismiss(animated: true)
        }
    }
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return self.urlsOfResources.count
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        let url = self.urlsOfResources[index]
        return url as QLPreviewItem
    }
}
