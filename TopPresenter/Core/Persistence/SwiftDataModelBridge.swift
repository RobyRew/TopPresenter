//
//  SwiftDataModelBridge.swift
//  TopPresenter
//
//  Rebuilds the `NSManagedObjectModel` that SwiftData created the store with,
//  derived from the SAME `Schema` value the app hands `ModelContainer`.
//
//  WHY THIS EXISTS
//  ---------------
//  `NSBatchInsertRequest` is Apple's supported way to write tens of thousands of
//  rows without materialising a managed object per row — the difference between
//  eight minutes and one for a full Bible library. It is Core Data API, so it
//  needs an `NSPersistentStoreCoordinator`, which needs a managed object model.
//  SwiftData builds one internally and does not vend it.
//
//  The load-bearing insight is that SwiftData's `Schema` is PUBLIC API and
//  describes exactly what went into the store: entity names, stored properties,
//  value types, optionality, relationship destinations, cardinality, delete
//  rules, uniqueness constraints. Deriving the Core Data model from `Schema`
//  rather than hand-writing an `.xcdatamodeld` means the two cannot drift: add a
//  property to a `@Model` and the bridge picks it up on the next launch, because
//  both sides read the same declaration.
//
//  Core Data will not open a store whose model version hashes disagree with the
//  model you hand it — that check is the whole safety net. `verify(_:matches:)`
//  runs it ahead of time against the store's own recorded hashes, so a caller
//  can fall back to the ordinary SwiftData path instead of failing, and
//  `ManagedObjectModelBridgeTests` runs it in CI so a mismatch is a red test
//  rather than a slow import in the field.
//

import CoreData
import SwiftData

