//
//  PhotoSuggestionsBrowserView.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/26/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import MapKit
import Photos
import SwiftUI

struct PhotoSuggestionsBrowser: View {

    var body: some View {
        List {
            Section {
                NavigationLink("Synced Assets") {
                    PhotoSuggestionsAssetRecordBrowser()
                        .environment(\.managedObjectContext, MainAppContext.shared.photoSuggestionsData.viewContext)
                }
                NavigationLink("MacroClusters") {
                    PhotoSuggestionsAssetMacroClusterBrowser()
                        .environment(\.managedObjectContext, MainAppContext.shared.photoSuggestionsData.viewContext)
                }
                NavigationLink("LocatedClusters") {
                    PhotoSuggestionsAssetLocatedClusterBrowser()
                        .environment(\.managedObjectContext, MainAppContext.shared.photoSuggestionsData.viewContext)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        await MainAppContext.shared.photoSuggestionsServices.stop()
                        await MainAppContext.shared.photoSuggestionsServices.reset()
                        MainAppContext.shared.photoSuggestionsData.reset()
                        await MainAppContext.shared.photoSuggestionsServices.start()
                    }
                } label: {
                    Text("Reset Photo Suggestions")
                }
            }
        }
        .navigationTitle("Photo Suggestions")
    }
}

// MARK: - Asset Records

struct PhotoSuggestionsAssetRecordBrowser: View {

    @FetchRequest(sortDescriptors: [SortDescriptor(\AssetRecord.creationDate, order: .reverse)])
    var assetRecords: FetchedResults<AssetRecord>

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 4)
        ScrollView {
            LazyVGrid(columns: columns, spacing: 1, content: {
                ForEach(assetRecords) { assetRecord in
                    NavigationLink {
                        PhotoSuggestionAssetRecordView(assetRecord: assetRecord)
                    } label: {
                        AssetImage(asset: assetRecord.asset)
                            .aspectRatio(1.0, contentMode: .fit)
                    }
                }
            })
        }
        .navigationTitle("Asset Records")
    }
}

struct PhotoSuggestionAssetRecordView: View {

    @ObservedObject var assetRecord: AssetRecord

    var body: some View {
        List {
            AssetImage(asset: assetRecord.asset, mode: .fullSize)
                .aspectRatio(1.0, contentMode: .fill)
                .padding(8)

            PhotoSuggestionsLabeledContent("Identifier", value: assetRecord.localIdentifier ?? "(unknown)")
                .contextMenu {
                    Button("Copy") {
                        UIPasteboard.general.string = assetRecord.localIdentifier
                    }
                }

            let clusterStatusDescriptor = switch assetRecord.macroClusterStatus {
            case .pending:
                "pending"
            case .core:
                "core"
            case .edge:
                "edge"
            case .orphan:
                "orphan"
            case .deletePending:
                "deletePending"
            case .invalidAssetForClustering:
                "invalidAssetForClustering"
            }

            PhotoSuggestionsLabeledContent("ClusterStatus", value: clusterStatusDescriptor)

            PhotoSuggestionsLabeledContent("CreationDate", value: assetRecord.creationDate, format: .dateTime)

            let mediaTypeDescriptor = switch assetRecord.mediaType {
            case .unknown:
                "unknown"
            case .image:
                "image"
            case .video:
                "video"
            case .audio:
                "audio"
            @unknown default:
                String(describing: assetRecord.mediaType)
            }

            PhotoSuggestionsLabeledContent("MediaType", value: mediaTypeDescriptor)

            PhotoSuggestionsLabeledContent {
                if let macroCluster = assetRecord.macroCluster {
                    NavigationLink {
                        PhotoSuggestionAssetMacroClusterView(assetMacroCluster: macroCluster)
                    } label: {
                        Text(macroCluster.id ?? "<unknown>")
                    }
                } else {
                    Text("none")
                }
            } label: {
                Text("MacroCluster")
            }

            PhotoSuggestionsLabeledContent {
                if let locatedCluster = assetRecord.locatedCluster {
                    NavigationLink {
                        PhotoSuggestionAssetLocatedClusterView(assetLocatedCluster: locatedCluster)
                    } label: {
                        Text(locatedCluster.id ?? "<unknown>")
                    }
                } else {
                    Text("none")
                }
            } label: {
                Text("LocatedCluster")
            }

            PhotoSuggestionsLabeledContent {
                if let location = assetRecord.location {
                    let intialRegion = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
                    Map(coordinateRegion: .constant(intialRegion), interactionModes: [], annotationItems: [assetRecord]) { assetRecord in
                        MapPin(coordinate: assetRecord.location?.coordinate ?? CLLocationCoordinate2D())
                    }
                    .aspectRatio(1, contentMode: .fit)
                } else {
                    Text("(null)")
                }

            } label: {
                Text("Location")
            }
        }
        .navigationTitle("Photo")
    }
}

