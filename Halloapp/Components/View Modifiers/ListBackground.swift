//
//  ListBackground.swift
//  HalloApp
//
//  Created by Tanveer on 9/18/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import SwiftUI
import UIKit

fileprivate struct RemoveListBackground: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            return content
                .scrollContentBackground(.hidden)
        } else {
            return content
                .onAppear {
                    UITableView.appearance().backgroundColor = .clear
                }
                .onDisappear {
                    UITableView.appearance().backgroundColor = .systemBackground
                }
        }
    }
}

extension View {

    func listBackground<V>(@ViewBuilder content: () -> V) -> some View where V : View {
        self
            .modifier(RemoveListBackground())
            .background {
                content()
            }
    }
}
