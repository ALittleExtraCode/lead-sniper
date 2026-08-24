import Cocoa

/// The menu bar. Written out rather than loaded from a nib, because the app is
/// built from a file list with no resource step.
enum Menu {
    static func install(target: AppDelegate) {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let app = NSMenu()
        appItem.submenu = app
        app.addItem(withTitle: L.t(.menuAbout),
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(withTitle: L.t(.menuCheckUpdates),
                    action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "").target = target
        app.addItem(.separator())
        app.addItem(withTitle: L.t(.menuHide),
                    action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: L.t(.menuHideOthers),
                                     action: #selector(NSApplication.hideOtherApplications(_:)),
                                     keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(.separator())
        app.addItem(withTitle: L.t(.menuQuit),
                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let file = NSMenu(title: L.t(.menuFile))
        fileItem.submenu = file
        file.addItem(withTitle: L.t(.menuSweep),
                     action: #selector(AppDelegate.sweepNow(_:)), keyEquivalent: "r").target = target
        file.addItem(withTitle: L.t(.menuSetup),
                     action: #selector(AppDelegate.openSetup(_:)), keyEquivalent: ",").target = target

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: L.t(.menuEdit))
        editItem.submenu = edit
        edit.addItem(withTitle: L.t(.menuUndo), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L.t(.menuRedo), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L.t(.menuCut), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L.t(.menuCopy), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L.t(.menuPaste), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L.t(.menuSelectAll), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let help = NSMenu(title: L.t(.menuHelp))
        helpItem.submenu = help
        help.addItem(withTitle: L.t(.menuSite),
                     action: #selector(AppDelegate.openSite(_:)), keyEquivalent: "").target = target

        NSApp.mainMenu = main
    }
}
