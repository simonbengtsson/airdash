import Cocoa
import ServiceManagement
import FlutterMacOS
import window_manager

class MainFlutterWindow: NSWindow {
    override func awakeFromNib() {
        let flutterViewController = FlutterViewController.init()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)
        
        let messenger = flutterViewController.engine.binaryMessenger
        let channel = FlutterMethodChannel(name: "io.flown.airdash/communicator", binaryMessenger: messenger)
        
        var fileLocationUrl: URL?
        
        channel.setMethodCallHandler { call, result in
            let args = call.arguments as? [String: Any]
            if call.method == "openFinder" {
                let filePath = args!["url"] as! String
                let url = URL(fileURLWithPath: filePath)
                
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
                let isDownloadsDir = downloadsDir.first?.path == filePath
                // Downloads directory is an alias so isDirectory says false for it
                if isDirectory || isDownloadsDir {
                    // This temporary file is a hack for opening the contents of the folder instead of selecting it
                    let tmpFilePath = url.path + "/.tmp_airdash"
                    FileManager.default.createFile(atPath: tmpFilePath, contents: nil, attributes: nil)
                    let tmpFile = URL(fileURLWithPath: tmpFilePath)
                    NSWorkspace.shared.activateFileViewerSelecting([tmpFile])
                    try? FileManager.default.removeItem(at: tmpFile)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                print("Opened finder with \(isDirectory) \(url.path)")
                result(true)
            } else if call.method == "saveFileLocationBookmark" {
                if let filePath = args!["url"] as? String, !filePath.isEmpty {
                    let url = URL(fileURLWithPath: filePath)
                    print("Bookmarking url: \(url.path)")
                    
                    let data = try! url.bookmarkData(options: [.withSecurityScope])
                    UserDefaults.standard.set(data, forKey: "fileLocationBookmark")
                } else {
                    UserDefaults.standard.removeObject(forKey: "fileLocationBookmark")
                }
                result(true)
            } else if call.method == "getFileLocation" {
                if let url = fileLocationUrl {
                    result(url.path)
                    return
                }
                if let bookmarkData = UserDefaults.standard.data(forKey: "fileLocationBookmark") {
                    var isStale = false
                    if let url = try? URL(resolvingBookmarkData: bookmarkData, options:[.withSecurityScope], bookmarkDataIsStale: &isStale), !isStale {
                        fileLocationUrl = url
                        let success = url.startAccessingSecurityScopedResource()
                        if success {
                            print("Bookmarked url \(success) \(url.path)")
                            result(url.path)
                            return
                        }
                    }
                }
                print("Nothing bookmarked or error retrieving bookmark")
                result(nil)
            } else if call.method == "endFileLocationAccess" {
                fileLocationUrl?.stopAccessingSecurityScopedResource()
                fileLocationUrl = nil
                result(true)
            } else if call.method == "toggleAutoStart"  {
                if #available(macOS 13.0, *) {
                    let isEnabled = SMAppService.mainApp.status == .enabled
                    do {
                        if isEnabled {
                            try SMAppService.mainApp.unregister()
                            print("Unregistered auto start")
                        } else {
                            try SMAppService.mainApp.register()
                            print("Regiestered auto start")
                        }
                        result(true)
                    } catch {
                        let errorMessage = "Failed to update auto start \(isEnabled) \(error.localizedDescription)"
                        print(errorMessage)
                        result(self.createSimpleFlutterError(errorMessage))
                    }
                } else {
                    result(self.createSimpleFlutterError("Only supported on macOS 13"))
                }
            } else if call.method == "getAutoStartStatus" {
                if #available(macOS 13.0, *) {
                    let isEnabled = SMAppService.mainApp.status == .enabled
                    result(isEnabled)
                } else {
                    result(self.createSimpleFlutterError("Only supported on macOS 13"))
                }
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
        
        RegisterGeneratedPlugins(registry: flutterViewController)
        
        super.awakeFromNib()
    }
    
    func createSimpleFlutterError(_ message: String) -> FlutterError {
        return FlutterError(code: "CALL_ERROR", message: message, details: nil)
    }

    override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        hiddenWindowAtLaunch()
    }
}
