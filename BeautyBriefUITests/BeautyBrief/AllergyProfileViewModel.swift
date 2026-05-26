import SwiftUI
import Combine

// ─────────────────────────────────────────────
//  AllergyProfileViewModel
//  Persists user allergy profile via UserDefaults
// ─────────────────────────────────────────────

@MainActor
final class AllergyProfileViewModel: ObservableObject {

    @Published var profile: AllergyProfile {
        didSet { save() }
    }

    private let storageKey = "beautybrief.allergyprofile.v2"

    init() {
        // 1. Try current (v2) storage first — the normal path for returning users.
        if let data = UserDefaults.standard.data(forKey: "beautybrief.allergyprofile.v2"),
           let saved = try? JSONDecoder().decode(AllergyProfile.self, from: data) {
            profile = saved
        }
        // 2. Migrate from v1 — first launch after app update from an older version.
        //    Re-encode to v2 and delete v1 so future launches take the fast path above.
        else if let data = UserDefaults.standard.data(forKey: "beautybrief.allergyprofile.v1"),
                let saved = try? JSONDecoder().decode(AllergyProfile.self, from: data) {
            profile = saved
            if let migrated = try? JSONEncoder().encode(saved) {
                UserDefaults.standard.set(migrated, forKey: "beautybrief.allergyprofile.v2")
                UserDefaults.standard.removeObject(forKey: "beautybrief.allergyprofile.v1")
            }
        }
        // 3. Fresh install — start with an empty profile.
        else {
            profile = AllergyProfile()
        }
    }

    // MARK: — Allergen management
    func toggleAllergen(_ allergen: KnownAllergen) {
        if profile.allergens.contains(allergen) {
            profile.allergens.remove(allergen)
        } else {
            profile.allergens.insert(allergen)
            profile.sensitivities.remove(allergen) // can't be both
        }
        profile.lastUpdated = .now
    }

    func toggleSensitivity(_ allergen: KnownAllergen) {
        if profile.sensitivities.contains(allergen) {
            profile.sensitivities.remove(allergen)
        } else {
            profile.sensitivities.insert(allergen)
            profile.allergens.remove(allergen)     // can't be both
        }
        profile.lastUpdated = .now
    }

    func toggleSkinType(_ type: SkinType) {
        if profile.skinTypes.contains(type) {
            profile.skinTypes.remove(type)
        } else {
            profile.skinTypes.insert(type)
        }
        profile.lastUpdated = .now
    }

    func toggleConcern(_ concern: SkinConcern) {
        if profile.skinConcerns.contains(concern) {
            profile.skinConcerns.remove(concern)
        } else {
            profile.skinConcerns.insert(concern)
        }
        profile.lastUpdated = .now
    }

    // MARK: — Lifestyle preferences
    func toggleLifestyle(_ pref: LifestylePreference) {
        if profile.lifestylePreferences.contains(pref) {
            profile.lifestylePreferences.remove(pref)
        } else {
            profile.lifestylePreferences.insert(pref)
        }
        profile.lastUpdated = .now
    }

    // MARK: — Personal details
    func updateName(_ name: String) {
        profile.name = name
        profile.lastUpdated = .now
    }

    // MARK: — Health modes
    func togglePregnancyMode() {
        profile.pregnancyMode.toggle()
        profile.lastUpdated = .now
    }

    func toggleBreastfeedingMode() {
        profile.breastfeedingMode.toggle()
        profile.lastUpdated = .now
    }

    // MARK: — Ingredient blacklist
    func addToBlacklist(_ ingredient: String) {
        let normalised = ingredient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalised.isEmpty, !profile.blacklistedIngredients.contains(normalised) else { return }
        profile.blacklistedIngredients.append(normalised)
        profile.lastUpdated = .now
    }

    func removeFromBlacklist(_ ingredient: String) {
        profile.blacklistedIngredients.removeAll { $0 == ingredient }
        profile.lastUpdated = .now
    }

    // MARK: — Computed helpers
    var allergenCount: Int { profile.allergens.count }
    var sensitivityCount: Int { profile.sensitivities.count }
    var hasProfile: Bool {
        allergenCount > 0 ||
        sensitivityCount > 0 ||
        !profile.lifestylePreferences.isEmpty ||
        !profile.skinConcerns.isEmpty ||
        profile.pregnancyMode ||
        profile.breastfeedingMode ||
        !profile.blacklistedIngredients.isEmpty
    }

    // MARK: — Allergen status helpers
    func status(for allergen: KnownAllergen) -> AllergenStatus {
        if profile.allergens.contains(allergen)     { return .allergen }
        if profile.sensitivities.contains(allergen) { return .sensitivity }
        return .none
    }

    enum AllergenStatus {
        case allergen, sensitivity, none
    }

    // MARK: — Persistence
    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func clearAll() {
        profile = AllergyProfile()
        // lastUpdated reset handled by AllergyProfile.init()
    }
}

#if DEBUG
extension AllergyProfileViewModel {
    static var preview: AllergyProfileViewModel {
        let vm = AllergyProfileViewModel()
        vm.profile.name = "Sarah"
        vm.profile.allergens = [.fragrance, .parabens]
        vm.profile.sensitivities = [.sulfates]
        vm.profile.skinTypes = [.sensitive]
        vm.profile.skinConcerns = [.eczema, .rosacea]
        vm.profile.lifestylePreferences = [.vegan, .crueltyFree]
        vm.profile.pregnancyMode = false
        return vm
    }
}
#endif
