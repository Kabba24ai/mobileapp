//
//  SDKUserDefault.swift
//  
//
//  Created by Covantex LLC on 31/03/22.
//

import Foundation
import MMKV
import ObjectMapper

/**
 SDKUserDefault : Handles saving and retrieving values, including models, using MMKV as a storage solution. It replaces UserDefaults and includes migration functionality.
 */
public class SDKUserDefault {
	private static var shared = SDKUserDefault()
	private var mmkv: MMKV?

	private init() {
			// Initialize MMKV in default directory: documentDirectory/mmkv to store MMKV files
		MMKV.initialize(rootDir: nil, logLevel: .warning, handler: MyMMKVHandler.init())

			// Now you can use MMKV normally
		self.mmkv = MMKV.default()
	}

		// Enum to hold predefined keys for storing values
	enum DefaultKey: String {
		case KEY_CATEGORYLIST
	}

		// Helper function that lists all keys to be migrated from UserDefaults to MMKV
	static func allKeysToMigrate() -> [DefaultKey] {
		return [.KEY_CATEGORYLIST]
	}


		/// Migrate userdefaults values to mmkv that is saved from SDK
		/// once migrated, we removed values from userdefaults
	static func migrateFromUserDefaults() {
			// Custom migration for specific keys defined in the SDK
		SDKUserDefault.migrateFromUserDefaults(allKeysToMigrate().map({ $0.rawValue }))
	}
}

	// MARK: - Overloaded save function for DefaultKey
extension SDKUserDefault {
	static func save(_ value: Bool, for key: DefaultKey) {
		self.save(value, for: key.rawValue)
	}

	static func save(_ value: Int, for key: DefaultKey) {
		self.save(value, for: key.rawValue)
	}

	static func save(_ value: Float, for key: DefaultKey) {
		self.save(value, for: key.rawValue)
	}

	static func save(_ value: Double, for key: DefaultKey) {
		self.save(value, for: key.rawValue)
	}

	static func save(_ value: String, for key: DefaultKey) {
		self.save(value, for: key.rawValue)
	}

	static func save(_ value: Date, for key: DefaultKey) {
		self.save(value, for: key.rawValue)
	}

	static func save(_ value: NSDictionary, for key: DefaultKey) {
		self.save(value, for: key.rawValue)
	}

	static func save(_ value: any Codable, for key: DefaultKey) {
		self.save(value, for: key.rawValue)
	}

	static func save<T: Codable>(_ values: [T], for key: DefaultKey) {
		self.save(values, for: key.rawValue)
	}
}

	// MARK: - Overloaded get,remove function for DefaultKey
extension SDKUserDefault {
	static func get(for key: DefaultKey) -> Bool? {
		return getBool(for: key.rawValue)
	}

	static func get(for key: DefaultKey) -> Int? {
		return getInt(for: key.rawValue)
	}

	static func get(for key: DefaultKey) -> Float? {
		return getFloat(for: key.rawValue)
	}

	static func get(for key: DefaultKey) -> Double? {
		return getDouble(for: key.rawValue)
	}

	static func get(for key: DefaultKey) -> String? {
		return getString(for: key.rawValue)
	}

	static func get(for key: DefaultKey) -> Date? {
		return getDate(for: key.rawValue)
	}

	static func get(for key: DefaultKey) -> Data? {
		return getData(for: key.rawValue)
	}

	static func get(for key: DefaultKey) -> NSDictionary? {
		return getDictionary(for: key.rawValue)
	}

	static func get<T: Codable>(_ type: T.Type, for key: DefaultKey) -> T? {
		return self.get(type, for: key.rawValue)
	}

	static func get<T: Codable>(_ type: [T].Type, for key: DefaultKey) -> [T]? {
		return self.get(type, for: key.rawValue)
	}

	static func remove(for key: DefaultKey) {
		remove(for: key.rawValue)
	}

	static func remove(for keys: [DefaultKey]) {
		remove(for: keys.map({ $0.rawValue }))
	}
}

	// MARK: - Function to set value using a String key
public extension SDKUserDefault {
		/// Remove value using key
		/// - Parameter keys: String
	static func remove(for key: String) {
		SDKUserDefault.shared.mmkv?.removeValue(forKey: key)
	}

		/// Remove values using keys
		/// - Parameter keys: [String]
	static func remove(for keys: [String]) {
		SDKUserDefault.shared.mmkv?.removeValues(forKeys: keys)
	}

		/// Save Bool value
		/// - Parameters:
		///   - value: Bool
		///   - key: String
	static func save(_ value: Bool, for key: String) {
		SDKUserDefault.shared.mmkv?.set(value, forKey: key)
	}