// MARK: - MacroCluster

struct PhotoSuggestionsAssetMacroClusterBrowser: View {

    @FetchRequest(sortDescriptors: [SortDescriptor(\AssetMacroCluster.startDate, order: .reverse)])
    var assetMacroClusters: FetchedResults<AssetMacroCluster>

    var body: some View {
        List {
            ForEach(assetMacroClusters) { assetMacroCluster in
                NavigationLink {
                    PhotoSuggestionAssetMacroClusterView(assetMacroCluster: assetMacroCluster)
                } label: {
                    Text(assetMacroCluster.id ?? "(unknown)")
                }
            }
        }
        .navigationTitle("MacroClusters")
    }
}

struct PhotoSuggestionAssetMacroClusterView: View {

    @ObservedObject var assetMacroCluster: AssetMacroCluster

    var body: some View {
        List {
            Section {
                PhotoSuggestionsLabeledContent("Identifier", value: assetMacroCluster.id ?? "(unknown)")
                    .contextMenu {
                        Button("Copy") {
                            UIPasteboard.general.string = assetMacroCluster.id
                        }
                    }

                PhotoSuggestionsLabeledContent("Start", value: assetMacroCluster.startDate, format: .dateTime)

                PhotoSuggestionsLabeledContent("End", value: assetMacroCluster.endDate, format: .dateTime)

                let clusterStatusDescriptor = switch assetMacroCluster.locatedClusterStatus {
                case .pending:
                    "pending"
                case .located:
                    "located"
                }

                PhotoSuggestionsLabeledContent("ClusterStatus", value: clusterStatusDescriptor)
            }
            Section("Located Clusters") {
                let locatedClusters = assetMacroCluster.locatedClustersAsSet.sorted {
                    $0.startDate ?? .distantFuture < $1.startDate ?? .distantFuture
                }
                ForEach(locatedClusters) { locatedCluster in
                    NavigationLink {
                        PhotoSuggestionAssetLocatedClusterView(assetLocatedCluster: locatedCluster)
                    } label: {
                        Text(locatedCluster.id ?? "<unknown")
                    }
                }
            }
            Section {
                EmptyView()
            } footer: {
                let assetRecords = assetMacroCluster.assetRecordsAsSet.sorted(using: SortDescriptor(\AssetRecord.creationDate))
                if !assetRecords.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 4), content: {
                        ForEach(assetRecords) { assetRecord in
                            NavigationLink {
                                PhotoSuggestionAssetRecordView(assetRecord: assetRecord)
                            } label: {
                                 AssetImage(asset: assetRecord.asset)
                                 .aspectRatio(1.0, contentMode: .fit)
                            }
                        }
                    })
                }
            }
        }
        .navigationTitle("MacroCluster")
    }
}

// MARK: - MacroCluster

struct PhotoSuggestionsAssetLocatedClusterBrowser: View {

    @FetchRequest(sortDescriptors: [SortDescriptor(\AssetLocatedCluster.startDate, order: .reverse)])
    var assetLocatedClusters: FetchedResults<AssetLocatedCluster>

    var body: some View {
        List {
            ForEach(assetLocatedClusters) { assetLocatedCluster in
                NavigationLink {
                    PhotoSuggestionAssetLocatedClusterView(assetLocatedCluster: assetLocatedCluster)
                } label: {
                    Text(assetLocatedCluster.id ?? "(unknown)")
                }
            }
        }
        .navigationTitle("LocatedClusters")
    }
}

struct PhotoSuggestionAssetLocatedClusterView: View {

    @ObservedObject var assetLocatedCluster: AssetLocatedCluster

