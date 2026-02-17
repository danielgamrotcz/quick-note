import Foundation

final class NoteQueue {
    static let shared = NoteQueue()

    enum SendResult {
        case sent
        case queued
        case configError(String)
    }

    struct PendingNote: Codable {
        let id: UUID
        let text: String
        let createdAt: Date
    }

    private let fileURL: URL
    private var inFlightIds = Set<UUID>()
    private let lock = NSLock()

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Capto", isDirectory: true)

        // One-time migration from QuickNote
        let oldDir = appSupport.appendingPathComponent("QuickNote", isDirectory: true)
        if FileManager.default.fileExists(atPath: oldDir.path)
            && !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.moveItem(at: oldDir, to: dir)
        }

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("pending-notes.json")
    }

    var pendingCount: Int {
        lock.withLock { loadNotes().count }
    }

    @discardableResult
    func enqueue(text: String) -> UUID {
        let note = PendingNote(id: UUID(), text: text, createdAt: Date())
        lock.withLock {
            var notes = loadNotes()
            notes.append(note)
            saveNotes(notes)
        }
        notifyChanged()
        return note.id
    }

    func remove(id: UUID) {
        lock.lock()
        var notes = loadNotes()
        notes.removeAll { $0.id == id }
        saveNotes(notes)
        inFlightIds.remove(id)
        lock.unlock()
        notifyChanged()
    }

    /// Try to send a specific note. Returns the result.
    func trySend(id: UUID) async -> SendResult {
        let note: PendingNote? = lock.withLock {
            let notes = loadNotes()
            guard let n = notes.first(where: { $0.id == id }) else { return nil }
            inFlightIds.insert(id)
            return n
        }

        guard let note else { return .sent }

        do {
            try await NotionService.shared.append(text: note.text)
            remove(id: id)
            return .sent
        } catch let error as NotionError {
            lock.lock()
            inFlightIds.remove(id)
            lock.unlock()
            switch error {
            case .invalidConfig:
                return .configError("Nastav Notion v nastavení – poznámka uložena")
            case .networkError:
                return .queued
            case .apiError(let code, _) where code >= 500 || code == 429:
                return .queued
            case .apiError(_, let message):
                return .configError("Notion: \(message) – poznámka uložena")
            }
        } catch {
            lock.lock()
            inFlightIds.remove(id)
            lock.unlock()
            return .queued
        }
    }

    /// Flush all pending notes sequentially. Safe to call multiple times.
    func flush() {
        Task { await flushAll() }
    }

    private func flushAll() async {
        while true {
            let note: PendingNote? = lock.withLock {
                loadNotes().first { !inFlightIds.contains($0.id) }
            }
            guard let note else { break }

            lock.lock()
            inFlightIds.insert(note.id)
            lock.unlock()

            do {
                try await NotionService.shared.append(text: note.text)
                remove(id: note.id)
            } catch {
                lock.lock()
                inFlightIds.remove(note.id)
                lock.unlock()
                break
            }
        }
    }

    // MARK: - File I/O

    private func loadNotes() -> [PendingNote] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([PendingNote].self, from: data)) ?? []
    }

    private func saveNotes(_ notes: [PendingNote]) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pendingNotesChanged, object: nil)
        }
    }
}
