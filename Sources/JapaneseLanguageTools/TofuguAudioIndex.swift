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

        let valuesCSV: String?
        do {
            valuesCSV = try dbQueue.read { db in
                try String.fetchOne(
                    db,
                    sql: """
                        SELECT "values_csv"
                        FROM "tofugu_audio_index"
                        WHERE "term" = ?
                        LIMIT 1
                        """,
                    arguments: [term]
                )
            }
        } catch {
            return nil
        }

        guard let valuesCSV else {
            return nil
        }

        let values = valuesCSV.split(separator: ",").map(String.init)
        guard values.contains(readingKana) else {
            return nil
        }

        let filename = "\(term)【\(readingKana)】.mp3"
        guard let escaped = "https://manabi.io/media/audio/tofugu/\(filename)"
            .addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
              let url = URL(string: escaped) else {
            return nil
        }

        return url
    }
}
