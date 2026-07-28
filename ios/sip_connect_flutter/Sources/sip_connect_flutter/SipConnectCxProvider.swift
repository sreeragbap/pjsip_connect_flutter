import Flutter
import UIKit
import CallKit
import PushKit
#if canImport(SipCoreModule)
import SipCoreModule
#endif

///////////////////////////////////////////////////////////////////////////////////////////////////
///SipConnectCxProvider

class SipConnectCxProvider : NSObject, CXProviderDelegate {
    private let _sipModule : SipCoreModule
    private let _eventHandler : SipConnectEventHandler
    private let _cxProvider: CXProvider!
    private let _cxCallCtrl: CXCallController
    private let _allowMuteByCallKit: Bool
    private let _reportCallAsVideo: Bool
    private var _callsList: [CallModel] = []
    private var _isAudioSessionActivated = false
    private var _isEnabledPushKit = false

    static let kECallNotFound: Int32       = -1040
    static let kEConfRequires2Calls: Int32 = -1055
    
    init(_ module:SipCoreModule, eventHandler:SipConnectEventHandler, 
         singleCallMode:Bool, includeInRecents:Bool, 
         allowMuteByCallKit:Bool, isEnabledPushKit:Bool, reportCallAsVideo:Bool) {
        _sipModule = module
        _eventHandler = eventHandler
        _allowMuteByCallKit = allowMuteByCallKit
        _reportCallAsVideo = reportCallAsVideo
        _isEnabledPushKit = isEnabledPushKit
        
        _cxCallCtrl = CXCallController()
        _cxProvider = CXProvider(configuration: Self.makeConfig(singleCallMode, includeInRecents:includeInRecents))
        
        super.init()
        _cxProvider.setDelegate(self, queue: DispatchQueue.main)
    
        _sipModule.writeLog("CxProvider: created")
    }
        
    //--------------------------------------------------------
    //Event handlers
    
    func containsCall(_ callId: Int) -> Bool {
        return _callsList.contains(where: {$0.id == callId})
    }
        
    func contains2Calls() ->Bool {
        return (_callsList.count > 1)
    }
        
    func onSipProceeding(_ callId: Int) {
        let call = _callsList.first(where: {$0.id == callId})
        if(call != nil) {
            _cxProvider.reportOutgoingCall(with:call!.uuid, startedConnectingAt: nil) //now
        }
    }
    
    func onSipTerminated(_ callId: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
            self?.manualDeactivateAudioSession()
        }

        let callIdx = _callsList.firstIndex(where: {$0.id == callId})
        if(callIdx == nil) {
            _sipModule.writeLog("CxProvider: onSipTerminated call not found callId:\(callId)")
            return
        }

        let call = self._callsList[callIdx!]
            
        call.cxEndAction?.fulfill()
        call.cxEndAction = nil

