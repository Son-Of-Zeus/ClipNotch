import AppKit
import ApplicationServices

struct BrowserPage: @unchecked Sendable {
    let processID: pid_t
    let application: AXUIElement
    let window: AXUIElement
    let webArea: AXUIElement
    let url: URL

    var host: String { url.host?.lowercased() ?? "" }

    func isSameDocument(as other: BrowserPage) -> Bool {
        processID == other.processID && url == other.url
            && CFEqual(window, other.window) && CFEqual(webArea, other.webArea)
    }
}

struct BrowserFormField: @unchecked Sendable, Identifiable {
    let id = UUID()
    let element: AXUIElement
    let categoryID: String
    let labels: [String]
}

struct AutofillFieldState: Sendable {
    let value: String
    let isWritable: Bool
    let isFocused: Bool
}

protocol AutofillFieldAccess: Actor {
    func isCurrent(_ page: BrowserPage) -> Bool
    func state(of field: BrowserFormField, on page: BrowserPage) -> AutofillFieldState?
    func write(_ text: String, to field: BrowserFormField, on page: BrowserPage)
    func focus(_ field: BrowserFormField, on page: BrowserPage) -> Bool
    func paste(into field: BrowserFormField, on page: BrowserPage, pasteboard: NSPasteboard, changeCount: Int) -> Bool
}

protocol BrowserFormAccess: AutofillFieldAccess {
    func currentPage(activate: Bool, retry: Bool) async -> BrowserPage?
    func scan(_ page: BrowserPage, categories: [AutofillCategory]) async -> [BrowserFormField]
    func observe(_ page: BrowserPage, changed: @escaping @Sendable (String) -> Void) async
    func stopObserving() async
}

private final class BrowserAXObserverHandler: @unchecked Sendable {
    let changed: @Sendable (String) -> Void
    let webArea: AXUIElement

    init(webArea: AXUIElement, changed: @escaping @Sendable (String) -> Void) {
        self.webArea = webArea
        self.changed = changed
    }
}

private let browserAXCallback: AXObserverCallback = { _, element, notification, context in
    guard let context else { return }
    let handler = Unmanaged<BrowserAXObserverHandler>.fromOpaque(context).takeUnretainedValue()
    let name = notification as String
    if name == kAXUIElementDestroyedNotification, !CFEqual(element, handler.webArea) { return }
    handler.changed(name)
}

