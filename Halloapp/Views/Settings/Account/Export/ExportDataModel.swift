//
//  ExportDataModel.swift
//  HalloApp
//
//  Created by Matt Geimer on 6/29/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import SwiftUI
import Core
import CoreCommon
import CocoaLumberjackSwift

class ExportDataModel: ObservableObject {
    @Published var status: DataExportRequestStatus = .awaitingResponse
    @Published var readyDate: Date? = nil
    @Published var url: URL? = nil
    
    init(previewMode: Bool = false) {
        if !previewMode {
            MainAppContext.shared.service.exportDataStatus(isSetRequest: false) { [weak self] result in
                DispatchQueue.main.async {
                    withAnimation {
                        switch result {
                            case .success(let exportData): self?.handleExportData(exportData)
                            case .failure(let error): self?.handleRequestError(error)
                        }
                    }
                }
            }
        }
    }
    
    func requestDataPressed() {
        withAnimation {
            status = .awaitingResponse
        }
        
        MainAppContext.shared.service.exportDataStatus(isSetRequest: true) { [weak self] result in
            DispatchQueue.main.async {
                withAnimation {
                    switch result {
                        case .success(let exportData): self?.handleExportData(exportData)
                        case .failure(let error): self?.handleRequestError(error)
                    }
                }
            }
        }
    }
    
    private func handleExportData(_ exportData: Server_ExportData) {
        switch exportData.status {
            case .pending: self.status = .requested
            case .ready: self.status = .available
            default: self.status = .notRequested
        }
        
        if exportData.status == .pending {
            readyDate = Date(timeIntervalSince1970: TimeInterval(exportData.dataReadyTs))
        } else if exportData.status == .ready {
            url = URL(string: exportData.dataURL)
        }
    }
    
    private func handleRequestError(_ error: RequestError) {
        DDLogError("ExportDataModel/handleRequestError: \(error)")
        
        withAnimation {
            status = .notRequested
        }
    }
}

/// Emum representing the current state of the request to export data. This is used to determine how the view should look
enum DataExportRequestStatus {
    case awaitingResponse, notRequested, requested, available
}
