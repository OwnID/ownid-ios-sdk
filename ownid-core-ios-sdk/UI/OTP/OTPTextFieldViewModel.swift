import SwiftUI
import Combine

extension OwnID.UISDK.OneTimePassword {
    final class ViewModel: ObservableObject {
        private enum Constants {
            static let characterLimit = 1
            static let zeroWidthSpaceCharacter = "\u{200B}"
        }
        
        private enum Direction {
            case forward, backward
        }
        
        init(codeLength: Int,
             store: Store<OwnID.UISDK.OneTimePassword.ViewState, OwnID.UISDK.OneTimePassword.Action>,
             context: OwnID.CoreSDK.Context?,
             operationType: OwnID.UISDK.OneTimePassword.OperationType,
             loginId: String,
             eventService: EventProtocol = OwnID.CoreSDK.eventService) {
            self.codeLength = codeLength
            self.store = store
            self.context = context
            self.loginId = loginId
            self.operationType = operationType
            self.eventService = eventService
            storage = Array(repeating: "", count: codeLength + 1)
            codes = Array(repeating: Constants.zeroWidthSpaceCharacter, count: codeLength)
            
            store.send(.viewLoaded)
        }
        
        let codeLength: Int
        let context: OwnID.CoreSDK.Context?
        let eventService: EventProtocol
        let operationType: OwnID.UISDK.OneTimePassword.OperationType
        
        private let loginId: String
        private let store: Store<OwnID.UISDK.OneTimePassword.ViewState, OwnID.UISDK.OneTimePassword.Action>
        private var storage: [String]
        
        @Published var codes: [String]
        @Published var nextUpdateAction: NextUpdateAcion?
        @Published var isDisabled = false
        private var disableTextFields = false
        
        @Published var currentFocusedFieldIndex: Int?
        
        private var isResetting = false
        private var direction: Direction = .forward
        private var directionWasChanged = false
        private var codeWasPasted = false
        
        private func storeFieldValue(index: Int, value: String) {
            storage[index] = value
        }
        
        func combineCode() -> String {
            let code = storage.reduce("", +)
            return code
        }
        
        private func submitCode() {
            disableTextFields = true
            let code = combineCode()
            if code.count == codeLength {
                store.send(.codeEntered(code: code, operationType: operationType))
            }
        }
        
        func processTextChange(for index: Int, binding: Binding<String>) {
            store.send(.codeEnteringStarted)
            
            let currentBindingValue = binding.wrappedValue
            let actualValue = currentBindingValue.replacingOccurrences(of: Constants.zeroWidthSpaceCharacter, with: "")
            if actualValue.count > Constants.characterLimit {
                binding.wrappedValue = String(actualValue.prefix(Constants.characterLimit))
            }
            
            if !actualValue.isNumber {
                binding.wrappedValue = Constants.zeroWidthSpaceCharacter
            }
            
            guard !isResetting else {
                if index == codeLength - 1 || codeWasPasted {
                    disableTextFields = false
                    isResetting = false
                    codeWasPasted = false
                    currentFocusedFieldIndex = 0
                }
                return
            }
            
            guard !disableTextFields else {
                return
            }
            
            let nextActionIsAddZero = nextUpdateAction == .addEmptySpace
            if actualValue.isEmpty, !nextActionIsAddZero {
                if direction == .forward {
                    direction = .backward
                    directionWasChanged = true
                }
                binding.wrappedValue = Constants.zeroWidthSpaceCharacter
                nextUpdateAction = .addEmptySpace
                focusOnNextLeftField(fieldIndex: index)
                return
            }
            if nextActionIsAddZero {
                nextUpdateAction = .none
                //logic for UITextField
                if #unavailable(iOS 16.0), directionWasChanged {
                    directionWasChanged = false
                    return
                }
            }
            if case .updatingFromPasteboard = nextUpdateAction {
                return
            }
            if actualValue.count == codeLength {
                processPastedCode(actualValue)
                return
            }
            
            var nextFieldValue = ""
            if actualValue.count > Constants.characterLimit {
                let current = actualValue
                nextFieldValue = String(current.dropFirst(Constants.characterLimit).prefix(Constants.characterLimit))
                binding.wrappedValue = String(actualValue.prefix(Constants.characterLimit))
                nextUpdateAction = .update(nextFieldValue)
                return
            }
            storeFieldValue(index: index, value: actualValue)
            moveFocusAndSubmitCodeIfNeeded(index, actualValue)
        }
        
        func resetCode() {
            isResetting = true
            for i in 0..<codes.count {
                codes[i] = Constants.zeroWidthSpaceCharacter
            }
            storage = Array(repeating: "", count: codeLength + 1)
        }
        
        func disableCodes() {
            isDisabled = true
        }
    }
}

private extension OwnID.UISDK.OneTimePassword.ViewModel {
    func moveFocusAndSubmitCodeIfNeeded(_ index: Int, _ actualValue: String) {
        if actualValue.isEmpty {
            focusOnNextLeftField(fieldIndex: index)
        } else {
            if index == codeLength - 1 {
                submitCode()
            } else {
                if direction == .backward {
                    direction = .forward
                    directionWasChanged = true
                }
                currentFocusedFieldIndex = index + 1
                if case .update(let value) = nextUpdateAction {
                    nextUpdateAction = .none
                    codes[index] = value
                }
            }
        }
    }
    
    func processPastedCode(_ actualValue: String) {
        let eventCategory: OwnID.CoreSDK.EventCategory = store.value.type == .login ? .login : .registration
        eventService.sendMetric(.trackMetric(action: .userPastedCode,
                                             category: eventCategory,
                                             context: context,
                                             loginId: loginId,
                                             source: operationType.metricName))
        codeWasPasted = true
        nextUpdateAction = .updatingFromPasteboard
        let fieldValue = actualValue
        for index in 0...codeLength - 1 {
            let character = fieldValue.prefix(index + 1).suffix(1)
            let codeNumber = String(character)
            codes[index] = codeNumber
            storeFieldValue(index: index, value: codeNumber)
        }
        submitCode()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.nextUpdateAction = .none
        }
    }
    
    func focusOnNextLeftField(fieldIndex: Int) {
        guard fieldIndex > 0 else { return }
        currentFocusedFieldIndex = fieldIndex - 1
    }
}

extension OwnID.UISDK.OneTimePassword.ViewModel {
    enum NextUpdateAcion: Equatable {
        case update(String)
        case updatingFromPasteboard
        case addEmptySpace
    }
}

private extension String {
    var isNumber: Bool {
        let digitsCharacters = CharacterSet(charactersIn: "0123456789")
        return CharacterSet(charactersIn: self).isSubset(of: digitsCharacters)
    }
}
