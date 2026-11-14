import Foundation
import Observation

enum OnboardingStep: Int, CaseIterable {
    case welcome, permission, practice, profiles, ready, shortcuts

    static let allCases: [Self] = [.welcome, .permission, .shortcuts, .practice, .profiles, .ready]
    var position: Int { Self.allCases.firstIndex(of: self)! }

    var name: String {
        switch self {
        case .welcome: "Welcome"
        case .permission: "Accessibility"
        case .shortcuts: "Shortcuts"
        case .practice: "Try it"
        case .profiles: "Saved details"
        case .ready: "Ready"
        }
    }
}

@Observable
@MainActor
final class OnboardingProgress {
    private(set) var step: OnboardingStep
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        step = OnboardingStep(rawValue: defaults.integer(forKey: "onboardingStep")) ?? .welcome
    }

    func move(to step: OnboardingStep) {
        self.step = step
        defaults.set(step.rawValue, forKey: "onboardingStep")
    }

    func reconcilePermission(_ granted: Bool, shortcutsReady: Bool) {
        let ready = granted && shortcutsReady
        if !ready && step.position > OnboardingStep.permission.position {
            move(to: .permission)
        } else if ready && step == .permission {
            move(to: .shortcuts)
        }
    }

    func advance(hasPermission: Bool, shortcutsReady: Bool) {
        guard step != .ready else { return }
        let next = OnboardingStep.allCases[step.position + 1]
        let ready = hasPermission && shortcutsReady
        move(to: !ready && next.position > OnboardingStep.permission.position ? .permission : next)
        if ready && step == .permission { move(to: .shortcuts) }
    }

    func back(hasPermission: Bool) {
        guard step != .welcome else { return }
        let previous = OnboardingStep.allCases[step.position - 1]
        move(to: previous == .permission && hasPermission ? .welcome : previous)
    }
}
