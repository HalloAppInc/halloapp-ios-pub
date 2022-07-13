//
//  LocationListViewController.swift
//  HalloApp
//
//  Created by Cay Zhang on 6/30/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon
import Core
import Combine
import MapKit

class LocationListViewController: UIViewController {
    private typealias Section = InsetCollectionView.Section
    private typealias Item = InsetCollectionView.Item

    init(viewModel: LocationListViewModel? = nil) {
        self.viewModel = viewModel ?? .init()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private(set) var viewModel: LocationListViewModel
    private var cancelBag: Set<AnyCancellable> = []
    
    lazy var collectionView: InsetCollectionView = {
        let collectionView = InsetCollectionView()
        collectionView.delegate = self
        
        let layout = InsetCollectionView.defaultLayout()
        let config = InsetCollectionView.defaultLayoutConfiguration()
        layout.configuration = config
        collectionView.collectionViewLayout = layout

        collectionView.backgroundColor = .primaryBg
        collectionView.keyboardDismissMode = .interactive
        return collectionView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        viewModel.$locations
            .sink { [weak self] locations in
                guard let self = self else { return }
                self.collectionView.apply(self.collection(fromLocations: locations))
            }
            .store(in: &cancelBag)
    }

    private func collection(fromLocations locations: [MKMapItem]) -> InsetCollectionView.Collection {
        InsetCollectionView.Collection {
            Section {
                return locations.map { location in
                    Item(title: location.name ?? Localizations.locationSharingUntitledLocation, icon: UIImage(systemName: "location.magnifyingglass")) { [locationSelected = viewModel.locationSelected] in
                        locationSelected.send(location)
                    }
                }
            }
        }
        .seperators()
    }
}

extension LocationListViewController: InsetCollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = self.collectionView.data.itemIdentifier(for: indexPath) as? InsetCollectionView.Item else {
            return
        }
        
        collectionView.deselectItem(at: indexPath, animated: true)
        item.action?()
    }
}

@MainActor
class LocationListViewModel: ObservableObject {
    var cancelBag: Set<AnyCancellable> = []
    
    // MARK: States
    @Published var locations: [MKMapItem] = []
    
    // MARK: Actions
    var updateLocations: PassthroughSubject<[MKMapItem], Never> = .init()
    var locationSelected: PassthroughSubject<MKMapItem, Never> = .init()
    
    init() {
        setupReducer()
    }
    
    func setupReducer() {
        updateLocations
            .assign(to: \.locations, on: self)
            .store(in: &cancelBag)
    }
}
