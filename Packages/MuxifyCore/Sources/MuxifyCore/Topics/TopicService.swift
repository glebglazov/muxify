import Foundation

/// The one way to read or change Topics. The app's sheets, the muxify://topic URL and the command line tool
/// all send a `TopicRequest` here, so every Topic edit runs the same steps: read, plan, git, record, tmux,
/// show. It blocks, so call it off the main thread.
public struct TopicService: Sendable {
    public let paths: MuxifyPaths
    public let server: TmuxServer
    /// The Projects a request may name, with the layouts that git reported.
    public let projects: [Project]
    /// `topics.session_order` in the Config, which places a new Session in a Topic the user ordered.
    public let sessionOrder: SessionOrder
    public let insertPosition: TopicInsertPosition
    private let store: TopicStore
    private let editLockTimeout: TimeInterval

    public init(paths: MuxifyPaths, server: TmuxServer = .local, projects: [Project] = [], sessionOrder: SessionOrder = .oldestFirst, insertPosition: TopicInsertPosition = .bottom) {
        self.init(paths: paths, server: server, projects: projects, sessionOrder: sessionOrder, insertPosition: insertPosition, editLockTimeout: 10)
    }

    init(paths: MuxifyPaths, server: TmuxServer, projects: [Project], sessionOrder: SessionOrder = .oldestFirst, insertPosition: TopicInsertPosition = .bottom, editLockTimeout: TimeInterval) {
        self.paths = paths
        self.server = server
        self.projects = projects
        self.sessionOrder = sessionOrder
        self.insertPosition = insertPosition
        self.editLockTimeout = editLockTimeout
        store = TopicStore(paths: paths)
    }

    /// `client` is the host's tmux client: the one that types keys for a plan and that switches to the result.
    /// It is a fact of the host, not of the request, so it is not on the wire. Nil switches nothing.
    /// A failure is returned, never thrown: its phase says how far the request got.
    public func handle(_ request: TopicRequest, client: String? = nil) -> TopicResponse {
        guard request.version <= TopicRequest.currentVersion else {
            return .failed(TopicFailure(kind: .unsupported, phase: .nothingChanged,
                                        message: "The Topic request has version \(request.version). This Muxify reads version \(TopicRequest.currentVersion) or earlier."))
        }
        if case .list = request.command { return list() }
        if case .show = request.command { return show(request, client: client) }
        // A Snooze writes one key of each record, so it takes only the record lock, as the app's Snooze does.
        if case .snooze(let deadline, let topics) = request.command { return snooze(request, topics, until: deadline, client: client) }
        if case .unsnooze(let topics) = request.command { return snooze(request, topics, until: nil, client: client) }
        do {
            return try FileLock.withLock(paths.editLock, .exclusive, rank: .edit, timeout: editLockTimeout) {
                switch request.command {
                case .lock: return changeLock(request, locked: true, client: client)
                case .unlock: return changeLock(request, locked: false, client: client)
                default: return edit(request, client: client)
                }
            }
        } catch {
            return .failed(failure(error, phase: .nothingChanged))
        }
    }

    /// The Sessions the Settle sheet offers, as the Topic's live Sessions are now. It reads and writes nothing else.
    public func settleChoices(for target: TopicTarget) -> Result<[TopicSettleSession], TopicFailure> {
        do {
            let records = try store.read().records
            let snapshot = server.snapshot()
            let topic = try openTopic(target, caller: nil, records: records, snapshot: snapshot, client: nil)
            let record = topic.remembering(snapshot, projects: projects, order: sessionOrder) ?? topic
            return .success(TopicSettleSession.choices(topic: record, snapshot: snapshot, projects: projects,
                                                       mergedWorktrees: TopicWorktrees.merged(in: record, root: paths.worktrees.path)))
        } catch {
            return .failure(failure(error, phase: .nothingChanged))
        }
    }

    public func forgetChoices(for target: TopicTarget) -> Result<TopicForgetChoices, TopicFailure> {
        do {
            let records = try store.read().records
            let snapshot = server.snapshot()
            let topic = try forgetTopic(target, caller: nil, records: records, snapshot: snapshot, client: nil)
            return .success(TopicForgetChoices(topic: topic, snapshot: snapshot, projects: projects, root: paths.worktrees.path))
        } catch { return .failure(failure(error, phase: .nothingChanged)) }
    }

