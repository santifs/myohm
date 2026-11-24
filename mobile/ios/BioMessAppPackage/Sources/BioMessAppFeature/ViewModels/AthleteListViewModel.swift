import Foundation
import SwiftData
import SwiftUI

/// ViewModel for the athlete list screen
/// Manages loading, filtering, selecting, and deleting athletes
@Observable
@MainActor
final class AthleteListViewModel {

    // MARK: - Data Properties

    /// All athletes loaded from the database
    var athletes: [Athlete] = []

    /// ID of the currently active athlete (stored in UserDefaults)
    var activeAthleteId: UUID? {
        didSet {
            if let id = activeAthleteId {
                UserDefaults.standard.set(id.uuidString, forKey: Self.activeAthleteKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.activeAthleteKey)
            }
        }
    }

    // MARK: - State Properties

    /// Whether athletes are currently being loaded
    var isLoading: Bool = false

    /// Whether the athlete wizard sheet is showing
    var showingWizard: Bool = false

    /// Search text for filtering athletes
    var searchText: String = ""

    /// Error message to display
    var errorMessage: String?

    // MARK: - Constants

    private static let activeAthleteKey = "active_athlete_id"

    // MARK: - Computed Properties

    /// The currently active athlete
    var activeAthlete: Athlete? {
        guard let activeId = activeAthleteId else { return nil }
        return athletes.first { $0.id == activeId }
    }

    /// Athletes filtered by search text
    var filteredAthletes: [Athlete] {
        guard !searchText.isEmpty else { return athletes }
        let lowercasedSearch = searchText.lowercased()
        return athletes.filter { athlete in
            athlete.fullName.lowercased().contains(lowercasedSearch)
        }
    }

    /// Athletes that are not the active athlete (for "all athletes" section)
    var nonActiveAthletes: [Athlete] {
        filteredAthletes.filter { $0.id != activeAthleteId }
    }

    /// Whether there are any athletes
    var hasAthletes: Bool {
        !athletes.isEmpty
    }

    /// Whether the active athlete exists and is valid
    var hasActiveAthlete: Bool {
        activeAthlete != nil
    }

    // MARK: - Initialization

    init() {
        // Load active athlete ID from UserDefaults
        if let storedId = UserDefaults.standard.string(forKey: Self.activeAthleteKey),
           let uuid = UUID(uuidString: storedId) {
            self.activeAthleteId = uuid
        }
    }

    // MARK: - Public Methods

    /// Load all athletes from the database
    /// - Parameter context: The SwiftData model context
    func loadAthletes(context: ModelContext) {
        isLoading = true
        defer { isLoading = false }

        do {
            let descriptor = FetchDescriptor<Athlete>(
                sortBy: [SortDescriptor(\.fullName, order: .forward)]
            )
            athletes = try context.fetch(descriptor)

            // Validate that active athlete still exists
            if let activeId = activeAthleteId,
               !athletes.contains(where: { $0.id == activeId }) {
                // Active athlete no longer exists, clear it
                activeAthleteId = nil
            }

            // If no active athlete but we have athletes, select the first one
            if activeAthleteId == nil, let firstAthlete = athletes.first {
                activeAthleteId = firstAthlete.id
            }
        } catch {
            errorMessage = "Error al cargar atletas: \(error.localizedDescription)"
            athletes = []
        }
    }

    /// Set the active athlete for measurements
    /// - Parameter athlete: The athlete to set as active
    func setActiveAthlete(_ athlete: Athlete) {
        withAnimation(.easeInOut(duration: 0.2)) {
            activeAthleteId = athlete.id
        }
    }

    /// Delete an athlete from the database
    /// - Parameters:
    ///   - athlete: The athlete to delete
    ///   - context: The SwiftData model context
    func deleteAthlete(_ athlete: Athlete, context: ModelContext) {
        // If deleting the active athlete, clear the selection
        if athlete.id == activeAthleteId {
            activeAthleteId = nil
        }

        // Remove from local array
        athletes.removeAll { $0.id == athlete.id }

        // Delete from context
        context.delete(athlete)

        // Save changes
        do {
            try context.save()

            // Select a new active athlete if needed
            if activeAthleteId == nil, let firstAthlete = athletes.first {
                activeAthleteId = firstAthlete.id
            }
        } catch {
            errorMessage = "Error al eliminar atleta: \(error.localizedDescription)"
            // Reload to get consistent state
            loadAthletes(context: context)
        }
    }

    /// Handle a newly created athlete
    /// - Parameter athlete: The newly created athlete
    func handleAthleteCreated(_ athlete: Athlete) {
        // Add to local list
        athletes.append(athlete)
        athletes.sort { $0.fullName < $1.fullName }

        // Set as active athlete
        setActiveAthlete(athlete)

        // Dismiss wizard
        showingWizard = false
    }

    /// Clear the search text
    func clearSearch() {
        searchText = ""
    }

    /// Clear any error message
    func clearError() {
        errorMessage = nil
    }
}
