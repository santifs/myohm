import Testing
import SwiftData
import Foundation
@testable import BioMessAppFeature

@Suite("SessionLookup")
struct SessionLookupTests {
    @MainActor
    @Test func findsRecentMatchingSession() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Athlete.self, MeasurementSession.self, Measurement.self,
            configurations: config
        )
        let ctx = container.mainContext

        let athlete = Athlete(fullName: "Test", dateOfBirth: Date())
        ctx.insert(athlete)

        let now = Date()
        let recent = MeasurementSession(
            athlete: athlete,
            startedAt: now.addingTimeInterval(-30 * 60),  // 30 min atrás
            sessionType: "basal",
            studyId: "biceps_tfg"
        )
        ctx.insert(recent)
        try ctx.save()

        let found = try SessionLookup.findRecentSession(
            athleteId: athlete.id,
            studyId: "biceps_tfg",
            sessionType: "basal",
            since: now.addingTimeInterval(-2 * 3600),
            in: ctx
        )
        #expect(found?.id == recent.id)
    }

    @MainActor
    @Test func ignoresSessionsOlderThanWindow() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Athlete.self, MeasurementSession.self, Measurement.self,
            configurations: config
        )
        let ctx = container.mainContext

        let athlete = Athlete(fullName: "Test", dateOfBirth: Date())
        ctx.insert(athlete)

        let now = Date()
        let stale = MeasurementSession(
            athlete: athlete,
            startedAt: now.addingTimeInterval(-3 * 3600),  // 3h atrás
            sessionType: "basal",
            studyId: "biceps_tfg"
        )
        ctx.insert(stale)
        try ctx.save()

        let found = try SessionLookup.findRecentSession(
            athleteId: athlete.id,
            studyId: "biceps_tfg",
            sessionType: "basal",
            since: now.addingTimeInterval(-2 * 3600),
            in: ctx
        )
        #expect(found == nil)
    }

    @MainActor
    @Test func ignoresDifferentSessionType() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Athlete.self, MeasurementSession.self, Measurement.self,
            configurations: config
        )
        let ctx = container.mainContext

        let athlete = Athlete(fullName: "Test", dateOfBirth: Date())
        ctx.insert(athlete)
        let now = Date()
        ctx.insert(MeasurementSession(
            athlete: athlete,
            startedAt: now,
            sessionType: "post_serie_1",
            studyId: "biceps_tfg"
        ))
        try ctx.save()

        let found = try SessionLookup.findRecentSession(
            athleteId: athlete.id,
            studyId: "biceps_tfg",
            sessionType: "basal",
            since: now.addingTimeInterval(-3600),
            in: ctx
        )
        #expect(found == nil)
    }

    @MainActor
    @Test func ignoresDifferentAthlete() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Athlete.self, MeasurementSession.self, Measurement.self,
            configurations: config
        )
        let ctx = container.mainContext

        let athleteA = Athlete(fullName: "A", dateOfBirth: Date())
        let athleteB = Athlete(fullName: "B", dateOfBirth: Date())
        ctx.insert(athleteA)
        ctx.insert(athleteB)

        let now = Date()
        ctx.insert(MeasurementSession(
            athlete: athleteA,
            startedAt: now,
            sessionType: "basal",
            studyId: "biceps_tfg"
        ))
        try ctx.save()

        // Querying B should NOT find A's session
        let found = try SessionLookup.findRecentSession(
            athleteId: athleteB.id,
            studyId: "biceps_tfg",
            sessionType: "basal",
            since: now.addingTimeInterval(-3600),
            in: ctx
        )
        #expect(found == nil)
    }

    @MainActor
    @Test func ignoresDifferentStudy() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Athlete.self, MeasurementSession.self, Measurement.self,
            configurations: config
        )
        let ctx = container.mainContext

        let athlete = Athlete(fullName: "Test", dateOfBirth: Date())
        ctx.insert(athlete)

        let now = Date()
        ctx.insert(MeasurementSession(
            athlete: athlete,
            startedAt: now,
            sessionType: "basal",
            studyId: "biceps_tfg"
        ))
        try ctx.save()

        // Querying same athlete + sessionType but different study should NOT match
        let found = try SessionLookup.findRecentSession(
            athleteId: athlete.id,
            studyId: "sentadilla_tfm",
            sessionType: "basal",
            since: now.addingTimeInterval(-3600),
            in: ctx
        )
        #expect(found == nil)
    }
}
