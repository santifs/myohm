import Foundation
import SwiftData
import SwiftUI

/// Represents the current state of the measurement flow
enum MeasurementFlowState: Equatable {
    case needsAthlete          // No active athlete selected
    case needsSession          // Has athlete but no session started
    case selectingMuscle       // In muscle selection phase
    case measuring             // Actively taking a measurement
    case sessionSummary        // Session complete, showing summary
}

/// Stores data about a completed muscle measurement within a session
struct MuscleMeasurement: Identifiable, Equatable {
    let id: UUID
    let target: MuscleTarget
    let perceivedFatigue: Int
    let timestamp: Date
    let measurementId: UUID?  // Reference to the raw measurement in history

    init(
        id: UUID = UUID(),
        target: MuscleTarget,
        perceivedFatigue: Int,
        timestamp: Date = Date(),
        measurementId: UUID? = nil
    ) {
        self.id = id
        self.target = target
        self.perceivedFatigue = perceivedFatigue
        self.timestamp = timestamp
        self.measurementId = measurementId
    }
}

/// ViewModel that manages the entire measurement flow
/// Coordinates athlete selection, session creation, muscle selection, and measurements
@Observable
@MainActor
final class MeasurementFlowViewModel {

    // MARK: - State Properties

    /// Current state of the measurement flow
    var flowState: MeasurementFlowState = .needsAthlete

    /// The currently active athlete
    var activeAthlete: Athlete?

    /// The current measurement session
    var currentSession: MeasurementSession?

    /// Currently selected muscle target
    var selectedMuscle: MuscleTarget?

    /// Perceived fatigue for the currently selected muscle (0-10)
    var currentMuscleFatigue: Int = 5

    /// All completed muscle measurements in this session
    var completedMeasurements: [MuscleMeasurement] = []

    /// Error message to display
    var errorMessage: String?

    /// Whether the pre-session form is being shown
    var showingPreSessionForm: Bool = false

    /// Whether athlete list is being shown
    var showingAthleteList: Bool = false

    /// Session type: "basal" or "match"
    var sessionType: String?

    // MARK: - Study state

    /// Active study (set by the View via `setActiveStudy`).
    /// `nil` means the legacy basal/match flow is in effect.
    private(set) var activeStudy: Study?

    /// Operator-entered or chip-picked session phase.
    /// Stored raw — normalized via `SessionTypeNormalizer` at lookup/save time.
    /// Touching this triggers an async refresh of `resumableSessionId`.
    var sessionTypeLabel: String = "" {
        didSet {
            refreshResumableTask?.cancel()
            refreshResumableTask = Task { [weak self] in await self?.refreshResumable() }
        }
    }

    /// Tracks the latest in-flight `refreshResumable` Task so a fresh
    /// trigger (typing or `setActiveStudy`) can cancel the previous one
    /// — prevents a slow fetch from overwriting a fresher result.
    private var refreshResumableTask: Task<Void, Never>?

    /// If non-nil, tapping "Medir" reuses this existing session
    /// (matching `(athlete, study, sessionType)` within the last 2h)
    /// instead of creating a new one.
    private(set) var resumableSessionId: UUID?

    /// Number of measurements already in the resumable session
    /// (shown by the View as "ya tiene N mediciones").
    private(set) var resumableMeasurementCount: Int = 0

    /// Set synchronously while `startProtocolSession` is running so a
    /// rapid double-tap on "Medir" can't create two sessions back to back.
    /// Cleared via `defer` in all exit paths.
    private(set) var isStartingSession: Bool = false

    /// In-flight save task tracked so cleanup-on-exit can await it
    /// before counting measurements.
    private var saveTask: Task<Void, Error>?

    /// Tracks the active session id for cleanup-on-exit
    /// (separate from `currentSession` because we need it after
    /// `currentSession` may have been cleared).
    private var activeSessionId: UUID?

    // MARK: - ViewModel dependencies

    /// Pre-session form view model
    var preSessionFormViewModel: PreSessionFormViewModel?

    // MARK: - Computed Properties

