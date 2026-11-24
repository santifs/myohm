import Foundation

/// Patient information for clinical measurements
@Observable
public final class PatientInfo: Codable, @unchecked Sendable {
    
    // MARK: - Properties

    public var name: String = ""
    public var exerciseName: String = ""
    public var age: String = ""
    public var gender: Gender = .male
    public var height: String = "" // cm
    public var weight: String = "" // kg
    
    // MARK: - Computed Properties
    
    /// Calculate BMI if height and weight are valid
    public var bmi: Float? {
        guard let heightValue = Float(height),
              let weightValue = Float(weight),
              heightValue > 0 else { return nil }
        
        let heightInMeters = heightValue / 100.0
        return weightValue / (heightInMeters * heightInMeters)
    }
    
    /// BMI category description
    public var bmiCategory: String {
        guard let bmi = bmi else { return "Unknown" }
        
        switch bmi {
        case ..<18.5:
            return "Underweight"
        case 18.5..<25.0:
            return "Normal weight"
        case 25.0..<30.0:
            return "Overweight"
        case 30.0...:
            return "Obese"
        default:
            return "Unknown"
        }
    }
    
    /// Age group for clinical context
    public var ageGroup: String {
        guard let ageValue = Int(age) else { return "Unknown" }
        
        switch ageValue {
        case 0..<18:
            return "Pediatric (\(ageValue)y)"
        case 18..<65:
            return "Adult (\(ageValue)y)"
        case 65...:
            return "Senior (\(ageValue)y)"
        default:
            return "Unknown"
        }
    }
    
    /// Check if all required fields are filled
    public var isValid: Bool {
        return !name.trimmingCharacters(in: .whitespaces).isEmpty &&
               !exerciseName.trimmingCharacters(in: .whitespaces).isEmpty &&
               !age.trimmingCharacters(in: .whitespaces).isEmpty &&
               !height.trimmingCharacters(in: .whitespaces).isEmpty &&
               !weight.trimmingCharacters(in: .whitespaces).isEmpty &&
               Int(age) != nil &&
               Float(height) != nil &&
               Float(weight) != nil
    }
    
    // MARK: - Validation
    
    public func validateAge() -> String? {
        guard !age.isEmpty else { return "Age is required" }
        guard let ageValue = Int(age), ageValue > 0, ageValue <= 150 else {
            return "Please enter a valid age (1-150)"
        }
        return nil
    }
    
    public func validateHeight() -> String? {
        guard !height.isEmpty else { return "Height is required" }
        guard let heightValue = Float(height), heightValue > 0, heightValue <= 300 else {
            return "Please enter a valid height in cm (1-300)"
        }
        return nil
    }
    
    public func validateWeight() -> String? {
        guard !weight.isEmpty else { return "Weight is required" }
        guard let weightValue = Float(weight), weightValue > 0, weightValue <= 500 else {
            return "Please enter a valid weight in kg (1-500)"
        }
        return nil
    }
    
    public func validateName() -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return "Name is required" }
        guard trimmedName.count >= 2 else { return "Name must be at least 2 characters" }
        return nil
    }

    public func validateExerciseName() -> String? {
        let trimmedName = exerciseName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return "Exercise name is required" }
        guard trimmedName.count >= 2 else { return "Exercise name must be at least 2 characters" }
        return nil
    }
    
    // MARK: - Persistence
    
    nonisolated(unsafe) private static let userDefaults = UserDefaults.standard
    private static let storageKey = "patient_info"
    
    public init() {
        loadFromStorage()
    }
    
    /// Load patient info from UserDefaults
    public func loadFromStorage() {
        guard let data = Self.userDefaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(PatientInfo.self, from: data) else {
            return // Use default empty values
        }

        self.name = decoded.name
        self.exerciseName = decoded.exerciseName
        self.age = decoded.age
        self.gender = decoded.gender
        self.height = decoded.height
        self.weight = decoded.weight
    }
    
    /// Save patient info to UserDefaults
    public func saveToStorage() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.userDefaults.set(data, forKey: Self.storageKey)
    }
    
    /// Clear all patient data
    public func clearAll() {
        name = ""
        exerciseName = ""
        age = ""
        gender = .male
        height = ""
        weight = ""
        saveToStorage()
    }
    
    /// Create a snapshot for measurement records
    public func snapshot(measurementNumber: Int = 1) -> PatientSnapshot {
        return PatientSnapshot(
            name: name,
            exerciseName: exerciseName,
            measurementNumber: measurementNumber,
            age: Int(age) ?? 0,
            gender: gender,
            height: Float(height) ?? 0,
            weight: Float(weight) ?? 0,
            bmi: bmi ?? 0,
            ageGroup: ageGroup,
            bmiCategory: bmiCategory
        )
    }
}

// MARK: - Gender Enum

public enum Gender: String, Sendable, Codable, CaseIterable {
    case male = "M"
    case female = "F"
    case other = "X"
    
    public var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        }
    }
}

// MARK: - Patient Snapshot for Measurements

/// Immutable snapshot of patient data at measurement time
public struct PatientSnapshot: Sendable, Codable, Equatable {
    public let name: String
    public let exerciseName: String
    public let measurementNumber: Int
    public let age: Int
    public let gender: Gender
    public let height: Float // cm
    public let weight: Float // kg
    public let bmi: Float
    public let ageGroup: String
    public let bmiCategory: String
    public let timestamp: Date

    public var displayName: String {
        return "\(name) - \(exerciseName) \(measurementNumber)"
    }

    public init(name: String, exerciseName: String, measurementNumber: Int, age: Int, gender: Gender, height: Float, weight: Float, bmi: Float, ageGroup: String, bmiCategory: String) {
        self.name = name
        self.exerciseName = exerciseName
        self.measurementNumber = measurementNumber
        self.age = age
        self.gender = gender
        self.height = height
        self.weight = weight
        self.bmi = bmi
        self.ageGroup = ageGroup
        self.bmiCategory = bmiCategory
        self.timestamp = Date()
    }
}