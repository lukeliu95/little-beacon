import Foundation

public extension RuleSet {
    func acceptingRemote(_ remote: RuleSet) -> RuleSet {
        remote.revision >= revision ? remote : self
    }
}
