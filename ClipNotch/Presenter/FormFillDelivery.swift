import AppKit

struct AutofillClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init?(pasteboard: NSPasteboard) {
        let changeCount = pasteboard.changeCount
        var saved: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                representations[type] = data
            }
            saved.append(representations)
        }
        guard changeCount == pasteboard.changeCount else { return nil }
        items = saved
    }

    @discardableResult
    func restore(to pasteboard: NSPasteboard, ifOwnedChangeCount changeCount: Int) -> Bool {
        guard pasteboard.changeCount == changeCount else { return false }
        let restored = items.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        pasteboard.clearContents()
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
        return true
    }
}

@MainActor
final class FormFillDelivery {
    enum Outcome: Equatable { case filled, skipped, stopped }

    private let accessibility: any AutofillFieldAccess
    private let pasteboard: NSPasteboard
    private let onPasteboardChange: () -> Void

    init(accessibility: any AutofillFieldAccess, pasteboard: NSPasteboard = .general, onPasteboardChange: @escaping () -> Void) {
        self.accessibility = accessibility
        self.pasteboard = pasteboard
        self.onPasteboardChange = onPasteboardChange
    }

    func fill(_ field: BrowserFormField, on page: BrowserPage, text: String, isCurrent: () -> Bool) async -> Outcome {
        guard !Task.isCancelled, isCurrent(), await accessibility.isCurrent(page) else { return .stopped }
        guard let initial = await accessibility.state(of: field, on: page), initial.value.isEmpty else { return .skipped }
        guard !Task.isCancelled, isCurrent() else { return .stopped }
        guard await accessibility.focus(field, on: page) else { return .skipped }
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return .stopped }
        guard isCurrent(), await accessibility.isCurrent(page) else { return .stopped }
        guard let focused = await accessibility.state(of: field, on: page), focused.value.isEmpty, focused.isFocused else { return .skipped }
        if initial.isWritable {
            await accessibility.write(text, to: field, on: page)
            for _ in 0..<3 {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return .stopped }
                guard isCurrent(), await accessibility.isCurrent(page) else { return .stopped }
                guard let state = await accessibility.state(of: field, on: page) else { return .skipped }
                if state.value == text { return .filled }
                if !state.value.isEmpty { return .skipped }
            }
        }

        guard !Task.isCancelled, isCurrent(), await accessibility.isCurrent(page) else { return .stopped }
        guard isCurrent(), let state = await accessibility.state(of: field, on: page),
              state.value.isEmpty, state.isFocused, let snapshot = AutofillClipboardSnapshot(pasteboard: pasteboard) else { return .skipped }
        guard !Task.isCancelled, isCurrent() else { return .stopped }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ownedChangeCount = pasteboard.changeCount
        onPasteboardChange()
        defer {
            if snapshot.restore(to: pasteboard, ifOwnedChangeCount: ownedChangeCount) { onPasteboardChange() }
        }
        guard isCurrent(), await accessibility.paste(into: field, on: page, pasteboard: pasteboard, changeCount: ownedChangeCount) else { return .stopped }
        // An issued paste must consume the clipboard before cancellation can restore it.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { continuation.resume() }
        }
        for _ in 0..<25 {
            do { try await Task.sleep(for: .milliseconds(60)) } catch { return .stopped }
            guard isCurrent(), await accessibility.isCurrent(page) else { return .stopped }
            guard let current = await accessibility.state(of: field, on: page) else { return .stopped }
            if current.value == text { return .filled }
            if !current.value.isEmpty { return .stopped }
        }
        return .stopped
    }
}