    private var executor: TopicExecutor { TopicExecutor(server: server, worktreesRoot: paths.worktrees.path) }

    private func list() -> TopicResponse {
        do {
            return .topics(try store.read().records.filter { $0.settledAt == nil }.map(TopicSummary.init(record:)))
        } catch {
            return .failed(failure(error, phase: .nothingChanged))
        }
    }

    private func show(_ request: TopicRequest, client: String?) -> TopicResponse {
        do {
            let records = try store.read().records
            let snapshot = server.snapshot()
            let topic = try openTopic(request.target, caller: request.caller, records: records, snapshot: snapshot, client: client)
            let branches = TopicBranches(records: [topic]) { try? String(contentsOfFile: $0, encoding: .utf8) }
            return .topic(TopicDetail(record: topic, snapshot: snapshot, projects: projects, branches: branches))
        } catch {
            return .failed(failure(error, phase: .nothingChanged))
        }
    }

    /// A nil `deadline` is an Unsnooze. Every Topic resolves before the one write, so a bad ref changes nothing.
    private func snooze(_ request: TopicRequest, _ topics: [TopicRef], until deadline: SnoozeDeadline?, client: String?) -> TopicResponse {
        do {
            if !topics.isEmpty, request.target != nil { throw TopicRequestError.targetAndTopics }
            let records = try store.read().records
            let resolved = topics.isEmpty
                ? [try openTopic(request.target, caller: request.caller, records: records, snapshot: server.snapshot(), client: client)]
                : try topics.map { try $0.resolve(in: records) }
            var ids: [String] = []
            for topic in resolved where !ids.contains(topic.id) { ids.append(topic.id) }
            let shortened = try store.write { transaction -> [String] in
                guard let deadline else {
                    for id in ids {
                        guard transaction.records.contains(where: { $0.id == id && $0.settledAt == nil }) else {
                            throw TopicRequestError.topicUnavailable(id)
                        }
                    }
                    for id in ids { try transaction.update(id) { $0.snoozedUntil = nil } }
                    return []
                }
                let set = SnoozeSet(ids, until: deadline, records: transaction.records)
                // A Topic that was Settled after the read has no save.
                if let settled = ids.first(where: { id in !set.saves.contains { $0.id == id } }) {
                    throw TopicRequestError.topicUnavailable(settled)
                }
                for save in set.saves { try transaction.update(save.id) { $0.snoozedUntil = save.snoozedUntil } }
                return set.shortened
            }
            return .snoozeChanged(TopicSnoozeChange(topicIDs: ids, shortened: shortened))
        } catch {
            return .failed(failure(error, phase: .nothingChanged))
        }
    }

    /// A plan with what the host shows when the plan itself selects nothing.
    private struct Planned {
        var edit: TopicEdit
        var shown: TopicChange.Shown?
        /// The Locked Session whose place a new Topic takes.
        var replacedLockOf: String? = nil
    }

    private func edit(_ request: TopicRequest, client: String?) -> TopicResponse {
        var phase = TopicFailure.Phase.nothingChanged
        do {
            let records = try store.read().records
            let snapshot = server.snapshot()
            let planned = try plan(request, records: records, snapshot: snapshot, client: client)
            let edit = planned.edit
            try TopicWorktrees.check(edit.commands)
            if let new = edit.newWorktree { try TopicWorktrees.add(new.worktree, at: new.commit) }
            let read = edit.record.flatMap { record in records.first { $0.id == record.id } }
            // A new Topic takes its place among the Locks too, and may renumber them.
            var commands = edit.commands
            if let record = edit.record {
                let locks = SessionLock.locks(in: snapshot.windows, records: records)
                let moved = try store.write(locks: locks) { transaction -> [SessionLock] in
                    try transaction.apply(TopicRecordChange(before: read, after: record), insertPosition: insertPosition, replacingLockOf: planned.replacedLockOf)
                }
                commands += moved.map { .tmux($0.setOption) }
                phase = .recordSaved
            } else {
                phase = .changesStarted
            }
            try executor.run(commands, client: client)
            switch edit.completion {
            case .save(let record):
                let before = edit.record ?? records.first { $0.id == record.id }
                let locks = SessionLock.locks(in: server.snapshot().windows, records: try store.read().records)
                let moved = try store.write(locks: locks) {
                    try $0.apply(TopicRecordChange(before: before, after: record), insertPosition: insertPosition)
                }
                try executor.run(moved.map { .tmux($0.setOption) }, client: client)
            case .forget(let id):
                try store.write { try $0.forget(id) }
            case nil: break
            }
            phase = .selectionFailed
            let shown = try executor.show(edit.selection, client: client) ?? planned.shown
            return .changed(TopicChange(topicID: edit.completion?.topicID ?? edit.record?.id,
                                        created: edit.record != nil && read == nil, shown: shown))
        } catch {
            return .failed(failure(error, phase: phase))
        }
    }

