import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = AppController()
        appController = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appController?.stop()
    }
}

@main
enum HorseApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
