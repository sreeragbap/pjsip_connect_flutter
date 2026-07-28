import Flutter
import UIKit
import CallKit
import PushKit
#if canImport(SipCoreModule)
import SipCoreModule
#endif

////////////////////////////////////////////////////////////////////////////////////////
//SipConnectEventHandler
class SipConnectEventHandler : NSObject, SipCoreEventDelegate {
    private var _channel : FlutterMethodChannel
    private var _callKitProvider : SipConnectCxProvider?
    private var _pushKitDisabled : Bool = true
    private var _ringer : Ringer?

    init(withChannel channel:FlutterMethodChannel) {
        self._channel      = channel
    }
    
    public func setRingTonePath(_ path : String) {
        DispatchQueue.main.async {
            self._ringer?.setRingTonePath(path)
        }
    }
    
    public func configure(_ callKitProvider : SipConnectCxProvider?, pushKitProvider : SipConnectPushRegistry?) {
        _pushKitDisabled = (pushKitProvider==nil)
        _callKitProvider = callKitProvider
        _ringer = (callKitProvider == nil) ? Ringer() : nil // Create ringer when CallKit disabled
    }
    
    public func didReceiveIncomingPush(_ dictionaryPayload : [AnyHashable : Any], callKit_callUUID: String) {
        var argsMap = [String:Any]()
        argsMap[kArgCallKitUuid] = callKit_callUUID
        argsMap[kArgPushPayload] = dictionaryPayload
        _channel.invokeMethod(kOnPushIncoming, arguments: argsMap)
    }
    
    //////////////////////////////////////////////////////////////////////////
    //Event handlers
    
    public func onTrialModeNotified() {
        DispatchQueue.main.async {
            let argsMap = [String:Any]()
            self._channel.invokeMethod(kOnTrialModeNotif, arguments: argsMap)
        }
    }

    public func onDevicesAudioChanged() {
        DispatchQueue.main.async {
            let argsMap = [String:Any]()
            self._channel.invokeMethod(kOnDevicesChanged, arguments: argsMap)
        }
    }

