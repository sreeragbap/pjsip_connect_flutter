import Flutter
import UIKit
import CallKit
import PushKit
#if canImport(SipCoreModule)
import SipCoreModule
#endif

///////////////////////////////////////////////////////////////////////////////////////////////////
///SipConnectPushRegistry

class SipConnectPushRegistry : NSObject, PKPushRegistryDelegate {
    static let shared = SipConnectPushRegistry()
    private var _callKitProvider : SipConnectCxProvider?
    private let _registry: PKPushRegistry
    private var _token: String?

    private override init() {
        _registry = PKPushRegistry(queue: .main)
        super.init()
        
        _registry.delegate = self
        _registry.desiredPushTypes = [.voIP]
    }

    public func setCallKitProvider(_ callKitProvider : SipConnectCxProvider?) {
        _callKitProvider = callKitProvider
    }

    public func getToken() -> String? {
        if(_token == nil) {
            let data = _registry.pushToken(for: .voIP)
            _token = (data != nil) ? format(data!) : nil
        }
        return _token
    }
    
    func format(_ token: Data) -> String? {
        return token.map { String(format: "%02x", $0) }.joined()
    }
    
    public func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        if(type == .voIP) {
            _token = format(pushCredentials.token)
        }
    }

    public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        if(type == .voIP) {
            _token = nil
        }
    }
           
    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload:
                                PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        if(type == .voIP) {
            _callKitProvider?.didReceiveIncomingPush(payload.dictionaryPayload)
        }
        completion()
    }

}//SipConnectPushRegistry