    private func plan(_ request: TopicRequest, records: [TopicRecord], snapshot: TmuxSnapshot, client: String?) throws -> Planned {
        func source() throws -> (TopicPaneSource, TmuxSnapshot) {
            guard let pane = paneRequest(request.target, caller: request.caller) else { throw TopicRequestError.noTarget }
            let resolved = try executor.pane(pane, in: snapshot, client: client)
            return (resolved.source, resolved.snapshot)
        }
        switch request.command {
        case .list, .show, .lock, .unlock, .snooze, .unsnooze:
            throw TopicRequestError.noTarget
        case .create(let title, let projectPath):
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let home: Project
            if let projectPath {
                home = try project(at: projectPath)
            } else if paneRequest(request.target, caller: request.caller) != nil {
                let (pane, _) = try source()
                home = TopicLocation(of: pane.window, record: TopicMembershipPlan.sourceRecord(for: pane.window, records: records), projects: projects).project
            } else {
                let slug = TopicNaming.slug(title: title, project: nil, records: records, sessionNames: [])
                let record = TopicRecord(newTopic: UUID().uuidString.lowercased(), title: title, slug: slug, now: Date())
                return Planned(edit: TopicEdit(record: record, commands: [], selection: .emptyTopic(record.id)))
            }
            let plan = TopicPlan(title: title, project: home, records: records,
                                 sessionNames: Set(snapshot.windows.map(\.sessionName)), clientTTY: client)
            return Planned(edit: TopicEdit(record: plan.record, commands: plan.commands, selection: .sessionName(plan.sessionName)))
        case .extract(let projectPath, let title):
            let (pane, fresh) = try source()
            let home = try projectPath.map { try project(at: $0) }
            return Planned(edit: try TopicPanePlan(source: pane, project: home, title: title ?? "", records: records, windows: fresh.windows,
                                                   projects: projects, clientTTY: client).edit)
        case .addProject(let projectPath, let choice):
            let topic = try openTopic(request.target, caller: request.caller, records: records, snapshot: snapshot, client: client)
            let project = try project(at: projectPath)
            return Planned(edit: try TopicProjectPlan(topic: topic, project: project, workingCopy: workingCopy(choice, of: project),
                                                      windows: snapshot.windows, projects: projects, order: sessionOrder).edit)
        case .settle(let choices, let outcome):
            let topic = try openTopic(request.target, caller: request.caller, records: records, snapshot: snapshot, client: client)
            try checkMembership(request.expectedSessionIDs, choices: choices, topic: topic, snapshot: snapshot)
            var snapshot = snapshot
            snapshot.commandLines = PaneCommandLines().updating(for: snapshot) {
                try? CommandRunner().run(CommandInvocation(executable: "/bin/sh", arguments: ["-c", PaneCommandLines.script]))
            }
            return Planned(edit: TopicSettlePlan(topic: topic, snapshot: snapshot, projects: projects, choices: choices, outcome: outcome,
                                                 mergedWorktrees: TopicWorktrees.merged(in: topic, root: paths.worktrees.path),
                                                 order: sessionOrder).edit)
        case .forget(let choices, let worktrees):
            let topic = try forgetTopic(request.target, caller: request.caller, records: records, snapshot: snapshot, client: client)
            try checkMembership(request.expectedSessionIDs, choices: choices, topic: topic, snapshot: snapshot)
            return Planned(edit: TopicForgetPlan(topic: topic, snapshot: snapshot, projects: projects, choices: choices,
                                                  worktrees: worktrees, root: paths.worktrees.path).edit)
        case .move(let destination):
            if case .newWindow(let title) = destination {
                if case .session = request.target { throw TopicRequestError.noTarget }
                if case .window = request.target { throw TopicRequestError.noTarget }
                let (pane, _) = try source()
                let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                var commands: [TopicPlan.Command] = []
                if pane.window.paneCount > 1 {
                    var arguments = ["break-pane", "-d", "-s", pane.paneID, "-t", pane.window.sessionID + ":"]
                    if !title.isEmpty { arguments += ["-n", title] }
                    commands.append(.tmux(arguments))
                } else if !title.isEmpty {
                    commands.append(.tmux(["rename-window", "-t", pane.window.id, title]))
                }
                return Planned(edit: TopicEdit(record: nil, commands: commands, selection: .paneID(pane.paneID)))
            }
            let moved: TopicMembershipPlan.Source
            let selection: TopicEdit.Selection
            let windows: [TmuxWindow]
            if case .session(let id) = request.target {
                guard let window = snapshot.windows.first(where: { $0.sessionID == id.rawValue }) else { throw TopicEditFailure.sourceUnavailable }
                (moved, selection, windows) = (.session(window), .unchanged, snapshot.windows)
            } else {
                let (pane, fresh) = try source()
                let paneTarget: Bool
                if case .window = request.target { paneTarget = false } else { paneTarget = true }
                guard let paneID = PaneID(rawValue: pane.paneID) else { throw TopicEditFailure.invalidTmuxResponse }
                (moved, selection, windows) = (paneTarget ? .pane(paneID, pane.window) : .window(pane.window),
                                                paneTarget ? .paneID(pane.paneID) : .unchanged, fresh.windows)
            }
            let plan: TopicMembershipPlan
            switch destination {
            case .newWindow: throw TopicRequestError.noTarget
            case .topic(let ref):
                plan = try TopicMembershipPlan(source: moved, destination: ref.resolve(in: records, open: true), records: records,
                                               windows: windows, projects: projects, clientTTY: client, order: sessionOrder)
            case .newTopic(let title):
                plan = try TopicMembershipPlan(source: moved, title: title, records: records, windows: windows,
                                               projects: projects, clientTTY: client, order: sessionOrder)
            }
            return Planned(edit: TopicEdit(record: plan.record, commands: plan.commands, selection: selection),
                           shown: WindowID(rawValue: moved.window.id).map { .window($0) }, replacedLockOf: plan.endedLockOf)
        case .removeFromTopic:
            if case .window = request.target {
                let (pane, fresh) = try source()
                let window = pane.window
                guard window.topicID != nil else {
                    return Planned(edit: TopicEdit(record: nil, commands: [], selection: .paneID(pane.paneID)))
                }
                let home = TopicMembershipPlan.project(of: window, records: records, projects: projects)
                let existing = fresh.windows.first {
                    $0.topicID == nil && TopicMembershipPlan.project(of: $0, records: records, projects: projects).folder == home.folder
                }
                let target: String
                var commands: [TopicPlan.Command] = []
                if let existing {
                    target = existing.sessionID + ":"
                } else {
                    guard !home.folder.path.isEmpty, !home.name.isEmpty, !home.name.contains("."),
                          !home.name.contains(":"), !home.name.contains("\n") else { throw TopicEditFailure.invalidProject }
                    let names = Set(fresh.windows.map(\.sessionName))
                    var name = home.name
                    var number = 2
                    while names.contains(name) { name = "\(home.name)-\(number)"; number += 1 }
                    target = "=" + name + ":"
                    commands.append(.newTopicSession(name: name, directory: home.folder.path))
                }
                if let client { commands.append(.tmux(["switch-client", "-c", client, "-t", target])) }
                commands.append(.tmux(["move-window", "-d", "-s", window.sessionID + ":" + window.id, "-t", target]))
                if existing == nil { commands.append(.removeTopicPlaceholder) }
                return Planned(edit: TopicEdit(record: nil, commands: commands, selection: .paneID(pane.paneID)))
            }
            let sessionID: String
            if case .session(let id) = request.target { sessionID = id.rawValue }
            else { sessionID = try source().0.window.sessionID }
            let plan = TopicMembershipPlan(removingSession: sessionID)
            return Planned(edit: TopicEdit(record: plan.record, commands: plan.commands, selection: .unchanged))
        case .rename(let title):
            let topic = try openTopic(request.target, caller: request.caller, records: records, snapshot: snapshot, client: client)
            return Planned(edit: try TopicRenamePlan(topic: topic, title: title, records: records,
                                                     windows: snapshot.windows, projects: projects).edit)
        case .moveSession(let placement):
            guard case .session(let id) = request.target else { throw TopicRequestError.noTarget }
            guard let topic = snapshot.windows.first(where: { $0.sessionID == id.rawValue })
                .flatMap({ window in records.first { $0.id == window.topicID && $0.settledAt == nil } }) else {
                throw TopicEditFailure.sessionUnavailable
            }
            return Planned(edit: try TopicSessionOrderPlan(moving: id.rawValue, to: placement, topic: topic, windows: snapshot.windows,
                                                           projects: projects, order: sessionOrder).edit)
        case .sortSessions:
            let topic = try openTopic(request.target, caller: request.caller, records: records, snapshot: snapshot, client: client)
            return Planned(edit: TopicSessionOrderPlan(sortingByCreation: topic).edit)
        case .reopen, .startFresh:
            guard case .topic(let ref) = request.target else { throw TopicRequestError.noTarget }
            let topic = try ref.resolve(in: records, open: false)
            return Planned(edit: try TopicReopenPlan(topic: topic, records: records, windows: snapshot.windows, projects: projects,
                                                     existingDirectories: TopicReopening.existingWorktrees(of: topic),
                                                     choice: request.command == .startFresh ? .startFresh : .reopen).edit)
        }
    }

