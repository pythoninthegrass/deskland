import AppKit
import DesklandCore

let command = LaunchCommand.parse(Array(CommandLine.arguments.dropFirst()))

if !SingleInstance.acquire() {
    if let forwarded = command.forwarded {
        SingleInstance.send(forwarded)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))   // lets the notification leave before exit
    }
    exit(0)
}
guard case let .run(autostart) = command else { exit(0) }   // --settings, --menu and --exit mean nothing without a running instance

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = HostController(showSettings: !autostart)
app.delegate = controller
app.run()
