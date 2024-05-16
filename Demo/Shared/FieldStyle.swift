import SwiftUI

extension View {
    func fieldStyle(backgroundColor: Color = Color("gray"), foregroundColor: Color = Color("text")) -> some View {
        self
            .disableAutocorrection(true)
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            .foregroundColor(foregroundColor)
            .background(backgroundColor)
            .cornerRadius(6)
    }
}
