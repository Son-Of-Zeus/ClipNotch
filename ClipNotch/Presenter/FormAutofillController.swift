import AppKit
import Observation
import SwiftUI

@Observable
@MainActor
final class FormAutofillSession {
    enum Stage: Equatable { case prompt, profiles, valueChoice, filling, result }

    let id = UUID()
    let page: BrowserPage
    private(set) var fields: [BrowserFormField]
    private(set) var categories: [AutofillCategory]
    var stage: Stage = .prompt
    var isPreparing = false
    var profiles: [DataPaletteProfile] = []
    var preferredProfileID: UUID?
    var suggestedProfileName: String?
    var selectedValues: [String: DataPaletteValue] = [:]
    var choiceCategoryID: String?
    var choices: [DataPaletteValue] = []
    var filledCount = 0
    var skippedLabels: [String] = []
    var wasStopped = false
    var isClosing = false

    init(page: BrowserPage, fields: [BrowserFormField], categories: [AutofillCategory]) {
        self.page = page
        self.fields = fields
        self.categories = categories.filter { category in fields.contains { $0.categoryID == category.id } }
    }

    func refresh(fields: [BrowserFormField], categories: [AutofillCategory], profiles: [DataPaletteProfile]) {
        guard stage == .prompt, !isPreparing else { return }
        self.fields = fields
        self.categories = categories.filter { category in fields.contains { $0.categoryID == category.id } }
        let eligible = AutofillProfileResolver.eligibleProfiles(for: Set(self.categories.map(\.id)), profiles: profiles)
        suggestedProfileName = eligible.count == 1 ? eligible.first?.name : nil
    }

    func coverage(for profile: DataPaletteProfile) -> String {
        categories.filter { category in
            profile.fields.contains { DataPaletteType.identifier(for: $0.label) == category.id && !$0.value.isEmpty }
        }.map(\.label).joined(separator: ", ")
    }
}

@MainActor
final class FormAutofillController {
    var onPermissionChange: (() -> Void)?
    private let appState: AppState
    private let panel: PanelManager
    private let monitor = BrowserFormMonitor()
    private let delivery: FormFillDelivery
    private var session: FormAutofillSession?
    private var visitPolicy = AutofillVisitPolicy()
    private var fillTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var lastDocument: DataPaletteDocument?
    private var metrics: NotchMetrics?
    private var promptHeight: CGFloat = 220

    init(appState: AppState, panel: PanelManager, pasteboardMonitor: PasteboardMonitor) {
        self.appState = appState
        self.panel = panel
        delivery = FormFillDelivery(accessibility: monitor.accessibility, onPasteboardChange: {
            pasteboardMonitor.skipCurrentChange()
        })
        monitor.isEnabled = { [weak self] in
            guard let self else { return false }
            let enabled = self.appState.hasCompletedOnboarding && self.appState.dataPalette.isLoaded
                && self.appState.autofillSettings.isEnabled
            let document = DataPaletteDocument(profiles: self.appState.dataPalette.profiles, synonyms: self.appState.dataPalette.synonyms)
            if let previous = self.lastDocument, previous != document { self.cancel() }
            self.lastDocument = document
            return enabled
        }
        monitor.categories = { [weak self] in self?.categories ?? [] }
        monitor.onInvalidation = { [weak self] in self?.cancel() }
        monitor.onPermissionChange = { [weak self] in self?.onPermissionChange?() }
        monitor.onScan = { [weak self] visit, page, fields in
            self?.received(visit: visit, page: page, fields: fields)
        }
    }

    private var categories: [AutofillCategory] {
        appState.dataPalette.dataTypes.filter { type in
            !AutofillProfileResolver.candidates(for: type.id, preferredProfileID: nil, profiles: appState.dataPalette.profiles).isEmpty
        }.map {
            AutofillCategory(id: $0.id, label: $0.label, synonyms: appState.dataPalette.synonyms[$0.id] ?? [])
        }
    }

    func start() { monitor.start() }
    func refresh() { monitor.refresh() }

    func stop() {
        monitor.stop()
        cancel()
    }

    func drawerWillOpen() { cancel() }

    func dismissWithEscape() -> Bool {
        guard session != nil else { return false }
        dismiss(excludeSite: false)
        return true
    }

    func handlePointer(_ point: NSPoint, isClick: Bool, isAppKitPoint: Bool = false) {
        guard session != nil, let metrics else { return }
        let point = isAppKitPoint ? point : ScreenUtilities.appKitPoint(fromQuartzPoint: point)
        let width = session?.stage == .result ? min(220, metrics.bodyWidth) : metrics.bodyWidth
        let local = CGPoint(x: point.x - (metrics.screen.frame.midX - width / 2),
                            y: metrics.screen.frame.maxY - point.y)
        let inside = NotchShape().path(in: CGRect(x: 0, y: 0, width: width, height: promptHeight)).contains(local)
        panel.setMouseInteraction(enabled: inside)
    }

    private func cancel() {
        preparationTask?.cancel()
        preparationTask = nil
        fillTask?.cancel()
        fillTask = nil
        resultTask?.cancel()
        resultTask = nil
        if let session {
            session.isClosing = true
            panel.setMouseInteraction(enabled: false)
            panel.close(after: 0.18)
        }
        session = nil
    }

