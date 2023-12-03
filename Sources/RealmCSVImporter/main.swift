#!/usr/bin/swift

import Foundation
import RealmSwift
import JapaneseLanguageTools

// Function to parse CSV and populate Realm
func populateRealmFromCSV(filePath: String) {
    let url = URL(fileURLWithPath: filePath)
    
    let documentDirectory = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    let realmPath = documentDirectory.appendingPathComponent("tofugu-audio-index-uncompcated.realm")
    if FileManager.default.fileExists(atPath: String(realmPath.absoluteString.dropFirst("file://".count))) {
        try! FileManager.default.removeItem(at: realmPath)
    }
    let realmConfig = Realm.Configuration(fileURL: realmPath, schemaVersion: 1)
    let realm = try! Realm(configuration: realmConfig)
    
    do {
        let data = try Data(contentsOf: url)
        let csvString = String(data: data, encoding: .utf8)!
        let rows = csvString.components(separatedBy: "\n").dropFirst()
        
        try! realm.write {
            for row in rows {
                let columns = row.components(separatedBy: ",")
                
                if columns.count == 2 {
                    let term = columns[0]
                    let values = columns[1]
                    
                    let termObject = TofuguAudioIndex()
                    termObject.term = term
                    termObject.values = values
                    print("\(term): \(values)")
                    
                    realm.add(termObject, update: .modified)
                }
            }
        }
        
        let compactedUrl = documentDirectory.appendingPathComponent("tofugu-audio-index.realm")
        autoreleasepool {
            let path = String(compactedUrl.absoluteString.dropFirst("file://".count))
            if FileManager.default.fileExists(atPath: path) {
                try! FileManager.default.removeItem(atPath: path)
            }
            try! realm.writeCopy(toFile: compactedUrl)
            print(compactedUrl)
        }
        
        print("Realm populated successfully!")
    } catch {
        print("Error: \(error)")
    }
}

// Check if a command-line argument is provided for the file path
guard CommandLine.arguments.count == 2 else {
    print("Usage: \(CommandLine.arguments[0]) <csvFilePath>")
    exit(1)
}

// Get the file path from the command-line arguments
let csvFilePath = CommandLine.arguments[1]

// Call the function to populate Realm
populateRealmFromCSV(filePath: csvFilePath)
