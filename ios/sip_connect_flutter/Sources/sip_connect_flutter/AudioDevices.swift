import Flutter
import UIKit
import CallKit
import PushKit
#if canImport(SipCoreModule)
import SipCoreModule
#endif

///////////////////////////////////////////////////////////////////////////////////////////////////
///AudioDevices

class AudioDevices {
    private var _isBtConnected: Bool = false
    private var _eventHandler : SipConnectEventHandler?
    static let kOutSpeaker=0
    static let kOutEarPiece=1
    static let kRouteBuildIn=2
    static let kRouteBluetooth=3
    
    public func configure(_ eventHandler : SipConnectEventHandler) {
        _eventHandler = eventHandler
        checkIsBtConnected(notify: false)
        addObserverForRouteChangeNotification()
    }

    deinit {
        removeObserverRouteChangeNotification()
    }
    
    func getCount() -> Int {
        return _isBtConnected ? 4 : 3
    }
        
    func getName(_ dvcIndex: Int) -> String {
        switch(dvcIndex) {
            case AudioDevices.kOutSpeaker:     return "Speaker"
            case AudioDevices.kOutEarPiece:    return "Earpiece"
            case AudioDevices.kRouteBuildIn:   return "BuiltIn"
            case AudioDevices.kRouteBluetooth: return "Bluetooth"
            default:                           return "---"
        }
    }
    
    private func checkIsBtConnected(notify : Bool){
        let currentRouteOutputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let btPorts: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        let newBtConnected = currentRouteOutputs.contains { btPorts.contains($0.portType) }
        if(newBtConnected == _isBtConnected) { return }
        
        _isBtConnected = newBtConnected
        if(notify) {  _eventHandler?.onDevicesAudioChanged() }
        print("sipconnect: isBtConnected: \(_isBtConnected)")
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        // Check whenever a new device is connected or disconnected
        if((reason == .newDeviceAvailable)||(reason == .newDeviceAvailable)){
            checkIsBtConnected(notify: true)
        }
    }
    
    private func addObserverForRouteChangeNotification() {
        NotificationCenter.default.addObserver(self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    private func removeObserverRouteChangeNotification() {
        NotificationCenter.default.removeObserver(self)
    }
}

