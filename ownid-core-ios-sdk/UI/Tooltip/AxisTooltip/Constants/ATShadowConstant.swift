//  Created by jasu on 2022/02/28.
//  Copyright (c) 2022 jasu All rights reserved.

import SwiftUI

/// Defines the shadow of the tooltip.
extension OwnID.UISDK {
    struct ATShadowConstant: Equatable {
        
        var color: Color
        var radius: CGFloat
        var x: CGFloat
        var y: CGFloat
        
        /// Initializes `ATShadowConstant`
        /// - Parameters:
        ///   - color: The shadow's color. The default value is `.black.opacity(0.3)`.
        ///   - radius: The shadow's size. The default value is `3`.
        ///   - x: A horizontal offset you use to position the shadow relative to the tooltip. The default value is `0`.
        ///   - y: A vertical offset you use to position the shadow relative to the tooltip. The default value is `0`.
        init(color: Color = .black.opacity(0.3),
                    radius: CGFloat = 3,
                    x: CGFloat = 0,
                    y: CGFloat = 0) {
            self.color = color
            self.radius = radius
            self.x = x
            self.y = y
        }
    }
}
