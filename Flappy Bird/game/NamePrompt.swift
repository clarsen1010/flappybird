//
//  NamePrompt.swift
//  FlappyBird
//
//  The standard iOS alerts the friends leaderboard uses: one with a text
//  field for a player name, a yes/no, and a plain notice. Each calls its
//  completion exactly once, whichever button is tapped.
//
import UIKit

enum NamePrompt {
    enum Answer {
        case text(String), delete, cancel
    }

    /// Asks for a player name. The field only ever holds what a name may
    /// hold (see NameRules.cleaned) and the action button stays off until
    /// the name is long enough.
    static func name(
        title: String,
        message: String,
        text: String = "",
        action: String,
        deleteTitle: String? = nil,
        done: @escaping (Answer) -> Void
    ) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        let save = UIAlertAction(title: action, style: .default) { [weak alert] _ in
            done(.text(alert?.textFields?.first?.text ?? ""))
        }
        save.isEnabled = text.count >= NameRules.minLength

        alert.addTextField { [weak save] field in
            field.text = text
            field.autocapitalizationType = .allCharacters
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            field.smartInsertDeleteType = .no
            field.keyboardType = .asciiCapable
            field.returnKeyType = .done
            field.accessibilityIdentifier = "playerName"

            field.addAction(UIAction { [weak field, weak save] _ in
                guard let field else { return }

                let cleaned = NameRules.cleaned(field.text ?? "")
                if field.text != cleaned {
                    field.text = cleaned
                }
                save?.isEnabled = cleaned.count >= NameRules.minLength
            }, for: .editingChanged)
        }

        alert.addAction(save)
        alert.preferredAction = save

        if let deleteTitle {
            alert.addAction(UIAlertAction(title: deleteTitle, style: .destructive) { _ in done(.delete) })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(.cancel) })
        return alert
    }

    static func confirm(
        title: String,
        message: String,
        action: String,
        done: @escaping (Bool) -> Void
    ) -> UIAlertController {
        UIAlertController(title: title, message: message, preferredStyle: .alert).then {
            $0.addAction(UIAlertAction(title: action, style: .destructive) { _ in done(true) })
            $0.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(false) })
        }
    }

    static func notice(
        title: String,
        message: String,
        done: @escaping () -> Void
    ) -> UIAlertController {
        UIAlertController(title: title, message: message, preferredStyle: .alert).then {
            $0.addAction(UIAlertAction(title: "OK", style: .cancel) { _ in done() })
        }
    }
}
