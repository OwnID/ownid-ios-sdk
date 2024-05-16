import SwiftUI

struct AppCoordinatorView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack {
                    HeaderView()
                    container()
                        .padding(.top)
                        .padding(.top)
                }
            }
        }
        .ignoresSafeArea()
    }
    
    func container() -> some View {
        appContent()
            .padding(EdgeInsets(top: 24, leading: 7, bottom: 24, trailing: 7))
    }

    @ViewBuilder
    func appContent() -> some View {
        LoggedOutCoordinatorView()
            .padding(.top)
            .padding(.bottom)
            .background(Color("tabsBackground").cornerRadius(6))
    }
}
