import AppKit
import ApplicationServices
import XCTest
@testable import ClipNotch

final class FormAutofillTests: XCTestCase {
    private let email = AutofillCategory(id: "email", label: "Email", synonyms: [])

    func testMatchingUsesLabelsAndSynonymsAndRejectsAmbiguity() {
        XCTAssertEqual(FormFieldMatcher.match(labels: ["EMAIL ADDRESS *"], categories: [email]), "email")
        XCTAssertNil(FormFieldMatcher.match(labels: ["Recovery email address"], categories: [email]))
        let custom = AutofillCategory(id: "customer id", label: "Customer ID", synonyms: ["Membership number"])
        XCTAssertEqual(FormFieldMatcher.match(labels: ["Membership number:"], categories: [custom]), "customer id")
        let collision = AutofillCategory(id: "account", label: "Account", synonyms: ["Email address"])
        XCTAssertNil(FormFieldMatcher.match(labels: ["Email address"], categories: [email, collision]))
        XCTAssertNil(FormFieldMatcher.match(labels: ["Email", "One-time verification code"], categories: [email]))
    }

    func testPreferredProfileUsesOtherProfilesOnlyForMissingValues() {
        let work = DataPaletteProfile(name: "Work", fields: [DataPaletteField(label: "Email", value: "work@example.com")])
        let personal = DataPaletteProfile(name: "Personal", fields: [
            DataPaletteField(label: "Email", value: "personal@example.com"),
            DataPaletteField(label: "Phone", value: "111")
        ])
        let other = DataPaletteProfile(name: "Other", fields: [DataPaletteField(label: "Phone", value: "222")])
        XCTAssertEqual(AutofillProfileResolver.candidates(for: "email", preferredProfileID: work.id, profiles: [work, personal]).map(\.profileID), [work.id])
        XCTAssertEqual(AutofillProfileResolver.candidates(for: "phone", preferredProfileID: work.id, profiles: [work, personal]).map(\.profileID), [personal.id])
        XCTAssertEqual(AutofillProfileResolver.candidates(for: "phone", preferredProfileID: work.id, profiles: [work, personal, other]).count, 2)
        XCTAssertTrue(AutofillProfileResolver.candidates(for: "address", preferredProfileID: work.id, profiles: [work, personal]).isEmpty)
    }

    func testGoogleFormsRequiredQuestionNameMatchesWithoutLooseSubstringMatching() {
        let teamName = AutofillCategory(id: "team name", label: "Team Name", synonyms: [])
        XCTAssertEqual(FormFieldMatcher.match(labels: ["Team Name Required question"], categories: [teamName]), "team name")
        XCTAssertEqual(FormFieldMatcher.match(labels: ["Team Name *"], categories: [teamName]), "team name")
        XCTAssertNil(FormFieldMatcher.match(labels: ["Team captain name Required question"], categories: [teamName]))
        let other = AutofillCategory(id: "other", label: "Other", synonyms: ["Team Name Required question"])
        XCTAssertNil(FormFieldMatcher.match(labels: ["Team Name Required question"], categories: [teamName, other]))
    }

    func testDuplicateValuesWithinPreferredProfileRequireChoice() {
        let profile = DataPaletteProfile(name: "Work", fields: [
            DataPaletteField(label: "Email", value: "first@example.com"),
            DataPaletteField(label: "Email", value: "second@example.com")
        ])
        XCTAssertEqual(AutofillProfileResolver.candidates(for: "email", preferredProfileID: profile.id, profiles: [profile]).count, 2)
    }