    /// Lock and Unlock change only the Session option and, when a Lock renumbers the list, the Topic records.
    private func changeLock(_ request: TopicRequest, locked: Bool, client: String?) -> TopicResponse {
        var phase = TopicFailure.Phase.nothingChanged
        do {
            let records = try store.read().records
            let snapshot = server.snapshot()
            let window = try noTopicSession(request.target, caller: request.caller, records: records, snapshot: snapshot, client: client)
            let commands: [TopicPlan.Command]
            if locked {
                let locks = SessionLock.locks(in: snapshot.windows, records: records)
                let changed = try store.write(locks: locks) { $0.lock(window.sessionID) }
                commands = changed.map { .tmux($0.setOption) }
            } else {
                commands = window.lockOrder == nil ? [] : [.tmux(SessionLock.unsetOption(window.sessionID))]
            }
            phase = .changesStarted
            try executor.run(commands, client: client)
            return .changed(TopicChange(topicID: nil))
        } catch {
            return .failed(failure(error, phase: phase))
        }
    }

    /// The No Topic Session that the target names, or the Session of the caller's Pane.
    private func noTopicSession(_ target: TopicTarget?, caller: TopicCaller?, records: [TopicRecord], snapshot: TmuxSnapshot,
                                client: String?) throws -> TmuxWindow {
        let found: TmuxWindow?
        switch target {
        case .session(let id)?: found = snapshot.windows.first { $0.sessionID == id.rawValue }
        case .sessionName(let name)?:
            guard let named = snapshot.windows.first(where: { $0.sessionName == name }) else {
                throw TopicRequestError.sessionUnavailable(name)
            }
            found = named
        case .topic?: throw TopicRequestError.noTarget
        default:
            guard let pane = paneRequest(target, caller: caller) else { throw TopicRequestError.noTarget }
            let sessionID = try executor.pane(pane, in: snapshot, client: client).source.window.sessionID
            found = snapshot.windows.first { $0.sessionID == sessionID }
        }
        guard let window = found else { throw TopicEditFailure.sourceUnavailable }
        if let topic = records.first(where: { $0.id == window.topicID && $0.settledAt == nil }) {
            throw TopicRequestError.sessionInTopic(session: window.sessionName, topic: TopicSummary(record: topic).label)
        }
        return window
    }

