import UIKit
import Social
import MobileCoreServices
import Photos

enum ShareError: String, Error {
    case unknownItemType
    case unknownDataType
    case invalidExtensionItem
}

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.clear
        view.isOpaque = false
        
        Task {
            do {
                let files = try await handleContent()
                saveItem(files: files)
            } catch {
                saveError(error: error)
            }
            redirectToHostApp()
        }
        
        // Delay completion somewhat since screenshot view otherwise did not close
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
            self.extensionContext!.completeRequest(returningItems: [])
            print("Completed request")
        }
    }
    
    deinit {
        print("Share extension deinit")
    }
    
    func handleContent() async throws -> [URL] {
        guard let content = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = content.attachments, !attachments.isEmpty
        else {
            throw ShareError.invalidExtensionItem
        }
        
        var files = [URL]()
        for attachment in attachments {
            let identifier = try getIdentifier(attachment)
            let data = try await attachment.loadItem(forTypeIdentifier: identifier)
            
            print("Loaded data of type \(type(of: data))")
            
            if let url = data as? URL {
                // Most files, images, weblinks etc
                print("URL found: \(url)")
                if let scheme = url.scheme, scheme.hasPrefix("http") {
                    files.append(url)
                } else {
                    let filename = url.lastPathComponent
                    // Need to copy otherwise file was not accessible in the host app. It kind of worked
                    // in simulator but on real device
                    let newPath = FileManager.default
                        .containerURL(forSecurityApplicationGroupIdentifier: getGroupId())!
                        .appendingPathComponent(filename)
                    try copyFile(at: url, to: newPath)
                    files.append(newPath)
                }
            } else if let text = data as? String {
                print("Text found: \(text)")
                
                let filename = "text.txt"
                let newPath = FileManager.default
                    .containerURL(forSecurityApplicationGroupIdentifier: getGroupId())!
                    .appendingPathComponent(filename)
                try text.write(to: newPath, atomically: true, encoding: String.Encoding.utf8)
                files.append(newPath)
            } else if let image = data as? UIImage {
                print("UIImage (screenshot) found")
                
                let data = image.pngData()!
                let filename = "screenshot.png"
                let newPath = FileManager.default
                    .containerURL(forSecurityApplicationGroupIdentifier: getGroupId())!
                    .appendingPathComponent(filename)
                try! data.write(to: newPath)
                files.append(newPath)
            } else {
                throw ShareError.unknownDataType
            }
        }
        return files
    }
    
    func copyFile(at source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }
    
    func saveItem(files: [URL]) {
        let store = UserDefaults(suiteName: getGroupId())!
        let urls = files.map { $0.absoluteString }
        store.set(urls, forKey: "files")
    }
    
    func saveError(error: Error) {
        let store = UserDefaults(suiteName: getGroupId())!
        if let error = error as? ShareError {
            store.set(error.rawValue, forKey: "errorType")
        } else {
            store.set("unknown", forKey: "errorType")
            store.set(error.localizedDescription, forKey: "errorMessage")
        }
    }
    
    func getIdentifier(_ attachment: NSItemProvider) throws -> String {
        // Urls can be loaded with kUTTypeItem as well but with kUTTypeURL we get a simpler
        // URL object instead of Data
        if attachment.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
            return kUTTypeURL as String
        } else if attachment.hasItemConformingToTypeIdentifier(kUTTypeItem as String) {
            return kUTTypeItem as String
        } else {
            throw ShareError.unknownItemType
        }
    }
    
    func getHostId() -> String {
        let extensionId = Bundle.main.bundleIdentifier!;
        var parts = extensionId.split(separator: ".")
        parts.removeLast()
        let hostId = parts.joined(separator: ".")
        return hostId
    }
    
    private func getGroupId() -> String {
        return "group.io.flown.airdashn.appgroup"
    }

    private func redirectToHostApp() {
        let url = URL(string: "ShareMedia-\(getHostId())://")
        var responder = self as UIResponder?
        let selectorOpenURL = sel_registerName("openURL:")

        while (responder != nil) {
            if (responder?.responds(to: selectorOpenURL))! {
                let _ = responder?.perform(selectorOpenURL, with: url)
            }
            responder = responder!.next
        }
        print("Redirected to host app")
    }
}

extension Array {
    subscript (safe index: UInt) -> Element? {
        return Int(index) < count ? self[Int(index)] : nil
    }
}
