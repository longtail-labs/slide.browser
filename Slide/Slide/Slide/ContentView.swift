//
//  ContentView.swift
//  Slide
//
//  Created by Jordan Howlett on 9/5/25.
//

import AppFeature
import ComposableArchitecture
import Foundation
import SwiftUI

struct ContentView: View {
    let store: StoreOf<SlideAppFeature>
    
    init(store: StoreOf<SlideAppFeature>) {
        self.store = store
    }
    
    var body: some View {
        SlideAppView(store: store)
            .preferredColorScheme(store.state.isDarkMode ? .dark : .light)
    }
}

#Preview {
    ContentView(store: SlideApp.store)
}
