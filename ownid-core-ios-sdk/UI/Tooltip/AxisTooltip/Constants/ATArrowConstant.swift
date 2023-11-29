//  Created by jasu on 2022/02/28.
//  Copyright (c) 2022 jasu All rights reserved.

import SwiftUI

/// The definition of arrow indication.
extension OwnID.UISDK {
    struct ATArrowConstant: Equatable {
        
        var width: CGFloat
        var height: CGFloat
        
        /// Initializes `ATArrowConstant`
        /// - Parameters:
        ///   - width: The width of the arrow. The default value is `10`.
        ///   - height: The height of the arrow. The default value is `10`.
        init(width: CGFloat = 10, height: CGFloat = 10) {
            self.width = width
            self.height = height
        }
    }
}