    /// Set of completed muscle targets
    var completedMuscleTargets: Set<MuscleTarget> {
        Set(completedMeasurements.map { $0.target })
    }

    /// Whether all muscles have been measured
    var isSessionComplete: Bool {
        completedMuscleTargets.count == MuscleTarget.allTargets.count
    }

    /// Summary of the current session
    var sessionSummary: String {
        guard !completedMeasurements.isEmpty else {
            return "Sin mediciones"
        }

        let muscleCount = completedMeasurements.count
        let avgFatigue = Double(completedMeasurements.map { $0.perceivedFatigue }.reduce(0, +)) / Double(muscleCount)

        return "\(muscleCount) mediciones | Fatiga promedio: \(String(format: "%.1f", avgFatigue))/10"
    }

    /// Display name of active athlete
    var athleteDisplayName: String {
        activeAthlete?.displayName ?? "No seleccionado"
    }

    /// Whether we have an active athlete
    var hasActiveAthlete: Bool {
        activeAthlete != nil
    }

    /// Whether we have an active session
    var hasActiveSession: Bool {
        currentSession != nil
    }

    /// Dominant side derived from athlete's dominant leg
    var dominantSide: BodySide {
        guard let athlete = activeAthlete else { return .right }
        switch athlete.dominantLeg {
        case .right:
            return .right
        case .left:
            return .left
        case .ambidextrous:
            return .right  // Default to right for experiment
        }
    }

    // MARK: - Context for MeasurementView

    /// Current session ID (to pass to MeasurementView for saving)
    var currentSessionId: UUID? {
        currentSession?.id
    }

    /// Current muscle group name (to pass to MeasurementView for saving)
    var currentMuscleGroup: String? {
        selectedMuscle?.muscle.rawValue
    }

    /// Current side (to pass to MeasurementView for saving)
    var currentSide: String? {
        selectedMuscle?.side.rawValue
    }

    /// Current perceived fatigue for the selected muscle
    var currentPerceivedFatigue: Int {
        currentMuscleFatigue
    }

    // MARK: - Private Properties

    private static let activeAthleteKey = "active_athlete_id"
    private var modelContext: ModelContext?

    // MARK: - Initialization

    init() {
        // Flow state will be determined by loadActiveAthlete
    }

    /// Set the model context for SwiftData persistence
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Public Methods

    /// Initialize the flow state based on current data
    /// - Parameter context: The SwiftData model context
    func initialize(context: ModelContext) {
        self.modelContext = context
        loadActiveAthlete(context: context)
        updateFlowState()
    }

    /// Load the active athlete from storage
    /// - Parameter context: The SwiftData model context
    func loadActiveAthlete(context: ModelContext) {
        guard let storedId = UserDefaults.standard.string(forKey: Self.activeAthleteKey),
              let uuid = UUID(uuidString: storedId) else {
            activeAthlete = nil
            return
        }

        // Fetch the athlete
        let descriptor = FetchDescriptor<Athlete>(
            predicate: #Predicate { $0.id == uuid }
        )

        do {
            let athletes = try context.fetch(descriptor)
            activeAthlete = athletes.first
        } catch {
            print("Error loading active athlete: \(error)")
            activeAthlete = nil
        }
    }

    /// Set a new active athlete
    /// - Parameter athlete: The athlete to set as active
    func setActiveAthlete(_ athlete: Athlete) {
        activeAthlete = athlete
        UserDefaults.standard.set(athlete.id.uuidString, forKey: Self.activeAthleteKey)

        // Reset session state since athlete changed
        resetSession()
        updateFlowState()
    }

    /// Clear the active athlete selection
    func clearActiveAthlete() {
        activeAthlete = nil
        UserDefaults.standard.removeObject(forKey: Self.activeAthleteKey)
        resetSession()
        updateFlowState()
    }

    /// Start a basal (at-home, single measurement) session
    func startBasalSession() {
        guard let athlete = activeAthlete else { return }
        sessionType = "basal"
        preSessionFormViewModel = PreSessionFormViewModel(athlete: athlete, sessionType: "basal")
        preSessionFormViewModel?.prefillFromAthlete()
        showingPreSessionForm = true
    }