    private func forgetTopic(_ target: TopicTarget?, caller: TopicCaller?, records: [TopicRecord],
                             snapshot: TmuxSnapshot, client: String?) throws -> TopicRecord {
        if case .topic(let ref)? = target { return try ref.resolve(in: records, open: false) }
        return try openTopic(target, caller: caller, records: records, snapshot: snapshot, client: client)
    }

    /// The Pane a request acts on: its target, else its caller. One rule for every command.
    private func paneRequest(_ target: TopicTarget?, caller: TopicCaller?) -> TopicPaneRequest? {
        switch target {
        case .pane(let id)?: return .pane(id.rawValue)
        case .window(let id)?: return .window(id.rawValue)
        case .topic?, .session?, .sessionName?: return nil
        case nil: break
        }
        switch caller {
        case .pane(let id)?: return .pane(id.rawValue)
        case .currentClient?: return .currentClient
        case nil: return nil
        }
    }

    /// The open Topic of the target, or of the Pane that the target or the caller names.
    private func openTopic(_ target: TopicTarget?, caller: TopicCaller?, records: [TopicRecord], snapshot: TmuxSnapshot,
                           client: String?) throws -> TopicRecord {
        if case .topic(let ref)? = target { return try ref.resolve(in: records, open: true) }
        guard let pane = paneRequest(target, caller: caller) else { throw TopicRequestError.noTarget }
        let window = try executor.pane(pane, in: snapshot, client: client).source.window
        guard let topic = records.first(where: { $0.id == window.topicID && $0.settledAt == nil }) else {
            throw TopicRequestError.sourceHasNoTopic
        }
        return topic
    }

