//
//  MediaAlbumsViewController.swift
//  HalloApp
//
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import Foundation
import Photos
import SwiftUI
import UIKit

typealias MediaAlbumsViewControllerCallback = (MediaAlbumsViewController, PHAssetCollection?, Bool) -> Void

private extension Localizations {

    static var albums: String {
        NSLocalizedString("media.albums", value: "Albums", comment: "Refers to albums in Photo Library.")
    }
}

class MediaAlbumsViewController: UIViewController {
    
    private let didFinish: MediaAlbumsViewControllerCallback
    
    init(didFinish: @escaping MediaAlbumsViewControllerCallback) {
        self.didFinish = didFinish
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use init(didFinish:)")
    }
    
    override func viewDidLoad() {
        fetch()
    }

    private func fetch() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .albumRegular, options: nil)
            let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            var albums = [Album]()

            for i in 0..<smartAlbums.count {
                albums.append(Album(smartAlbums[i]))
            }

            for i in 0..<userAlbums.count {
                albums.append(Album(userAlbums[i]))
            }

            DispatchQueue.main.async {
                self.display(albums: albums)
            }
        }
    }

    private func display(albums: [Album]) {
        let hostingController = UIHostingController(rootView: AlbumsView(albums: albums) { [weak self] album, cancel in
            guard let self = self else { return }
            self.didFinish(self, album?.album, cancel)
        })

        self.addChild(hostingController)
        self.view.addSubview(hostingController.view)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        hostingController.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        hostingController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        hostingController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
    }
}

fileprivate class Album : ObservableObject, Identifiable {
    @Published var image: UIImage?
    
    let id: String
    let album: PHAssetCollection
    let title: String
    let count: Int
    
    init(_ album: PHAssetCollection) {
        self.id = album.localIdentifier
        self.album = album
        
        title = album.localizedTitle ?? ""
        count = PHAsset.fetchAssets(in: album, options: nil).count
        
        if count > 0 {
            fetchThumbnail()
        }
    }
    
    func fetchThumbnail() {
        let options = PHFetchOptions()
        options.fetchLimit = 1

        guard let asset = PHAsset.fetchKeyAssets(in: album, options: options)?.firstObject else { return }
        
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 256, height: 256), contentMode: .aspectFill, options: nil) { [weak self] image, _ in
            guard let self = self else { return }
            self.image = image
        }
    }
}

fileprivate struct AlbumsView: View {
    @State var albums: [Album]
    var complete: (Album?, Bool) -> Void
    
    var topBar: some View {
        ZStack {
            HStack {
                Button(action: { self.complete(nil, true) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .bold))
                        .accessibility(label: Text(Localizations.buttonCancel))
                        .padding()
                }
                
                Spacer()
            }
            
            Text(Localizations.albums)
                .font(.gotham(fixedSize: 17, weight: .medium))
        }
    }
    
    var body: some View {
        VStack {
            topBar
            
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(albums) { album in
                        AlbumView(album: album)
                            .contentShape(Rectangle())  // Apply gesture on the whole region and not just on the items
                            .onTapGesture {
                                self.complete(album, false)
                            }
                    }
                }
            }
        }
    }
}

fileprivate struct AlbumView: View {
    @ObservedObject var album: Album
    
    var body: some View {
        album.image.map { image in
            HStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .cornerRadius(8)
                    .clipped()
                    .padding()
                
                VStack(alignment: .leading) {
                    Text(album.title)
                        .fontWeight(.medium)
                    
                    Text("\(album.count)")
                }
                
                Spacer()
            }
        }
    }
}