    /// Start a match (multi-measurement) session
    func startMatchSession() {
        guard let athlete = activeAthlete else { return }
        sessionType = "match"
        preSessionFormViewModel = PreSessionFormViewModel(athlete: athlete, sessionType: "match")
        preSessionFormViewModel?.prefillFromAthlete()
        showingPreSessionForm = true
    }

    /// Handle session creation from the pre-session form
    /// Auto-selects quadriceps + dominant side and goes directly to measuring
    func handleSessionCreated(_ session: MeasurementSession) {
        currentSession = session
        showingPreSessionForm = false

        // Auto-select quadriceps on dominant side - skip muscle/side selection
        selectedMuscle = MuscleTarget(muscle: .quadriceps, side: dominantSide)
        currentMuscleFatigue = session.generalFatigue ?? 5
        flowState = .measuring
    }

    /// Select a muscle for measurement
    /// - Parameter target: The muscle target to select
    func selectMuscle(_ target: MuscleTarget?) {
        selectedMuscle = target
    }

    /// Start measuring the currently selected muscle
    func startMeasurement() {
        guard selectedMuscle != nil else { return }
        flowState = .measuring
    }

    /// Complete a measurement for the current muscle
    /// For basal sessions: auto-finishes after the first measurement
    /// For match sessions: stays on results so user can choose "Tomar Otra Medición" or "Finalizar Sesión"
    func completeMeasurement(measurementId: UUID?) {
        guard let target = selectedMuscle else { return }

        // Create in-memory measurement for UI tracking
        let muscleMeasurement = MuscleMeasurement(
            target: target,
            perceivedFatigue: currentMuscleFatigue,
            measurementId: measurementId
        )

        completedMeasurements.append(muscleMeasurement)

        // For basal sessions, auto-finish after the first measurement
        if sessionType == "basal" {
            flowState = .sessionSummary
            return
        }

        // Note: Measurement is already saved to SwiftData by MeasurementView
        // We just track the completion for UI purposes
        // Do NOT change flowState - let MeasurementView show results
        // User will tap "Tomar Otra Medición" (stays in .measuring) or "Finalizar Sesión"
    }

    /// Cancel the current measurement and go back to muscle selection
    func cancelMeasurement() {
        flowState = .selectingMuscle
    }

    /// Finish the current session and show summary
    func finishCurrentSession() {
        flowState = .sessionSummary
    }

    /// Finish the session early (before all muscles measured)
    func finishSessionEarly() {
        flowState = .sessionSummary
    }

    /// Start a new session (reset current state)
    func startNewSession() {
        resetSession()
        updateFlowState()
    }

    /// Show the athlete selection list
    func showAthleteSelection() {
        showingAthleteList = true
    }

    /// Hide the athlete selection list
    func hideAthleteSelection() {
        showingAthleteList = false
    }

    /// Clear any error message
    func clearError() {
        errorMessage = nil
    }

    // MARK: - Protocol Flow

    /// Configure the active study (called by the View on appear /
    /// when the user changes the active study in Settings).
    /// Resets muscle/side selection to the protocol's defaults and
    /// re-evaluates whether there's a recent session to resume.
    func setActiveStudy(_ study: Study?) {
        activeStudy = study
        refreshResumableTask?.cancel()
        refreshResumableTask = Task { [weak self] in await self?.refreshResumable() }
    }

    /// Tap a suggestion chip — fills the label.
    /// The `didSet` on `sessionTypeLabel` triggers `refreshResumable`.
    func pickSessionTypeSuggestion(_ suggestion: String) {
        sessionTypeLabel = suggestion
    }

