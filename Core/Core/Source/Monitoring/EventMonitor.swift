//
//  EventMonitor.swift
//  Core
//
//  Created by Garrett on 9/29/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

final public class EventMonitor {

    public init(events: [CountableEvent] = []) {
        for event in events {
            add(event, to: &activeReport)
        }
    }

    /// Records event count for future report
    public func observe(_ event: CountableEvent) {
        monitorQueue.async {
            self.add(event, to: &self.activeReport)
        }
    }

    /// Records event counts for future report
    public func observe<S: Sequence>(_ events: S) where S.Element == CountableEvent {
        monitorQueue.async {
            for event in events {
                self.add(event, to: &self.activeReport)
            }
        }
    }

    /// Aggregates event counts observed since last report and runs completion handler on main thread
    public func generateReport(completion: @escaping ([CountableEvent]) -> Void) {
        monitorQueue.async {
            let eventsInReport = self.events(in: self.activeReport)
            self.activeReport = Report()
            DispatchQueue.main.async {
                completion(eventsInReport)
            }
        }
    }

    // MARK: Private

    private typealias Metric = [CountableEvent]
    private typealias Namespace = [String: Metric]
    private typealias Report = [String: Namespace]

    private var activeReport = Report()
    private var monitorQueue = DispatchQueue(label: "EventMonitor", qos: .userInitiated)

    private func add(_ event: CountableEvent, to report: inout Report) {
        var namespace = report[event.namespace] ?? Namespace()
        var metric = namespace[event.metric] ?? Metric()
        if let existingEvent = metric.first(where: { $0.dimensions == event.dimensions }) {
            existingEvent.count += event.count
        } else {
            metric.append(event)
        }

        namespace[event.metric] = metric
        report[event.namespace] = namespace
    }

    private func events(in report: Report) -> [CountableEvent] {
        return report.values.reduce([]) { events, namespace in
            let eventsInNamespace = namespace.values.reduce([]) { namespaceEvents, metric in
                namespaceEvents + metric
            }
            return events + eventsInNamespace
        }
    }
}
