import Cocoa
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
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
        
        RegisterGeneratedPlugins(registry: flutterViewController)
        
        super.awakeFromNib()
    }

    override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        hiddenWindowAtLaunch()
    }
}
