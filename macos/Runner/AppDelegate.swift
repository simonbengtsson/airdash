import Cocoa
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
    
    //let bluetoothService = BluetoothService()
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    override func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = #imageLiteral(resourceName: "Tray Logo")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.image?.size = NSSize(width: 14.0, height: 14.0)
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.isVisible = false
        
        //bluetoothService.start()
    }
    
    @objc func statusItemClicked(_ sender: NSStatusItem) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let appName = Bundle.main.infoDictionary!["CFBundleName"] as! String
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate), keyEquivalent: "q"))
            let button = statusItem.button!
            let p = NSPoint(x: button.frame.origin.x, y: button.frame.origin.y + button.frame.size.height + 8)
            menu.popUp(positioning: nil, at: p, in: button)
        } else {
            NSApplication.shared.windows.forEach { $0.makeKeyAndOrderFront(nil) }
            print("show window")
        }
    }
    
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
