import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

struct DemoOperationDialog<Success: Sendable, Failure: OperationFailure>: View {
    let operationUIController: OwnIDOperationUIController<Success, Failure>
    @StateObject private var containerController: OwnIDUIContainerController

    init(
        operationUIController: OwnIDOperationUIController<Success, Failure>,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.operationUIController = operationUIController
        _containerController = StateObject(wrappedValue: OwnIDUIContainerController(closeAction: onDismiss))
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.42)
                .ignoresSafeArea()
                // close() asks the app-owned dialog to dismiss. The SDK sees the
                // final close only after ownIDOperationContainer reports disappear.
                .onTapGesture { containerController.close() }

            // operationUIController drives the SDK operation UI. containerController
            // is also passed below so the SDK can request app-owned dismissal.
            OwnIDOperationView(
                operationUIController: operationUIController,
                containerController: containerController
            )
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
            .frame(maxWidth: 420)
            .padding(.horizontal, 28)
        }
        // Reports the app-owned dialog root appear/disappear to the same
        // container controller passed to OwnIDOperationView.
        .ownIDOperationContainer(containerController)
        .transition(.opacity)
        .zIndex(1)
    }
}
