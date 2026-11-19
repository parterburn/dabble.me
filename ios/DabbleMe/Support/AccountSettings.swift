import Foundation

/// Settings that belong to the account rather than the phone, kept on dabble.me as well
/// (GET/PATCH /api/v1/app_settings), so signing out, reinstalling or a new phone doesn't lose
/// them: the entry template, whether new entries start with it, and what the Home Screen widget
/// shows next to today's date (Settings → Home Screen Widget; a widget's own Edit Widget choice
/// is the phone's alone).
///
/// The phone keeps its own copy, which is what the composer and the widget read (offline too).
/// This keeps the two in step:
/// - a change made here is marked pending and sent up; it stays pending until the server has it,
///   so a send that fails is tried again on the next refresh instead of being overwritten by the
///   server's older copy;
/// - on each refresh, what the server has replaces the phone's copy (another phone may have
///   changed it), except where a change made here is still pending;
/// - what the server has never had, the phone's own is sent up (a template written before this
///   build).
/// The phone's copy is for one account: a different account signing in starts from that
/// account's settings, never from what the last one left here.
@MainActor
enum AccountSettings {
    enum Field: String, CaseIterable {
        case entryTemplate, entryTemplateAuto, widgetContent
    }

    static let pendingKey = "accountSettings.pending"
    /// The account the phone's copy belongs to.
    static let accountKey = "accountSettings.account"

    private static var isSyncing = false
    private static var needsSync = false

    /// A setting was changed on this phone: keep it on the account too.
    static func changed(_ field: Field, model: AppModel) {
        markPending(field)
        sync(with: model)
    }

    /// Changed here, to be sent with the next sync (the template, while it's being typed).
    static func markPending(_ field: Field) {
        pending.insert(field)
    }

    /// Brings the phone's copy and the account's into step (each refresh, and after a change).
    /// One sync at a time; a request for another while one runs makes it go round again.
    static func sync(with model: AppModel) {
        guard !isSyncing else {
            needsSync = true
            return
        }
        isSyncing = true
        Task {
            defer { isSyncing = false }
            repeat {
                needsSync = false
                await syncOnce(model)
            } while needsSync
        }
    }

    /// Signing out: the next account starts from its own settings.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
        UserDefaults.standard.removeObject(forKey: accountKey)
    }

    // MARK: - Sync

    private static func syncOnce(_ model: AppModel) async {
        guard model.isSignedIn, let account = model.me?.id else { return }
        let server: AppSettings
        do {
            server = try await model.api.get("api/v1/app_settings")
        } catch {
            return // Tried again on the next refresh.
        }
        guard model.isSignedIn, model.me?.id == account else { return }

        // What another account left on the phone isn't this one's.
        let defaults = UserDefaults.standard
        if let owner = defaults.object(forKey: accountKey) as? Int, owner != account {
            EntryTemplate.clear()
            WidgetSnapshot.defaults?.removeObject(forKey: WidgetSnapshot.contentKey)
            WidgetSnapshot.defaults?.removeObject(forKey: WidgetSnapshot.showMemoriesKey)
            defaults.removeObject(forKey: pendingKey)
        }
        defaults.set(account, forKey: accountKey)

        let pending = self.pending
        var update = AppSettingsUpdate()

        // The template.
        let localTemplate = EntryTemplate.storedRuns
        if pending.contains(.entryTemplate) || (server.entryTemplate == nil && !localTemplate.isEmpty) {
            update.entryTemplate = localTemplate
        } else if let runs = server.entryTemplate, runs != localTemplate {
            EntryTemplate.runs = runs
        }

        // Whether new entries start with it.
        let localAuto = defaults.object(forKey: EntryTemplate.autoKey) as? Bool
        if pending.contains(.entryTemplateAuto) || (server.entryTemplateAuto == nil && localAuto != nil) {
            update.entryTemplateAuto = localAuto ?? false
        } else if let auto = server.entryTemplateAuto, auto != localAuto {
            defaults.set(auto, forKey: EntryTemplate.autoKey)
        }

        // What the widget shows.
        let localContent = WidgetSnapshot.hasChosenContent ? WidgetSnapshot.content : nil
        if pending.contains(.widgetContent) || (server.widgetContent == nil && localContent != nil) {
            update.widgetContent = WidgetSnapshot.content.rawValue
        } else if let raw = server.widgetContent, let content = WidgetContent(rawValue: raw), content != localContent {
            WidgetSync.setContent(content, model: model)
        }

        guard !update.isEmpty else { return }
        do {
            let _: AppSettings = try await model.api.patch("api/v1/app_settings", update)
        } catch {
            return // Still pending: sent again on the next refresh.
        }
        // Saved: no longer pending, unless it was changed again while it was on its way.
        var stillPending = self.pending
        if let sent = update.entryTemplate, sent == EntryTemplate.storedRuns { stillPending.remove(.entryTemplate) }
        if let sent = update.entryTemplateAuto, sent == (defaults.object(forKey: EntryTemplate.autoKey) as? Bool ?? false) {
            stillPending.remove(.entryTemplateAuto)
        }
        if let sent = update.widgetContent, sent == WidgetSnapshot.content.rawValue { stillPending.remove(.widgetContent) }
        self.pending = stillPending
    }

    private static var pending: Set<Field> {
        get { Set((UserDefaults.standard.stringArray(forKey: pendingKey) ?? []).compactMap(Field.init(rawValue:))) }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: pendingKey)
            } else {
                UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: pendingKey)
            }
        }
    }
}

/// GET/PATCH /api/v1/app_settings. Each is nil when the account has never had it set.
struct AppSettings: Decodable, Sendable {
    var entryTemplate: [DocumentRun]?
    var entryTemplateAuto: Bool?
    var widgetContent: String?
}

/// Only what's set is sent (an empty template is `[]`, not left out). A nil optional is left
/// out of the JSON: the synthesized encoder would send it as null, and the server would treat
/// that as a value.
struct AppSettingsUpdate: Encodable, Sendable {
    var entryTemplate: [DocumentRun]? = nil
    var entryTemplateAuto: Bool? = nil
    var widgetContent: String? = nil

    var isEmpty: Bool { entryTemplate == nil && entryTemplateAuto == nil && widgetContent == nil }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(entryTemplate, forKey: .entryTemplate)
        try container.encodeIfPresent(entryTemplateAuto, forKey: .entryTemplateAuto)
        try container.encodeIfPresent(widgetContent, forKey: .widgetContent)
    }

    private enum CodingKeys: String, CodingKey {
        case entryTemplate, entryTemplateAuto, widgetContent
    }
}
