import SwiftUI

struct CustomActionButton: View {
    let action: (() -> Void)
    var body: some View {
        Button {
            action()
        } label: {
            VStack {
                Text("Tap Here")
                Image(systemName: "button.programmable.square")
                    .foregroundColor(.red)
            }
        }
    }
}