    @MainActor
    func testSynonymsSurviveProfileEditsAndExistingDocumentsStillLoad() async throws {
        let profile = DataPaletteProfile(name: "Work")
        let encodedProfile = try JSONEncoder().encode(profile)
        var oldDocument = Data("{\"profiles\":[".utf8)
        oldDocument.append(encodedProfile)
        oldDocument.append(Data("]}".utf8))
        XCTAssertTrue(try JSONDecoder().decode(DataPaletteDocument.self, from: oldDocument).synonyms.isEmpty)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = DataPalettePersistence(directory: directory, encryption: testEncryption)
        let store = DataPaletteStore(persistence: persistence)
        await store.load()
        let type = DataPaletteType(label: "Phone")
        let savedAliases = await store.saveSynonyms(["Mobile", "Contact number"], for: type)
        XCTAssertTrue(savedAliases)
        let savedProfile = await store.save(profile)
        XCTAssertTrue(savedProfile)
        let document = try await persistence.load()
        XCTAssertEqual(document.synonyms["phone"], ["Contact number", "Mobile"])
    }

    @MainActor
    func testNotNowIsVisitScopedAndNeverSuggestIsHostScopedAndPersistent() throws {
        var policy = AutofillVisitPolicy()
        let visit = UUID()
        policy.enter(visit)
        policy.dismiss()
        policy.enter(visit)
        XCTAssertFalse(policy.permits(host: "example.com", excludedHosts: []))
        policy.enter(UUID())
        XCTAssertTrue(policy.permits(host: "example.com", excludedHosts: []))
        let directory = makeStorageDirectory()
        let preferences = try PreferencesStore(directory: directory, encryption: testEncryption)
        let settings = AutofillSettings(preferences: preferences)
        settings.exclude("EXAMPLE.COM")
        let reloaded = AutofillSettings(preferences: try PreferencesStore(directory: directory, encryption: testEncryption))
        XCTAssertFalse(policy.permits(host: "example.com", excludedHosts: reloaded.excludedHosts))
        XCTAssertTrue(policy.permits(host: "sub.example.com", excludedHosts: reloaded.excludedHosts))
        reloaded.allow("example.com")
        XCTAssertTrue(reloaded.excludedHosts.isEmpty)
    }

