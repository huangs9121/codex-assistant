import Foundation
import CodexQuotaCore

enum KeyMappingTests {
    static let source = KeyMappingShortcut(keyCode: 40, flags: KeyboardShortcut.controlFlag)
    static let target = KeyMappingShortcut(keyCode: 8, flags: KeyboardShortcut.commandFlag)
    static var rule: KeyMappingRule { .init(trigger: .shortcut(source), target: target) }
    static var all: [(name: String, run: () -> Bool)] { [
        ("Fn target and modifier gesture are valid while ordinary modifier keys stay invalid", {
            let fn = KeyMappingShortcut(keyCode: 63, flags: 0)
            return fn.isValid && fn.isFunctionKey && fn.displayString.contains("Fn")
                && !KeyMappingTrigger.shortcut(fn).isValid
                && KeyMappingTrigger.modifierTap(keyCodes: [63], tapCount: 1).isValid
                && !KeyMappingShortcut(keyCode: 55, flags: 0).isValid
                && !KeyMappingShortcut(keyCode: 63, flags: KeyboardShortcut.commandFlag).isValid
        }),
        ("multiple mapping rules select the matching source", {
            var engine = KeyMappingEngine()
            let second = KeyMappingRule(trigger: .shortcut(.init(keyCode: 0, flags: 0)), target: .init(keyCode: 11, flags: 0))
            return engine.process(phase: .down, keyCode: 40, flags: source.flags, rules: [second, rule]) == target
                && engine.process(phase: .down, keyCode: 0, flags: 0, rules: [second, rule]) == second.target
        }),
        ("key release and repeats retain the pressed mapping after configuration changes", {
            var engine = KeyMappingEngine()
            guard engine.process(phase: .down, keyCode: 40, flags: source.flags, rules: [rule]) == target else { return false }
            return engine.process(phase: .down, keyCode: 40, flags: 0, isRepeat: true, rules: []) == target
                && engine.process(phase: .up, keyCode: 40, flags: 0, rules: []) == target
                && engine.pressed.isEmpty
        }),
        ("unmatched held keys cannot begin mapping halfway through", {
            var engine = KeyMappingEngine()
            guard engine.process(phase: .down, keyCode: 40, flags: 0, rules: [rule]) == nil,
                  engine.process(phase: .down, keyCode: 40, flags: source.flags, isRepeat: true, rules: [rule]) == nil else { return false }
            _ = engine.process(phase: .up, keyCode: 40, flags: 0, rules: [rule])
            return engine.process(phase: .down, keyCode: 40, flags: source.flags, rules: [rule]) == target
        }),
        ("generated mapped keys bypass chained mappings", {
            var engine = KeyMappingEngine()
            let chain = KeyMappingRule(trigger: .shortcut(target), target: source)
            return engine.process(phase: .down, keyCode: 8, flags: target.flags, isGenerated: true, rules: [chain]) == nil
                && engine.pressed.isEmpty
        }),
        ("disabled and incomplete rows are inert", {
            var engine = KeyMappingEngine(); var disabled = rule; disabled.isEnabled = false
            return engine.process(phase: .down, keyCode: 40, flags: source.flags,
                                  rules: [disabled, .init(trigger: .shortcut(source)), .init()]) == nil
        }),
        ("caps lock and device flags do not change shortcut matching", {
            var engine = KeyMappingEngine()
            return engine.process(phase: .down, keyCode: 40, flags: source.flags | (1 << 16) | 1, rules: [rule]) == target
        }),
        ("overlapping modifier taps and duplicate chords report conflicts", {
            let first = KeyMappingRule(trigger: .modifierTap(keyCodes: [54, 55], tapCount: 2), target: target)
            let overlap = KeyMappingRule(trigger: .modifierTap(keyCodes: [55], tapCount: 1), target: target)
            var disabled = rule; disabled.isEnabled = false
            return KeyMappingRule.conflictingRule(for: overlap, in: [first]) != nil
                && KeyMappingRule.conflictingRule(for: rule, in: [rule]) != nil
                && KeyMappingRule.conflictingRule(for: disabled, in: [rule]) == nil
                && KeyMappingRule.conflictingRule(for: first, in: [first]) == nil
        }),
        ("stop returns every held target exactly once", {
            var engine = KeyMappingEngine()
            _ = engine.process(phase: .down, keyCode: 40, flags: source.flags, rules: [rule])
            return engine.releaseAll() == [target] && engine.releaseAll().isEmpty
                && engine.process(phase: .up, keyCode: 40, flags: 0, rules: [rule]) == nil
        }),
        ("mapping storage round trip preserves gestures and empty rows", {
            let rules = [rule, KeyMappingRule(trigger: .modifierTap(keyCodes: [55], tapCount: 2), target: target, note: "Codex"), .init()]
            guard let data = try? JSONEncoder().encode(rules) else { return false }
            return (try? JSONDecoder().decode([KeyMappingRule].self, from: data)) == rules
        })
    ] }
}
