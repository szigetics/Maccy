import Cocoa
import KeyboardShortcuts
import LoginServiceKit
import Preferences
import Sparkle

class Maccy: NSObject {
  static public var returnFocusToPreviousApp = true

  @objc public let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

  private let about = About()
  private let clipboard = Clipboard()
  private let history = History()
  private var menu: Menu!
  private var window: NSWindow!
  @objc private var menuLink: NSStatusItem!

  private lazy var preferencesWindowController = PreferencesWindowController(
    preferencePanes: [
      GeneralPreferenceViewController(),
      AppearancePreferenceViewController(),
      AdvancedPreferenceViewController()
    ]
  )

  private var filterMenuRect: NSRect {
    return NSRect(x: 0, y: 0, width: menu.menuWidth, height: UserDefaults.standard.hideSearch ? 1 : 29)
  }

  private var ignoreEventsObserver: NSKeyValueObservation?
  private var hideFooterObserver: NSKeyValueObservation?
  private var hideSearchObserver: NSKeyValueObservation?
  private var hideTitleObserver: NSKeyValueObservation?
  private var pasteByDefaultObserver: NSKeyValueObservation?
  private var pinToObserver: NSKeyValueObservation?
  private var sortByObserver: NSKeyValueObservation?
  private var statusItemConfigurationObserver: NSKeyValueObservation?
  private var statusItemVisibilityObserver: NSKeyValueObservation?