nonisolated enum SwiftDataModelBridge {

    // MARK: Errors

    enum BridgeError: Error, CustomStringConvertible {
        /// A property type this bridge has never seen. Never silently skipped:
        /// a missing property changes the entity's version hash, so the store
        /// would refuse the model anyway — better to say which property.
        case unsupportedType(entity: String, property: String, type: String)
        /// An `@Attribute(…)` option this bridge does not know how to reproduce.
        /// Options change the version hash, so guessing would produce a model the
        /// store refuses — naming it is the only useful answer.
        case unsupportedOption(entity: String, property: String, option: String)
        case missingDestination(entity: String, relationship: String, destination: String)

        var description: String {
            switch self {
            case let .unsupportedType(entity, property, type):
                return "\(entity).\(property) has type \(type), which SwiftDataModelBridge cannot map to an NSAttributeType."
            case let .unsupportedOption(entity, property, option):
                return "\(entity).\(property) carries the attribute option \(option), which SwiftDataModelBridge cannot reproduce."
            case let .missingDestination(entity, relationship, destination):
                return "\(entity).\(relationship) points at \(destination), which is not in the schema."
            }
        }
    }

    // MARK: Building

    /// The Core Data model for `schema`, or a thrown `BridgeError` naming the
    /// property that could not be mapped.
    static func managedObjectModel(for schema: Schema) throws -> NSManagedObjectModel {
        var entities: [String: NSEntityDescription] = [:]

        // Pass 1 — bare entities, so relationships in pass 2 have something to
        // point at regardless of declaration order.
        for entity in schema.entities {
            let described = NSEntityDescription()
            described.name = entity.name
            // The class name is not part of the version hash, and nothing here
            // ever instantiates one: batch insert writes dictionaries.
            described.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            entities[entity.name] = described
        }

        // Pass 2 — properties.
        for entity in schema.entities {
            guard let described = entities[entity.name] else { continue }
            var properties: [NSPropertyDescription] = []

            for property in entity.storedProperties {
                if let attribute = property as? Schema.Attribute {
                    properties.append(try describe(attribute, in: entity.name))
                } else if let relationship = property as? Schema.Relationship {
                    properties.append(try describe(relationship, in: entity.name, entities: entities))
                }
            }

            described.properties = properties
            described.uniquenessConstraints = entity.uniquenessConstraints
            if let superName = entity.superentityName, let superEntity = entities[superName] {
                superEntity.subentities.append(described)
            }
        }

        // Pass 3 — inverses, which can only be wired once both sides own their
        // relationship objects.
        for entity in schema.entities {
            guard let described = entities[entity.name] else { continue }
            for relationship in entity.relationships {
                guard let inverseName = relationship.inverseName,
                      let mine = described.relationshipsByName[relationship.name],
                      let theirs = entities[relationship.destination]?.relationshipsByName[inverseName]
                else { continue }
                mine.inverseRelationship = theirs
                theirs.inverseRelationship = mine
            }
        }

        let model = NSManagedObjectModel()
        model.entities = schema.entities.compactMap { entities[$0.name] }
        return model
    }

    private static func describe(_ attribute: Schema.Attribute,
                                 in entityName: String) throws -> NSAttributeDescription {
        let described = NSAttributeDescription()
        described.name = attribute.name
        guard let type = attributeType(for: attribute.valueType) else {
            throw BridgeError.unsupportedType(entity: entityName, property: attribute.name,
                                              type: String(describing: attribute.valueType))
        }
        described.attributeType = type
        described.isOptional = attribute.isOptional
        described.versionHashModifier = attribute.hashModifier

        // Options are part of the version hash — `.externalStorage` on
        // MediaItem's two `Data?` columns is the difference between a model the
        // store opens and one it refuses, and it is invisible in the value type.
        for option in attribute.options {
            switch option {
            case .externalStorage:
                described.allowsExternalBinaryDataStorage = true
            case .spotlight:
                described.isIndexedBySpotlight = true
            case .allowsCloudEncryption:
                described.allowsCloudEncryption = true
            case .preserveValueOnDeletion:
                described.preservesValueInHistoryOnDeletion = true
            case .unique:
                break   // carried by the entity's uniquenessConstraints
            case .ephemeral:
                break   // @Transient never reaches storedProperties
            default:
                throw BridgeError.unsupportedOption(entity: entityName, property: attribute.name,
                                                    option: String(describing: option))
            }
        }
        return described
    }

    private static func describe(_ relationship: Schema.Relationship,
                                 in entityName: String,
                                 entities: [String: NSEntityDescription]) throws -> NSRelationshipDescription {
        guard let destination = entities[relationship.destination] else {
            throw BridgeError.missingDestination(entity: entityName, relationship: relationship.name,
                                                 destination: relationship.destination)
        }
        let described = NSRelationshipDescription()
        described.name = relationship.name
        described.destinationEntity = destination
        described.isOptional = relationship.isOptional
        described.deleteRule = deleteRule(for: relationship.deleteRule)
        described.versionHashModifier = relationship.hashModifier
        if relationship.isToOneRelationship {
            described.minCount = relationship.minimumModelCount ?? 0
            described.maxCount = 1
        } else {
            // A maxCount of 0 means unbounded, which is what SwiftData reports
            // for an ordinary to-many.
            described.minCount = relationship.minimumModelCount ?? 0
            described.maxCount = relationship.maximumModelCount ?? 0
        }
        return described
    }

    // MARK: Type mapping
    //
    // Deliberately a closed list rather than a permissive default. Every stored
    // property in this app's schema is one of these — SwiftData sees `[VerseRun]`
    // and friends only as the `…JSON: String` columns they are encoded into, and
    // the SwiftUI types (`Color`, `NSImage`) are @Transient, so they never reach
    // `storedProperties`. If that ever stops being true the import throws with
    // the property's name instead of quietly writing a store nothing can open.

    private static func attributeType(for valueType: Any.Type) -> NSAttributeType? {
        switch unwrapOptional(valueType) {
        case is String.Type:  return .stringAttributeType
        case is Int.Type:     return .integer64AttributeType
        case is Int64.Type:   return .integer64AttributeType
        case is Int32.Type:   return .integer32AttributeType
        case is Int16.Type:   return .integer16AttributeType
        case is Bool.Type:    return .booleanAttributeType
        case is Double.Type:  return .doubleAttributeType
        case is Float.Type:   return .floatAttributeType
        case is Date.Type:    return .dateAttributeType
        case is UUID.Type:    return .UUIDAttributeType
        case is Data.Type:    return .binaryDataAttributeType
        case is URL.Type:     return .URIAttributeType
        case is Decimal.Type: return .decimalAttributeType
        default:              return nil
        }
    }

    /// `Optional<String>.self` → `String.self`. `Schema.Attribute.valueType`
    /// keeps the optional wrapper, but the Core Data attribute type is the
    /// wrapped one — optionality is carried by `isOptional`.
    private static func unwrapOptional(_ type: Any.Type) -> Any.Type {
        (type as? any OptionalTypeErasure.Type)?.wrappedType ?? type
    }

    private static func deleteRule(for rule: Schema.Relationship.DeleteRule) -> NSDeleteRule {
        switch rule {
        case .noAction: return .noActionDeleteRule
        case .nullify:  return .nullifyDeleteRule
        case .cascade:  return .cascadeDeleteRule
        case .deny:     return .denyDeleteRule
        @unknown default: return .nullifyDeleteRule
        }
    }
}