    @MainActor
    func testDirectWriteDoesNotTouchClipboardOrPaste() async {
        let access = MockFormAccessibility()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("original", forType: .string)
        var changes = 0
        let delivery = FormFillDelivery(accessibility: access, pasteboard: pasteboard, onPasteboardChange: { changes += 1 })
        let outcome = await delivery.fill(access.field, on: await access.page, text: "saved", isCurrent: { true })
        XCTAssertEqual(outcome, .filled)
        let count = await access.pasteCount
        XCTAssertEqual(count, 0)
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    @MainActor
    func testUnchangedWriteUsesPasteAndRestoresAllClipboardRepresentations() async throws {
        let access = MockFormAccessibility()
        await access.setWriteResult("")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let original = NSPasteboardItem()
        original.setString("original", forType: .string)
        let rtf = try NSAttributedString(string: "original").data(
            from: NSRange(location: 0, length: 8), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        original.setData(rtf, forType: .rtf)
        pasteboard.writeObjects([original])
        XCTAssertNotNil(AutofillClipboardSnapshot(pasteboard: pasteboard))
        var changes = 0
        let delivery = FormFillDelivery(accessibility: access, pasteboard: pasteboard, onPasteboardChange: { changes += 1 })
        let outcome = await delivery.fill(access.field, on: await access.page, text: "saved", isCurrent: { true })
        XCTAssertEqual(outcome, .filled)
        let count = await access.pasteCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(changes, 2)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertEqual(pasteboard.data(forType: .rtf), rtf)
    }

    @MainActor
    func testPartialWriteAndUnverifiedFocusNeverPaste() async {
        for result in ["partial", ""] {
            let access = MockFormAccessibility()
            await access.setWriteResult(result)
            await access.setFocusAllowed(result == "partial")
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            let delivery = FormFillDelivery(accessibility: access, pasteboard: pasteboard, onPasteboardChange: {})
            _ = await delivery.fill(access.field, on: await access.page, text: "saved", isCurrent: { true })
            let count = await access.pasteCount
            XCTAssertEqual(count, 0)
        }
    }

    @MainActor
    func testSuccessfulFocusRequestWithoutVerifiedFocusNeverWritesOrPastes() async {
        let access = MockFormAccessibility()
        await access.setFocusVerified(false)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let delivery = FormFillDelivery(accessibility: access, pasteboard: pasteboard, onPasteboardChange: {})
        let outcome = await delivery.fill(access.field, on: await access.page, text: "saved", isCurrent: { true })
        XCTAssertEqual(outcome, .skipped)
        let writes = await access.values
        let pastes = await access.pasteCount
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(pastes, 0)
    }

    @MainActor
    func testSequentialFieldsKeepTheirOwnValuesWithDelayedBrowserPaste() async {
        let access = MockFormAccessibility()
        await access.setWriteResult("")
        await access.setPasteDelay(.milliseconds(900))
        let phone = BrowserFormField(element: AXUIElementCreateSystemWide(), categoryID: "phone", labels: ["Phone"])
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("original", forType: .string)
        let delivery = FormFillDelivery(accessibility: access, pasteboard: pasteboard, onPasteboardChange: {})
        let emailResult = await delivery.fill(access.field, on: await access.page, text: "test@example.com", isCurrent: { true })
        let phoneResult = await delivery.fill(phone, on: await access.page, text: "5550101001", isCurrent: { true })
        XCTAssertEqual(emailResult, .filled)
        XCTAssertEqual(phoneResult, .filled)
        let values = await access.values
        XCTAssertEqual(values[access.field.id], "test@example.com")
        XCTAssertEqual(values[phone.id], "5550101001")
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    @MainActor
    func testNavigationStopsDeliveryAndClipboardOwnershipProtectsNewCopy() async {
        let access = MockFormAccessibility()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("original", forType: .string)
        let snapshot = AutofillClipboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("temporary", forType: .string)
        let ownedCount = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("user copied", forType: .string)
        XCTAssertFalse(snapshot?.restore(to: pasteboard, ifOwnedChangeCount: ownedCount) ?? true)
        XCTAssertEqual(pasteboard.string(forType: .string), "user copied")
        await access.navigate(to: "https://example.com/next")
        let delivery = FormFillDelivery(accessibility: access, pasteboard: pasteboard, onPasteboardChange: {})
        let outcome = await delivery.fill(access.field, on: MockFormAccessibility.makePage(), text: "saved", isCurrent: { true })
        XCTAssertEqual(outcome, .stopped)
        let count = await access.pasteCount
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testCancellationAfterPasteWaitsBeforeRestoringClipboard() async throws {
        let access = MockFormAccessibility()
        await access.setWriteResult("")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("original", forType: .string)
        let delivery = FormFillDelivery(accessibility: access, pasteboard: pasteboard, onPasteboardChange: {})
        let page = await access.page
        let operation = Task { await delivery.fill(access.field, on: page, text: "saved", isCurrent: { true }) }
        for _ in 0..<100 {
            if await access.pasteCount > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let count = await access.pasteCount
        XCTAssertEqual(count, 1)
        operation.cancel()
        XCTAssertEqual(pasteboard.string(forType: .string), "saved")
        let outcome = await operation.value
        XCTAssertEqual(outcome, .stopped)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    @MainActor
    func testDelayedTreeIsRetriedAndURLPollingFindsNavigationWithoutNotification() async {
        let access = MockFormAccessibility()
        await access.setScanBehavior(emptyScans: 1)
        let monitor = BrowserFormMonitor(accessibility: access, isBrowserActive: { true }, hasPermission: { true })
        monitor.isEnabled = { true }
        monitor.categories = { [self.email] }
        let ready = expectation(description: "delayed tree ready")
        let navigated = expectation(description: "URL change detected")
        monitor.onScan = { _, page, fields in
            XCTAssertFalse(fields.isEmpty)
            if page.url.path == "/next" { navigated.fulfill() } else { ready.fulfill() }
        }
        monitor.start()
        defer { monitor.stop() }
        await fulfillment(of: [ready], timeout: 4)
        await access.navigate(to: "https://example.com/next")
        await fulfillment(of: [navigated], timeout: 4)
        let scans = await access.scanCount
        XCTAssertEqual(scans, 3)
    }

    @MainActor
    func testFrequentLayoutEventsDoNotStarvePendingScan() async throws {
        let access = MockFormAccessibility()
        let monitor = BrowserFormMonitor(accessibility: access, isBrowserActive: { true }, hasPermission: { true })
        monitor.isEnabled = { true }
        monitor.categories = { [self.email] }
        let scanned = expectation(description: "scan completes during layout changes")
        scanned.assertForOverFulfill = false
        monitor.onScan = { _, _, _ in scanned.fulfill() }
        monitor.start()
        defer { monitor.stop() }
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(70))
            await access.emit("AXLayoutChanged")
        }
        let count = await access.scanCount
        XCTAssertGreaterThan(count, 0)
        await fulfillment(of: [scanned], timeout: 2)
    }

    @MainActor
    func testSelectionChangeWithinSameDocumentKeepsThePromptSession() async {
        let access = MockFormAccessibility()
        let monitor = BrowserFormMonitor(accessibility: access, isBrowserActive: { true }, hasPermission: { true })
        monitor.isEnabled = { true }
        monitor.categories = { [self.email] }
        let first = expectation(description: "initial scan")
        let second = expectation(description: "selection rescan")
        var scans = 0
        var invalidations = 0
        monitor.onInvalidation = { invalidations += 1 }
        monitor.onScan = { _, _, _ in
            scans += 1
            if scans == 1 { first.fulfill() } else if scans == 2 { second.fulfill() }
        }
        monitor.start()
        defer { monitor.stop() }
        await fulfillment(of: [first], timeout: 3)
        let previousInvalidations = invalidations
        await access.emit(kAXSelectedChildrenChangedNotification)
        await fulfillment(of: [second], timeout: 3)
        XCTAssertEqual(invalidations, previousInvalidations)
    }

    @MainActor
    func testPermissionLossInvalidatesPendingWork() {
        let access = MockFormAccessibility()
        var permission = true
        let monitor = BrowserFormMonitor(accessibility: access, isBrowserActive: { true }, hasPermission: { permission })
        monitor.isEnabled = { true }
        var permissionChanges = 0
        var invalidations = 0
        monitor.onPermissionChange = { permissionChanges += 1 }
        monitor.onInvalidation = { invalidations += 1 }
        monitor.start()
        defer { monitor.stop() }
        permission = false
        monitor.refresh()
        XCTAssertEqual(permissionChanges, 2)
        XCTAssertEqual(invalidations, 1)
    }

    @MainActor
    func testNavigationDiscardsAResultFromAnOldScan() async {
        let access = MockFormAccessibility()
        await access.setScanBehavior(delay: .milliseconds(700))
        let started = expectation(description: "old scan started")
        await access.onScanStart { page in
            if page.url.path == "/form" { started.fulfill() }
        }
        let monitor = BrowserFormMonitor(accessibility: access, isBrowserActive: { true }, hasPermission: { true })
        monitor.isEnabled = { true }
        monitor.categories = { [self.email] }
        let current = expectation(description: "new scan accepted")
        monitor.onScan = { _, page, _ in
            XCTAssertEqual(page.url.path, "/next")
            current.fulfill()
        }
        monitor.start()
        defer { monitor.stop() }
        await fulfillment(of: [started], timeout: 4)
        await access.navigate(to: "https://example.com/next")
        await access.emit("AXLoadComplete")
        await fulfillment(of: [current], timeout: 4)
    }

    @MainActor
    func testNavigationNotificationScansNewDocumentAndInvalidatesOldTarget() async throws {
        let access = MockFormAccessibility()
        let monitor = BrowserFormMonitor(accessibility: access, isBrowserActive: { true }, hasPermission: { true })
        monitor.isEnabled = { true }
        monitor.categories = { [self.email] }
        let firstScan = expectation(description: "initial scan")
        let secondScan = expectation(description: "navigation scan")
        var visits: [UUID] = []
        var invalidations = 0
        monitor.onInvalidation = { invalidations += 1 }
        monitor.onScan = { visit, page, _ in
            if visits.last == visit { return }
            visits.append(visit)
            if page.url.path == "/next" { secondScan.fulfill() } else { firstScan.fulfill() }
        }
        monitor.start()
        defer { monitor.stop() }
        await fulfillment(of: [firstScan], timeout: 4)
        await access.navigate(to: "https://example.com/next")
        await access.emit("AXLoadComplete")
        await fulfillment(of: [secondScan], timeout: 4)
        XCTAssertEqual(visits.count, 2)
        XCTAssertGreaterThanOrEqual(invalidations, 2)
    }
}

private actor MockFormAccessibility: BrowserFormAccess {
    var page = makePage()
    let field = BrowserFormField(element: AXUIElementCreateSystemWide(), categoryID: "email", labels: ["Email"])
    var values: [UUID: String] = [:]
    var writeResult: String?
    var focusAllowed = true
    var focusedFieldID: UUID?
    var focusVerified = true
    var pasteDelay: Duration = .zero
    var pasteCount = 0
    var changed: (@Sendable (String) -> Void)?
    var emptyScans = 0
    var scanDelay: Duration = .zero
    var scanCount = 0
    var scanStarted: (@Sendable (BrowserPage) -> Void)?

    nonisolated static func makePage(_ url: String = "https://example.com/form") -> BrowserPage {
        let element = AXUIElementCreateSystemWide()
        return BrowserPage(processID: 1, application: element, window: element, webArea: element, url: URL(string: url)!)
    }

    func setWriteResult(_ result: String) { writeResult = result }
    func setFocusAllowed(_ allowed: Bool) { focusAllowed = allowed }
    func setFocusVerified(_ verified: Bool) { focusVerified = verified }
    func setPasteDelay(_ delay: Duration) { pasteDelay = delay }
    func navigate(to url: String) { page = Self.makePage(url) }
    func emit(_ name: String) { changed?(name) }
    func setScanBehavior(emptyScans: Int = 0, delay: Duration = .zero) {
        self.emptyScans = emptyScans
        scanDelay = delay
    }
    func onScanStart(_ callback: @escaping @Sendable (BrowserPage) -> Void) { scanStarted = callback }
    func currentPage(activate: Bool, retry: Bool) -> BrowserPage? { page }
    func scan(_ page: BrowserPage, categories: [AutofillCategory]) async -> [BrowserFormField] {
        scanCount += 1
        scanStarted?(page)
        try? await Task.sleep(for: scanDelay)
        if emptyScans > 0 {
            emptyScans -= 1
            return []
        }
        return [field]
    }
    func observe(_ page: BrowserPage, changed: @escaping @Sendable (String) -> Void) { self.changed = changed }
    func stopObserving() { changed = nil }
    func isCurrent(_ page: BrowserPage) -> Bool { self.page.isSameDocument(as: page) }
    func state(of field: BrowserFormField, on page: BrowserPage) -> AutofillFieldState? {
        AutofillFieldState(value: values[field.id] ?? "", isWritable: true, isFocused: focusedFieldID == field.id)
    }
    func write(_ text: String, to field: BrowserFormField, on page: BrowserPage) { values[field.id] = writeResult ?? text }
    func focus(_ field: BrowserFormField, on page: BrowserPage) -> Bool {
        focusedFieldID = focusAllowed && focusVerified ? field.id : nil
        return focusAllowed
    }
    func paste(into field: BrowserFormField, on page: BrowserPage, pasteboard: NSPasteboard, changeCount: Int) -> Bool {
        pasteCount += 1
        if pasteDelay == .zero {
            values[field.id] = pasteboard.string(forType: .string) ?? ""
        } else {
            Task {
                try? await Task.sleep(for: pasteDelay)
                values[field.id] = pasteboard.string(forType: .string) ?? ""
            }
        }
        return true
    }
}