    /// `path` is a request's, given on this Mac, so it may reach the Config's folder through a symlink.
    private func project(at path: String) throws -> Project {
        let folder = Folder.local(path)
        guard let match = projects.first(where: { $0.folder == folder }) else {
            throw TopicRequestError.projectUnavailable(path)
        }
        return match
    }

    private func workingCopy(_ choice: TopicWorkingCopyChoice, of project: Project) throws -> TopicWorkingCopy {
        func worktree(at path: String) throws -> Worktree {
            let folder = Folder.local(path)
            guard let match = project.layout.worktrees.first(where: { $0.folder == folder }) else {
                throw TopicRequestError.projectUnavailable(path)
            }
            return match
        }
        switch choice {
        case .project: return .homeProject
        case .worktree(let path): return .worktree(try worktree(at: path))
        case .newWorktree(let path, let base):
            return .newWorktree(at: try TopicWorktrees.commit(base, in: try worktree(at: path)), root: paths.worktrees.path)
        }
    }

    private func checkMembership(_ expected: [String]?, choices: [TopicSettleSession], topic: TopicRecord, snapshot: TmuxSnapshot) throws {
        if let expected {
            let current = Set(snapshot.windows.filter { $0.topicID == topic.id }.map(\.sessionID))
            guard current == Set(expected) else { throw TopicRequestError.topicMembershipChanged }
        }
        for choice in choices {
            if let reviewed = choice.reviewedWindows,
               reviewed.mapValues({ $0.sorted() }) != TopicSettleSession.windows(in: choice.id, snapshot: snapshot) {
                throw TopicRequestError.topicMembershipChanged
            }
        }
    }

    private func failure(_ error: Error, phase: TopicFailure.Phase) -> TopicFailure {
        TopicFailure(kind: Self.kind(of: error), phase: phase, message: message(error))
    }

    /// Our failure types say what went wrong in Topic words. A Foundation error only says what the system
    /// refused, and its own description is `Error Domain=… Code=…`, so it gets the state folder and a plain reason.
    private func message(_ error: Error) -> String {
        // POSIXError and CocoaError have no description of their own; an NSError has one, but it is the raw form.
        if !(type(of: error) is NSObject.Type), let ours = (error as Any) as? CustomStringConvertible { return ours.description }
        let foundation = error as NSError
        var reason = foundation.domain == NSPOSIXErrorDomain ? String(cString: strerror(Int32(foundation.code)))
                                                            : foundation.localizedDescription
        if !reason.hasSuffix(".") { reason += "." }
        return "Muxify could not read or write the Topic records in \(paths.state.path). \(reason)"
    }

