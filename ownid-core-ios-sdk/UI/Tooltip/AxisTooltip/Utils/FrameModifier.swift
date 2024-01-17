//  Created by jasu on 2022/02/27.
//  Copyright (c) 2022 jasu All rights reserved.

import SwiftUI

extension OwnID.UISDK {
    struct FrameModifier: ViewModifier {
        
        @Binding var rect: CGRect
        
        init(_ rect: Binding<CGRect>) {
            _rect = rect
        }
        
        func body(content: Content) -> some View {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: FramePreferenceKey.self, value: proxy.frame(in: .global))
                    }
                )
                .onPreferenceChange(FramePreferenceKey.self) { preference in
                    self.rect = preference
                }
        }
    }
    
    struct FramePreferenceKey: PreferenceKey {
        typealias V = CGRect
        static var defaultValue: V = .zero
        static func reduce(value: inout V, nextValue: () -> V) {
            value = nextValue()
        }
    }
}

extension View {
    func takeFrame(_ rect: Binding<CGRect>) -> some View {
        self.modifier(OwnID.UISDK.FrameModifier(rect))
    }
}
