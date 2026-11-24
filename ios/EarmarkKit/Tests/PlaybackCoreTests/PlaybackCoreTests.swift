import Testing
@testable import PlaybackCore

/// Two files of 100 s and 50 s; chapters at 0, 60, 120 (the second chapter spans the file boundary).
private let timeline = BookTimeline(
    tracks: [TrackSpan(start: 0, duration: 100), TrackSpan(start: 100, duration: 50)],
    chapters: [
        ChapterSpan(id: 0, title: "One", start: 0, end: 60),
        ChapterSpan(id: 1, title: "Two", start: 60, end: 120),
        ChapterSpan(id: 2, title: "Three", start: 120, end: 150),
    ],
    duration: 150)

@Suite struct BookTimelineTests {
    @Test func locatesTheTrackAndOffset() {
        #expect(timeline.locate(30)?.track == 0 && timeline.locate(30)?.offset == 30)
        #expect(timeline.locate(130)?.track == 1 && timeline.locate(130)?.offset == 30)
    }

    @Test func aBoundaryBelongsToTheNextTrack() {
        #expect(timeline.locate(100)?.track == 1 && timeline.locate(100)?.offset == 0)
    }

    @Test func theEndOfTheBookIsTheEndOfTheLastTrack() {
        let end = timeline.locate(150)
        #expect(end?.track == 1 && end?.offset == 50)
        #expect(timeline.locate(999)?.offset == 50)
        #expect(timeline.locate(-5)?.track == 0 && timeline.locate(-5)?.offset == 0)
    }

    @Test func noTracksMeansNoLocation() {
        #expect(BookTimeline(tracks: [], chapters: [], duration: 0).locate(10) == nil)
    }

    @Test func globalTimeRoundTripsThroughLocate() {
        for time in [0.0, 42.5, 99.9, 100, 149.5] {
            let place = timeline.locate(time)!
            #expect(timeline.globalTime(track: place.track, offset: place.offset) == time)
        }
        #expect(timeline.globalTime(track: 9, offset: 3) == 0)
    }

    @Test func findsTheChapterAcrossAFileBoundary() {
        #expect(timeline.chapter(at: 0)?.title == "One")
        #expect(timeline.chapter(at: 60)?.title == "Two")
        #expect(timeline.chapter(at: 110)?.title == "Two")
        #expect(timeline.chapter(at: 150)?.title == "Three")
    }

    @Test func chapterProgressIsAFraction() {
        #expect(timeline.chapterProgress(at: 90) == 0.5)
        #expect(timeline.chapterProgress(at: 0) == 0)
    }

    @Test func nextAndPreviousChapter() {
        #expect(timeline.nextChapterStart(after: 10) == 60)
        #expect(timeline.nextChapterStart(after: 130) == nil)
        // More than 3 s in: previous goes to the start of this chapter; within 3 s: to the one before.
        #expect(timeline.previousChapterStart(before: 70) == 60)
        #expect(timeline.previousChapterStart(before: 61) == 0)
        #expect(timeline.previousChapterStart(before: 1) == 0)
    }
}

@Suite struct SkipRulesTests {
    @Test func skipsBack15AndForward30AndStaysInsideTheBook() {
        #expect(SkipRules.skippedBack(from: 100, in: timeline) == 85)
        #expect(SkipRules.skippedBack(from: 5, in: timeline) == 0)
        #expect(SkipRules.skippedForward(from: 100, in: timeline) == 130)
        #expect(SkipRules.skippedForward(from: 140, in: timeline) == 150)
    }

    @Test func resumeStarts15SecondsEarlierButNeverBeforeTheStart() {
        #expect(SkipRules.resumeTime(saved: 100, in: timeline) == 85)
        #expect(SkipRules.resumeTime(saved: 10, in: timeline) == 0)
    }
}

@Suite struct SleepTimerTests {
    @Test func offNeverFires() {
        var timer = SleepTimer()
        let fired = timer.tick(playedSeconds: 10_000, position: 5)
        #expect(!fired)
    }

    @Test func aDurationCountsPlayedSecondsAndFiresOnce() {
        var timer = SleepTimer()
        timer.set(.duration(60))
        let early = timer.tick(playedSeconds: 30, position: 0)
        #expect(!early)
        #expect(timer.remaining == 30)
        let fired = timer.tick(playedSeconds: 31, position: 0)
        #expect(fired)
        #expect(timer.mode == .off)
        let again = timer.tick(playedSeconds: 100, position: 0)
        #expect(!again)
    }

    @Test func endOfChapterFiresJustBeforeTheChapterEnds() {
        var timer = SleepTimer()
        timer.set(.endOfChapter(chapterEnd: 120))
        let early = timer.tick(playedSeconds: 1, position: 119)
        #expect(!early)
        let fired = timer.tick(playedSeconds: 1, position: 119.8)
        #expect(fired)
        #expect(timer.mode == .off)
    }

    @Test func settingAgainRestartsTheCount() {
        var timer = SleepTimer()
        timer.set(.duration(60))
        _ = timer.tick(playedSeconds: 50, position: 0)
        timer.set(.duration(60))
        #expect(timer.remaining == 60)
    }

    @Test func negativeElapsedTimeIsIgnored() {
        var timer = SleepTimer()
        timer.set(.duration(10))
        _ = timer.tick(playedSeconds: -50, position: 0)
        #expect(timer.remaining == 10)
    }
}

@Suite struct SyncPolicyTests {
    @Test func isDueEvery15SecondsListened() {
        var policy = SyncPolicy()
        policy.played(14)
        #expect(!policy.isDue)
        policy.played(1)
        #expect(policy.isDue)
    }

    @Test func aReportCarriesTheListeningTimeAndResetsIt() {
        var policy = SyncPolicy()
        policy.played(20)
        let report = policy.report(at: 300)
        #expect(report == SyncReport(currentTime: 300, timeListened: 20))
        #expect(!policy.isDue)
        let second = policy.report(at: 301)
        #expect(second.timeListened == 0)
    }

    @Test func aPauseReportBeforeTheIntervalStillCountsWhatWasHeard() {
        var policy = SyncPolicy()
        policy.played(4)
        let report = policy.report(at: 12)
        #expect(report.timeListened == 4)
    }
}

@Suite struct SavedPositionTests {
    private let phone = SavedPosition(time: 500, lastUpdate: 2_000)
    private let server = SavedPosition(time: 900, lastUpdate: 3_000)

    @Test func theNewestPositionWins() {
        #expect(SavedPosition.newest(local: phone, server: server) == server)
        #expect(SavedPosition.newest(local: SavedPosition(time: 1, lastUpdate: 4_000), server: server)?.time == 1)
    }

    @Test func aTieKeepsTheServer() {
        let same = SavedPosition(time: 5, lastUpdate: 3_000)
        #expect(SavedPosition.newest(local: same, server: server) == server)
    }

    @Test func oneSideMissingUsesTheOther() {
        #expect(SavedPosition.newest(local: nil, server: server) == server)
        #expect(SavedPosition.newest(local: phone, server: nil) == phone)
        #expect(SavedPosition.newest(local: nil, server: nil) == nil)
    }
}
