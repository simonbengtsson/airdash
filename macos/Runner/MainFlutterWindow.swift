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
                let url = URL(fileURLWithPath: args!["url"] as! String)
                // This can be used if not wanting to opening the file, and instead open finder
                NSWorkspace.shared.activateFileViewerSelecting([url])
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