    private static func kind(of error: Error) -> TopicFailure.Kind {
        switch error {
        case let error as TopicRequestError:
            switch error {
            case .invalidURL, .targetAndTopics: return .unsupported
            case .noTarget: return .noTarget
            case .projectUnavailable: return .projectUnavailable
            case .sourceHasNoTopic: return .sourceHasNoTopic
            case .topicUnavailable: return .topicUnavailable
            case .topicAmbiguous: return .topicAmbiguous
            case .topicMembershipChanged: return .topicMembershipChanged
            case .sessionUnavailable: return .sourceUnavailable
            case .sessionInTopic: return .sessionInTopic
            case .baseUnavailable, .worktreeBaseMissing, .worktreeHasChanges: return .gitFailed
            }
        case let error as TopicEditFailure:
            switch error {
            case .destinationUnavailable: return .topicUnavailable
            case .sourceUnavailable, .sessionUnavailable: return .sourceUnavailable
            case .duplicateProject: return .duplicateProject
            case .invalidProject: return .projectUnavailable
            case .sessionNameInUse: return .sessionNameInUse
            case .invalidTmuxResponse: return .tmuxFailed
            }
        case let error as TopicMembershipPlan.Failure:
            switch error {
            case .occupiedProject: return .duplicateProject
            case .sessionNameInUse: return .sessionNameInUse
            case .invalidProject: return .projectUnavailable
            case .sourceUnavailable: return .sourceUnavailable
            case .destinationUnavailable: return .topicUnavailable
            }
        case is TopicTransaction.Failure: return .topicUnavailable
        case is FileLock.Busy: return .storeBusy
        case is TmuxError: return .tmuxFailed
        case is ShellError: return .gitFailed
        default: return .storeFailed
        }
    }
}

extension TopicRef {
    /// The record this names. `.named` takes an open Topic's id first, then the one open Topic with that slug or title.
    /// `open` false also finds a Settled Topic.
    public func resolve(in records: [TopicRecord], open: Bool = true) throws -> TopicRecord {
        let candidates = open ? records.filter { $0.settledAt == nil } : records
        switch self {
        case .id(let id):
            guard let topic = candidates.first(where: { $0.id == id }) else { throw TopicRequestError.topicUnavailable(id) }
            return topic
        case .named(let value):
            if let exact = candidates.first(where: { $0.id == value }) { return exact }
            let matches = candidates.filter { $0.slug == value || $0.title == value }
            guard let only = matches.first else { throw TopicRequestError.topicUnavailable(value) }
            guard matches.count == 1 else { throw TopicRequestError.topicAmbiguous(value) }
            return only
        }
    }
}

public enum TopicRequestError: Error, CustomStringConvertible {
    case invalidURL
    case noTarget
    case projectUnavailable(String)
    case sourceHasNoTopic
    case topicUnavailable(String)
    case topicAmbiguous(String)
    case topicMembershipChanged
    case baseUnavailable(ref: String, worktree: String)
    case worktreeBaseMissing(base: String, worktree: String)
    case worktreeHasChanges(String)
    case sessionUnavailable(String)
    case sessionInTopic(session: String, topic: String)
    case targetAndTopics

    public var description: String {
        switch self {
        case .invalidURL: return "The Topic URL is invalid."
        case .noTarget: return "The request names no Topic, Window or Pane, and it does not come from a Pane."
        case .projectUnavailable(let path): return "The Config has no Project at \(path)."
        case .sourceHasNoTopic: return "The Pane is not in an open Topic."
        case .topicUnavailable(let value): return "No open Topic matches \(value)."
        case .topicMembershipChanged: return "The Topic Sessions, Windows or Panes changed. Review them and confirm again."
        case .topicAmbiguous(let value): return "More than one open Topic matches \(value). Use an id."
        case .baseUnavailable(let ref, let worktree): return "No commit matches \(ref) in \(worktree)."
        case .worktreeBaseMissing(let base, let worktree):
            return "The Worktree \(worktree) and its branch are gone, and the repository does not have their base commit \(base). Muxify did not make the Worktree again."
        case .worktreeHasChanges(let worktree):
            return "The Worktree \(worktree) has uncommitted changes. Commit or remove them, or keep the Worktree."
        case .sessionUnavailable(let name): return "No tmux Session has the name \(name)."
        case .sessionInTopic(let session, let topic):
            return "The Session \(session) is in the Topic \(topic). Only a No Topic Session can be Locked."
        case .targetAndTopics: return "The request names a target and a list of Topics. Name only one of them."
        }
    }
}
