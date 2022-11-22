import Cocoa
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
    
    //let bluetoothService = BluetoothService()
    
    override func applicationDidFinishLaunching(_ notification: Notification) {
        // Unsure why this is needed since it's not mentioned in the tray_manager docs
        // but without it the tray icon did not show up
        NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }
    
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
