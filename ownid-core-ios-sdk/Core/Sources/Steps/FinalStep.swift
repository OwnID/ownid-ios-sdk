import Foundation
import Combine

extension OwnID.CoreSDK.CoreViewModel {
    private enum Constants {
        static let contextKey = "context"
        static let payloadKey = "payload"
        static let loginIdKey = "loginId"
        static let errorKey = "error"
        static let dataKey = "data"
        static let metadataKey = "metadata"
        static let typeKey = "type"
        static let flowInfo = "flowInfo"
        static let authType = "authType"
    }
    
    struct FinalRequestBody: Encodable {
        let sessionVerifier: OwnID.CoreSDK.SessionVerifier
    }

    class FinalStep: BaseStep {
        override func run(state: inout OwnID.CoreSDK.CoreViewModel.State) -> [Effect<OwnID.CoreSDK.CoreViewModel.Action>] {
            let requestBody = FinalRequestBody(sessionVerifier: state.sessionVerifier)
            let requestLanguage = state.supportedLanguages.rawValue.first
            let action = state.session.perform(url: state.finalUrl,
                                               method: .post,
                                               body: requestBody)
                .receive(on: DispatchQueue.main)
                .handleEvents(receiveOutput: { response in
                    OwnID.CoreSDK.logger.log(level: .debug, message: "Final Request Finished", type: Self.self)
                })
                .tryMap { response in
                    let context = response[Constants.contextKey] as? String ?? ""
                    
                    guard let responsePayload = response[Constants.payloadKey] as? [String: Any] else {
                        let message = OwnID.CoreSDK.ErrorMessage.requestError
                        throw OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message))
                    }
                    
                    if let serverError = responsePayload[Constants.errorKey] as? String {
                        throw OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: serverError))
                    }
                    
                    let ownIdData: String?
                    if let data = responsePayload[Constants.dataKey] as? [String: Any] {
                        let jsonData = try JSONSerialization.data(withJSONObject: data)
                        ownIdData = String(data: jsonData, encoding: .utf8)
                    } else {
                        ownIdData = responsePayload[Constants.dataKey] as? String
                    }
                    
                    let loginId = responsePayload[Constants.loginIdKey] as? String ?? ""
                    let metadata = responsePayload[Constants.metadataKey]
                    let stringType = responsePayload[Constants.typeKey] as? String ?? ""
                    var authTypeValue: String?
                    if let flowInfo = response[Constants.flowInfo] as? [String: Any], let authType = flowInfo[Constants.authType] as? String {
                        authTypeValue = authType
                    }
                    let payload = OwnID.CoreSDK.Payload(data: ownIdData,
                                                        metadata: metadata,
                                                        context: context,
                                                        loginId: loginId,
                                                        responseType: OwnID.CoreSDK.StatusResponseType(rawValue: stringType) ?? .registrationInfo,
                                                        authType: OwnID.CoreSDK.AuthType(rawValue: authTypeValue ?? ""),
                                                        requestLanguage: requestLanguage)
                    return payload
                }
                .mapError({ error in
                    if let error = error as? OwnID.CoreSDK.Error {
                        return error
                    }
                    return .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: OwnID.CoreSDK.ErrorMessage.requestError))
                })
                .map { Action.statusRequestLoaded(response: $0) }
                .catch({ error in
                    return Just(Action.error(OwnID.CoreSDK.ErrorWrapper(error: error, type: Self.self)))
                })
                .eraseToEffect()
            return [action]
        }
    }
}
