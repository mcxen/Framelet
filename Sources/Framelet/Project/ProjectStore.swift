import Foundation

struct ProjectStore: Sendable {
    let fileExtension = "frameletproject"

    func load(from url: URL) throws -> EditingProject {
        let data = try Data(contentsOf: url)
        var project = try JSONDecoder.framelet.decode(EditingProject.self, from: data)
        project = try ProjectMigration.migrate(project)
        return project
    }

    func save(_ project: EditingProject, to url: URL) throws {
        var copy = project
        copy.modifiedAt = Date()
        let data = try JSONEncoder.framelet.encode(copy)
        try data.write(to: url, options: [.atomic])
    }
}

enum ProjectMigration {
    static func migrate(_ project: EditingProject) throws -> EditingProject {
        project
    }
}

extension JSONEncoder {
    static var framelet: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var framelet: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
