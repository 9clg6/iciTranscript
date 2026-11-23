import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Closing the window hides it (MainFlutterWindow.windowShouldClose): the app
  // lives on in the menu bar (StatusPanelPlugin) until Quit.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // Dock click with the window hidden: show it again. A minimized window
  // counts as visible: AppKit restores it itself.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if flag { return true }
    StatusPanelPlugin.showMainWindow()
    return false
  }

  // Cmd+Q, the app menu, Dock › Quit, logout: the same Dart `quit` as the
  // panel (note saved, owned servers stopped), bounded (StatusPanelPlugin).
  // Without the plugin (engine not up), quit at once.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    return StatusPanelPlugin.shared?.requestQuit() == true ? .terminateLater : .terminateNow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
