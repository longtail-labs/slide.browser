// Generated using the ObjectBox Swift Generator — https://objectbox.io
// DO NOT EDIT

// swiftlint:disable all
import ObjectBox
import Foundation

// MARK: - Entity metadata

extension OBXObject: ObjectBox.Entity {}
extension OBXProject: ObjectBox.Entity {}

extension OBXObject: ObjectBox.__EntityRelatable {
    public typealias EntityType = OBXObject

    public var _id: EntityId<OBXObject> {
        return EntityId<OBXObject>(self.id.value)
    }
}

extension OBXObject: ObjectBox.EntityInspectable {
    public typealias EntityBindingType = OBXObjectBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    public static let entityInfo = ObjectBox.EntityInfo(name: "OBXObject", id: 1)

    public static let entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: OBXObject.self, id: 1, uid: 7761048279580004352)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 3082382515409988608)
        try entityBuilder.addProperty(name: "uuid", type: PropertyType.string, flags: [.unique, .indexHash, .indexed], id: 2, uid: 4303760175968794624, indexId: 1, indexUid: 9028802235143042816)
        try entityBuilder.addProperty(name: "createdAt", type: PropertyType.date, id: 3, uid: 7415458692116092672)
        try entityBuilder.addProperty(name: "updatedAt", type: PropertyType.date, id: 4, uid: 7391187128820018944)
        try entityBuilder.addProperty(name: "kind", type: PropertyType.long, flags: [.indexed], id: 6, uid: 5726493081152361472, indexId: 9, indexUid: 7751602147216954368)
        try entityBuilder.addProperty(name: "payload", type: PropertyType.byteVector, id: 7, uid: 6383205187403596032)
        try entityBuilder.addProperty(name: "displayName", type: PropertyType.string, flags: [.indexHash, .indexed], id: 13, uid: 1900971037767069440, indexId: 10, indexUid: 6186563457996950784)
        try entityBuilder.addProperty(name: "sortOrder", type: PropertyType.long, flags: [.indexed], id: 11, uid: 6664627743093585920, indexId: 11, indexUid: 5223418705796602368)
        try entityBuilder.addProperty(name: "lastAccessedAt", type: PropertyType.date, id: 12, uid: 2721118919032238080)
        try entityBuilder.addToOneRelation(name: "project", targetEntityInfo: ToOne<OBXProject>.Target.entityInfo, flags: [.indexed, .indexPartialSkipZero], id: 16, uid: 6121247658162977792, indexId: 15, indexUid: 4389619077202498048)

        try entityBuilder.lastProperty(id: 16, uid: 6121247658162977792)
    }
}