		/// Save Int value
		/// - Parameters:
		///   - value: Int
		///   - key: String
	static func save(_ value: Int, for key: String) {
		SDKUserDefault.shared.mmkv?.set(Int64(value), forKey: key)
	}

		/// Save Float value
		/// - Parameters:
		///   - value: Float
		///   - key: String
	static func save(_ value: Float, for key: String) {
		SDKUserDefault.shared.mmkv?.set(value, forKey: key)
	}

		/// Save Double value
		/// - Parameters:
		///   - value: Double
		///   - key: String
	static func save(_ value: Double, for key: String) {
		SDKUserDefault.shared.mmkv?.set(value, forKey: key)
	}

		/// Save String value
		/// - Parameters:
		///   - value: String
		///   - key: String
	static func save(_ value: String, for key: String) {
		SDKUserDefault.shared.mmkv?.set(value, forKey: key)
	}

		/// Save Date value
		/// - Parameters:
		///   - value: Date
		///   - key: String
	static func save(_ value: Date, for key: String) {
		SDKUserDefault.shared.mmkv?.set(value, forKey: key)
	}

		/// Save Data value
		/// - Parameters:
		///   - value: Data
		///   - key: String
	static func save(_ value: Data, for key: String) {
		SDKUserDefault.shared.mmkv?.set(value, forKey: key)
	}

		/// Save NSDictionary value
		/// - Parameters:
		///   - value: NSDictionary
		///   - key: String
	static func save(_ value: NSDictionary, for key: String) {
		SDKUserDefault.shared.mmkv?.set(value, forKey: key)
	}

		/// Save Codable value
		/// - Parameters:
		///   - value: Codable
		///   - key: String
	static func save<T: Codable>(_ value: T, for key: String) {
		if let encodedData = try? JSONEncoder().encode(value) {
			SDKUserDefault.shared.mmkv?.set(encodedData, forKey: key)
		}
	}

		/// Save [Codable] Array values
		/// - Parameters:
		///   - value: [Codable] array
		///   - key: String
	static func save<T: Codable>(_ values: [T], for key: String) {
		if let encodedData = try? JSONEncoder().encode(values) {
			SDKUserDefault.shared.mmkv?.set(encodedData, forKey: key)
		}
	}
}

	// MARK: - Function to get value based on the type
public extension SDKUserDefault {
		/// Get Bool value if available
		/// - Parameter key: String
		/// - Returns: Bool
	static func getBool(for key: String) -> Bool? {
		return SDKUserDefault.shared.mmkv?.bool(forKey: key)
	}

		/// Get Int value if available
		/// - Parameter key: String
		/// - Returns: Int
	static func getInt(for key: String) -> Int? {
		if let value = SDKUserDefault.shared.mmkv?.int64(forKey: key) {
			return Int(value)
		}

		return nil
	}

		/// Get Float value if available
		/// - Parameter key: String
		/// - Returns: Float
	static func getFloat(for key: String) -> Float? {
		return SDKUserDefault.shared.mmkv?.float(forKey: key)
	}

		/// Get Double value if available
		/// - Parameter key: String
		/// - Returns: Double
	static func getDouble(for key: String) -> Double? {
		return SDKUserDefault.shared.mmkv?.double(forKey: key)
	}

		/// Get String value if available
		/// - Parameter key: String
		/// - Returns: String
	static func getString(for key: String) -> String? {
		return SDKUserDefault.shared.mmkv?.string(forKey: key)
	}

		/// Get Date value if available
		/// - Parameter key: String
		/// - Returns: Date
	static func getDate(for key: String) -> Date? {
		return SDKUserDefault.shared.mmkv?.date(forKey: key)
	}

		/// Get Data value if available
		/// - Parameter key: String
		/// - Returns: Data
	static func getData(for key: String) -> Data? {
		return SDKUserDefault.shared.mmkv?.data(forKey: key)
	}

		/// Get NSDictionary value if available
		/// - Parameter key: String
		/// - Returns: NSDictionary
	static func getDictionary(for key: String) -> NSDictionary? {
		if let dict = SDKUserDefault.shared.mmkv?.object(of: NSDictionary.self, forKey: key) as? NSDictionary {
			return dict
		}
		return nil
	}

