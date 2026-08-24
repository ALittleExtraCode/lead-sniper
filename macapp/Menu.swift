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
        // The three tabs, on the numbers, which is what every Mac app with tabs
        // does and therefore what people try first.
        for (index, title) in [L.t(.tabFind), L.t(.tabRadar), L.t(.tabSetup)].enumerated() {
            let item = file.addItem(withTitle: title,
                                    action: #selector(AppDelegate.showTab(_:)),
                                    keyEquivalent: "\(index + 1)")
            item.tag = index
            item.target = target
        }
        file.addItem(.separator())
        file.addItem(withTitle: L.t(.menuSweep),
                     action: #selector(AppDelegate.sweepNow(_:)), keyEquivalent: "r").target = target
        file.addItem(withTitle: L.t(.menuFindPlaces),
                     action: #selector(AppDelegate.findPlaces(_:)), keyEquivalent: "f").target = target
        file.addItem(.separator())
        // The triage keys, so they are discoverable in the menu as well as on
        // screen. D and U work bare in the list; these work anywhere.
        file.addItem(withTitle: L.t(.notRelevant),
                     action: #selector(AppDelegate.notRelevant(_:)), keyEquivalent: "d").target = target
        let copyOpen = file.addItem(withTitle: L.t(.copyAndOpen),
                                    action: #selector(AppDelegate.copyAndOpen(_:)),
                                    keyEquivalent: "\r")
        copyOpen.target = target
        file.addItem(.separator())
        file.addItem(withTitle: L.t(.exportLeads),
                     action: #selector(AppDelegate.exportLeads(_:)), keyEquivalent: "e").target = target

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