extension OBXObject {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXObject.id == myId }
    public static var id: Property<OBXObject, Id, Id> { return Property<OBXObject, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXObject.uuid.startsWith("X") }
    public static var uuid: Property<OBXObject, String, Void> { return Property<OBXObject, String, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXObject.createdAt > 1234 }
    public static var createdAt: Property<OBXObject, Date, Void> { return Property<OBXObject, Date, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXObject.updatedAt > 1234 }
    public static var updatedAt: Property<OBXObject, Date, Void> { return Property<OBXObject, Date, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXObject.kind > 1234 }
    public static var kind: Property<OBXObject, Int, Void> { return Property<OBXObject, Int, Void>(propertyId: 6, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXObject.payload > 1234 }
    public static var payload: Property<OBXObject, Data, Void> { return Property<OBXObject, Data, Void>(propertyId: 7, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXObject.displayName.startsWith("X") }
    public static var displayName: Property<OBXObject, String, Void> { return Property<OBXObject, String, Void>(propertyId: 13, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXObject.sortOrder > 1234 }
    public static var sortOrder: Property<OBXObject, Int, Void> { return Property<OBXObject, Int, Void>(propertyId: 11, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXObject.lastAccessedAt > 1234 }
    public static var lastAccessedAt: Property<OBXObject, Date?, Void> { return Property<OBXObject, Date?, Void>(propertyId: 12, isPrimaryKey: false) }
    public static var project: Property<OBXObject, EntityId<ToOne<OBXProject>.Target>, ToOne<OBXProject>.Target> { return Property(propertyId: 16) }


    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == OBXObject {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    public static var id: Property<OBXObject, Id, Id> { return Property<OBXObject, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .uuid.startsWith("X") }

    public static var uuid: Property<OBXObject, String, Void> { return Property<OBXObject, String, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .createdAt > 1234 }

    public static var createdAt: Property<OBXObject, Date, Void> { return Property<OBXObject, Date, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .updatedAt > 1234 }

    public static var updatedAt: Property<OBXObject, Date, Void> { return Property<OBXObject, Date, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .kind > 1234 }

    public static var kind: Property<OBXObject, Int, Void> { return Property<OBXObject, Int, Void>(propertyId: 6, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .payload > 1234 }

    public static var payload: Property<OBXObject, Data, Void> { return Property<OBXObject, Data, Void>(propertyId: 7, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .displayName.startsWith("X") }

    public static var displayName: Property<OBXObject, String, Void> { return Property<OBXObject, String, Void>(propertyId: 13, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .sortOrder > 1234 }

    public static var sortOrder: Property<OBXObject, Int, Void> { return Property<OBXObject, Int, Void>(propertyId: 11, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .lastAccessedAt > 1234 }

    public static var lastAccessedAt: Property<OBXObject, Date?, Void> { return Property<OBXObject, Date?, Void>(propertyId: 12, isPrimaryKey: false) }

    public static var project: Property<OBXObject, ToOne<OBXProject>.Target.EntityBindingType.IdType, ToOne<OBXProject>.Target> { return Property<OBXObject, ToOne<OBXProject>.Target.EntityBindingType.IdType, ToOne<OBXProject>.Target>(propertyId: 16) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `OBXObject.EntityBindingType`.
public final class OBXObjectBinding: ObjectBox.EntityBinding, Sendable {
    public typealias EntityType = OBXObject
    public typealias IdType = Id

    public required init() {}

    public func generatorBindingVersion() -> Int { 1 }

    public func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    public func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    public func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_uuid = propertyCollector.prepare(string: entity.uuid)
        let propertyOffset_payload = propertyCollector.prepare(bytes: OBXJSONPayloadConverter.convert(entity.payload))
        let propertyOffset_displayName = propertyCollector.prepare(string: entity.displayName)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.createdAt, at: 2 + 2 * 3)
        propertyCollector.collect(entity.updatedAt, at: 2 + 2 * 4)
        propertyCollector.collect(entity.kind.rawValue, at: 2 + 2 * 6)
        propertyCollector.collect(entity.sortOrder, at: 2 + 2 * 11)
        propertyCollector.collect(entity.lastAccessedAt, at: 2 + 2 * 12)
        try propertyCollector.collect(entity.project, at: 2 + 2 * 16, store: store)
        propertyCollector.collect(dataOffset: propertyOffset_uuid, at: 2 + 2 * 2)
        propertyCollector.collect(dataOffset: propertyOffset_payload, at: 2 + 2 * 7)
        propertyCollector.collect(dataOffset: propertyOffset_displayName, at: 2 + 2 * 13)
    }

    public func postPut(fromEntity entity: EntityType, id: ObjectBox.Id, store: ObjectBox.Store) throws {
        if entityId(of: entity) == 0 {  // New object was put? Attach relations now that we have an ID.
            entity.project.attach(to: store.box(for: OBXProject.self))
        }
    }
    public func setToOneRelation(_ propertyId: obx_schema_id, of entity: EntityType, to entityId: ObjectBox.Id?) {
        switch propertyId {
            case 16:
                entity.project.targetId = (entityId != nil) ? EntityId<OBXProject>(entityId!) : nil
            default:
                fatalError("Attempt to change nonexistent ToOne relation with ID \(propertyId)")
        }
    }
    public func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = OBXObject()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.uuid = entityReader.read(at: 2 + 2 * 2)
        entity.createdAt = entityReader.read(at: 2 + 2 * 3)
        entity.updatedAt = entityReader.read(at: 2 + 2 * 4)
        entity.kind = optConstruct(OBXObjectKind.self, rawValue: entityReader.read(at: 2 + 2 * 6)) ?? .link
        entity.payload = OBXJSONPayloadConverter.convert(entityReader.read(at: 2 + 2 * 7))
        entity.displayName = entityReader.read(at: 2 + 2 * 13)
        entity.sortOrder = entityReader.read(at: 2 + 2 * 11)
        entity.lastAccessedAt = entityReader.read(at: 2 + 2 * 12)

        entity.project = entityReader.read(at: 2 + 2 * 16, store: store)
        return entity
    }
}



extension OBXProject: ObjectBox.__EntityRelatable {
    public typealias EntityType = OBXProject

    public var _id: EntityId<OBXProject> {
        return EntityId<OBXProject>(self.id.value)
    }
}

extension OBXProject: ObjectBox.EntityInspectable {
    public typealias EntityBindingType = OBXProjectBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    public static let entityInfo = ObjectBox.EntityInfo(name: "OBXProject", id: 5)

    public static let entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: OBXProject.self, id: 5, uid: 1625400271676509184)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 3565152551701036288)
        try entityBuilder.addProperty(name: "uuid", type: PropertyType.string, flags: [.unique, .indexHash, .indexed], id: 2, uid: 5792766816951504384, indexId: 16, indexUid: 1817120202964355840)
        try entityBuilder.addProperty(name: "name", type: PropertyType.string, id: 3, uid: 8872110609166560768)
        try entityBuilder.addProperty(name: "icon", type: PropertyType.string, id: 4, uid: 1496407145807463936)
        try entityBuilder.addProperty(name: "colorHex", type: PropertyType.string, id: 5, uid: 4386070632065392896)
        try entityBuilder.addProperty(name: "sortOrder", type: PropertyType.long, flags: [.indexed], id: 6, uid: 8272883558117980160, indexId: 17, indexUid: 1464942761998942208)
        try entityBuilder.addProperty(name: "createdAt", type: PropertyType.date, id: 7, uid: 6315793359465739776)
        try entityBuilder.addProperty(name: "updatedAt", type: PropertyType.date, id: 8, uid: 1455191714596236288)

        try entityBuilder.lastProperty(id: 8, uid: 1455191714596236288)
    }
}

extension OBXProject {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXProject.id == myId }
    public static var id: Property<OBXProject, Id, Id> { return Property<OBXProject, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXProject.uuid.startsWith("X") }
    public static var uuid: Property<OBXProject, String, Void> { return Property<OBXProject, String, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXProject.name.startsWith("X") }
    public static var name: Property<OBXProject, String, Void> { return Property<OBXProject, String, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXProject.icon.startsWith("X") }
    public static var icon: Property<OBXProject, String, Void> { return Property<OBXProject, String, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXProject.colorHex.startsWith("X") }
    public static var colorHex: Property<OBXProject, String, Void> { return Property<OBXProject, String, Void>(propertyId: 5, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXProject.sortOrder > 1234 }
    public static var sortOrder: Property<OBXProject, Int, Void> { return Property<OBXProject, Int, Void>(propertyId: 6, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXProject.createdAt > 1234 }
    public static var createdAt: Property<OBXProject, Date, Void> { return Property<OBXProject, Date, Void>(propertyId: 7, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { OBXProject.updatedAt > 1234 }
    public static var updatedAt: Property<OBXProject, Date, Void> { return Property<OBXProject, Date, Void>(propertyId: 8, isPrimaryKey: false) }
    /// Use `OBXProject.objects` to refer to this ToMany relation property in queries,
    /// like when using `QueryBuilder.and(property:, conditions:)`.

    public static var objects: ToManyProperty<OBXObject> { return ToManyProperty(.valuePropertyId(16)) }


    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == OBXProject {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    public static var id: Property<OBXProject, Id, Id> { return Property<OBXProject, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .uuid.startsWith("X") }

    public static var uuid: Property<OBXProject, String, Void> { return Property<OBXProject, String, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .name.startsWith("X") }

    public static var name: Property<OBXProject, String, Void> { return Property<OBXProject, String, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .icon.startsWith("X") }

    public static var icon: Property<OBXProject, String, Void> { return Property<OBXProject, String, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .colorHex.startsWith("X") }

    public static var colorHex: Property<OBXProject, String, Void> { return Property<OBXProject, String, Void>(propertyId: 5, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .sortOrder > 1234 }

    public static var sortOrder: Property<OBXProject, Int, Void> { return Property<OBXProject, Int, Void>(propertyId: 6, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .createdAt > 1234 }

    public static var createdAt: Property<OBXProject, Date, Void> { return Property<OBXProject, Date, Void>(propertyId: 7, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .updatedAt > 1234 }

    public static var updatedAt: Property<OBXProject, Date, Void> { return Property<OBXProject, Date, Void>(propertyId: 8, isPrimaryKey: false) }

    /// Use `.objects` to refer to this ToMany relation property in queries, like when using
    /// `QueryBuilder.and(property:, conditions:)`.

    public static var objects: ToManyProperty<OBXObject> { return ToManyProperty(.valuePropertyId(16)) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `OBXProject.EntityBindingType`.
public final class OBXProjectBinding: ObjectBox.EntityBinding, Sendable {
    public typealias EntityType = OBXProject
    public typealias IdType = Id

    public required init() {}

    public func generatorBindingVersion() -> Int { 1 }

    public func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    public func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    public func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_uuid = propertyCollector.prepare(string: entity.uuid)
        let propertyOffset_name = propertyCollector.prepare(string: entity.name)
        let propertyOffset_icon = propertyCollector.prepare(string: entity.icon)
        let propertyOffset_colorHex = propertyCollector.prepare(string: entity.colorHex)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.sortOrder, at: 2 + 2 * 6)
        propertyCollector.collect(entity.createdAt, at: 2 + 2 * 7)
        propertyCollector.collect(entity.updatedAt, at: 2 + 2 * 8)
        propertyCollector.collect(dataOffset: propertyOffset_uuid, at: 2 + 2 * 2)
        propertyCollector.collect(dataOffset: propertyOffset_name, at: 2 + 2 * 3)
        propertyCollector.collect(dataOffset: propertyOffset_icon, at: 2 + 2 * 4)
        propertyCollector.collect(dataOffset: propertyOffset_colorHex, at: 2 + 2 * 5)
    }

    public func postPut(fromEntity entity: EntityType, id: ObjectBox.Id, store: ObjectBox.Store) throws {
        if entityId(of: entity) == 0 {  // New object was put? Attach relations now that we have an ID.
            let objects = ToMany<OBXObject>.backlink(
                sourceBox: store.box(for: ToMany<OBXObject>.ReferencedType.self),
                sourceProperty: ToMany<OBXObject>.ReferencedType.project,
                targetId: EntityId<OBXProject>(id.value))
            if !entity.objects.isEmpty {
                objects.replace(entity.objects)
            }
            entity.objects = objects
            try entity.objects.applyToDb()
        }
    }
    public func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = OBXProject()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.uuid = entityReader.read(at: 2 + 2 * 2)
        entity.name = entityReader.read(at: 2 + 2 * 3)
        entity.icon = entityReader.read(at: 2 + 2 * 4)
        entity.colorHex = entityReader.read(at: 2 + 2 * 5)
        entity.sortOrder = entityReader.read(at: 2 + 2 * 6)
        entity.createdAt = entityReader.read(at: 2 + 2 * 7)
        entity.updatedAt = entityReader.read(at: 2 + 2 * 8)

        entity.objects = ToMany<OBXObject>.backlink(
            sourceBox: store.box(for: ToMany<OBXObject>.ReferencedType.self),
            sourceProperty: ToMany<OBXObject>.ReferencedType.project,
            targetId: EntityId<OBXProject>(entity.id.value))
        return entity
    }
}


/// Helper function that allows calling Enum(rawValue: value) with a nil value, which will return nil.
fileprivate func optConstruct<T: RawRepresentable>(_ type: T.Type, rawValue: T.RawValue?) -> T? {
    guard let rawValue = rawValue else { return nil }
    return T(rawValue: rawValue)
}

// MARK: - Store setup

fileprivate func cModel() throws -> OpaquePointer {
    let modelBuilder = try ObjectBox.ModelBuilder()
    try OBXObject.buildEntity(modelBuilder: modelBuilder)
    try OBXProject.buildEntity(modelBuilder: modelBuilder)
    modelBuilder.lastEntity(id: 5, uid: 1625400271676509184)
    modelBuilder.lastIndex(id: 17, uid: 1464942761998942208)
    return modelBuilder.finish()
}

extension ObjectBox.Store {
    /// A store with a fully configured model. Created by the code generator with your model's metadata in place.
    ///
    /// # In-memory database
    /// To use a file-less in-memory database, instead of a directory path pass `memory:` 
    /// together with an identifier string:
    /// ```swift
    /// let inMemoryStore = try Store(directoryPath: "memory:test-db")
    /// ```
    ///
    /// - Parameters:
    ///   - directoryPath: The directory path in which ObjectBox places its database files for this store,
    ///     or to use an in-memory database `memory:<identifier>`.
    ///   - maxDbSizeInKByte: Limit of on-disk space for the database files. Default is `1024 * 1024` (1 GiB).
    ///   - fileMode: UNIX-style bit mask used for the database files; default is `0o644`.
    ///     Note: directories become searchable if the "read" or "write" permission is set (e.g. 0640 becomes 0750).
    ///   - maxReaders: The maximum number of readers.
    ///     "Readers" are a finite resource for which we need to define a maximum number upfront.
    ///     The default value is enough for most apps and usually you can ignore it completely.
    ///     However, if you get the maxReadersExceeded error, you should verify your
    ///     threading. For each thread, ObjectBox uses multiple readers. Their number (per thread) depends
    ///     on number of types, relations, and usage patterns. Thus, if you are working with many threads
    ///     (e.g. in a server-like scenario), it can make sense to increase the maximum number of readers.
    ///     Note: The internal default is currently around 120. So when hitting this limit, try values around 200-500.
    ///   - readOnly: Opens the database in read-only mode, i.e. not allowing write transactions.
    ///
    /// - important: This initializer is created by the code generator. If you only see the internal `init(model:...)`
    ///              initializer, trigger code generation by building your project.
    public convenience init(directoryPath: String, maxDbSizeInKByte: UInt64 = 1024 * 1024,
                            fileMode: UInt32 = 0o644, maxReaders: UInt32 = 0, readOnly: Bool = false) throws {
        try self.init(
            model: try cModel(),
            directory: directoryPath,
            maxDbSizeInKByte: maxDbSizeInKByte,
            fileMode: fileMode,
            maxReaders: maxReaders,
            readOnly: readOnly)
    }
}

// swiftlint:enable all
