import Foundation
import GRDB
import SQLiteData

@Table("tofugu_audio_index")
private struct TofuguAudioIndexRow: Hashable, Codable, Sendable {
    @Column(primaryKey: true)
    var term: String
    var values_csv: String
}

public enum TofuguAudioIndex {
    private static let dbQueue: DatabaseQueue? = {
        guard let url = Bundle.module.url(forResource: "tofugu-audio-index", withExtension: "sqlite") else {
            return nil
        }

        var configuration = Configuration()
        configuration.readonly = true
        configuration.maximumReaderCount = 1
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA query_only=ON;")
            try db.execute(sql: "PRAGMA mmap_size=67108864;")
            try db.execute(sql: "PRAGMA cache_size=-10000;")
        }

        return try? DatabaseQueue(path: url.path, configuration: configuration)
    }()

    public static func audioURL(term: String, readingKana: String) -> URL? {
        guard let dbQueue else {
            return nil
        }

        let recording: (term: String, reading: String)?
        do {
            recording = try dbQueue.read { db in
                // SQLite compares exact bytes, while callers can supply canonically
                // equivalent kana. Keep each spelling: Swift String equality would
                // collapse the composed and decomposed lookup keys.
                for spelling in [term, term.precomposedStringWithCanonicalMapping,
                                 term.decomposedStringWithCanonicalMapping] {
                    guard let row = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT "term", "values_csv"
                            FROM "tofugu_audio_index"
                            WHERE "term" = ?
                            LIMIT 1
                            """,
                        arguments: [spelling]
                    ) else { continue }
                    let indexedTerm: String = row["term"]
                    let valuesCSV: String = row["values_csv"]
                    if let reading = valuesCSV.split(separator: ",").first(where: {
                        String($0) == readingKana
                    }) {
                        return (term: indexedTerm, reading: String(reading))
                    }
                }
                return nil
            }
        } catch {
            return nil
        }

        guard let recording else {
            return nil
        }

        let filename = "\(recording.term)【\(recording.reading)】.mp3"
        guard let escaped = "https://manabi.io/media/audio/tofugu/\(filename)"
            .addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
              let url = URL(string: escaped) else {
            return nil
        }

        return url
    }
}
