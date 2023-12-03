import Foundation
import RealmSwift

public class TofuguAudioIndex: Object {
    @objc public dynamic var Term: String? = nil
    @objc public dynamic var Values: String? = nil
    
    public static var realm: Realm? {
        return try? Realm(configuration: TofuguAudioIndexRealmConfigurer.configuration)
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
        let config = Realm.Configuration(fileURL: url, schemaVersion: 1, migrationBlock: migrationBlock(migration:oldSchemaVersion:), objectTypes: [TofuguAudioIndex.self])
        return config
    }
    
    static private func migrationBlock(migration: Migration, oldSchemaVersion: UInt64) {
//        if oldSchemaVersion < schemaVersion {
//            if oldSchemaVersion < 32 {
//            }
//        }
    }
}
