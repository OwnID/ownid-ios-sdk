//  Created by jasu on 2022/02/17.
//  Copyright (c) 2022 jasu All rights reserved.

import SwiftUI

extension View {
    func axisToolTip<F: View>(isPresented: Binding<Bool>,
                              alignment: Alignment = .center,
                              constant: OwnID.UISDK.ATConstant = .init(),
                              @ViewBuilder foreground: @escaping () -> F) -> some View {
        self.modifier(OwnID.UISDK.AxisTooltip(isPresented: isPresented,
                                              alignment: alignment,
                                              constant: constant,
                                              foreground: foreground))
    }
    
    func axisToolTip<B: View, F: View>(isPresented: Binding<Bool>,
                                       alignment: Alignment = .center,
                                       constant: OwnID.UISDK.ATConstant = .init(),
                                       @ViewBuilder background: @escaping () -> B,
                                       @ViewBuilder foreground: @escaping () -> F) -> some View {
        self.modifier(OwnID.UISDK.AxisTooltip(isPresented: isPresented,
                                              alignment: alignment,
                                              constant: constant,
                                              background: background,
                                              foreground: foreground))
    }
}