    var body: some View {
        List {
            Section {
                PhotoSuggestionsLabeledContent("Identifier", value: assetLocatedCluster.id ?? "(unknown)")
                    .contextMenu {
                        Button("Copy") {
                            UIPasteboard.general.string = assetLocatedCluster.id
                        }
                    }

                PhotoSuggestionsLabeledContent("Start", value: assetLocatedCluster.startDate, format: .dateTime)

                PhotoSuggestionsLabeledContent("End", value: assetLocatedCluster.endDate, format: .dateTime)

                let geocodeStatus = switch assetLocatedCluster.locationStatus {
                case .pending:
                    "pending"
                case .located:
                    "located"
                case .failed:
                    "failed"
                case .noLocation:
                    "noLocation"
                }

                PhotoSuggestionsLabeledContent("GeocodeStatus", value: geocodeStatus)

                PhotoSuggestionsLabeledContent("GeocodedName", value: assetLocatedCluster.geocodedLocationName ?? "(null)")

                PhotoSuggestionsLabeledContent("GeocodedAddress", value: assetLocatedCluster.geocodedAddress ?? "(null)")

                PhotoSuggestionsLabeledContent("GeocodedDate", value: assetLocatedCluster.lastGeocodeDate, format: .dateTime)

                PhotoSuggestionsLabeledContent {
                    if let macroCluster = assetLocatedCluster.macroCluster {
                        NavigationLink {
                            PhotoSuggestionAssetMacroClusterView(assetMacroCluster: macroCluster)
                        } label: {
                            Text(macroCluster.id ?? "<unknown>")
                        }
                    } else {
                        Text("none")
                    }
                } label: {
                    Text("MacroCluster")
                }

                PhotoSuggestionsLabeledContent {
                    if let location = assetLocatedCluster.location {
                        let intialRegion = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
                        Map(coordinateRegion: .constant(intialRegion), interactionModes: [], annotationItems: [assetLocatedCluster]) { assetRecord in
                            MapPin(coordinate: assetRecord.location?.coordinate ?? CLLocationCoordinate2D())
                        }
                        .aspectRatio(1, contentMode: .fit)
                    } else {
                        Text("(null)")
                    }

                } label: {
                    Text("Location")
                }
            } footer: {
                let assetRecords = assetLocatedCluster.assetRecordsAsSet.sorted(using: SortDescriptor(\AssetRecord.creationDate))
                if !assetRecords.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 4), content: {
                        ForEach(assetRecords) { assetRecord in
                            NavigationLink {
                                PhotoSuggestionAssetRecordView(assetRecord: assetRecord)
                            } label: {
                                 AssetImage(asset: assetRecord.asset)
                                 .aspectRatio(1.0, contentMode: .fit)
                            }
                        }
                    })
                }
            }
        }
        .navigationTitle("LocatedCluster")
    }
}

// MARK: - Utility

struct PhotoSuggestionsLabeledContent<Label: View, Content: View>: View {

    let label: Label
    let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            label
            Spacer()
            content
                .foregroundColor(.secondary)
        }
    }

    init(@ViewBuilder _ content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
    }
}

extension PhotoSuggestionsLabeledContent where Label == Text, Content == Text {

    init<S1: StringProtocol, S2: StringProtocol>(_ label: S1, value: S2) {
        self.init {
            Text(value)
        } label: {
            Text(label)
        }
    }

    init<S, F>(_ label: S, value: F.FormatInput?, format: F) where S: StringProtocol, F : FormatStyle, F.FormatInput : Equatable, F.FormatOutput == String {
        self.init(label, value: value.flatMap { format.format($0) } ?? "")
    }
}

struct AssetImage: UIViewRepresentable {
 
    let asset: PHAsset?

    var mode: AssetImageView.AssetMode = .thumbnail

    func makeUIView(context: Context) -> AssetImageView {
        let assetImageView = AssetImageView()
        assetImageView.assetMode = mode
        assetImageView.backgroundColor = .tertiarySystemBackground
        assetImageView.clipsToBounds = true
        assetImageView.contentMode = .scaleAspectFill
        assetImageView.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        assetImageView.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        assetImageView.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
        assetImageView.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        return assetImageView
    }

    func updateUIView(_ assetImageView: AssetImageView, context: Context) {
        assetImageView.asset = asset
    }
}