  override init() {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.showInStatusBar: UserDefaults.Values.showInStatusBar])
    super.init()

    ignoreEventsObserver = UserDefaults.standard.observe(\.ignoreEvents, options: .new, changeHandler: { _, change in
      if let newValue = change.newValue {
        self.statusItem.button?.appearsDisabled = newValue
      }
    })
    hideFooterObserver = UserDefaults.standard.observe(\.hideFooter, options: .new, changeHandler: { _, _ in
      self.rebuild()
    })
    hideSearchObserver = UserDefaults.standard.observe(\.hideSearch, options: .new, changeHandler: { _, _ in
      self.rebuild()
    })
    hideTitleObserver = UserDefaults.standard.observe(\.hideTitle, options: .new, changeHandler: { _, _ in
      self.rebuild()
    })
    pasteByDefaultObserver = UserDefaults.standard.observe(\.pasteByDefault, options: .new, changeHandler: { _, _ in
      self.rebuild()
    })
    pinToObserver = UserDefaults.standard.observe(\.pinTo, options: .new, changeHandler: { _, _ in
      self.rebuild()
    })
    sortByObserver = UserDefaults.standard.observe(\.sortBy, options: .new, changeHandler: { _, _ in
      self.rebuild()
    })
    statusItemConfigurationObserver = UserDefaults.standard.observe(\.showInStatusBar,
                                                                    options: .new,
                                                                    changeHandler: { _, change in
      if self.statusItem.isVisible != change.newValue! {
        self.statusItem.isVisible = change.newValue!
      }
    })
    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new, changeHandler: { _, change in
      if UserDefaults.standard.showInStatusBar != change.newValue! {
        UserDefaults.standard.showInStatusBar = change.newValue!
      }
    })

    menu = Menu(history: history, clipboard: clipboard)
    start()
  }

  deinit {
    ignoreEventsObserver?.invalidate()
    hideFooterObserver?.invalidate()
    hideSearchObserver?.invalidate()
    hideTitleObserver?.invalidate()
    pasteByDefaultObserver?.invalidate()
    pinToObserver?.invalidate()
    sortByObserver?.invalidate()
    statusItemConfigurationObserver?.invalidate()
    statusItemVisibilityObserver?.invalidate()
  }

  func popUp() {
    withFocus {
      switch UserDefaults.standard.popupPosition {
      case "center":
        if let screen = NSScreen.main {
          let topLeftX = (screen.frame.width - self.menu.size.width) / 2
          let topLeftY = (screen.frame.height + self.menu.size.height) / 2
          self.menu.popUp(positioning: nil, at: NSPoint(x: topLeftX, y: topLeftY), in: nil)
        }
      case "statusItem":
        if let button = self.statusItem.button, let window = button.window {
          self.menu.popUp(positioning: nil, at: window.frame.origin, in: nil)
        }
      default:
        self.menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
      }
    }
  }

  @objc
  func popUpStatusItem() {
    withFocus {
      self.statusItem.popUpMenu(self.menu)
    }
  }

  private func start() {
    statusItem.button?.image = NSImage(named: "StatusBarMenuImage")
    statusItem.button?.appearsDisabled = UserDefaults.standard.ignoreEvents
    statusItem.behavior = .removalAllowed
    statusItem.isVisible = UserDefaults.standard.showInStatusBar
    // Simulate statusItem.menu but allowing to withFocus
    statusItem.button?.target = self
    statusItem.button?.action = #selector(popUpStatusItem)

    clipboard.onNewCopy(history.add)
    clipboard.onNewCopy(menu.add)
    clipboard.startListening()

    populateHeader()
    populateItems()
    populateFooter()

    // Link menu to that UI tests can discover it.
    // Normally we would use statusItem.menu, but we cannot because
    // there is no way to activate the application when it is clicked.
    // Hence, we create additional hidden NSStatusItem for tests only.
    if ProcessInfo.processInfo.arguments.contains("ui-testing") {
      menuLink = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      menuLink.isVisible = false
      menuLink.menu = menu
    }
  }

  private func populateHeader() {
    let headerItemView = FilterMenuItemView(frame: filterMenuRect)
    headerItemView.title = "Maccy"

    let headerItem = NSMenuItem()
    headerItem.title = "Maccy"
    headerItem.view = headerItemView
    headerItem.isEnabled = false

    menu.addItem(headerItem)
  }

  private func populateItems() {
    menu.buildItems()
  }

  private func populateFooter() {
    MenuFooter.allCases.map({ $0.menuItem }).forEach({ item in
      item.action = #selector(menuItemAction)
      item.target = self
      menu.addItem(item)
    })
  }

  @objc
  func menuItemAction(_ sender: NSMenuItem) {
    if let tag = MenuFooter(rawValue: sender.tag) {
      switch tag {
      case .about:
        Maccy.returnFocusToPreviousApp = false
        about.openAbout(sender)
      case .clear:
        clearUnpinned()
      case .clearAll:
        clearAll()
      case .quit:
        NSApp.stop(sender)
      case .preferences:
        Maccy.returnFocusToPreviousApp = false
        preferencesWindowController.show()
      default:
        break
      }
    }
  }

  private func clearUnpinned() {
    history.all.filter({ $0.pin == nil }).forEach(history.remove(_:))
    menu.clearUnpinned()
  }

  private func clearAll() {
    history.clear()
    menu.clearAll()
  }

  private func rebuild() {
    menu.clearAll()
    menu.removeAllItems()

    populateHeader()
    populateItems()
    populateFooter()
  }

  // Executes closure with application focus (pun intended).
  //
  // Beware of hacks. This code is so fragile that you should
  // avoid touching it unless you really know what you do.
  // The code is based on hours of googling, trial-and-error
  // and testing sessions. Apologies to any future me.
  //
  // Once we scheduled menu popup, we need to activate
  // the application to let search text field become first
  // responder and start receiving key events.
  // Without forced activation, agent application
  // (LSUIElement) doesn't receive the focus.
  // Once activated, we need to run the closure asynchronously
  // (and with slight delay) because NSMenu.popUp() is blocking
  // execution until menu is closed (https://stackoverflow.com/q/1857603).
  // Annoying side-effect of running NSMenu.popUp() asynchronously
  // is global hotkey being immediately enabled so we no longer
  // can close menu by pressing the hotkey again. To workaround
  // this problem, lifecycle of global hotkey should live here.
  // 30ms delay was chosen by trial-and-error. It's the smallest value
  // not causing menu to close on the  first time it is opened after
  // the application launch.
  //
  // Once we are done working with menu, we need to return
  // focus to previous application. However, if our selection
  // triggered new windows (Preferences, About, Accessibility),
  // we should preserve focus. Additionally, we should not
  // hide an application if there are additional visible windows
  // opened before.
  private func withFocus(_ closure: @escaping () -> Void) {
    Maccy.returnFocusToPreviousApp = NSApp.windows.filter({ $0.isVisible }).count == 0
    KeyboardShortcuts.disable(.popup)
    NSApp.activate(ignoringOtherApps: true)
    Timer.scheduledTimer(withTimeInterval: 0.03, repeats: false) { _ in
      closure()
      KeyboardShortcuts.enable(.popup)
      if Maccy.returnFocusToPreviousApp {
        NSApp.hide(self)
      }
    }
  }
}
