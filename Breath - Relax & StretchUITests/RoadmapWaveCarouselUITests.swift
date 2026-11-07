import XCTest

/// Task 4 (manual verification) of docs/superpowers/plans/2026-08-14-roadmap-wave-carousel.md.
/// Screenshot pass, not behavior assertions: confirms the zoomed-wave carousel
/// pages on both RoadmapWave call sites (Home hero, Customize roadmap), with
/// no clipped content at the container edges once paged to an off-center node.
///
/// Paging must be driven via `app.scrollViews.firstMatch.swipeLeft()`, not a
/// raw `XCUICoordinate.press(forDuration:thenDragTo:)` — the latter was tried
/// first and reliably produced a no-op (identical before/after screenshots)
/// against this ScrollView's custom `ScrollTargetBehavior`, even with slow
/// velocity and multiple waypoints. `swipeLeft()` (XCUITest's dedicated
/// scroll-view gesture) reliably registers and pages correctly.
final class RoadmapWaveCarouselUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testCarouselOnHomeHeroAndCustomizeRoadmap() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
        ]
        app.launch()

        // Home hero roadmap at rest (node 0 focused).
        let customizeButton = app.buttons["Customize"]
        XCTAssertTrue(customizeButton.waitForExistence(timeout: 10))
        attach(app, "01-home-hero-carousel-rest")

        // Page the hero roadmap to an off-center exercise, check for
        // clipping on off-center nodes.
        XCTAssertGreaterThan(app.scrollViews.count, 0, "RoadmapWave's ScrollView should be in the hierarchy")
        app.scrollViews.firstMatch.swipeLeft()
        app.scrollViews.firstMatch.swipeLeft()
        sleep(1)
        attach(app, "02-home-hero-carousel-paged")

        // Customize sheet: the numbered roadmap.
        customizeButton.tap()
        let addExercises = app.buttons["Add Exercises"]
        XCTAssertTrue(addExercises.waitForExistence(timeout: 10))
        attach(app, "03-customize-carousel-rest")

        // Page the Customize roadmap through its range to check every node
        // (including the low side of the curve, where the earlier
        // curve/node coordinate-mismatch bug showed up) for clean rendering.
        XCTAssertGreaterThan(app.scrollViews.count, 0, "CustomizeRoutineView's roadmap ScrollView should be in the hierarchy")
        app.scrollViews.firstMatch.swipeLeft()
        app.scrollViews.firstMatch.swipeLeft()
        sleep(1)
        attach(app, "04-customize-carousel-paged")
    }
}
