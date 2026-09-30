import Foundation

enum NoteInsertSettings {
    static let templateKey = "note.template"
    static let colorKey = "note.color"
    static let positionKey = "note.position"
    static let sizeKey = "note.size"

    static var template: NoteTemplate {
        NoteTemplate(rawValue: UserDefaults.standard.string(forKey: templateKey) ?? "") ?? .linedCollege
    }

    static var color: NotePaperColor {
        NotePaperColor(rawValue: UserDefaults.standard.string(forKey: colorKey) ?? "") ?? .rice
    }

    static var position: PageIdentity.InsertPosition {
        PageIdentity.InsertPosition(rawValue: UserDefaults.standard.string(forKey: positionKey) ?? "") ?? .after
    }

    static var size: NotePageSize {
        NotePageSize(rawValue: UserDefaults.standard.string(forKey: sizeKey) ?? "") ?? .a4
    }

    static func remember(template: NoteTemplate, color: NotePaperColor, position: PageIdentity.InsertPosition, size: NotePageSize) {
        let defaults = UserDefaults.standard
        defaults.set(template.rawValue, forKey: templateKey)
        defaults.set(color.rawValue, forKey: colorKey)
        defaults.set(position.rawValue, forKey: positionKey)
        defaults.set(size.rawValue, forKey: sizeKey)
    }
}
