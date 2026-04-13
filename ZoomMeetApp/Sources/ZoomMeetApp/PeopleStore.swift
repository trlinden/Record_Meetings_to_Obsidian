import Foundation

struct PeopleStore {
    struct Person {
        let shortName: String
        let fullName: String
    }

    let people: [Person]

    init(filePath: String) {
        guard let contents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            people = []
            return
        }
        people = contents.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.components(separatedBy: " ")
            let shortName = parts[0]
            return Person(shortName: shortName, fullName: trimmed)
        }
    }

    func suggestions(for prefix: String) -> [String] {
        guard !prefix.isEmpty else { return [] }
        let lower = prefix.lowercased()
        return people
            .filter { $0.shortName.lowercased().hasPrefix(lower) }
            .map { $0.shortName }
    }
}
