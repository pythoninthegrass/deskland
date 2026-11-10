import AppKit
import Carbon
import DesklandCore
import ServiceManagement

// Ctrl+Option+H through Carbon, which needs no permission.
@MainActor
final class Hotkey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let box: Unmanaged<HotkeyBox>

    final class HotkeyBox { let fire: @MainActor () -> Void; init(_ f: @escaping @MainActor () -> Void) { fire = f } }

    init?(onPress: @escaping @MainActor () -> Void) {
        box = Unmanaged.passRetained(HotkeyBox(onPress))
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return noErr }
            let b = Unmanaged<HotkeyBox>.fromOpaque(data).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { b.fire() } }
            return noErr
        }, 1, &spec, box.toOpaque(), &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x444B4C44), id: 1)   // 'DKLD'
        let reg = RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey), id,
                                      GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, reg == noErr else { box.release(); return nil }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        ref = nil; handlerRef = nil
    }
}

enum Autostart {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    // Needs a real app bundle; a bare `swift run` binary fails and the failure is logged.
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("设置开机自动启动失败：\(error.localizedDescription)")
        }
    }
}

// A second launch finds the first through an exclusive lock in the profile directory and forwards its command.
enum SingleInstance {
    nonisolated(unsafe) private static var lockFD: Int32 = -1
    private static let channel = Notification.Name("app.deskland.preview.command")

    static func acquire() -> Bool {
        try? FileManager.default.createDirectory(at: AppPaths.profileDir, withIntermediateDirectories: true)
        let fd = open(AppPaths.profileDir.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else { if fd >= 0 { close(fd) }; return false }
        lockFD = fd
        return true
    }

    static func send(_ command: LaunchCommand) {
        DistributedNotificationCenter.default().postNotificationName(
            channel, object: AppPaths.profileDir.path, userInfo: ["command": command.wireName], deliverImmediately: true)
    }

    @MainActor
    static func listen(_ handler: @escaping @MainActor (LaunchCommand) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: channel, object: AppPaths.profileDir.path, queue: .main) { note in
            guard let name = note.userInfo?["command"] as? String, let c = LaunchCommand(wireName: name) else { return }
            MainActor.assumeIsolated { handler(c) }
        }
    }
}
