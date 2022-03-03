//
//  EventMonitor.swift
//  Core
//
//  Created by Garrett on 9/29/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation

final public class EventMonitor {

    /// Records event count for future report
    public func count(_ event: CountableEvent) {
        monitorQueue.async {
            self.activeReport.add(event: event)
        }
    }

    /// Records event for future report
    public func observe(_ event: DiscreteEvent) {
        monitorQueue.async {
            self.activeReport.discreteEvents.append(event)
        }
    }

    /// Records event counts for future report
    public func count<S: Sequence>(_ events: S) where S.Element == CountableEvent {
        monitorQueue.async {
            for event in events {
                self.activeReport.add(event: event)
            }
        }
    }

    /// Records events for future report
    public func observe<S: Sequence>(_ events: S) where S.Element == DiscreteEvent {
        monitorQueue.async {
            self.activeReport.discreteEvents += events
        }
    }

    /// Aggregates events observed since last report and runs completion handler on main thread
    public func generateReport(completion: @escaping ([CountableEvent], [DiscreteEvent]) -> Void) {
        monitorQueue.async {
            let countableEventsInReport = self.activeReport.countableEvents
            let discreteEventsInReport = self.activeReport.discreteEvents
            self.activeReport = Report()
            DispatchQueue.main.async {
                completion(countableEventsInReport, discreteEventsInReport)
            }
        }
    }

    /// Adds any unreported events to user defaults and removes them from active report
    public func saveReport(to userDefaults: UserDefaults) {
        monitorQueue.async {
            guard !self.activeReport.isEmpty else {
                DDLogInfo("EventMonitor/save/skipping [empty]")
                return
            }
            var reportToArchive = self.activeReport
            if let data = userDefaults.data(forKey: self.UserDefaultsKey) {
                // Load already saved values. In case of load error, skip them and preserve newest events.
                do {
                    let savedReport = try PropertyListDecoder().decode(Report.self, from: data)
                    reportToArchive.mergeEvents(from: savedReport)
                } catch {
                    DDLogError("EventMonitor/save/loading-error \(error)")
                }
            }
            do {
                let archive = try PropertyListEncoder().encode(reportToArchive)
                userDefaults.set(archive, forKey: self.UserDefaultsKey)
                self.activeReport = Report()
                DDLogInfo("EventMonitor/save/saved [\(reportToArchive.countableEvents.count) countable] [\(reportToArchive.discreteEvents.count) discrete]")
            } catch {
                DDLogError("EventMonitor/save/archiving-error \(error)")
            }
        }
    }

    /// Loads values from user defaults and optionally removes them from user defaults
    public func loadReport(from userDefaults: UserDefaults, clearingData: Bool = true) throws {
        guard let data = userDefaults.data(forKey: UserDefaultsKey) else {
            DDLogInfo("EventMonitor/load/skipping [empty]")
            return
        }
        let report = try PropertyListDecoder().decode(Report.self, from: data)
        if clearingData {
            userDefaults.removeObject(forKey: UserDefaultsKey)
        }
        monitorQueue.async {
            DDLogInfo("EventMonitor/load/adding [\(report.countableEvents.count) countable] [\(report.discreteEvents.count) discrete]")
            self.activeReport.mergeEvents(from: report)
        }
    }

    // MARK: Private

    private let UserDefaultsKey = "com.halloapp.eventmonitor.report"
    private var activeReport = Report()
    private var monitorQueue = DispatchQueue(label: "com.halloapp.eventmonitor", qos: .userInitiated)

    private typealias Metric = [CountableEvent]
    private typealias Namespace = [String: Metric]

    private struct Report: Codable {
        var namespaces = [String: Namespace]()
        var discreteEvents = [DiscreteEvent]()

        var isEmpty: Bool {
            discreteEvents.isEmpty && namespaces.values.allSatisfy { $0.values.isEmpty }
        }

        var countableEvents: [CountableEvent] {
            return namespaces.values.reduce([]) { events, namespace in
                let eventsInNamespace = namespace.values.reduce([]) { namespaceEvents, metric in
                    namespaceEvents + metric
                }
                return events + eventsInNamespace
            }
        }

        mutating func add(event: CountableEvent) {
            var namespace = namespaces[event.namespace] ?? Namespace()
            var metric = namespace[event.metric] ?? Metric()
            if let existingEvent = metric.first(where: { $0.dimensions == event.dimensions }) {
                existingEvent.count += event.count
            } else {
                metric.append(event)
            }

            namespace[event.metric] = metric
            namespaces[event.namespace] = namespace
        }

        mutating func mergeEvents(from otherReport: Report) {
            discreteEvents += otherReport.discreteEvents
            otherReport.countableEvents.forEach { add(event: $0) }
        }
    }
}
