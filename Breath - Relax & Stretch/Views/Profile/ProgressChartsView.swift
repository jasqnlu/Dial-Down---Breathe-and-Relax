import SwiftUI
import SwiftData
import Charts

// MARK: - ProgressChartsView

struct ProgressChartsView: View {

    @Query(sort: \Session.startedAt) private var sessions: [Session]
    @Query private var profiles: [UserProfile]
    @Query private var exercises: [Exercise]
    @Query(sort: \FlexibilityCheckIn.date) private var checkIns: [FlexibilityCheckIn]

    @State private var selectedDay: DaySelection?
    @State private var showingStreakShare = false
    @State private var showingCheckIn = false

    private var profile: UserProfile? { profiles.first }

    private struct DaySelection: Identifiable {
        let date: Date
        var id: Date { date }
    }

    // MARK: - Body

    // No NavigationStack here: this view is pushed onto the Profile tab's
    // stack, so wrapping another stack would nest navigation bars. The title
    // and toolbar attach to the outer stack's bar.
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                weeklyBarChartSection
                allTimeStatsSection
                flexibilitySection
                streakCalendarSection
                yearHeatmapSection
                pointsHistorySection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color.luminaSurface)
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.large)
        .floatingTabBarClearance()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingStreakShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share streak card")
            }
        }
        .sheet(item: $selectedDay) { selection in
            SessionDayDetailView(
                date: selection.date,
                sessions: sessionsOnDay(selection.date),
                exercises: exercises
            )
        }
        .sheet(isPresented: $showingCheckIn) {
            FlexibilityCheckInView()
        }
        .sheet(isPresented: $showingStreakShare) {
            StreakCardShareSheet(
                streak: profile?.streak ?? longestStreak,
                totalPoints: profile?.totalPoints ?? sessions.reduce(0) { $0 + $1.pointsEarned },
                totalMinutes: totalMinutes,
                displayName: profile?.displayName ?? ""
            )
        }
    }

    // MARK: - Section 1: This Week

    private var weeklyBarChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("This Week")

            let weekData = minutesPerDayLastSevenDays()

            if weekData.allSatisfy({ $0.minutes == 0 }) {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "chart.bar",
                    description: Text("Complete a session to see your weekly activity.")
                )
                .frame(height: 180)
                .cardStyle()
            } else {
                Chart(weekData) { point in
                    BarMark(
                        x: .value("Day", point.label),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(Color.luminaPrimary)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 180)
                .padding()
                .cardStyle()
            }
        }
    }

    // MARK: - Section 2: All Time

    private var allTimeStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("All Time")

            HStack(spacing: 12) {
                statCard(
                    value: "\(sessions.count)",
                    label: "Sessions",
                    icon: "figure.mind.and.body"
                )
                statCard(
                    value: "\(totalMinutes)",
                    label: "Minutes",
                    icon: "clock.fill"
                )
                statCard(
                    value: "\(profile?.streak ?? longestStreak)",
                    label: "Streak",
                    icon: "flame.fill"
                )
            }
        }
    }

    // MARK: - Section 2b: Flexibility Check-Ins

    // Fixed color per test (identity never follows how many series happen to
    // be chartable), ordered blue/orange/green/purple for adjacent-pair
    // distinguishability under color-vision deficiency. Identity never rides
    // on color alone: every series also carries its SF Symbol + name.
    private static let testColors: [FlexibilityTest: Color] = [
        .toeTouch:      .pastelBlue,
        .shoulderReach: .pastelPeach,
        .neckRotation:  .pastelMint,
        .butterfly:     .pastelLavender
    ]

    private var flexibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Flexibility")
                Spacer()
                if !checkIns.isEmpty {
                    Button {
                        showingCheckIn = true
                    } label: {
                        Label("Check In", systemImage: "checklist")
                    }
                    .buttonStyle(LuminaPillButtonStyle(kind: .ghost, compact: true))
                }
            }

            if checkIns.isEmpty {
                ContentUnavailableView {
                    Label("No check-ins yet", systemImage: "figure.flexibility")
                } description: {
                    Text("Test how far you can reach every couple of weeks and watch your range grow.")
                } actions: {
                    Button("Start First Check-In") { showingCheckIn = true }
                        .buttonStyle(LuminaPillButtonStyle())
                }
                .frame(height: 220)
                .cardStyle()
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if FlexibilityStats.isDue(checkIns) {
                        Label("It's been a couple of weeks — time for a new check-in.",
                              systemImage: "clock.badge.exclamationmark")
                            .font(.luminaCaption)
                            .foregroundStyle(Color.luminaOnSurfaceVariant)
                    }

                    ForEach(FlexibilityTest.allCases) { test in
                        if let latest = FlexibilityStats.latest(checkIns, for: test) {
                            HStack(spacing: 10) {
                                LuminaIconBadge(systemName: test.icon,
                                                tint: Self.testColors[test] ?? .pastelBlue, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(test.name)
                                        .font(.luminaCardTitle)
                                        .foregroundStyle(Color.luminaOnSurface)
                                    Text(test.levels[min(latest.level, test.levels.count - 1)])
                                        .font(.luminaCaption)
                                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                                }
                                Spacer()
                                if let delta = FlexibilityStats.delta(checkIns, for: test) {
                                    deltaBadge(delta)
                                }
                            }
                        }
                    }

                    if !flexibilityChartPoints.isEmpty {
                        flexibilityChart
                    }
                }
                .padding()
                .cardStyle()
            }
        }
    }

    /// Progress since the first check-in, in levels. Deliberately plain
    /// secondary ink (arrow carries the direction) — green/red would collide
    /// with the series colors above.
    private func deltaBadge(_ delta: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "equal")
                .font(.luminaCaption)
            Text(delta == 0 ? "steady" : "\(abs(delta)) \(abs(delta) == 1 ? "level" : "levels")")
                .font(.luminaCaption)
        }
        .foregroundStyle(Color.luminaOnSurfaceVariant)
        .accessibilityLabel(
            delta == 0 ? "No change since first check-in"
                       : "\(delta > 0 ? "Up" : "Down") \(abs(delta)) levels since first check-in"
        )
    }

    /// Step line per test, only for tests with ≥ 2 check-ins (a single point
    /// draws no line and just adds legend noise). Levels display as 1–5.
    private var flexibilityChart: some View {
        Chart(flexibilityChartPoints) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Level", point.level + 1),
                series: .value("Test", point.testName)
            )
            .interpolationMethod(.stepEnd)
            .foregroundStyle(by: .value("Test", point.testName))
            .lineStyle(StrokeStyle(lineWidth: 2))

            PointMark(
                x: .value("Date", point.date),
                y: .value("Level", point.level + 1)
            )
            .foregroundStyle(by: .value("Test", point.testName))
            .symbolSize(36)
        }
        .chartForegroundStyleScale([
            FlexibilityTest.toeTouch.name:      Self.testColors[.toeTouch]!,
            FlexibilityTest.shoulderReach.name: Self.testColors[.shoulderReach]!,
            FlexibilityTest.neckRotation.name:  Self.testColors[.neckRotation]!,
            FlexibilityTest.butterfly.name:     Self.testColors[.butterfly]!
        ])
        .chartYScale(domain: 0...5)
        .chartYAxis {
            AxisMarks(position: .leading, values: [1, 2, 3, 4, 5]) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 180)
        .padding(.top, 4)
    }

    private var flexibilityChartPoints: [FlexibilityPoint] {
        FlexibilityTest.allCases.flatMap { test -> [FlexibilityPoint] in
            // checkIns arrives date-sorted from the @Query.
            let history = checkIns.filter { $0.testID == test.rawValue }
            guard history.count >= 2 else { return [] }
            return history.map {
                FlexibilityPoint(date: $0.date, level: $0.level, testName: test.name)
            }
        }
    }

    // MARK: - Section 3: Streak Calendar

    private var streakCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Streak Calendar")

            VStack(alignment: .leading, spacing: 10) {
                // Month label
                Text(currentMonthLabel)
                    .font(.luminaCardTitle)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)

                // Day-of-week header
                let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
                HStack(spacing: 6) {
                    ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.luminaCaption)
                            .foregroundStyle(Color.luminaOnSurfaceVariant)
                            .frame(maxWidth: .infinity)
                    }
                }

                // 5-week grid
                ScrollView(.horizontal, showsIndicators: false) {
                    let grid = calendarGrid()
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 7),
                        spacing: 6
                    ) {
                        ForEach(grid) { cell in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(cell.hasSession ? Color.pastelMint : Color.luminaContainer)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if let day = cell.day {
                                        Text("\(day)")
                                            .font(.luminaCaption)
                                            .foregroundStyle(cell.hasSession ? Color.onPastel : Color.luminaOnSurfaceVariant)
                                    }
                                }
                                .onTapGesture {
                                    if cell.hasSession, let date = cell.date {
                                        selectedDay = DaySelection(date: date)
                                    }
                                }
                                .accessibilityAddTraits(cell.hasSession ? .isButton : [])
                        }
                    }
                }
            }
            .padding()
            .cardStyle()
        }
    }

    // MARK: - Section 3b: Year Heatmap

    private var yearHeatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Year in Review")

            VStack(alignment: .leading, spacing: 8) {
                let weeks = yearHeatmapWeeks()
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 3) {
                            ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                                VStack(spacing: 3) {
                                    ForEach(week, id: \.self) { day in
                                        let count = sessionCount(on: day)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(heatColor(for: count, isFuture: day > Date()))
                                            .frame(width: 10, height: 10)
                                            .onTapGesture {
                                                if count > 0 { selectedDay = DaySelection(date: day) }
                                            }
                                    }
                                }
                                .id(weekIndex)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onAppear {
                        proxy.scrollTo(weeks.count - 1, anchor: .trailing)
                    }
                }

                HStack(spacing: 4) {
                    Text("Less")
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                    ForEach([0, 1, 2, 3], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(heatColor(for: level, isFuture: false))
                            .frame(width: 10, height: 10)
                    }
                    Text("More")
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }
            }
            .padding()
            .cardStyle()
        }
    }

    private func sessionCount(on date: Date) -> Int {
        let cal = Calendar.current
        return sessions.filter { cal.isDate($0.startedAt, inSameDayAs: date) }.count
    }

    private func heatColor(for count: Int, isFuture: Bool) -> Color {
        if isFuture { return Color.clear }
        switch count {
        case 0:  return Color.luminaContainer
        case 1:  return Color.pastelMint.opacity(0.4)
        case 2:  return Color.pastelMint.opacity(0.7)
        default: return Color.pastelMint
        }
    }

    // Returns 53ish columns of 7 days (Sun…Sat) covering the last 365 days, oldest first.
    private func yearHeatmapWeeks() -> [[Date]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let yearAgo = cal.date(byAdding: .day, value: -364, to: today) else { return [] }

        let startWeekday = cal.component(.weekday, from: yearAgo) // 1 = Sunday
        guard let alignedStart = cal.date(byAdding: .day, value: -(startWeekday - 1), to: yearAgo) else { return [] }

        var columns: [[Date]] = []
        var weekStart = alignedStart
        while weekStart <= today {
            var week: [Date] = []
            for i in 0..<7 {
                if let d = cal.date(byAdding: .day, value: i, to: weekStart) {
                    week.append(d)
                }
            }
            columns.append(week)
            guard let next = cal.date(byAdding: .day, value: 7, to: weekStart) else { break }
            weekStart = next
        }
        return columns
    }

    // MARK: - Section 4: Points History

    private var pointsHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Points History")

            let pointsData = cumulativePointsLast30Days()

            if pointsData.isEmpty {
                ContentUnavailableView(
                    "No data yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Earn points by completing sessions.")
                )
                .frame(height: 160)
                .cardStyle()
            } else {
                Chart(pointsData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Points", point.cumulativePoints)
                    )
                    .foregroundStyle(Color.luminaPrimary)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Points", point.cumulativePoints)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.luminaPrimary.opacity(0.3), Color.luminaPrimary.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 160)
                .padding()
                .cardStyle()
            }
        }
    }

    // MARK: - Helpers: Data

    private var totalMinutes: Int {
        sessions.reduce(0) { $0 + $1.durationMinutes }
    }

    private var longestStreak: Int {
        guard !sessions.isEmpty else { return 0 }
        let cal = Calendar.current
        let sessionDays = Set(sessions.map { cal.startOfDay(for: $0.startedAt) }).sorted()
        var maxStreak = 1
        var current = 1
        for i in 1..<sessionDays.count {
            let diff = cal.dateComponents([.day], from: sessionDays[i - 1], to: sessionDays[i]).day ?? 0
            if diff == 1 {
                current += 1
                maxStreak = max(maxStreak, current)
            } else if diff > 1 {
                current = 1
            }
        }
        return maxStreak
    }

    // Returns [DayPoint] for the last 7 calendar days (oldest first).
    private func minutesPerDayLastSevenDays() -> [DayPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset -> DayPoint in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let label = day.shortWeekdayLabel
            let minutes = sessions
                .filter { cal.isDate($0.startedAt, inSameDayAs: day) }
                .reduce(0) { $0 + $1.durationMinutes }
            return DayPoint(date: day, label: label, minutes: minutes)
        }
    }

    // Returns cumulative points plotted over the last 30 days.
    private func cumulativePointsLast30Days() -> [PointsDataPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let startDay = cal.date(byAdding: .day, value: -29, to: today) else { return [] }

        let relevant = sessions.filter { $0.startedAt >= startDay }
        guard !relevant.isEmpty else { return [] }

        var running = 0
        return relevant.map { session -> PointsDataPoint in
            running += session.pointsEarned
            return PointsDataPoint(date: session.startedAt, cumulativePoints: running)
        }
    }

    // MARK: - Helpers: Calendar Grid

    private struct CalendarCell: Identifiable {
        let id: Int          // index in the 35-cell grid
        let day: Int?        // nil for padding cells before month starts
        let date: Date?      // nil for padding cells before month starts
        let hasSession: Bool
    }

    private var currentMonthLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: Date())
    }

    private func calendarGrid() -> [CalendarCell] {
        let cal = Calendar.current
        let today = Date()
        guard
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today)),
            let range = cal.range(of: .day, in: .month, for: monthStart)
        else { return [] }

        let sessionDays = Set(sessions.map { cal.startOfDay(for: $0.startedAt) })

        // Weekday of the first day (1 = Sunday in Gregorian)
        let firstWeekday = cal.component(.weekday, from: monthStart)
        let leadingPads  = firstWeekday - 1

        // Build 5 rows * 7 columns = 35 cells
        let totalCells = 35
        var cells: [CalendarCell] = []
        for i in 0..<totalCells {
            let dayNumber = i - leadingPads + 1
            if dayNumber < 1 || dayNumber > range.count {
                cells.append(CalendarCell(id: i, day: nil, date: nil, hasSession: false))
            } else {
                let cellDate = cal.date(byAdding: .day, value: dayNumber - 1, to: monthStart) ?? monthStart
                let hasSession = sessionDays.contains(cal.startOfDay(for: cellDate))
                cells.append(CalendarCell(id: i, day: dayNumber, date: cellDate, hasSession: hasSession))
            }
        }
        return cells
    }

    private func sessionsOnDay(_ date: Date) -> [Session] {
        let cal = Calendar.current
        return sessions.filter { cal.isDate($0.startedAt, inSameDayAs: date) }
    }

    // MARK: - Sub-views

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.luminaTitle)
            .foregroundStyle(Color.luminaOnSurface)
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            LuminaIconBadge(systemName: icon, size: 36)
            Text(value)
                .font(.luminaHeadline)
                .foregroundStyle(Color.luminaOnSurface)
            Text(label)
                .font(.luminaCaption)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .cardStyle()
    }
}

