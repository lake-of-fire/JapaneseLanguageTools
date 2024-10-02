import Foundation
import RealmSwift
import BigSyncKit

public class TofuguAudioIndex: Object {
    @Persisted(primaryKey: true) public var term: String = ""
    @Persisted public var values: String = ""

    public static var realm: Realm? {
        do {
            return try Realm(configuration: TofuguAudioIndexRealmConfigurer.configuration)
        } catch {
            debugPrint(error)
            return nil
        }
    }
    
    public override init() {
        super.init()
    }
    
    public static func audioURL(term: String, readingKana: String) -> URL? {
        guard let result = realm?.object(ofType: TofuguAudioIndex.self, forPrimaryKey: term), result.values.split(separator: ",").map({ String($0) }).contains(readingKana) else {
            return nil
        }
        let filename = "\(term)【\(readingKana)】.mp3"
        guard let escapedUrl = "https://manabi.io/media/audio/tofugu/\(filename)".addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed), let audioURL = URL(string: escapedUrl) else {
            return nil
        }
        return audioURL
    }
}

public enum TofuguAudioIndexRealmConfigurer {
    static let schemaVersion: UInt64 = 1
    
    public static var configuration: Realm.Configuration {
        guard let url = Bundle.module.url(forResource: "tofugu-audio-index", withExtension: "realm") else { fatalError("no tofugu audio index") }
        // Disable file protection for this directory
        //        try! FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: url.path)
        //        var url = url.appendingPathComponent("collections")
        //        self.configuration = Realm.Configuration(fileURL: url)
        let config = Realm.Configuration(
            fileURL: url,
            readOnly: true,
            schemaVersion: 1,
            migrationBlock: migrationBlock(migration:oldSchemaVersion:),
            objectTypes: [TofuguAudioIndex.self]
        )
        return config
    }
    
    static private func migrationBlock(migration: Migration, oldSchemaVersion: UInt64) {
//        if oldSchemaVersion < schemaVersion {
//            if oldSchemaVersion < 32 {
//            }
//        }
    }
}