	/**
	 Retrieve a Codable object using a String key
	 - Parameter type: The type of Codable object to retrieve
	 - Parameter key: The String key for the data
	 - Returns: A decoded Codable object, if available
	 */
	static func get<T: Codable>(_ type: T.Type, for key: String) -> T? {
		let decoder = JSONDecoder()
		if let data = SDKUserDefault.shared.mmkv?.data(forKey: key), let decodedObject = try? decoder.decode(T.self, from: data) {
			return decodedObject
		}
		return nil
	}

	/**
	 Retrieve an array of Codable objects using a String key
	 - Parameter type: The array type of Codable objects to retrieve
	 - Parameter key: The String key for the data
	 - Returns: A decoded array of Codable objects, if available
	 */
	static func get<T: Codable>(_ type: [T].Type, for key: String) -> [T]? {
		guard let dataFromMMKV = SDKUserDefault.shared.mmkv?.data(forKey: key) else {
			return []
		}

		let decoder = JSONDecoder()
		if let decodedArray = try? decoder.decode([T].self, from: dataFromMMKV) {
			return decodedArray
		} else {
			return []
		}
	}
}

public extension SDKUserDefault {
		/// Migrate from UserDefault to MMKV & delete object from UserDefault
		/// - Parameter keys: [String]
	static func migrateFromUserDefaults(_ keys: [String]) {
		let userDefaults = UserDefaults.standard
		for key in keys {
			if let value = userDefaults.object(forKey: key) {
				switch value {
					case let boolValue as Bool:
						self.save(boolValue, for: key)
						userDefaults.removeObject(forKey: key)
					case let intValue as Int:
						self.save(intValue, for: key)
						userDefaults.removeObject(forKey: key)
					case let floatValue as Float:
						self.save(floatValue, for: key)
						userDefaults.removeObject(forKey: key)
					case let doubleValue as Double:
						self.save(doubleValue, for: key)
						userDefaults.removeObject(forKey: key)
					case let stringValue as String:
						self.save(stringValue, for: key)
						userDefaults.removeObject(forKey: key)
					case let dateValue as Date:
						self.save(dateValue, for: key)
						userDefaults.removeObject(forKey: key)
					case let dataValue as Data:
						self.save(dataValue, for: key)
						userDefaults.removeObject(forKey: key)
					case let dictValue as NSDictionary:
						self.save(dictValue, for: key)
						userDefaults.removeObject(forKey: key)
					case let dictValue as any Codable:
						self.save(dictValue, for: key)
						userDefaults.removeObject(forKey: key)
					default: break
				}
			}
		}
		userDefaults.synchronize()
	}
}

	// Custom MMKV handler to catch errors
class MyMMKVHandler: NSObject, MMKVHandler {
	func mmkvLog(_ level: MMKVLogLevel, file: String!, line: Int32, function: String!, message: String!) {
		print("[MMKV] \(file ?? ""):\(line) \(function ?? "") -> \(message ?? "")")
	}
}



extension SDKUserDefault {
    static func saveMappableArray<T: Mappable>(_ values: [T], for key: String) {
        // Convert array → JSON string
        guard let jsonString = Mapper().toJSONString(values, prettyPrint: false) else { return }
        SDKUserDefault.shared.mmkv?.set(jsonString, forKey: key)
    }
    
    static func getMappableArray<T: Mappable>(_ type: T.Type, for key: String) -> [T]? {
        guard let jsonString = SDKUserDefault.shared.mmkv?.string(forKey: key) else {
            return nil
        }
        return Mapper<T>().mapArray(JSONString: jsonString)
    }
    
    // MARK: - Save Mappable Object
    static func saveMappableObject<T: Mappable>(_ value: T, for key: String) {
        guard let jsonString = value.toJSONString(prettyPrint: false) else { return }
        SDKUserDefault.shared.mmkv?.set(jsonString, forKey: key)
    }
    
    // MARK: - Get Mappable Object
    static func getMappableObject<T: Mappable>(_ type: T.Type, for key: String) -> T? {
        guard let jsonString = SDKUserDefault.shared.mmkv?.string(forKey: key) else { return nil }
        return Mapper<T>().map(JSONString: jsonString)
    }
    
    // MARK: - Save WebView Data
    static func saveWebviewData(_ htmlString: String, for key: String, order_id: String) {
        SDKUserDefault.shared.mmkv?.set(htmlString, forKey: "\(key)_\(order_id)")
    }
    
    // MARK: - Get WebView Data
    static func getWebviewData(_ key: String, order_id: String) -> String? {
        var cacheData = ""
        if let cachedHTML = SDKUserDefault.shared.mmkv?.string(forKey: "\(key)_\(order_id)") {
            cacheData = cachedHTML
        }
        return cacheData
    }
    
}