    public func onAccountRegState(_ accId: Int, regState: RegState, response: String) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgAccId] = accId
            argsMap[kRegState] = regState.rawValue
            argsMap[kResponse] = response
            self._channel.invokeMethod(kOnAccountRegState, arguments: argsMap)
        }
    }
    
    public func onSubscriptionState(_ subscrId: Int, subscrState: SubscrState, response: String) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgSubscrId] = subscrId
            argsMap[kSubscrState] = subscrState.rawValue
            argsMap[kResponse] = response
            self._channel.invokeMethod(kOnSubscriptionState, arguments: argsMap)
        }
    }
    
    public func onNetworkState(_ name: String, netState: NetworkState) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgName] = name
            argsMap[kNetState] = netState.rawValue
            self._channel.invokeMethod(kOnNetworkState, arguments: argsMap)
        }
    }

    public func onPlayerState(_ playerId: Int, playerState: PlayerState) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgPlayerId] = playerId
            argsMap[kPlayerState] = playerState.rawValue
            self._channel.invokeMethod(kOnPlayerState, arguments: argsMap)
        }
    }
    
    public func onRingerState(_ started: Bool) {    
        DispatchQueue.main.async {
            if(started) { self._ringer?.play() }
            else        { self._ringer?.stop() }
        }
    }

    public func onCallProceeding(_ callId: Int, response:String){
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgCallId] = callId
            argsMap[kResponse] = response
            self._channel.invokeMethod(kOnCallProceeding, arguments: argsMap)
            self._callKitProvider?.onSipProceeding(callId)
        }
    }

    public func onCallTerminated(_ callId: Int, statusCode:Int) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgCallId] = callId
            argsMap[kArgStatusCode] = statusCode
            self._channel.invokeMethod(kOnCallTerminated, arguments: argsMap)
            self._callKitProvider?.onSipTerminated(callId)
        }
    }

    public func onCallConnected(_ callId: Int, hdrFrom:String, hdrTo:String, withVideo:Bool) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgWithVideo] = withVideo
            argsMap[kArgCallId] = callId
            argsMap[kFrom] = hdrFrom
            argsMap[kTo] = hdrTo
            self._channel.invokeMethod(kOnCallConnected, arguments: argsMap)
            self._callKitProvider?.onSipConnected(callId, withVideo:withVideo)
        }
    }

    public func onCallIncoming(_ callId:Int, accId:Int, withVideo:Bool, hdrFrom:String, hdrTo:String) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgWithVideo] = withVideo
            argsMap[kArgCallId] = callId
            argsMap[kArgAccId] = accId
            argsMap[kFrom] = hdrFrom
            argsMap[kTo] = hdrTo
            self._channel.invokeMethod(kOnCallIncoming, arguments: argsMap)
            
            if(self._pushKitDisabled) {
                self._callKitProvider?.onSipIncoming(callId, withVideo:withVideo, hdrFrom:hdrFrom, hdrTo:hdrTo)
            }
        }
    }

    public func onCallDtmfReceived(_ callId:Int, tone:Int) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgCallId] = callId
            argsMap[kArgTone] = tone
            self._channel.invokeMethod(kOnCallDtmfReceived, arguments: argsMap)
        }
    }

    public func onCallSwitched(_ callId:Int) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgCallId] = callId
            self._channel.invokeMethod(kOnCallSwitched, arguments: argsMap)
        }
    }
    
    public func onCallTransferred(_ callId:Int, statusCode:Int) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgCallId] = callId
            argsMap[kArgStatusCode] = statusCode
            self._channel.invokeMethod(kOnCallTransferred, arguments: argsMap)
        }
    }

    public func onCallRedirected(_ origCallId: Int, relatedCallId: Int, referTo: String) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgFromCallId] = origCallId
            argsMap[kArgToCallId] = relatedCallId
            argsMap[kArgToExt] = referTo
            self._channel.invokeMethod(kOnCallRedirected, arguments: argsMap)
            self._callKitProvider?.onSipRedirected(origCallId:origCallId, relatedCallId:relatedCallId, referTo:referTo)
        }
    }

    public func onCallVideoUpgraded(_ callId: Int, withVideo:Bool) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgCallId] = callId
            argsMap[kArgWithVideo] = withVideo
            self._channel.invokeMethod(kOnCallVideoUpgraded, arguments: argsMap)
        }
    }

    public func onCallVideoUpgradeRequested(_ callId: Int) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgCallId] = callId
            self._channel.invokeMethod(kOnCallVideoUpgradeRequested, arguments: argsMap)
        }
    }

    public func onCallHeld(_ callId:Int, holdState:HoldState) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgCallId] = callId
            argsMap[kHoldState] = holdState.rawValue
            self._channel.invokeMethod(kOnCallHeld, arguments: argsMap)
        }
    }

    public func onMessageSentState(_ messageId:Int, success:Bool, response:String) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgMsgId] = messageId
            argsMap[kSuccess] = success
            argsMap[kResponse] = response
            self._channel.invokeMethod(kOnMessageSentState, arguments: argsMap)
        }
    }

    public func onMessageIncoming(_ messageId:Int, accId:Int, hdrFrom:String, body:String) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgMsgId] = messageId
            argsMap[kArgAccId] = accId
            argsMap[kFrom] = hdrFrom
            argsMap[kBody] = body
            self._channel.invokeMethod(kOnMessageIncoming, arguments: argsMap)
        }
    }

    public func onSipNotify(_ accId:Int, hdrEvent:String, body:String) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgAccId] = accId
            argsMap[kEvent] = hdrEvent
            argsMap[kBody] = body
            self._channel.invokeMethod(kOnSipNotify, arguments: argsMap)
        }
    }

    public func onVuMeterLevel(_ micLevel:Int, spkLevel:Int) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kMicLevel] = micLevel
            argsMap[kSpkLevel] = spkLevel
            self._channel.invokeMethod(kOnVuMeterLevel, arguments: argsMap)
        }
    }
    
    public func onCallKitMuted(_ callId:Int, mute:Bool) {
        DispatchQueue.main.async {
            var argsMap = [String:Any]()
            argsMap[kArgCallId] = callId
            argsMap[kArgMute] = mute
            self._channel.invokeMethod(kOnCallKitMuted, arguments: argsMap)
        }
    }
}