// MARK: - Supporting Types

private struct DayPoint: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let minutes: Int
}

private struct PointsDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let cumulativePoints: Int
}

private struct FlexibilityPoint: Identifiable {
    let id = UUID()
    let date: Date
    let level: Int
    let testName: String
}

// MARK: - Card Style Modifier

private extension View {
    func cardStyle() -> some View {
        self
            .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

// MARK: - Date Helper

private extension Date {
    var shortWeekdayLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        let full = fmt.string(from: self)   // e.g. "Mon"
        return String(full.prefix(3))
    }
}

// MARK: - Preview

#Preview {
    let schema = Schema([Session.self, UserProfile.self, Exercise.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    // Seed sample sessions
    let ctx = container.mainContext
    let cal = Calendar.current
    let today = Date()
    for offset in [0, 1, 2, 4, 5] {
        let start = cal.date(byAdding: .day, value: -offset, to: today)!
        let end   = cal.date(byAdding: .minute, value: Int.random(in: 8...25), to: start)!
        let s = Session(routineID: UUID(), startedAt: start, completionPercent: 1.0, pointsEarned: Int.random(in: 30...120))
        s.completedAt = end
        ctx.insert(s)
    }
    let profile = UserProfile(profileID: "preview@example.com", displayName: "Alex")
    profile.streak = 3
    profile.totalMinutes = 87
    profile.totalPoints = 340
    ctx.insert(profile)

    return NavigationStack { ProgressChartsView() }
        .modelContainer(container)
}
