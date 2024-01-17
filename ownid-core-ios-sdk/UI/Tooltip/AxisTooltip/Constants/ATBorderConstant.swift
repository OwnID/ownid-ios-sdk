//  Created by jasu on 2022/02/28.
//  Copyright (c) 2022 jasu All rights reserved.

import SwiftUI

/// The definition of a border.
extension OwnID.UISDK {
    struct ATBorderConstant: Equatable {
        
        var radius: CGFloat
        var lineWidth: CGFloat
        var color: Color
        var style: StrokeStyle?
        
        /// Initializes `ATBorderConstant`
        /// - Parameters:
        ///   - radius: The corner radius of the rectangle. The default value is `10`.
        ///   - lineWidth: The width of the stroke that outlines this shape. The default value is `2`.
        ///   - color: The color of the line. The default value is `.white.opacity(0.1)`.
        ///   - style: The stroke characteristics --- such as the line's width and
        ///   whether the stroke is dashed --- that determine how to render this shape. The default value is `nil`.
        init(radius: CGFloat = 10,
             lineWidth: CGFloat = 2,
             color: Color = .white.opacity(0.1),
             style: StrokeStyle? = nil) {
            self.radius = radius
            self.lineWidth = lineWidth
            self.color = color
            self.style = style
        }
    }
}
