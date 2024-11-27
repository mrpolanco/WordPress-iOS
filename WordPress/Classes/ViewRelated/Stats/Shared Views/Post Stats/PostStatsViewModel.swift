import Foundation
import WordPressFlux

/// The view model used by PostStatsTableViewController to show
/// stats for a selected post.
///
class PostStatsViewModel: Observable {

    // MARK: - Properties

    let changeDispatcher = Dispatcher<Void>()

    private var selectedDate = Date()
    private var postID: Int?
    private var postTitle: String?
    private var postURL: URL?
    private weak var postStatsDelegate: PostStatsDelegate?

    private let store: StatsPeriodStore
    private var receipt: Receipt?
    private var changeReceipt: Receipt?
    private var postStats: StatsPostDetails?
    var currentTabIndex: Int = 0

    private lazy var calendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .autoupdatingCurrent
        return cal
    }()

    private lazy var fullDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate(StatsPeriodUnit.day.dateFormatTemplate)
        return df
    }()

    private lazy var weekDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate(StatsPeriodUnit.week.dateFormatTemplate)
        return df
    }()

    private let weekFormat = NSLocalizedString("%@ - %@, %@", comment: "Post Stats label for week date range. Ex: Mar 25 - Mar 31, 2019")

    weak var statsBarChartViewDelegate: StatsBarChartViewDelegate?

    // MARK: - Init

    init(postID: Int,
         selectedDate: Date,
         postTitle: String?,
         postURL: URL?,
         postStatsDelegate: PostStatsDelegate,
         store: StatsPeriodStore) {
        self.selectedDate = selectedDate
        self.postID = postID
        self.postTitle = postTitle
        self.postURL = postURL
        self.postStatsDelegate = postStatsDelegate
        self.store = store

        self.postStats = store.getPostStats(for: postID)

        self.changeReceipt = store.onChange { [weak self] in
            self?.emitChange()
        }

        self.receipt = store.query(.postStats(postID: postID))
    }

    // MARK: - Table View

    func tableViewSnapshot() -> ImmuTableDiffableDataSourceSnapshot {
        if let postId = postID, store.fetchingFailed(for: .postStats(postID: postId)) {
            return ImmuTableDiffableDataSourceSnapshot()
        }

        postStats = store.getPostStats(for: postID)

        return blocks(for: store.postStatsFetchingStatuses(for: postID)) {
            var tableRows = [any HashableImmutableRow]()
            tableRows.append(titleTableRow())
            tableRows.append(contentsOf: overviewTableRows())
            tableRows.append(contentsOf: yearsTableRows())
            tableRows.append(contentsOf: yearsTableRows(forAverages: true))
            tableRows.append(contentsOf: recentWeeksTableRows())
            tableRows.append(TableFooterRow())
            return tableRows
        }
    }

    func isFetchingPostDetails() -> Bool {
        return postStats == nil && store.isFetchingPostStats(for: postID)
    }

    // MARK: - Refresh Data

    func refreshPostStats(postID: Int, selectedDate: Date) {
        self.selectedDate = selectedDate
        ActionDispatcher.dispatch(PeriodAction.refreshPeriod(query: .postStats(postID: postID)))
    }

    func fetchDataHasFailed() -> Bool {
        if let postID {
            return store.fetchingFailed(for: .postStats(postID: postID))
        }
        return true
    }
}

// MARK: - Private Extension

private extension PostStatsViewModel {

    // MARK: - Create Table Rows

    func titleTableRow() -> any HashableImmutableRow {
        return PostStatsTitleRow(postTitle: postTitle ?? StatSection.noPostTitle,
                                 postURL: postURL,
                                 postStatsDelegate: postStatsDelegate)
    }

    func overviewTableRows() -> [any HashableImmutableRow] {
        var tableRows = [any HashableImmutableRow]()
        tableRows.append(PostStatsEmptyCellHeaderRow(statSection: .postStatsGraph))

        let lastTwoWeeks = postStats?.lastTwoWeeks ?? []
        let dayData = dayDataFrom(lastTwoWeeks)

        let overviewData = OverviewTabData(tabTitle: StatSection.periodOverviewViews.tabTitle,
                                           tabData: dayData.viewCount,
                                           difference: dayData.difference,
                                           differencePercent: dayData.percentage,
                                           date: selectedDate,
                                           period: .day
        )

        let chart = PostChart(postViews: lastTwoWeeks)

        let selectedDateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let indexToHighlight = lastTwoWeeks.lastIndex(where: {
            $0.date == selectedDateComponents
        })

        let row = OverviewRow(tabsData: [overviewData], chartData: [chart], chartStyling: [chart.barChartStyling], period: nil, statsBarChartViewDelegate: statsBarChartViewDelegate, chartHighlightIndex: indexToHighlight, tabIndex: currentTabIndex)
        tableRows.append(row)

        return tableRows
    }

    func yearsTableRows(forAverages: Bool = false) -> [any HashableImmutableRow] {
        var tableRows = [any HashableImmutableRow]()

        let statSection = forAverages ? StatSection.postStatsAverageViews :
                                        StatSection.postStatsMonthsYears
        let itemSubtitle = forAverages ? StatSection.postStatsAverageViews.itemSubtitle :
                                         StatSection.postStatsMonthsYears.itemSubtitle
        let dataSubtitle = forAverages ? StatSection.postStatsAverageViews.dataSubtitle :
                                         StatSection.postStatsMonthsYears.dataSubtitle

        tableRows.append(CellHeaderRow(statSection: statSection))
        tableRows.append(TopTotalsPostStatsRow(itemSubtitle: itemSubtitle,
                                               dataSubtitle: dataSubtitle,
                                               dataRows: yearsDataRows(forAverages: forAverages),
                                               limitRowsDisplayed: true,
                                               postStatsDelegate: postStatsDelegate,
                                               statSection: statSection))

        return tableRows
    }

