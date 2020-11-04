import Foundation

class ExPlat: ABTesting {
    let service: ExPlatService

    init(service: ExPlatService = ExPlatService.withDefaultApi()) {
        self.service = service
    }

    func refresh(completion: (() -> Void)? = nil) {
        service.getAssignments { assignments in
            guard let assignments = assignments else {
                completion?()
                return
            }

            UserDefaults.standard.setValue(assignments.variations, forKey: "ab-testing-assignments")
            completion?()
        }
    }

    func experiment(_ name: String) -> String? {
        guard let assignments = UserDefaults.standard.object(forKey: "ab-testing-assignments") as? [String: String?] else {
            return nil
        }

        return assignments[name] ?? nil
    }
}
