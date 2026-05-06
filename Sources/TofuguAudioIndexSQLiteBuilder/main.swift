import Foundation
import SQLite3

let SQLITE_TRANSIENT_SWIFT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

func populateSQLiteFromCSV(csvPath: String, sqlitePath: String) {
    guard let input = FileHandle(forReadingAtPath: csvPath) else {
        fputs("Could not open CSV at \(csvPath)\n", stderr)
        return
    }
    defer { input.closeFile() }

    let data = input.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else {
        fputs("Failed to decode CSV as UTF-8\n", stderr)
        return
    }

    var db: OpaquePointer?
    if sqlite3_open(sqlitePath, &db) != SQLITE_OK {
        fputs("Failed to create sqlite db\n", stderr)
        return
    }
    defer { sqlite3_close(db) }

    sqlite3_exec(db, "PRAGMA journal_mode=OFF;", nil, nil, nil)
    sqlite3_exec(db, "PRAGMA synchronous=OFF;", nil, nil, nil)
    sqlite3_exec(db, "DROP TABLE IF EXISTS tofugu_audio_index;", nil, nil, nil)
    sqlite3_exec(db, "CREATE TABLE tofugu_audio_index (term TEXT PRIMARY KEY, values_csv TEXT NOT NULL);", nil, nil, nil)

    var stmt: OpaquePointer?
    if sqlite3_prepare_v2(db, "INSERT INTO tofugu_audio_index(term, values_csv) VALUES (?1, ?2);", -1, &stmt, nil) != SQLITE_OK {
        fputs("Failed to prepare insert\n", stderr)
        return
    }
    defer { sqlite3_finalize(stmt) }

    sqlite3_exec(db, "BEGIN;", nil, nil, nil)

    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    var count = 0
    for line in lines.dropFirst() {
        let parts = line.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count < 2 { continue }
        let term = String(parts[0])
        let values = String(parts[1])

        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        sqlite3_bind_text(stmt, 1, term, -1, SQLITE_TRANSIENT_SWIFT)
        sqlite3_bind_text(stmt, 2, values, -1, SQLITE_TRANSIENT_SWIFT)
        if sqlite3_step(stmt) == SQLITE_DONE {
            count += 1
        }
    }

    sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_tofugu_term ON tofugu_audio_index(term);", nil, nil, nil)

    print("Wrote \(count) rows to \(sqlitePath)")
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let csvPath = root.appendingPathComponent("tofugu-audio-index.csv").path
let sqlitePath = root
    .appendingPathComponent("Sources/JapaneseLanguageTools/Resources/tofugu-audio-index.sqlite")
    .path

populateSQLiteFromCSV(csvPath: csvPath, sqlitePath: sqlitePath)