    /// Start a protocol-driven session: reuse a recent matching session
    /// if one exists (within 2h), otherwise create a new one. Skips the
    /// questionnaire (PreSessionFormView) entirely. If the active Study
    /// declares exactly one muscle and one side, jumps straight to
    /// `.measuring` with that target preselected; otherwise jumps to
    /// `.selectingMuscle`.
    func startProtocolSession() {
        guard !isStartingSession else { return }  // double-tap guard
        isStartingSession = true
        defer { isStartingSession = false }

        guard
            let context = modelContext,
            let athlete = activeAthlete,
            let study = activeStudy
        else {
            errorMessage = "Configura un atleta y un estudio antes de medir."
            return
        }
        guard let normalizedSessionType = SessionTypeNormalizer.normalize(sessionTypeLabel) else {
            errorMessage = "Selecciona o escribe la fase del protocolo."
            return
        }

        do {
            let cutoff = Date().addingTimeInterval(-2 * 3600)
            let session: MeasurementSession
            if let existing = try SessionLookup.findRecentSession(
                athleteId: athlete.id,
                studyId: study.rawValue,
                sessionType: normalizedSessionType,
                since: cutoff,
                in: context
            ) {
                session = existing
            } else {
                session = MeasurementSession(
                    athlete: athlete,
                    startedAt: Date(),
                    sessionType: normalizedSessionType,
                    studyId: study.rawValue
                )
                context.insert(session)
                try context.save()
            }
            currentSession = session
            activeSessionId = session.id
            sessionType = normalizedSessionType  // mantener el campo legacy para UI
            currentMuscleFatigue = 5

            // Skip muscle/side picker if the protocol has only one of each.
            if study.muscleGroups.count == 1 && study.sides.count == 1 {
                let muscle = study.muscleGroups[0]
                let side = study.sides[0]
                selectedMuscle = MuscleTarget(muscle: muscle, side: side)
                flowState = .measuring
            } else {
                flowState = .selectingMuscle
            }
        } catch {
            errorMessage = "Error al iniciar sesión: \(error.localizedDescription)"
        }
    }

    /// Track a save task so `cleanupIfEmpty` waits for it to finish before
    /// counting measurements. Fixes the cleanup race that bit us in Android:
    /// `confirmFatigue` may have launched a save Task that hasn't completed
    /// when the user backs out of the measurement screen.
    func registerSaveTask(_ task: Task<Void, Error>) {
        saveTask = task
    }

    /// If the active session has zero measurements, delete it.
    /// Awaits any pending save task before counting so we don't leave
    /// empty sessions behind when the operator cancels mid-save.
    func cleanupIfEmpty() async {
        guard
            let context = modelContext,
            let sessionId = activeSessionId
        else { return }

        _ = try? await saveTask?.value  // wait for in-flight save

        do {
            let count = try SessionLookup.measurementCount(sessionId: sessionId, in: context)
            guard count == 0 else {
                activeSessionId = nil
                return
            }

            let predicate = #Predicate<MeasurementSession> { $0.id == sessionId }
            let descriptor = FetchDescriptor<MeasurementSession>(predicate: predicate)
            if let session = try context.fetch(descriptor).first {
                context.delete(session)
                try context.save()
                print("Cleaned up empty session \(sessionId)")
            }
        } catch {
            print("cleanupIfEmpty failed: \(error)")
        }

        activeSessionId = nil
    }

    /// Compute and publish whether there's a session within the last 2h
    /// matching `(athlete, study, normalized session type)`. Triggered by
    /// the `didSet` on `sessionTypeLabel` and by `setActiveStudy`.
    @MainActor
    private func refreshResumable() async {
        guard
            let context = modelContext,
            let athleteId = activeAthlete?.id,
            let study = activeStudy,
            let sessionType = SessionTypeNormalizer.normalize(sessionTypeLabel)
        else {
            resumableSessionId = nil
            resumableMeasurementCount = 0
            return
        }
        let cutoff = Date().addingTimeInterval(-2 * 3600)
        do {
            let existing = try SessionLookup.findRecentSession(
                athleteId: athleteId,
                studyId: study.rawValue,
                sessionType: sessionType,
                since: cutoff,
                in: context
            )
            let count: Int
            if let existing {
                count = try SessionLookup.measurementCount(
                    sessionId: existing.id,
                    in: context
                )
            } else {
                count = 0
            }
            // A newer trigger superseded this Task — drop the result so
            // we don't overwrite the latest state with stale data.
            if Task.isCancelled { return }
            resumableSessionId = existing?.id
            resumableMeasurementCount = count
        } catch {
            if Task.isCancelled { return }
            resumableSessionId = nil
            resumableMeasurementCount = 0
        }
    }