private protocol OptionalTypeErasure {
    nonisolated static var wrappedType: Any.Type { get }
}

extension Optional: OptionalTypeErasure {
    nonisolated static var wrappedType: Any.Type { Wrapped.self }
}

// MARK: - Opening a SwiftData store with Core Data

nonisolated extension SwiftDataModelBridge {

    enum StoreAccessError: Error, CustomStringConvertible {
        /// Tests and previews run on in-memory stores, which have no file for a
        /// second coordinator to open. Not a failure — a reason to use the
        /// ordinary SwiftData path.
        case inMemoryStore
        /// More than one configuration means more than one store file, and
        /// nothing here knows which one an entity lives in.
        case ambiguousConfiguration(count: Int)
        case storeMissing(URL)

        var description: String {
            switch self {
            case .inMemoryStore:
                return "The container is in memory, so there is no store file to open."
            case let .ambiguousConfiguration(count):
                return "The container has \(count) configurations; the bridge handles exactly one."
            case let .storeMissing(url):
                return "No store file at \(url.path)."
            }
        }
    }

    /// A Core Data stack over the very file `container` writes to.
    ///
    /// Throws rather than traps for every reason it might not be possible —
    /// in-memory store, several configurations, a model the store rejects — so
    /// that a caller's answer can be "use the SwiftData path instead" rather
    /// than "fail the import". `addPersistentStore` is the real check: Core Data
    /// compares the model's version hashes against the ones recorded in the
    /// store when SwiftData created it, and refuses anything that disagrees.
    static func coordinator(for container: ModelContainer) throws -> NSPersistentStoreCoordinator {
        guard container.configurations.count == 1 else {
            throw StoreAccessError.ambiguousConfiguration(count: container.configurations.count)
        }
        guard let configuration = container.configurations.first else {
            throw StoreAccessError.ambiguousConfiguration(count: 0)
        }
        guard !configuration.isStoredInMemoryOnly else { throw StoreAccessError.inMemoryStore }
        guard FileManager.default.fileExists(atPath: configuration.url.path) else {
            throw StoreAccessError.storeMissing(configuration.url)
        }

        let model = try managedObjectModel(for: container.schema)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        // Persistent history tracking is not optional here, it is the difference
        // between a writable store and a read-only one. SwiftData turns it on
        // for every store it creates, and Core Data refuses writes through a
        // connection that did not ask for it:
        //
        //   NSCocoaErrorDomain 513 — "File is in Read Only mode due to Persistent
        //   History being detected but NSPersistentHistoryTrackingKey was not
        //   included."
        //
        // It is also invisible on a store nothing has written yet, which is how
        // it survives a spike and shows up the first time a real import runs.
        _ = try coordinator.addPersistentStore(
            type: .sqlite, at: configuration.url,
            options: [
                NSPersistentHistoryTrackingKey: true as NSNumber,
                // Announce writes the way any second connection should. SwiftData
                // does not currently refresh a `@Query` from these, so callers
                // still perform a real SwiftData save afterwards — but a store
                // written behind everyone's back is worse than a redundant
                // notification.
                NSPersistentStoreRemoteChangeNotificationPostOptionKey: true as NSNumber,
            ])
        return coordinator
    }

    /// Whether the derived model still matches what created the store, without
    /// opening anything. Exists for diagnostics and for the CI guard; the import
    /// path just tries `coordinator(for:)` and falls back when it throws.
    static func matchesStore(_ schema: Schema, at url: URL) throws -> Bool {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        let recorded = (metadata[NSStoreModelVersionHashesKey] as? [String: Data]) ?? [:]
        let derived = try managedObjectModel(for: schema).entityVersionHashesByName
        return recorded == derived
    }
}
