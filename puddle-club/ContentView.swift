//
//  ContentView.swift
//  puddle-club
//
//  Created by Matthew Pence on 3/3/26.
//

import SwiftUI

struct ContentView: View {
    @State private var searchText = ""
    @State private var isSearchFocused = false

    var body: some View {
        HomeView(searchText: $searchText)
            .safeAreaInset(edge: .bottom) {
                FloatingSearchBar(text: $searchText, isFocused: $isSearchFocused)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
    }
}

