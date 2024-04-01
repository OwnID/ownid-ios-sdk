import Gigya
import OwnIDCoreSDK

extension OwnID.GigyaSDK {
    final class ErrorMapper {
        static var allowedActionsErrorCodes = [206001, 206002, 206006, 403102, 403101]
    }
}
