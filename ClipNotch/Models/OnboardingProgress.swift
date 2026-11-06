import Foundation
import Observation

enum OnboardingStep: Int, CaseIterable {
    case welcome, permission, practice, profiles, ready

    var name: String {
        switch self {
        case .welcome: "Welcome"
        case .permission: "Accessibility"
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
        if !ready && step.rawValue > OnboardingStep.permission.rawValue {
            move(to: .permission)
        } else if ready && step == .permission {
            move(to: .practice)
        }
    }

    func advance(hasPermission: Bool, shortcutsReady: Bool) {
        guard step != .ready else { return }
        let next = OnboardingStep(rawValue: step.rawValue + 1)!
        let ready = hasPermission && shortcutsReady
        move(to: !ready && next.rawValue > OnboardingStep.permission.rawValue ? .permission : next)
        if ready && step == .permission { move(to: .practice) }
    }

    func back(hasPermission: Bool) {
        guard step != .welcome else { return }
        let previous = OnboardingStep(rawValue: step.rawValue - 1)!
        move(to: previous == .permission && hasPermission ? .welcome : previous)
    }
}