        if(!call.endedByLocalSide) {
            var reason : CXCallEndedReason = .failed
            if(call.connectedSuccessfully || call.isIncoming) {  reason = .remoteEnded } else
            if(!call.isIncoming) { reason = .unanswered }
            
            self._cxProvider.reportCall(with:call.uuid, endedAt: nil, reason: reason)
        }
        //Remove call item from collection
        _callsList.remove(at:callIdx!)
        _sipModule.writeLog("CxProvider: onSipTerminated remove callId:\(call.id) <=> \(call.uuid)")
    }
    
    func onSipConnected(_ callId: Int, withVideo:Bool) {
        //Activate audio (case when enabled PushKit+CallKit, but push notif hasn't received or didActivate hasn't triggered)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
            self?.manualActivateAudioSession()
        }

        //Find call
        let call = self._callsList.first(where: {$0.id == callId})
        if(call == nil) {
            _sipModule.writeLog("CxProvider: onSipConnected not found callId:\(callId)")
            return
        }

        //Set 'connected' time of the outgoing call
        call!.connectedSuccessfully = true
        if(!call!.isIncoming) {
            _cxProvider.reportOutgoingCall(with:call!.uuid, connectedAt: nil)
        }

        //Update 'withVideo' flag
        //if(call!.withVideo != withVideo) {
            call!.withVideo = withVideo

            let update = CXCallUpdate()
            update.hasVideo = withVideo
            update.supportsHolding = true
            update.supportsDTMF = true
            update.supportsGrouping = true
            update.supportsUngrouping = true
            _cxProvider.reportCall(with: call!.uuid, updated: update)
            _sipModule.writeLog("CxProvider: onSipConnected callId:\(callId)")
        //}
    }
    
    func manualActivateAudioSession() {
        //Case when enabled PushKit+CallKit, but push notif hasn't received or didActivate hasn't triggered
        if(!_isAudioSessionActivated && _isEnabledPushKit) {
            _sipModule.writeLog("CxProvider: manually activate audio session")
            _sipModule.activate(AVAudioSession.sharedInstance())
            _isAudioSessionActivated = true
        }
    }

    func manualDeactivateAudioSession() {
        if(_isAudioSessionActivated && _isEnabledPushKit && _callsList.isEmpty) {
            _sipModule.writeLog("CxProvider: manually deactivate audio session")
            _sipModule.deactivate(AVAudioSession.sharedInstance())
            _isAudioSessionActivated = false
        }
    }

    func preConfigureAudioSession(_ withVideo:Bool) {
        guard _callsList.isEmpty else { return }

        let sharedSession = AVAudioSession.sharedInstance()
        do {
            _sipModule.writeLog("CxProvider: preConfigure AVAudioSession")
            try sharedSession.setCategory(.playAndRecord, mode: withVideo ? .videoChat : .voiceChat,
                                          options: [.allowBluetooth, .mixWithOthers])
            try sharedSession.setActive(false)
        } catch {
            _sipModule.writeLog("CxProvider: failed to configure AVAudioSession: \(error.localizedDescription)")
        }
    }

    func onSipIncoming(_ callId:Int, withVideo:Bool, hdrFrom:String, hdrTo:String) {
        let call = CallModel(callId:callId, withVideo:withVideo, from:hdrFrom)
        _callsList.append(call)
        
        reportNewIncomingCall(call)
        _sipModule.writeLog("CxProvider: onSipIncoming - added new call with uuid:\(call.uuid)")
    }

    public func onPushIncoming() -> String {
        _sipModule.handleIncomingPush()
        preConfigureAudioSession(_reportCallAsVideo)

        let call = CallModel(callId:kInvalidId, withVideo:_reportCallAsVideo, from:"SipConnectPushKit")
        _callsList.append(call)
        
        reportNewIncomingCall(call)
        
        _sipModule.writeLog("CxProvider: onPushIncoming - added new call with uuid:\(call.uuid)")
        return call.uuid.uuidString
    }

    public func didReceiveIncomingPush(_ dictionaryPayload : [AnyHashable : Any]) {
        _sipModule.writeLog("CxProvider: didReceiveIncomingPushWith: \(dictionaryPayload)")
        let callKit_callUUID = onPushIncoming()
        _eventHandler.didReceiveIncomingPush(dictionaryPayload, callKit_callUUID:callKit_callUUID)
    }

    func reportNewIncomingCall(_ call : CallModel) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: call.fromTo)
        update.hasVideo = call.withVideo || _reportCallAsVideo
        update.supportsUngrouping = true
        update.supportsGrouping = true
        update.supportsHolding = true
        update.supportsDTMF = true
        
        _cxProvider.reportNewIncomingCall(with: call.uuid, update: update,
                                 completion: { error in self.printResult("CXCallUpdate", err:error)
        })
    }

    func proceedCxAnswerAction(_ call: CallModel) {
        call.answeredByCallKit = false
        let err = _sipModule.callAccept(Int32(call.id), withVideo:call.withVideo)
        if (err == kErrorCodeEOK) { call.cxAnswerAction?.fulfill() }
        else                      { call.cxAnswerAction?.fail()    }
        _sipModule.writeLog("CxProvider: proceedCxAnswerAction err:\(err) sipCallId:\(call.id) uuid:\(call.uuid))")
    }

    func proceedCxEndAction(_ call: CallModel) {
        var err = kErrorCodeEOK
        if(call.isIncoming && !call.connectedSuccessfully) {
            err = _sipModule.callReject(Int32(call.id), statusCode:486) }
        else {
            call.endedByLocalSide = true
            err = _sipModule.callBye(Int32(call.id))
        }
                    
        if (err != kErrorCodeEOK) {
            call.cxEndAction?.fail()
        }
        _sipModule.writeLog("CxProvider: proceedCxEndAction err:\(err) sipCallId:\(call.id) uuid:\(call.uuid))")
    }

    public func getCallKitUUID(_ callId:Int) -> String? {
        let call = _callsList.first(where: {$0.id == callId})
        return call?.uuid.uuidString;
    }

    public func sipAppUpdateCallDetails(_ callKit_callUUID:UUID, callId:Int?,
                                       localizedName:String?, genericHandle:String?, withVideo:Bool?) {
        let call = self.getCallByUUID(callKit_callUUID)
        if(call == nil) {
            self._sipModule.writeLog("CxProvider: sipAppUpdateCallDetails uuid:\(callKit_callUUID) call not found")
            return
        }
        
        if(callId != nil) {
            //INVITE received - match SIP callId and UUID
            self._sipModule.writeLog("CxProvider: sipAppUpdateCallDetails uuid:\(callKit_callUUID) set sipCallId:\(callId!)")
            call!.setSipCallId(callId: callId!, withVideo: withVideo)
            
            if(call!.rejectedByCallKit) {
                self.proceedCxEndAction(call!)
            }
            else if(call!.answeredByCallKit) {
                self.proceedCxAnswerAction(call!)
            }
        }

        if((genericHandle != nil)||(localizedName != nil)||(withVideo != nil)) {
            self._sipModule.writeLog("CxProvider: sipAppUpdateCallDetails uuid:\(callKit_callUUID) genericHandle:\(String(describing: genericHandle)) localizedName:\(String(describing: localizedName)) withVideo:\(String(describing: withVideo))")
            
            let update = CXCallUpdate()
            if(genericHandle != nil) { update.remoteHandle = CXHandle(type: .generic, value: genericHandle!) }
            if(localizedName != nil) { update.localizedCallerName = localizedName! }
            if(withVideo != nil)     { update.hasVideo = withVideo! }

            update.supportsUngrouping = true
            update.supportsGrouping = true
            update.supportsHolding = true
            update.supportsDTMF = true
            
            self._cxProvider.reportCall(with: call!.uuid, updated: update)
        }
    }

    public func onSipRedirected(origCallId: Int, relatedCallId: Int, referTo: String) {
        let origCall = _callsList.first(where: {$0.id == origCallId})//Find 'origCallId'
        if(origCall != nil) {
            //Clone 'origCall' and add to collection of calls as related one
            _callsList.append(CallModel(callId:relatedCallId, withVideo:origCall!.withVideo, from:origCall!.fromTo))
        }
    }
    
    //--------------------------------------------------------
    //Actions

    private static func makeConfig(_ singleCallMode : Bool, includeInRecents : Bool) ->CXProviderConfiguration {
        let providerConfiguration : CXProviderConfiguration
        if #available(iOS 14.0, *) {
            providerConfiguration = CXProviderConfiguration()
        } else {
            providerConfiguration = CXProviderConfiguration(localizedName: "AppName")
        }
        
        providerConfiguration.supportsVideo = true
        providerConfiguration.includesCallsInRecents = includeInRecents
        providerConfiguration.maximumCallGroups = singleCallMode ? 1 : 5
        providerConfiguration.maximumCallsPerCallGroup = singleCallMode ? 1 : 5
        providerConfiguration.supportedHandleTypes = [.phoneNumber, .generic]
        
        if let iconMaskImage = UIImage(named: "CallKitIcon") {
            providerConfiguration.iconTemplateImageData = iconMaskImage.pngData()
        }
        return providerConfiguration
    }

    func cxActionNewOutgoingCall(_ destData : SipCoreDestData) {
        //Hold existing calls
        let transaction = CXTransaction()
        _callsList.forEach { call in
            if(!call.isHeld) {
                transaction.addAction(CXSetHeldCallAction(call: call.uuid, onHold: true))
            }
        }

        //Add new call
        let call = CallModel(destData)
        _callsList.append(call)

        let handle = CXHandle(type: .generic, value: destData.toExt)
        let startAction = CXStartCallAction(call: call.uuid, handle: handle)
        startAction.isVideo = call.withVideo
        transaction.addAction(startAction)

        _cxCallCtrl.request(transaction) { error in self.printResult("CXStart", err:error) }
    }

    func cxActionPlayDtmf(_ callId:Int, digits: String) -> Int32 {
        let call = _callsList.first(where: {$0.id == callId})
        if(call != nil) {
            let action = CXPlayDTMFCallAction(call: call!.uuid, digits: digits, type: .singleTone)
            let transaction = CXTransaction(action: action)
        
            _cxCallCtrl.request(transaction) { error in self.printResult("CXPlayDTMF", err:error) }
            return kErrorCodeEOK;
        }
        return SipConnectCxProvider.kECallNotFound
    }

    func cxActionSetHeld(_ callId:Int) -> Int32 {
        let call = _callsList.first(where: {$0.id == callId})
        if(call != nil) {
            let action = CXSetHeldCallAction(call: call!.uuid, onHold: !call!.isHeld)
            let transaction = CXTransaction(action: action)
        
            _cxCallCtrl.request(transaction) { error in self.printResult("CXSetHeld", err:error) }
            return kErrorCodeEOK;
        }
        return SipConnectCxProvider.kECallNotFound
    }

    func cxActionSetMuted(_ callId:Int, muted: Bool) -> Int32 {
        _sipModule.writeLog("CxProvider: action CXSetMuted callId:\(callId) muted:\(muted)")
        
        let call = _callsList.first(where: {$0.id == callId})
        if(call != nil) {
            call!.micMuted = muted
            let action = CXSetMutedCallAction(call: call!.uuid, muted: muted)
            let transaction = CXTransaction(action: action)
        
            _cxCallCtrl.request(transaction) { error in self.printResult("CXSetMuted", err:error) }
            return kErrorCodeEOK;
        }
        return SipConnectCxProvider.kECallNotFound
    }
    
    public func cxActionEndCall(_ callId:Int) -> Int32 {
        let call = _callsList.first(where: {$0.id == callId})
        if(call == nil) { return SipConnectCxProvider.kECallNotFound }

        doEndCall(call!.uuid)
        return kErrorCodeEOK;
    }

    public func cxActionEndCall(_ callKit_callUUID:UUID) -> Int32 {
        let callIdx = _callsList.firstIndex(where: {$0.uuid == callKit_callUUID})
        if(callIdx == nil) { return SipConnectCxProvider.kECallNotFound }

        doEndCall(callKit_callUUID)
        _callsList.remove(at:callIdx!)
        return kErrorCodeEOK
    }

    func doEndCall(_ callUUID:UUID) {
        _sipModule.writeLog("CxProvider: endCall uuid:\(callUUID))")

        let action = CXEndCallAction(call: callUUID)
        let transaction = CXTransaction(action: action)
        
        _cxCallCtrl.request(transaction) { error in self.printResult("CXEndCall", err:error) }
    } 

    func cxActionSwitchToCall(_ callId:Int) -> Int32 {
        let callToSwitch = _callsList.first(where: {$0.id == callId})
        if(callToSwitch != nil) {
            //Unhold callToSwitch, hold the rest
            let transaction = CXTransaction()
            _callsList.forEach { call in
                let newHoldState = callToSwitch!.uuid != call.uuid
                if(newHoldState != call.isHeld) {
                    transaction.addAction(CXSetHeldCallAction(call: call.uuid, onHold: newHoldState))
                }
            }
            _cxCallCtrl.request(transaction) { error in self.printResult("CXSwitchToCallAction", err:error) }
            return kErrorCodeEOK
        }
        return SipConnectCxProvider.kECallNotFound
    }

    func cxActionGroupCall() -> Int32 {
        let callsWithSipId = _callsList.filter{ $0.id != 0}
        if(callsWithSipId.count >= 2) {
            let groupAction = CXSetGroupCallAction(call: callsWithSipId[0].uuid, callUUIDToGroupWith: callsWithSipId[1].uuid)
            let transaction = CXTransaction()
            transaction.addAction(groupAction)
            
            _callsList.forEach { call in
                if(call.isHeld) {
                    transaction.addAction(CXSetHeldCallAction(call: call.uuid, onHold: false))
                }
            }
        
            _cxCallCtrl.request(transaction) { error in self.printResult("CXSetGroupCallAction", err:error) }
            return kErrorCodeEOK;
        }
        return SipConnectCxProvider.kEConfRequires2Calls
    }

    func cxActionAnswer(_ callId:Int, withVideo:Bool) -> Int32 {
        let call = _callsList.first(where: {$0.id == callId})
        if(call != nil) {
            call!.withVideo = withVideo
            let action = CXAnswerCallAction(call: call!.uuid)
            let transaction = CXTransaction(action: action)
        
            _cxCallCtrl.request(transaction) { error in self.printResult("CXAnswer", err:error) }
            return kErrorCodeEOK;
        }
        return SipConnectCxProvider.kECallNotFound
    }
    
    func printResult(_ name: String, err: Error?) {
        let strErr = (err != nil) ? ("<\(name)> \(err!)") : ("<\(name)> requested successfully")
        _sipModule.writeLog("CxProvider: completion: \(strErr)")
    }

    ///------------------------------------------------------------------------------
    ///CXProviderDelegate
    ///
    func providerDidReset(_ provider: CXProvider) {
        _sipModule.writeLog("CxProvider: providerDidReset")
    }
    
    func provider(_: CXProvider, perform action: CXStartCallAction) {
        let call = getCallByUUID(action.callUUID)
        if(call != nil) {
            action.fulfill()
            _sipModule.writeLog("CxProvider: CXStartCall success uuid:\(action.callUUID)")
        } else {
            action.fail()
            _sipModule.writeLog("CxProvider: CXStartCall not found uuid:\(action.callUUID)")
        }
    }
    
    func provider(_: CXProvider, perform action: CXEndCallAction) {
        let call = getCallByUUID(action.callUUID)
        if(call == nil) {
            _sipModule.writeLog("CxProvider: CXEndCall uuid:\(action.callUUID) not found")
            action.fail()
            return
        }
        
        call!.cxEndAction = action

        if(call!.id == kInvalidId) {
            call!.rejectedByCallKit = true
            _sipModule.writeLog("CxProvider: CXEndCall uuid:\(action.callUUID) SIP hasn't received yet")
        }
        else {
            _sipModule.writeLog("CxProvider: CXEndCall uuid:\(action.callUUID) callId:\(call!.id)")
            proceedCxEndAction(call!)
        }
    }
    
    func provider(_: CXProvider, perform action: CXAnswerCallAction) {
        let call = getCallByUUID(action.callUUID)
        if(call == nil) {
            _sipModule.writeLog("CxProvider: CXAnswer uuid:\(action.callUUID) not found")
            action.fail()
            return
        }
       
        call!.cxAnswerAction = action
        call!.answeredByCallKit = true
        
        if (call!.id == kInvalidId) {
            _sipModule.writeLog("CxProvider: CXAnswer uuid:\(action.callUUID) SIP hasn't received yet")
        }else{
            _sipModule.writeLog("CxProvider: CXAnswer uuid:\(action.callUUID) callId:\(call!.id)")
            proceedCxAnswerAction(call!)
        }
    }
    
    func provider(_: CXProvider, perform action: CXPlayDTMFCallAction) {
        _sipModule.writeLog("CxProvider: CXPlayDTMF uuid:\(action.callUUID) dtmf:\(action.digits)")
       
        let call = getCallByUUID(action.callUUID)
        if((call != nil) && (_sipModule.callSendDtmf(Int32(call!.id), dtmfs:action.digits) == kErrorCodeEOK)) {
            action.fulfill()
        }else{
            action.fail()
        }
    }

    func provider(_: CXProvider, perform action: CXSetHeldCallAction) {
        var res:Int32 = -1
        let call = getCallByUUID(action.callUUID)
        if((call != nil)&&(call!.isHeld != action.isOnHold)) {
            call!.isHeld = action.isOnHold//TODO check, may be fullfil only when event received
            res = _sipModule.callHold(Int32(call!.id))
            action.fulfill()
        }else{
            action.fail()
        }
        _sipModule.writeLog("CxProvider: CXSetHeld uuid:\(action.callUUID) isOnHold:\(action.isOnHold) res:\(res)")
    }
    
    func provider(_: CXProvider, perform action: CXSetMutedCallAction) {
        var res:Int32 = -1
        let call = getCallByUUID(action.callUUID)
        if(call != nil)&&(_allowMuteByCallKit || (call!.micMuted == action.isMuted)) {
            res = _sipModule.callMuteMic(Int32(call!.id), mute:action.isMuted)
            _eventHandler.onCallKitMuted(call!.id, mute:action.isMuted)
            action.fulfill()
        }
        else {
            action.fail()
        }
        _sipModule.writeLog("CxProvider: perform CXSetMuted uuid:\(action.callUUID) muted:\(action.isMuted) res:\(res)")
    }
        
    func provider(_: CXProvider, timedOutPerforming action: CXAction) {
        _sipModule.writeLog("CxProvider: CXAction timedOutPerforming uuid:\(action.uuid)")
    }
    
    func provider(_: CXProvider, perform action: CXSetGroupCallAction) {
        let call = getCallByUUID(action.callUUID)
        if(call == nil) {
            _sipModule.writeLog("CxProvider: CXSetGroup not found uuid:\(action.callUUID)")
            action.fail()
            return
        }
        
        if (action.callUUIDToGroupWith != nil) {
            let err = _sipModule.mixerMakeConference()//TODO fix case when callKit started conf, but flutter can't see that
            _sipModule.writeLog("CxProvider: CXSetGroup group uuid:\(action.callUUID) with:\(action.callUUIDToGroupWith!) err:\(err)")
            //_sipModule._eventHandler.onCallConfStarted()
        } else {
            _sipModule.writeLog("CxProvider: CXSetGroup ungroup uuid:\(action.callUUID)")
            _sipModule.mixerSwitchCall(Int32(call!.id))
        }
        action.fulfill()
    }
   
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        _sipModule.writeLog("CxProvider: didActivate")
        _sipModule.activate(audioSession)
        _isAudioSessionActivated = true
    }

    func provider(_: CXProvider, didDeactivate audioSession: AVAudioSession) {
        _sipModule.writeLog("CxProvider: didDeactivate")
        _sipModule.deactivate(audioSession)
        _isAudioSessionActivated = false
    }

    public func  getCallByUUID(_ uuid: UUID) -> CallModel? {
        return _callsList.first(where: {$0.uuid == uuid})
    }

    class CallModel : Identifiable, Equatable {
        private(set) var uuid = UUID()
        private(set) var mySipCallId : Int  //Assigned by SIP module.
        //When this instance created by push - 'myCallId' will set to 'kInvalidId
        //  and proper value assigned only when received SIP INVITE
        //App has to match call by comparing data from push and SIP.
        
        public var withVideo = false
        public let isIncoming : Bool
        public var isHeld : Bool = false
        public var connectedSuccessfully = false
        public var answeredByCallKit = false
        public var rejectedByCallKit = false
        public var endedByLocalSide = false
        public var micMuted = false
        public var fromTo : String
        
        public var cxAnswerAction : CXAnswerCallAction?
        public var cxEndAction : CXEndCallAction?
                  
        init(_ destData:SipCoreDestData) {
            self.mySipCallId = Int(destData.myCallId)
            self.isIncoming = false

            self.withVideo = (destData.withVideo != nil) ? destData.withVideo!.boolValue : false
            self.fromTo = destData.toExt
        }

        init(callId:Int, withVideo:Bool, from:String) {
            self.mySipCallId = callId
            self.isIncoming = true
            self.withVideo = withVideo
            self.fromTo = from
        }

        public func setSipCallId(callId:Int, withVideo:Bool?) {
            self.mySipCallId = callId
            if(withVideo != nil) { self.withVideo = withVideo! }
        }
    
        var id : Int { get { return mySipCallId } }
        
        static func ==(lhs: CallModel, rhs: CallModel) -> Bool {
            return lhs.uuid == rhs.uuid
        }
    }
    
}//SipConnectCxProvider
