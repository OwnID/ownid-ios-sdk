import Foundation
import Combine

extension OwnID.UISDK.Enroll {
    struct ViewState {
        var isLoading = false
    }
    
    enum Action {
        case viewLoaded
        case cancel
        case continueFlow
        case notNow
    }
}

extension OwnID.UISDK.Enroll {
    static func viewModelReducer(state: inout ViewState, action: Action) -> [Effect<Action>] {
        switch action {
        case .viewLoaded:
            state.isLoading = false
        case .cancel:
            state.isLoading = false
        case .continueFlow:
            state.isLoading = true
        case .notNow:
            state.isLoading = false
        }
        return []
    }
}