    // MARK: - Private Methods

    /// Update the flow state based on current data
    private func updateFlowState() {
        if activeAthlete == nil {
            flowState = .needsAthlete
        } else if currentSession == nil {
            flowState = .needsSession
        } else if completedMeasurements.isEmpty && flowState != .measuring {
            flowState = .selectingMuscle
        } else if flowState != .measuring && flowState != .sessionSummary {
            flowState = .selectingMuscle
        }
    }

    /// Reset the current session state.
    /// Note: `activeStudy` is intentionally NOT cleared here — it's app-wide
    /// state set via `setActiveStudy` and survives session boundaries.
    private func resetSession() {
        currentSession = nil
        selectedMuscle = nil
        currentMuscleFatigue = 5
        completedMeasurements = []
        preSessionFormViewModel = nil
        sessionType = nil
        sessionTypeLabel = ""
        resumableSessionId = nil
        resumableMeasurementCount = 0
        activeSessionId = nil
        saveTask = nil
    }
}

// MARK: - Extension for MeasurementSession Linking

extension MeasurementFlowViewModel {

    /// Get all measurement data for export or analysis
    var sessionMeasurementData: [(target: MuscleTarget, fatigue: Int, timestamp: Date)] {
        completedMeasurements.map { ($0.target, $0.perceivedFatigue, $0.timestamp) }
    }

    /// Summary statistics for the session
    var sessionStatistics: SessionStatistics? {
        guard !completedMeasurements.isEmpty else { return nil }

        let fatigueValues = completedMeasurements.map { $0.perceivedFatigue }
        let avgFatigue = Double(fatigueValues.reduce(0, +)) / Double(fatigueValues.count)
        let maxFatigue = fatigueValues.max() ?? 0
        let minFatigue = fatigueValues.min() ?? 0

        // Calculate bilateral differences
        var bilateralDifferences: [MuscleGroup: Int] = [:]
        for muscle in MuscleGroup.allCases {
            let leftFatigue = completedMeasurements
                .first { $0.target.muscle == muscle && $0.target.side == .left }?
                .perceivedFatigue
            let rightFatigue = completedMeasurements
                .first { $0.target.muscle == muscle && $0.target.side == .right }?
                .perceivedFatigue

            if let left = leftFatigue, let right = rightFatigue {
                bilateralDifferences[muscle] = abs(left - right)
            }
        }

        return SessionStatistics(
            totalMeasurements: completedMeasurements.count,
            averageFatigue: avgFatigue,
            maxFatigue: maxFatigue,
            minFatigue: minFatigue,
            bilateralDifferences: bilateralDifferences,
            sessionDuration: sessionDuration
        )
    }

    /// Duration of the session
    private var sessionDuration: TimeInterval {
        guard let firstMeasurement = completedMeasurements.first,
              let lastMeasurement = completedMeasurements.last else {
            return 0
        }
        return lastMeasurement.timestamp.timeIntervalSince(firstMeasurement.timestamp)
    }
}

/// Statistics for a completed measurement session
struct SessionStatistics {
    let totalMeasurements: Int
    let averageFatigue: Double
    let maxFatigue: Int
    let minFatigue: Int
    let bilateralDifferences: [MuscleGroup: Int]
    let sessionDuration: TimeInterval

    var formattedDuration: String {
        let minutes = Int(sessionDuration / 60)
        let seconds = Int(sessionDuration.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }

    var fatigueLevel: String {
        switch averageFatigue {
        case 0...3: return "Baja"
        case 4...6: return "Moderada"
        case 7...10: return "Alta"
        default: return "---"
        }
    }

    var hasBilateralImbalance: Bool {
        bilateralDifferences.values.contains { $0 >= 3 }
    }

    var imbalanceWarnings: [String] {
        bilateralDifferences.compactMap { muscle, diff in
            if diff >= 3 {
                return "\(muscle.displayName): diferencia de \(diff) puntos"
            }
            return nil
        }
    }
}
