import SwiftUI
import Gigya
import DemoComponents

struct LogInView: View {
    @ObservedObject var viewModel: LogInViewModel
    
    var body: some View {
        page()
    }
}

private extension LogInView {
    
    @ViewBuilder
    func page() -> some View {
        switch viewModel.state {
        case .loading:
            content()
                .loading()
            
        default:
            content()
        }
    }
    
    @ViewBuilder
    func content() -> some View {
        VStack {
            Text("OwnID Demo\nGigya Screensets")
                .font(.title)
                .multilineTextAlignment(.center)
                .verticalFixedSizeMultiline()
                .padding()
            Text("OwnID enables your users to create a digital identity on their phone to instantly login to your websites or apps.")
                .font(.body)
                .multilineTextAlignment(.center)
                .verticalFixedSizeMultiline()
                .padding()
            Text("Passwords are finally gone.")
                .bold()
                .multilineTextAlignment(.center)
                .verticalFixedSizeMultiline()
                .padding()
            if case .loading = viewModel.state {
                createScreenSetsView()
            }
            error()
            BlueButton(text: "Sign In", action: viewModel.logIn)
        }
    }
    
    @ViewBuilder
    func error() -> some View {
        if let error = viewModel.inlineError {
            inlineError(for: error)
        }
    }
    
    func createScreenSetsView() -> some View {
        let view = ScreenSetsView(screensetResult: viewModel.screensetResult)
        return view
    }
}