    func yearsDataRows(forAverages: Bool = false) -> [StatsTotalRowData] {

        guard let yearsData = (forAverages ? postStats?.dailyAveragesPerMonth : postStats?.monthlyBreakdown),
            let maxYear = StatsDataHelper.maxYearFrom(yearsData: yearsData) else {
            return []
        }

        let minYear = maxYear - StatsDataHelper.maxRowsToDisplay
        var yearRows = [StatsTotalRowData]()

        // Create Year rows in descending order
        for year in (minYear...maxYear).reversed() {
            let months = StatsDataHelper.monthsFrom(yearsData: yearsData, forYear: year)
            let yearTotalViews = StatsDataHelper.totalViewsFrom(monthsData: months)

            let rowValue: Int = {
                if forAverages {
                    return months.count > 0 ? (yearTotalViews / months.count) : 0
                }
                return yearTotalViews
            }()

            if rowValue > 0 {
                yearRows.append(StatsTotalRowData(name: String(year),
                                                  data: rowValue.abbreviatedString(),
                                                  showDisclosure: true,
                                                  childRows: StatsDataHelper.childRowsForYear(months),
                                                  statSection: forAverages ? .postStatsAverageViews : .postStatsMonthsYears))
            }
        }

        return yearRows
    }

    func recentWeeksTableRows() -> [any HashableImmutableRow] {
        var tableRows = [any HashableImmutableRow]()

        let statSection = StatSection.postStatsRecentWeeks
        tableRows.append(CellHeaderRow(statSection: statSection))
        tableRows.append(TopTotalsPostStatsRow(itemSubtitle: StatSection.postStatsRecentWeeks.itemSubtitle,
                                               dataSubtitle: StatSection.postStatsRecentWeeks.dataSubtitle,
                                               dataRows: recentWeeksDataRows(),
                                               limitRowsDisplayed: false,
                                               postStatsDelegate: postStatsDelegate,
                                               statSection: statSection))

        return tableRows
    }

    func recentWeeksDataRows() -> [StatsTotalRowData] {
        let recentWeeks = postStats?.recentWeeks ?? []

        return recentWeeks.reversed().prefix(StatsDataHelper.maxRowsToDisplay).map {
            StatsTotalRowData(name: displayWeek(startDay: $0.startDay, endDay: $0.endDay),
                              data: $0.totalViewsCount.abbreviatedString(),
                              showDisclosure: true,
                              childRows: childRowsForWeek($0),
                              statSection: .postStatsRecentWeeks)
        }
    }

    // MARK: - Recent Weeks Helpers

    func childRowsForWeek(_ week: StatsWeeklyBreakdown) -> [StatsTotalRowData] {
        return week.days.reversed().map {
            StatsTotalRowData(name: displayDay(forDate: $0.date),
                              data: $0.viewsCount.abbreviatedString())
        }
    }

    func displayWeek(startDay: DateComponents, endDay: DateComponents) -> String {
        guard
            let startDate = calendar.date(from: startDay),
            let endDate = calendar.date(from: endDay),
            let year = endDay.year else {
                return ""
        }

        // If there is only one day in the week, display just the single day.
        if startDate == endDate {
            return fullDateFormatter.string(from: startDate)
        }

        // If there are multiple days in the week, show the date range.
        return String.localizedStringWithFormat(weekFormat,
                                                weekDateFormatter.string(from: startDate),
                                                weekDateFormatter.string(from: endDate),
                                                String(year))
    }

    func displayDay(forDate date: DateComponents) -> String {
        guard let day = calendar.date(from: date) else {
            return ""
        }

        return weekDateFormatter.string(from: day)
    }

    // MARK: - Overview Helpers

    func dayDataFrom(_ daysData: [StatsPostViews]) -> (viewCount: Int, difference: Int, percentage: Int) {
        // Use date without time
        let date = selectedDate.normalizedDate()
        let matchingDay = daysData.first { calendar.date(from: $0.date) == date }

        guard let currentDay = matchingDay else {
            return (0, 0, 0)
        }

        let currentCount = currentDay.viewsCount

        let previousDate = calendar.date(byAdding: .day, value: -1, to: date)
        let previousDay = daysData.first { calendar.date(from: $0.date) == previousDate }
        let previousCount = previousDay?.viewsCount ?? 0

        let difference = currentCount - previousCount
        var roundedPercentage = 0

        if previousCount > 0 {
            let percentage = (Float(difference) / Float(previousCount)) * 100
            roundedPercentage = Int(round(percentage))
        }

        return (currentCount, difference, roundedPercentage)
    }

    func blocks(for state: StoreFetchingStatus, block: () -> [any HashableImmutableRow]) -> ImmuTableDiffableDataSourceSnapshot {
        if postStats != nil {
            return .singleSectionSnapshot(block())
        }

        var rows = [any HashableImmutableRow]()
        let sections: [StatSection] = [.postStatsMonthsYears,
                                       .postStatsAverageViews,
                                       .postStatsRecentWeeks]

        switch state {
        case .idle, .success:
            rows.append(contentsOf: block())
        case .loading:
            rows.append(StatsGhostTitleRow())
            rows.append(PostStatsEmptyCellHeaderRow())
            rows.append(StatsGhostChartImmutableRow())
            sections.forEach {
                rows.append(CellHeaderRow(statSection: $0))
                rows.append(StatsGhostTopImmutableRow(statSection: $0))
            }
        case .error:
            return ImmuTableDiffableDataSourceSnapshot()
        }

        return .singleSectionSnapshot(rows)
    }
}