// All tree reads and writes run on this actor, away from the main actor.
actor BrowserAccessibility: BrowserFormAccess {
    private var activatedProcess: pid_t?
    private var activatedLaunchDate: Date?
    private var requestedManualAccessibility = false
    private var usedEnhancedAccessibility = false
    private var observer: AXObserver?
    private var observedElements: [AXUIElement] = []
    private var observerHandler: BrowserAXObserverHandler?

    static let supportedBrowsers: Set<String> = ["com.google.Chrome", "com.apple.Safari"]

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        guard !Task.isCancelled else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        guard !Task.isCancelled else { return [] }
        AXUIElementSetMessagingTimeout(element, 0.15)
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count) == .success,
              count > 0 else { return [] }
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, min(count, 256), &values) == .success else { return [] }
        return values as? [AXUIElement] ?? []
    }

    private func webArea(in window: AXUIElement) -> AXUIElement? {
        var queue = [window]
        var index = 0
        let deadline = Date().addingTimeInterval(0.35)
        while index < queue.count, index < 400, Date() < deadline, !Task.isCancelled {
            let element = queue[index]
            index += 1
            if attribute(element, kAXRoleAttribute) as? String == "AXWebArea" { return element }
            queue.append(contentsOf: children(of: element).prefix(max(0, 400 - queue.count)))
        }
        return nil
    }

    func currentPage(activate: Bool = false, retry: Bool = false) -> BrowserPage? {
        guard !Task.isCancelled, AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              Self.supportedBrowsers.contains(app.bundleIdentifier ?? "") else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.15)
        if activate, app.bundleIdentifier == "com.google.Chrome" {
            // Chromium enables accessibility when its application role is requested.
            _ = attribute(application, kAXRoleAttribute)
            if activatedProcess != app.processIdentifier || activatedLaunchDate != app.launchDate {
                activatedProcess = app.processIdentifier
                activatedLaunchDate = app.launchDate
                requestedManualAccessibility = false
                usedEnhancedAccessibility = false
            }
            if !requestedManualAccessibility {
                requestedManualAccessibility = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue) != .cannotComplete
            } else if retry, !usedEnhancedAccessibility {
                usedEnhancedAccessibility = AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) != .cannotComplete
            }
        }
        guard let window = elementAttribute(application, kAXFocusedWindowAttribute),
              let area = webArea(in: window), let value = attribute(area, kAXURLAttribute),
              let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return BrowserPage(processID: app.processIdentifier, application: application, window: window, webArea: area, url: url)
    }

    func isCurrent(_ page: BrowserPage) -> Bool {
        guard let current = currentPage(), attribute(current.webArea, "AXLoaded") as? Bool != false else { return false }
        return page.isSameDocument(as: current)
    }

    private func labels(of element: AXUIElement) -> [String] {
        var labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, "AXPlaceholderValue"].compactMap {
            attribute(element, $0) as? String
        }.filter { !$0.isEmpty }
        if let titleElement = elementAttribute(element, "AXTitleUIElement") {
            for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                if let text = attribute(titleElement, key) as? String, !text.isEmpty { labels.append(text) }
            }
        }
        // A single adjacent label in a small group is usable when no name is exposed.
        if labels.isEmpty, let parent = elementAttribute(element, kAXParentAttribute) {
            let siblings = children(of: parent)
            let inputs = siblings.filter { ["AXTextField", "AXTextArea"].contains(attribute($0, kAXRoleAttribute) as? String ?? "") }
            if inputs.count == 1, let index = siblings.firstIndex(where: { CFEqual($0, element) }), index > 0 {
                let previous = siblings[index - 1]
                if attribute(previous, kAXRoleAttribute) as? String == "AXStaticText",
                   let text = attribute(previous, kAXValueAttribute) as? String { labels.append(text) }
            }
        }
        return labels
    }

    private func isEditable(_ element: AXUIElement) -> Bool {
        guard ["AXTextField", "AXTextArea"].contains(attribute(element, kAXRoleAttribute) as? String ?? ""),
              attribute(element, kAXSubroleAttribute) as? String != "AXSecureTextField",
              attribute(element, kAXEnabledAttribute) as? Bool == true,
              attribute(element, "AXHidden") as? Bool != true else { return false }
        return !FormFieldMatcher.isSensitive(labels(of: element))
    }

    func scan(_ page: BrowserPage, categories: [AutofillCategory]) -> [BrowserFormField] {
        guard isCurrent(page) else { return [] }
        if children(of: page.webArea).isEmpty {
            _ = currentPage(activate: true, retry: true)
            return []
        }
        var stack = [page.webArea]
        var index = 0
        var fields: [BrowserFormField] = []
        let deadline = Date().addingTimeInterval(1.5)
        while let element = stack.popLast(), index < 2_000, Date() < deadline, !Task.isCancelled {
            index += 1
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            if !CFEqual(element, page.webArea), attribute(element, kAXRoleAttribute) as? String == "AXWebArea" {
                // Consent for the top-level site does not cover a different iframe origin.
                guard let url = attribute(element, kAXURLAttribute) as? URL,
                      url.scheme == page.url.scheme, url.host == page.url.host, url.port == page.url.port else { continue }
            }
            if ["AXTextField", "AXTextArea"].contains(role), isEditable(element), attribute(element, kAXValueAttribute) as? String == "" {
                let names = labels(of: element)
                if let categoryID = FormFieldMatcher.match(labels: names, categories: categories) {
                    fields.append(BrowserFormField(element: element, categoryID: categoryID, labels: names))
                }
            }
            stack.append(contentsOf: children(of: element).prefix(max(0, 2_000 - index - stack.count)).reversed())
        }
        return fields
    }

    private func belongsToPage(_ element: AXUIElement, page: BrowserPage) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<64 {
            guard let node = current else { return false }
            if CFEqual(node, page.webArea) { return true }
            if attribute(node, kAXRoleAttribute) as? String == "AXWebArea" {
                guard let url = attribute(node, kAXURLAttribute) as? URL,
                      url.scheme == page.url.scheme, url.host == page.url.host, url.port == page.url.port else { return false }
            }
            current = elementAttribute(node, kAXParentAttribute)
        }
        return false
    }

    func state(of field: BrowserFormField, on page: BrowserPage) -> AutofillFieldState? {
        guard !Task.isCancelled, isCurrent(page), belongsToPage(field.element, page: page), isEditable(field.element),
              labels(of: field.element) == field.labels,
              let value = attribute(field.element, kAXValueAttribute) as? String else { return nil }
        var writable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(field.element, kAXValueAttribute as CFString, &writable)
        let focusedElement = elementAttribute(page.application, kAXFocusedUIElementAttribute)
        return AutofillFieldState(value: value, isWritable: writable.boolValue,
                                  isFocused: focusedElement.map { CFEqual($0, field.element) } ?? false)
    }

    func write(_ text: String, to field: BrowserFormField, on page: BrowserPage) {
        guard let state = state(of: field, on: page), state.isWritable, state.isFocused, state.value.isEmpty,
              !Task.isCancelled, isCurrent(page) else { return }
        AXUIElementSetAttributeValue(field.element, kAXValueAttribute as CFString, text as CFString)
    }

    func focus(_ field: BrowserFormField, on page: BrowserPage) -> Bool {
        guard let state = state(of: field, on: page), state.value.isEmpty,
              !Task.isCancelled, isCurrent(page) else { return false }
        return AXUIElementSetAttributeValue(field.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    func paste(into field: BrowserFormField, on page: BrowserPage, pasteboard: NSPasteboard, changeCount: Int) -> Bool {
        guard let state = state(of: field, on: page), state.value.isEmpty, state.isFocused,
              !Task.isCancelled, pasteboard.changeCount == changeCount else { return false }
        PasteDelivery.postSyntheticPaste(to: page.processID)
        return true
    }

    func observe(_ page: BrowserPage, changed: @escaping @Sendable (String) -> Void) async {
        await stopObserving()
        var created: AXObserver?
        guard AXObserverCreate(page.processID, browserAXCallback, &created) == .success, let created else { return }
        let handler = BrowserAXObserverHandler(webArea: page.webArea, changed: changed)
        let context = Unmanaged.passUnretained(handler).toOpaque()
        let elements = [page.application, page.window, page.webArea]
        let notifications = [kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification,
                             kAXSelectedChildrenChangedNotification, kAXUIElementDestroyedNotification,
                             kAXValueChangedNotification, "AXLoadComplete", "AXLayoutChanged"]
        for element in elements {
            for name in notifications { AXObserverAddNotification(created, element, name as CFString, context) }
        }
        observerHandler = handler
        observer = created
        observedElements = elements
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    func stopObserving() async {
        let previous = observer
        let handler = observerHandler
        observer = nil
        observedElements = []
        observerHandler = nil
        await MainActor.run {
            if let previous {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(previous), .commonModes)
            }
            withExtendedLifetime(handler) {}
        }
    }
}

@MainActor
final class BrowserFormMonitor {
    let accessibility: any BrowserFormAccess
    private let isBrowserActive: () -> Bool
    private let hasPermission: () -> Bool
    var categories: () -> [AutofillCategory] = { [] }
    var isEnabled: () -> Bool = { false }
    var onScan: ((UUID, BrowserPage, [BrowserFormField]) -> Void)?
    var onInvalidation: (() -> Void)?
    var onPermissionChange: (() -> Void)?
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var task: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var scanID = UUID()
    private var page: BrowserPage?
    private var visitID = UUID()
    private var generation = UUID()
    private var observationID = UUID()
    private var suspended = false
    private var isActive = false
    private var previousCategories: [AutofillCategory] = []
    private var previousPermission: Bool?

    init(accessibility: any BrowserFormAccess = BrowserAccessibility(),
         isBrowserActive: @escaping () -> Bool = {
             BrowserAccessibility.supportedBrowsers.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
         }, hasPermission: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.accessibility = accessibility
        self.isBrowserActive = isBrowserActive
        self.hasPermission = hasPermission
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPage() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.didWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification].contains(notification.name) {
                        self.suspended = true
                    } else if notification.name != NSWorkspace.didActivateApplicationNotification {
                        self.suspended = false
                    }
                    self.invalidate(leavingPage: false)
                    self.checkPage(forceScan: true)
                }
            })
        }
        checkPage()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
        invalidate(leavingPage: true)
        Task { await accessibility.stopObserving() }
    }

    func refresh() { checkPage(forceScan: true) }

    private func invalidate(leavingPage: Bool) {
        generation = UUID()
        task?.cancel()
        task = nil
        scanTask?.cancel()
        scanTask = nil
        onInvalidation?()
        if leavingPage {
            observationID = UUID()
            page = nil
            visitID = UUID()
        }
    }

    private func checkPage(forceScan: Bool = false) {
        let permission = hasPermission()
        if previousPermission != permission {
            previousPermission = permission
            onPermissionChange?()
        }
        let enabled = isEnabled()
        let activeBrowser = isBrowserActive()
        guard !suspended, enabled, permission, activeBrowser else {
            if isActive { invalidate(leavingPage: false) }
            isActive = false
            return
        }
        let resumed = !isActive
        isActive = true
        guard task == nil else { return }
        let generation = generation
        task = Task { [weak self] in
            guard let self else { return }
            var current = await accessibility.currentPage(activate: true, retry: false)
            if current == nil {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                current = await accessibility.currentPage(activate: true, retry: true)
            }
            guard !Task.isCancelled, generation == self.generation else { return }
            self.task = nil
            guard let current else {
                self.invalidate(leavingPage: true)
                return
            }
            let changed = page.map { !$0.isSameDocument(as: current) } ?? true
            if changed {
                self.invalidate(leavingPage: true)
                self.page = current
            }
            if changed || resumed {
                self.observationID = UUID()
                let observerGeneration = self.observationID
                await accessibility.observe(current) { [weak self] name in
                    Task { @MainActor in
                        guard let self, self.observationID == observerGeneration else { return }
                        self.handleNotification(name)
                    }
                }
                guard observerGeneration == self.observationID else { return }
            }
            let currentCategories = categories()
            if changed || resumed || forceScan || currentCategories != previousCategories {
                previousCategories = currentCategories
                scheduleScan(replacingPending: true)
            }
        }
    }

    private func handleNotification(_ name: String) {
        guard !suspended, isEnabled(), isBrowserActive() else { return }
        if ["AXLoadComplete", kAXUIElementDestroyedNotification].contains(name) {
            invalidate(leavingPage: true)
            checkPage()
        } else if [kAXFocusedWindowChangedNotification, kAXSelectedChildrenChangedNotification].contains(name) {
            checkPage(forceScan: true)
        } else {
            checkPage()
            scheduleScan()
        }
    }

    private func scheduleScan(replacingPending: Bool = false) {
        guard replacingPending || scanTask == nil else { return }
        scanTask?.cancel()
        guard isBrowserActive(), let page, !categories().isEmpty else { return }
        let generation = generation
        let visit = visitID
        let categories = categories()
        let requestID = UUID()
        scanID = requestID
        scanTask = Task { [weak self] in
            guard let self else { return }
            defer { if scanID == requestID { scanTask = nil } }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            var fields = await accessibility.scan(page, categories: categories)
            if fields.isEmpty {
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                fields = await accessibility.scan(page, categories: categories)
            }
            let current = await accessibility.isCurrent(page)
            guard current, !Task.isCancelled, generation == self.generation, isEnabled(), isBrowserActive() else { return }
            onScan?(visit, page, fields)
        }
    }
}
