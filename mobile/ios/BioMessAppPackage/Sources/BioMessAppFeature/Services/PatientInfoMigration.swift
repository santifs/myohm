import Foundation
import SwiftData

/// Handles migration of legacy PatientInfo data to the new Athlete model
@MainActor
public final class PatientInfoMigration {

    // MARK: - Constants

    /// UserDefaults key to track if migration has been completed
    private static let migrationCompletedKey = "patientinfo_migration_completed_v1"

    /// UserDefaults key where old PatientInfo is stored
    private static let patientInfoStorageKey = "patient_info"

    // MARK: - Migration Status

    /// Check if migration is needed
    /// Returns true if old PatientInfo data exists AND migration hasn't been done
    public static func needsMigration() -> Bool {
        // Check if migration was already completed
        let migrated = UserDefaults.standard.bool(forKey: migrationCompletedKey)
        if migrated { return false }

        // Check if PatientInfo data exists in UserDefaults
        return hasLegacyPatientInfo()
    }

    /// Check if legacy PatientInfo data exists in UserDefaults
    private static func hasLegacyPatientInfo() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: patientInfoStorageKey) else {
            return false
        }

        // Try to decode to verify it's valid data
        guard let patientInfo = try? JSONDecoder().decode(PatientInfo.self, from: data) else {
            return false
        }

        // Only consider it valid if it has at least a name
        return !patientInfo.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Migration

    /// Perform the migration from PatientInfo to Athlete
    /// - Parameter context: The SwiftData ModelContext to insert the new Athlete
    /// - Returns: The migrated Athlete, or nil if migration failed or wasn't needed
    @discardableResult
    public static func migrate(context: ModelContext) -> Athlete? {
        // Load the old PatientInfo
        let oldInfo = PatientInfo()

        // Verify we have valid data to migrate
        guard !oldInfo.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            // Mark as completed even if no data - prevents future attempts
            markMigrationCompleted()
            return nil
        }

        // Create Athlete from old data
        let athlete = Athlete(
            fullName: oldInfo.name.trimmingCharacters(in: .whitespaces),
            dateOfBirth: calculateDateOfBirth(fromAge: oldInfo.age),
            dominantLeg: .right  // Default, user can change later
        )

        // Create initial Anthropometrics if height/weight are available
        let weight = Double(oldInfo.weight)
        let height = Double(oldInfo.height)

        if weight != nil || height != nil {
            let anthropometrics = Anthropometrics(
                athlete: athlete,
                measuredAt: Date(),
                weightKg: weight,
                heightCm: height
            )
            context.insert(anthropometrics)
        }

        // Insert the athlete into SwiftData
        context.insert(athlete)

        // Save the context
        do {
            try context.save()
        } catch {
            print("[PatientInfoMigration] Failed to save context: \(error)")
            return nil
        }

        // Mark migration as complete
        markMigrationCompleted()

        print("[PatientInfoMigration] Successfully migrated PatientInfo '\(oldInfo.name)' to Athlete")

        return athlete
    }

    // MARK: - Private Helpers

    /// Calculate an approximate date of birth from an age string
    /// - Parameter ageString: The age as a string (e.g., "25")
    /// - Returns: An approximate date of birth, or a default date if parsing fails
    private static func calculateDateOfBirth(fromAge ageString: String) -> Date {
        guard let age = Int(ageString), age > 0, age < 150 else {
            // Return a default date (30 years ago) if age is invalid
            return Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
        }

        // Approximate: today minus age years
        // Note: This won't be exact since we don't know the exact birth date
        return Calendar.current.date(byAdding: .year, value: -age, to: Date()) ?? Date()
    }

    /// Mark the migration as completed in UserDefaults
    private static func markMigrationCompleted() {
        UserDefaults.standard.set(true, forKey: migrationCompletedKey)
    }

    // MARK: - Cleanup (Optional)

    /// Clear the old PatientInfo data from UserDefaults
    /// Call this after confirming the migration was successful and the user doesn't need rollback
    public static func clearLegacyData() {
        UserDefaults.standard.removeObject(forKey: patientInfoStorageKey)
        print("[PatientInfoMigration] Cleared legacy PatientInfo data")
    }

    /// Reset migration status (for testing purposes)
    public static func resetMigrationStatus() {
        UserDefaults.standard.removeObject(forKey: migrationCompletedKey)
        print("[PatientInfoMigration] Reset migration status")
    }
}