    private func received(visit: UUID, page: BrowserPage, fields: [BrowserFormField]) {
        visitPolicy.enter(visit)
        guard !appState.isDrawerOpen, !appState.isRecordingShortcut,
              visitPolicy.permits(host: page.host, excludedHosts: appState.autofillSettings.excludedHosts) else { return }
        if let session {
            guard session.page.isSameDocument(as: page), session.stage == .prompt, !session.isPreparing else { return }
            if fields.isEmpty {
                cancel()
            } else {
                session.refresh(fields: fields, categories: categories, profiles: appState.dataPalette.profiles)
            }
            return
        }
        guard !fields.isEmpty else { return }
        let session = FormAutofillSession(page: page, fields: fields, categories: categories)
        session.refresh(fields: fields, categories: categories, profiles: appState.dataPalette.profiles)
        self.session = session
        let metrics = ScreenUtilities.notchMetrics(bodyHeight: 480)
        self.metrics = metrics
        panel.open(frame: metrics.windowFrame, content: AutofillPromptView(
            session: session, metrics: metrics,
            onAccept: { [weak self] in self?.accept() },
            onNotNow: { [weak self] in self?.dismiss(excludeSite: false) },
            onNever: { [weak self] in self?.dismiss(excludeSite: true) },
            onProfile: { [weak self] profile in self?.choose(profile: profile) },
            onValue: { [weak self] value in self?.choose(value: value) },
            onHeightChange: { [weak self] height in
                self?.promptHeight = height
                self?.handlePointer(NSEvent.mouseLocation, isClick: false, isAppKitPoint: true)
            }
        ))
        handlePointer(NSEvent.mouseLocation, isClick: false, isAppKitPoint: true)
    }

    private func dismiss(excludeSite: Bool) {
        if excludeSite, let session { appState.autofillSettings.exclude(session.page.host) }
        visitPolicy.dismiss()
        cancel()
    }

    private func accept() {
        guard let session, session.stage == .prompt, !session.isPreparing else { return }
        let approvedCategories = Set(session.categories.map(\.id))
        session.isPreparing = true
        preparationTask = Task { [weak self, weak session] in
            guard let self, let session else { return }
            let fields = await monitor.accessibility.scan(session.page, categories: categories)
            let current = await monitor.accessibility.isCurrent(session.page)
            guard !Task.isCancelled, self.session === session else { return }
            guard current else { cancel(); monitor.refresh(); return }
            session.isPreparing = false
            guard !fields.isEmpty else { cancel(); return }
            session.refresh(fields: fields, categories: categories, profiles: appState.dataPalette.profiles)
            // New categories must be shown in the prompt before they receive consent.
            guard Set(session.categories.map(\.id)).isSubset(of: approvedCategories) else { return }
            session.profiles = appState.dataPalette.profiles
            let eligible = AutofillProfileResolver.eligibleProfiles(for: Set(session.categories.map(\.id)), profiles: session.profiles)
            if eligible.count == 1 {
                choose(profile: eligible[0])
            } else if !eligible.isEmpty {
                session.stage = .profiles
            } else {
                cancel()
            }
        }
    }

    private func choose(profile: DataPaletteProfile) {
        guard let session, session.stage == .prompt || session.stage == .profiles else { return }
        session.preferredProfileID = profile.id
        resolveValues()
    }

    private func choose(value: DataPaletteValue) {
        guard let session, session.stage == .valueChoice, let categoryID = session.choiceCategoryID,
              session.choices.contains(where: { $0.id == value.id }),
              DataPaletteType.identifier(for: value.field.label) == categoryID else { return }
        session.selectedValues[categoryID] = value
        resolveValues()
    }

    private func resolveValues() {
        guard let session else { return }
        for category in session.categories where session.selectedValues[category.id] == nil {
            let choices = AutofillProfileResolver.candidates(for: category.id, preferredProfileID: session.preferredProfileID, profiles: session.profiles)
            if choices.count == 1 {
                session.selectedValues[category.id] = choices[0]
            } else if choices.count > 1 {
                session.choiceCategoryID = category.id
                session.choices = choices
                session.stage = .valueChoice
                return
            }
        }
        beginFilling(session)
    }

    private func beginFilling(_ session: FormAutofillSession) {
        session.stage = .filling
        visitPolicy.dismiss()
        fillTask = Task { [weak self, weak session] in
            guard let self, let session else { return }
            for field in session.fields {
                guard isCurrent(session) else { return }
                let label = session.categories.first { $0.id == field.categoryID }?.label ?? field.categoryID
                guard let value = session.selectedValues[field.categoryID],
                      DataPaletteType.identifier(for: value.field.label) == field.categoryID else {
                    session.skippedLabels.append(label)
                    continue
                }
                let outcome = await delivery.fill(field, on: session.page, text: value.field.value, isCurrent: { [weak self] in
                    self?.isCurrent(session) == true
                })
                guard self.session === session else { return }
                switch outcome {
                case .filled: session.filledCount += 1
                case .skipped: session.skippedLabels.append(label)
                case .stopped:
                    session.wasStopped = true
                    session.skippedLabels.append(contentsOf: session.fields.dropFirst(session.filledCount + session.skippedLabels.count).map { remaining in
                        session.categories.first { $0.id == remaining.categoryID }?.label ?? remaining.categoryID
                    })
                }
                if outcome == .stopped { break }
            }
            guard self.session === session else { return }
            session.stage = .result
            resultTask = Task { [weak self, weak session] in
                do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
                guard let self, let session, self.session === session else { return }
                self.cancel()
            }
        }
    }

    private func isCurrent(_ session: FormAutofillSession) -> Bool {
        !Task.isCancelled && self.session === session && !appState.isDrawerOpen
            && appState.autofillSettings.isEnabled && AXIsProcessTrusted()
            && !appState.autofillSettings.excludedHosts.contains(session.page.host)
            && session.profiles == appState.dataPalette.profiles
    }
}
