import Flutter
import UIKit
import CallKit
import PushKit
#if canImport(SipCoreModule)
import SipCoreModule
#endif

////////////////////////////////////////////////////////////////////////////////////////
//Method and argument names constants

let kBadArgumentsError          = "Bad argument. Map with fields expected"
let kModuleNotInitializedError  = "SipConnect module has not initialized yet"

let kChannelName                = "sip_connect_flutter"

let kMethodModuleInitialize     = "Module_Initialize"
let kMethodModuleUnInitialize   = "Module_UnInitialize"
let kMethodModuleHomeFolder     = "Module_HomeFolder"
let kMethodModuleVersionCode    = "Module_VersionCode"
let kMethodModuleVersion        = "Module_Version"

let kMethodAccountAdd           = "Account_Add"
let kMethodAccountUpdate        = "Account_Update"
let kMethodAccountRegister      = "Account_Register"
let kMethodAccountUnregister    = "Account_Unregister"
let kMethodAccountDelete        = "Account_Delete"
let kMethodAccountGenInstId     = "Account_GenInstId"

let kMethodCallInvite           = "Call_Invite"
let kMethodCallReject           = "Call_Reject"
let kMethodCallAccept           = "Call_Accept"
let kMethodCallHold             = "Call_Hold"
let kMethodCallGetHoldState     = "Call_GetHoldState"
let kMethodCallGetSipHeader     = "Call_GetSipHeader";
let kMethodCallGetStats         = "Call_GetStats";
let kMethodCallMuteMic          = "Call_MuteMic"
let kMethodCallMuteCam          = "Call_MuteCam"
let kMethodCallSendDtmf         = "Call_SendDtmf"
let kMethodCallPlayTone         = "Call_PlayTone"
let kMethodCallPlayFile         = "Call_PlayFile"
let kMethodCallStopPlayFile     = "Call_StopPlayFile"
let kMethodCallRecordFile       = "Call_RecordFile"
let kMethodCallStopRecordFile   = "Call_StopRecordFile"
let kMethodCallTransferBlind    = "Call_TransferBlind"
let kMethodCallTransferAttended = "Call_TransferAttended"
let kMethodCallUpgradeToVideo   = "Call_UpgradeToVideo"
let kMethodCallAcceptVideoUpgrade = "Call_AcceptVideoUpgrade"
let kMethodCallStopRingtone     = "Call_StopRingtone"
let kMethodCallBye              = "Call_Bye"

let kMethodMixerSwitchToCall   = "Mixer_SwitchToCall"
let kMethodMixerMakeConference = "Mixer_MakeConference"

let kMethodMessageSend         = "Message_Send"

let kMethodSubscriptionAdd     = "Subscription_Add"
let kMethodSubscriptionDelete  = "Subscription_Delete"

let kMethodDvcGetPushKitToken  = "Dvc_GetPushKitToken"
let kMethodDvcUpdCallKitDetails = "Dvc_UpdCallKitDetails"
let kMethodDvcGetCallKitUUID   = "Dvc_GetCallKitUUID"
let kMethodDvcEndCallKitCall   = "Dvc_EndCallKitCall"

let kMethodDvcGetPlayoutNumber = "Dvc_GetPlayoutDevices"
let kMethodDvcGetRecordNumber  = "Dvc_GetRecordingDevices"
let kMethodDvcGetVideoNumber   = "Dvc_GetVideoDevices"
let kMethodDvcGetPlayout       = "Dvc_GetPlayoutDevice"
let kMethodDvcGetRecording     = "Dvc_GetRecordingDevice"
let kMethodDvcGetVideo         = "Dvc_GetVideoDevice"
let kMethodDvcSetPlayout       = "Dvc_SetPlayoutDevice"
let kMethodDvcSetRecording     = "Dvc_SetRecordingDevice"
let kMethodDvcSetVideo         = "Dvc_SetVideoDevice"
let kMethodDvcSetVideoParams   = "Dvc_SetVideoParams"
let kMethodDvcSwitchCamera     = "Dvc_SwitchCamera"

let kMethodVideoRendererCreate = "Video_RendererCreate"
let kMethodVideoRendererSetSrc = "Video_RendererSetSrc"
let kMethodVideoRendererDispose = "Video_RendererDispose"

let kOnPushIncoming     = "OnPushIncoming"
let kOnTrialModeNotif   = "OnTrialModeNotif"
let kOnDevicesChanged   = "OnDevicesChanged"
let kOnAccountRegState  = "OnAccountRegState"
let kOnSubscriptionState = "OnSubscriptionState"
let kOnNetworkState     = "OnNetworkState"
let kOnPlayerState      = "OnPlayerState"
let kOnRingerState      = "OnRingerState"
let kOnCallProceeding   = "OnCallProceeding"
let kOnCallTerminated   = "OnCallTerminated"
let kOnCallConnected    = "OnCallConnected"
let kOnCallIncoming     = "OnCallIncoming"
let kOnCallDtmfReceived = "OnCallDtmfReceived"
let kOnCallTransferred  = "OnCallTransferred"
let kOnCallRedirected   = "OnCallRedirected"
let kOnCallVideoUpgraded = "OnCallVideoUpgraded"
let kOnCallVideoUpgradeRequested = "OnCallVideoUpgradeRequested"
let kOnCallSwitched     = "OnCallSwitched"
let kOnCallHeld         = "OnCallHeld"
let kOnCallKitMuted     = "OnCallKitMuted"

let kOnMessageSentState = "OnMessageSentState"
let kOnMessageIncoming  = "OnMessageIncoming"

let kOnSipNotify        = "OnSipNotify"
let kOnVuMeterLevel     = "OnVuMeterLevel"

let kArgVideoTextureId  = "videoTextureId"

let kArgStatusCode = "statusCode"
let kArgExpireTime = "expireTime"
let kArgWithVideo  = "withVideo"
let kArgDurationMs  = "durationMs"

let kArgDvcIndex = "dvcIndex"
let kArgDvcName  = "dvcName"
let kArgDvcGuid  = "dvcGuid"

let kArgCallId     = "callId"
let kArgFromCallId = "fromCallId"
let kArgToCallId   = "toCallId"
let kArgToExt      = "toExt"

let kArgCallKitUuid = "callKitUuid"
let kArgPushPayload = "pushPayload"
let kArgPushName   = "pushName"
let kArgPushHandle = "pushHandle"

let kArgAccId    = "accId"
let kArgPlayerId = "playerId"
let kArgSubscrId = "subscrId"
let kArgMsgId    = "msgId"
let kRegState    = "regState"
let kHoldState   = "holdState"
let kPlayerState = "playerState"
let kSubscrState = "subscrState"
let kNetState    = "netState"
let kResponse    = "response"
let kSuccess     = "success"

let kArgName   = "name"
let kArgTone   = "tone"
let kFrom      = "from"
let kTo        = "to"
let kBody      = "body"
let kEvent    = "event"
let kMicLevel = "mic"
let kSpkLevel = "spk"
let kArgMute = "mute"

////////////////////////////////////////////////////////////////////////////////////////
//SipConnectFlutterPlugin
public class SipConnectFlutterPlugin: NSObject, FlutterPlugin {
  typealias ArgsMap = Dictionary<AnyHashable,Any>

    var _sipModule : SipCoreModule
    var _eventHandler : SipConnectEventHandler
    var _callKitProvider : SipConnectCxProvider?
    var _pushKitProvider : SipConnectPushRegistry?
    var _textureRegistry : FlutterTextureRegistry
    var _binMessenger : FlutterBinaryMessenger
    var _renderers = [Int64 : FlutterVideoRenderer]()
    var _devicesList = AudioDevices()
    var _initialized = false

    init(withChannel channel:FlutterMethodChannel, registrar: FlutterPluginRegistrar) {
        self._sipModule = SipCoreModule()
        self._eventHandler = SipConnectEventHandler(withChannel:channel)
        self._textureRegistry = registrar.textures()
        self._binMessenger = registrar.messenger()
    }
    
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: kChannelName, binaryMessenger: registrar.messenger())
        
    let instance = SipConnectFlutterPlugin(withChannel:channel, registrar:registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let argsMap = call.arguments as? ArgsMap
    if (argsMap==nil) {
        result(FlutterError(code: "-", message: kBadArgumentsError, details: nil))
        return
    }

    if(_initialized) {
      switch call.method {
        case kMethodModuleInitialize   :  handleModuleInitialize(argsMap!, result:result)
        case kMethodModuleUnInitialize :  handleModuleUnInitialize(argsMap!, result:result)
        case kMethodModuleHomeFolder   :  handleModuleHomeFolder(argsMap!, result:result)
        case kMethodModuleVersionCode  :  handleModuleVersionCode(argsMap!, result:result)
        case kMethodModuleVersion      :  handleModuleVersion(argsMap!, result:result)
                
        case kMethodAccountAdd         :  handleAccountAdd(argsMap!, result:result)
        case kMethodAccountUpdate      :  handleAccountUpdate(argsMap!, result:result)
        case kMethodAccountRegister    :  handleAccountRegister(argsMap!, result:result)
        case kMethodAccountUnregister  :  handleAccountUnregister(argsMap!, result:result)
        case kMethodAccountDelete      :  handleAccountDelete(argsMap!, result:result)
        case kMethodAccountGenInstId   :  handleAccountGenInstId(argsMap!, result:result)
                
        case kMethodCallInvite        :   handleCallInvite(argsMap!, result:result)
        case kMethodCallReject        :   handleCallReject(argsMap!, result:result)
        case kMethodCallAccept        :   handleCallAccept(argsMap!, result:result)
        case kMethodCallHold          :   handleCallHold(argsMap!, result:result)
        case kMethodCallGetHoldState  :   handleCallGetHoldState(argsMap!, result:result)
        case kMethodCallGetSipHeader  :   handleCallGetSipHeader(argsMap!, result:result)
        case kMethodCallGetStats      :   handleCallGetStats(argsMap!, result:result)
        case kMethodCallMuteMic       :   handleCallMuteMic(argsMap!, result:result)
        case kMethodCallMuteCam       :   handleCallMuteCam(argsMap!, result:result)
        case kMethodCallSendDtmf      :   handleCallSendDtmf(argsMap!, result:result)
        case kMethodCallPlayTone      :   handleCallPlayTone(argsMap!, result:result)
        case kMethodCallPlayFile      :   handleCallPlayFile(argsMap!, result:result)
        case kMethodCallStopPlayFile  :   handleCallStopPlayFile(argsMap!, result:result)
        case kMethodCallRecordFile     :  handleCallRecordFile(argsMap!, result:result)
        case kMethodCallStopRecordFile :  handleCallStopRecordFile(argsMap!, result:result)
        case kMethodCallTransferBlind  :  handleCallTransferBlind(argsMap!, result:result)
        case kMethodCallTransferAttended : handleCallTransferAttended(argsMap!, result:result)
        case kMethodCallUpgradeToVideo:   handleCallUpgradeToVideo(argsMap!, result:result)
        case kMethodCallAcceptVideoUpgrade: handleCallAcceptVideoUpgrade(argsMap!, result:result)
        case kMethodCallStopRingtone  :   handleCallStopRingtone(argsMap!, result:result)
        case kMethodCallBye :             handleCallBye(argsMap!, result:result)

        case kMethodMixerSwitchToCall   : handleMixerSwitchToCall(argsMap!, result:result)
        case kMethodMixerMakeConference : handleMixerMakeConference(argsMap!, result:result)

        case kMethodMessageSend :          handleMessageSend(argsMap!, result:result)

        case kMethodSubscriptionAdd     : handleSubscriptionAdd(argsMap!, result:result)
        case kMethodSubscriptionDelete  : handleSubscriptionDelete(argsMap!, result:result)

        case kMethodDvcGetPushKitToken  : handleDvcGetPushkitToken(argsMap!, result:result)
        case kMethodDvcUpdCallKitDetails : handleDvcUpdCallKitDetails(argsMap!, result:result)
        case kMethodDvcGetCallKitUUID  :   handleDvcGetCallKitUUID(argsMap!, result:result)
        case kMethodDvcEndCallKitCall  :   handleDvcEndCallKitCall(argsMap!, result:result)
          
        case kMethodDvcGetPlayoutNumber:   handleDvcGetPlayoutNumber(argsMap!, result:result)
        case kMethodDvcGetRecordNumber :   handleDvcGetRecordNumber(argsMap!, result:result)
        case kMethodDvcGetVideoNumber  :   handleDvcGetVideoNumber(argsMap!, result:result)
        case kMethodDvcGetPlayout      :   handleDvcGetPlayout(argsMap!, result:result)
        case kMethodDvcGetRecording    :   handleDvcGetRecording(argsMap!, result:result)
        case kMethodDvcGetVideo        :   handleDvcGetVideo(argsMap!, result:result)
        case kMethodDvcSetPlayout      :   handleDvcSetPlayout(argsMap!, result:result)
        case kMethodDvcSetRecording    :   handleDvcSetRecording(argsMap!, result:result)
        case kMethodDvcSetVideo        :   handleDvcSetVideo(argsMap!, result:result)
        case kMethodDvcSwitchCamera    :   handleDvcSwitchCamera(argsMap!, result:result)
        case kMethodDvcSetVideoParams  :   handleDvcSetVideoParams(argsMap!, result:result)
          
        case kMethodVideoRendererCreate :  handleVideoRendererCreate(argsMap!, result:result)
        case kMethodVideoRendererSetSrc :  handleVideoRendererSetSrc(argsMap!, result:result)
        case kMethodVideoRendererDispose:  handleVideoRendererDispose(argsMap!, result:result)

        default:      result(FlutterMethodNotImplemented)
      }//switch
   }else{
      if(call.method==kMethodModuleInitialize) { handleModuleInitialize(argsMap!, result:result) }
      else { result(FlutterError(code: "UNAVAILABLE", message:kModuleNotInitializedError, details: nil)) }
   }
  }//handle
        
  deinit {
        _sipModule.unInitialize()
  }

  func handleModuleInitialize(_ args : ArgsMap, result: @escaping FlutterResult) {
        //Check already initialized
        if (_sipModule.isInitialized()) {
            _initialized = true
            result("Already initialized")
            return
        }
        
        //Get arguments from map
        let iniData = SipCoreIniData()
        
        let license = args["license"] as? String
        if(license != nil) { iniData.license = license }
        
        let brandName = args["brandName"] as? String
        if(brandName != nil) { iniData.brandName = brandName }
        
        let logLevelFile = args["logLevelFile"] as? Int
        if(logLevelFile != nil) { iniData.logLevelFile = NSNumber(value: logLevelFile!) }
        
        let logLevelIde = args["logLevelIde"] as? Int
        if(logLevelIde != nil) { iniData.logLevelIde = NSNumber(value: logLevelIde!) }
        
        let rtpStartPort = args["rtpStartPort"] as? Int
        if(rtpStartPort != nil) { iniData.rtpStartPort = NSNumber(value: rtpStartPort!) }
        
        let tlsVerifyServer = args["tlsVerifyServer"] as? Bool
        if(tlsVerifyServer != nil) { iniData.tlsVerifyServer = NSNumber(value: tlsVerifyServer!) }
        
        let singleCallMode = args["singleCallMode"] as? Bool
        if(singleCallMode != nil) { iniData.singleCallMode = NSNumber(value: singleCallMode!) }
        
        let shareUdpTransport = args["shareUdpTransport"] as? Bool
        if(shareUdpTransport != nil) { iniData.shareUdpTransport = NSNumber(value: shareUdpTransport!) }
      
        let unregOnDestroy = args["unregOnDestroy"] as? Bool
        if(unregOnDestroy != nil) { iniData.unregOnDestroy = NSNumber(value: unregOnDestroy!) }

        let useDnsSrv = args["useDnsSrv"] as? Bool
        if(useDnsSrv != nil) { iniData.useDnsSrv = NSNumber(value: useDnsSrv!) }

        let recordStereo = args["recordStereo"] as? Bool
        if(recordStereo != nil) { iniData.recordStereo = NSNumber(value: recordStereo!) }

        let enableVideoCall = args["enableVideoCall"] as? Bool
        if(enableVideoCall != nil) { iniData.enableVideoCall = NSNumber(value: enableVideoCall!) }

        let transpForceIPv4 = args["transpForceIPv4"] as? Bool
        if(transpForceIPv4 != nil) { iniData.transpForceIPv4 = NSNumber(value: transpForceIPv4!) }

        let enableAes128Sha32 = args["enableAes128Sha32"] as? Bool
        if(enableAes128Sha32 != nil) { iniData.enableAes128Sha32 = NSNumber(value: enableAes128Sha32!) }

        let enableVUmeter = args["enableVUmeter"] as? Bool
        if(enableVUmeter != nil) { iniData.enableVUmeter = NSNumber(value: enableVUmeter!) }
      
        let enablePushKit = args["enablePushKit"] as? Bool
        let enableCallKit = args["enableCallKit"] as? Bool
        let enableCallKitRecents = args["enableCallKitRecents"] as? Bool ?? false
        let enableCallKitMute = args["enableCallKitMute"] as? Bool ?? true
        let reportCallAsVideo = args["enableCallKitReportCallAsVideo"] as? Bool ?? false
      
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        iniData.homeFolder = documentsURL.path + "/"

        let err = _sipModule.initialize(_eventHandler, iniData:iniData)
        _initialized = (err == kErrorCodeEOK)
        
        #if os(iOS) && !targetEnvironment(simulator)
        if((err == kErrorCodeEOK) && (enableCallKit == true)) {
            _callKitProvider = SipConnectCxProvider(_sipModule, eventHandler:_eventHandler,
                                    singleCallMode:(singleCallMode ?? false), includeInRecents:enableCallKitRecents,
                                    allowMuteByCallKit:enableCallKitMute, isEnabledPushKit:(enablePushKit == true),
                                    reportCallAsVideo:reportCallAsVideo)
        }
      
        if((err == kErrorCodeEOK) && (_callKitProvider != nil) && (enablePushKit == true)) {
            _pushKitProvider = SipConnectPushRegistry.shared
            _pushKitProvider?.setCallKitProvider(_callKitProvider)
            _sipModule.writeLog("SipConnectPushRegistry: created")
        }
        #endif
      
        _sipModule.enableCallKit(_callKitProvider != nil)
      
        _eventHandler.configure(_callKitProvider, pushKitProvider:_pushKitProvider)
        _devicesList.configure(_eventHandler)
        
        sendResult(err, result:result)
    }
    
    func handleModuleUnInitialize(_ args : ArgsMap, result: @escaping FlutterResult) {
        let err = _sipModule.unInitialize()
        _initialized = false
        sendResult(err, result:result)
    }

    func handleModuleHomeFolder(_ args : ArgsMap, result: @escaping FlutterResult) {
        let path = _sipModule.homeFolder()
        result(path)
    }

    func handleModuleVersionCode(_ args : ArgsMap, result: @escaping FlutterResult) {
        let versionCode = _sipModule.versionCode()
        result(versionCode)
    }

    func handleModuleVersion(_ args : ArgsMap, result: @escaping FlutterResult) {
        let version = _sipModule.version()
        result(version)
    }

    ////////////////////////////////////////////////////////////////////////////////////////
    //SipConnect Account methods implementation

    func parseAccData(_ args : ArgsMap) -> SipCoreAccData {
        //Get arguments from map
        let accData = SipCoreAccData()
        
        let sipServer = args["sipServer"] as? String
        if(sipServer != nil) { accData.sipServer = sipServer! }
        
        let sipExtension = args["sipExtension"] as? String
        if(sipExtension != nil) { accData.sipExtension = sipExtension! }
        
        let sipPassword = args["sipPassword"] as? String
        if(sipPassword != nil) { accData.sipPassword = sipPassword! }
        
        let sipAuthId = args["sipAuthId"] as? String
        if(sipAuthId != nil) { accData.sipAuthId = sipAuthId! }
        
        let sipProxy = args["sipProxy"] as? String
        if(sipProxy != nil) { accData.sipProxy = sipProxy! }
        
        let displName = args["displName"] as? String
        if(displName != nil) { accData.displName = displName! }
        
        let userAgent = args["userAgent"] as? String
        if(userAgent != nil) { accData.userAgent = userAgent! }
        
        let expireTime = args["expireTime"] as? Int
        if(expireTime != nil) { accData.expireTime = NSNumber(value:expireTime!) }
      
        let transport = args["transport"] as? Int
        if(transport != nil) { accData.transport = SipTransport(rawValue: transport!)! }
        
        let port = args["port"] as? Int
        if(port != nil) { accData.port = NSNumber(value:port!) }
         
        let tlsCaCertPath = args["tlsCaCertPath"] as? String
        if(tlsCaCertPath != nil) { accData.tlsCaCertPath = tlsCaCertPath! }

        let tlsUseSipScheme = args["tlsUseSipScheme"] as? Bool
        if(tlsUseSipScheme != nil) { accData.tlsUseSipScheme = NSNumber(value:tlsUseSipScheme!) }

        let rtcpMuxEnabled = args["rtcpMuxEnabled"] as? Bool
        if(rtcpMuxEnabled != nil) { accData.rtcpMuxEnabled = NSNumber(value:rtcpMuxEnabled!) }

        let iceEnabled = args["iceEnabled"] as? Bool
        if(iceEnabled != nil) { accData.iceEnabled = NSNumber(value:iceEnabled!) }

        let instanceId = args["instanceId"] as? String
        if(instanceId != nil) { accData.instanceId = instanceId! }
        
        let ringTonePath = args["ringTonePath"] as? String
        if(ringTonePath != nil) { accData.ringTonePath = ringTonePath! }

        let keepAliveTime = args["keepAliveTime"] as? Int
        if(keepAliveTime != nil) { accData.keepAliveTime = NSNumber(value:keepAliveTime!) }

        let rewriteContactIp = args["rewriteContactIp"] as? Bool
        if(rewriteContactIp != nil) { accData.rewriteContactIp = NSNumber(value: rewriteContactIp!) }
         
        let verifyIncomingCall = args["verifyIncomingCall"] as? Bool
        if(verifyIncomingCall != nil) { accData.verifyIncomingCall = NSNumber(value: verifyIncomingCall!) }
         
        let forceSipProxy = args["forceSipProxy"] as? Bool
        if(forceSipProxy != nil) { accData.forceSipProxy = NSNumber(value: forceSipProxy!) }
         
        let secureMedia = args["secureMedia"] as? Int
        if(secureMedia != nil) { accData.secureMedia = NSNumber(value:secureMedia!) }
         
        let upgradeToVideo = args["upgradeToVideo"] as? Int
        if(upgradeToVideo != nil) { accData.upgradeToVideo = NSNumber(value:upgradeToVideo!) }

        let xheaders = args["xheaders"] as? Dictionary<AnyHashable,Any>
        if(xheaders != nil) { accData.xheaders = xheaders }

        let stunServer = args["stunServer"] as? String
        if(stunServer != nil) { accData.stunServer = stunServer! }

        let turnServer = args["turnServer"] as? String
        if(turnServer != nil) { accData.turnServer = turnServer! }

        let turnUser = args["turnUser"] as? String
        if(turnUser != nil) { accData.turnUser = turnUser! }

        let turnPassword = args["turnPassword"] as? String
        if(turnPassword != nil) { accData.turnPassword = turnPassword! }
        
        let xContactUriParams = args["xContactUriParams"] as? Dictionary<AnyHashable,Any>
        if(xContactUriParams != nil) { accData.xContactUriParams = xContactUriParams }
        
        let aCodecs = args["aCodecs"] as? [Int]
        if(aCodecs != nil) { accData.aCodecs = aCodecs }
        
        let vCodecs = args["vCodecs"] as? [Int]
        if(vCodecs != nil) { accData.vCodecs = vCodecs }
        
        return accData
    }
    
    func handleAccountAdd(_ args : ArgsMap, result: @escaping FlutterResult) {
        let accData = parseAccData(args)
        let err = _sipModule.accountAdd(accData)
        setRingtonePath(err, assetPath:accData.ringTonePath)
        if(err == kErrorCodeEOK){
            result(accData.myAccId)
        }else{
            result(FlutterError(code: String(err), message: _sipModule.getErrorText(err), details: accData.myAccId))
        }
    }

    func handleAccountUpdate(_ args : ArgsMap, result: @escaping FlutterResult) {
        let accData = parseAccData(args)
        let accId   = args[kArgAccId] as? Int

        if(accId != nil) {
            let err = _sipModule.accountUpdate(accData, accId:Int32(accId!))
            setRingtonePath(err, assetPath:accData.ringTonePath)
            sendResult(err, result:result)
        }else{
            sendBadArguments(result:result)
        }
    }

    func handleAccountRegister(_ args : ArgsMap, result: @escaping FlutterResult) {
        let accId      = args[kArgAccId] as? Int
        let expireTime = args[kArgExpireTime] as? Int

        if((accId != nil) && ( expireTime != nil)) {
            let err = _sipModule.accountRegister(Int32(accId!), expireTime:Int32(expireTime!))
            sendResult(err, result:result)
        }else{
            sendBadArguments(result:result)
        }
    }

    func handleAccountUnregister(_ args : ArgsMap, result: @escaping FlutterResult) {
        let accId = args[kArgAccId] as? Int

        if(accId != nil) {
            let err = _sipModule.accountUnRegister(Int32(accId!))
            sendResult(err, result:result)
        }else{
            sendBadArguments(result:result)
        }
    }

    func handleAccountDelete(_ args : ArgsMap, result: @escaping FlutterResult) {
        let accId = args[kArgAccId] as? Int

        if(accId != nil) {
            let err = _sipModule.accountDelete(Int32(accId!))
            sendResult(err, result:result)
        }else{
            sendBadArguments(result:result)
        }
    }

    func handleAccountGenInstId(_ args : ArgsMap, result: @escaping FlutterResult) {
        let instId = _sipModule.accountGenInstId()
        result(instId)
    }

    ////////////////////////////////////////////////////////////////////////////////////////
    //SipConnect Calls methods implementation

    func handleCallInvite(_ args : ArgsMap, result: @escaping FlutterResult) {
        //Get arguments from map
        let destData = SipCoreDestData()
        
        let toExt = args["extension"] as? String
        if(toExt != nil) { destData.toExt = toExt! }
        
        let fromAccId = args[kArgAccId] as? Int
        if(fromAccId != nil) { destData.fromAccId = Int32(fromAccId!) }
        
        let inviteTimeout = args["inviteTimeout"] as? Int
        if(inviteTimeout != nil) { destData.inviteTimeoutSec = NSNumber(value:inviteTimeout!) }
        
        let withVideo = args[kArgWithVideo] as? Bool
        if(withVideo != nil) { destData.withVideo = NSNumber(value: withVideo!) }
        
        let xheaders = args["xheaders"] as? Dictionary<AnyHashable,Any>
        if(xheaders != nil) { destData.xheaders = xheaders }
     
        let displName = args["displName"] as? String
        if(displName != nil) { destData.displName = displName! }
     
        let err = _sipModule.callInvite(destData)
        if(err == kErrorCodeEOK){
            _callKitProvider?.cxActionNewOutgoingCall(destData)
            result(destData.myCallId)
        }else{
            result(FlutterError(code: String(err), message: _sipModule.getErrorText(err), details: nil))
        }
    }

    func handleCallReject(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId     = args[kArgCallId] as? Int
        let statusCode = args[kArgStatusCode] as? Int

        if((callId != nil) && ( statusCode != nil)) {
            let err = _sipModule.callReject(Int32(callId!), statusCode:Int32(statusCode!))
            sendResult(err, result:result)
        }else{
            sendBadArguments(result:result)
        }
    }

    func handleCallAccept(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId = args[kArgCallId] as? Int
        let withVideo = args[kArgWithVideo] as? Bool

        if((callId == nil)||(withVideo == nil)) {
            sendBadArguments(result:result)
            return
        }

        if(_callKitProvider == nil || !_callKitProvider!.containsCall(callId!)) {
            let err = _sipModule.callAccept(Int32(callId!), withVideo:withVideo!)
            sendResult(err, result:result)
        }else{
            let err = _callKitProvider!.cxActionAnswer(callId!, withVideo:withVideo!)
            sendResult(err, result:result)
        }
    }

    func handleCallHold(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId = args[kArgCallId] as? Int

        if(callId == nil) {
            sendBadArguments(result:result)
            return;
        }

        if(_callKitProvider == nil || !_callKitProvider!.containsCall(callId!)) {
            let err = _sipModule.callHold(Int32(callId!))
            sendResult(err, result:result)
        }else{
            let err = _callKitProvider!.cxActionSetHeld(callId!)
            sendResult(err, result:result)
    }
}

    func handleCallGetHoldState(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId = args[kArgCallId] as? Int

        if(callId == nil) {
            sendBadArguments(result:result)
            return
        }
        
        let data = SipCoreHoldData()
        let err = _sipModule.callGetHoldState(Int32(callId!), holdState:data)
        if(err == kErrorCodeEOK){
            result(data.holdState.rawValue)
        }else{
            result(FlutterError(code: String(err), message: _sipModule.getErrorText(err), details: nil))
        }
    }

    func handleCallGetSipHeader(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId = args[kArgCallId] as? Int
        let hdrName = args["hdrName"] as? String

        if((callId == nil)||(hdrName == nil)) {
            sendBadArguments(result:result)
            return
        }
        
        let hdrVal = _sipModule.callGetSipHeader(Int32(callId!), hdrName:hdrName!)
        result(hdrVal)
    }

    func handleCallGetStats(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId = args[kArgCallId] as? Int

        if(callId == nil) {
            sendBadArguments(result:result)
            return
        }
        
        let statsVal = _sipModule.callGetStats(Int32(callId!))
        result(statsVal)
    }

    func handleCallMuteMic(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId = args[kArgCallId] as? Int
        let mute   = args[kArgMute] as? Bool

        if((callId == nil)||(mute==nil)) {
            sendBadArguments(result:result)
            return
        }
        
        if(_callKitProvider == nil || !_callKitProvider!.containsCall(callId!)) {
            let err = _sipModule.callMuteMic(Int32(callId!), mute:mute!)
            sendResult(err, result:result)
        }else{
            let err = _callKitProvider!.cxActionSetMuted(callId!, muted:mute!);
            sendResult(err, result:result)
        }
    }

    func handleCallMuteCam(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId = args[kArgCallId] as? Int
        let mute   = args[kArgMute] as? Bool

        if((callId == nil)||(mute==nil)) {
            sendBadArguments(result:result)
            return
        }
        let err = _sipModule.callMuteCam(Int32(callId!), mute:mute!)
        sendResult(err, result:result)
    }

    func handleCallSendDtmf(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId         = args[kArgCallId] as? Int
        let durationMs     = args[kArgDurationMs] as? Int
        let intertoneGapMs = args["intertoneGapMs"] as? Int
        let method         = args["method"] as? Int
        let dtmfs          = args["dtmfs"] as? String
        
        if((callId == nil)||(durationMs==nil)||(intertoneGapMs==nil)||(dtmfs==nil)||(method==nil)) {
            sendBadArguments(result:result)
            return
        }

        if(_callKitProvider == nil || !_callKitProvider!.containsCall(callId!)) {
           let m = (method! == DtmfMethod.rtp.rawValue) ? DtmfMethod.rtp : DtmfMethod.info
        
           let err = _sipModule.callSendDtmf(Int32(callId!), dtmfs:dtmfs!,
                                    durationMs:Int32(durationMs!),
                                    intertoneGapMs:Int32(intertoneGapMs!),
                                    method:m)
            sendResult(err, result:result)
        }else {
            let err = _callKitProvider!.cxActionPlayDtmf(callId!, digits:dtmfs!);
            sendResult(err, result:result)
        }
    }

    func handleCallPlayTone(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId     = args[kArgCallId] as? Int
        let toneType   = args["toneType"] as? String
        let durationMs = args[kArgDurationMs] as? Int

        if((callId == nil)||(toneType==nil)||(durationMs==nil)) {
            sendBadArguments(result:result)
            return
        }

        let data = SipCorePlayerData()
        let err = _sipModule.callPlayTone(Int32(callId!), toneType:toneType!,
                                             durationMs:Int32(durationMs!), playerData:data)
        if(err == kErrorCodeEOK){
            result(data.playerId)
        }else{
            result(FlutterError(code: String(err), message: _sipModule.getErrorText(err), details: nil))
        }
    }

    func handleCallPlayFile(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId        = args[kArgCallId] as? Int
        let pathToMp3File = args["pathToMp3File"] as? String
        let loop          = args["loop"] as? Bool
        
        if((callId == nil)||(pathToMp3File==nil)||(loop==nil)) {
            sendBadArguments(result:result)
            return
        }
        
        let data = SipCorePlayerData()
        let err = _sipModule.callPlayFile(Int32(callId!), pathToMp3File:pathToMp3File!, 
                                              loop:loop!, playerData:data)
        if(err == kErrorCodeEOK){
            result(data.playerId)
        }else{
            result(FlutterError(code: String(err), message: _sipModule.getErrorText(err), details: nil))
        }
    }

    func handleCallStopPlayFile(_ args : ArgsMap, result: @escaping FlutterResult) {
        let playerId = args[kArgPlayerId] as? Int
        
        if(playerId != nil) {
            let err = _sipModule.callStopPlayFile(Int32(playerId!))
            sendResult(err, result:result)
        }else{
            sendBadArguments(result:result)
        }
    }

    func handleCallRecordFile(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId        = args[kArgCallId] as? Int
        let pathToMp3File = args["pathToMp3File"] as? String
        
        if((callId != nil)&&(pathToMp3File != nil)) {
            let err = _sipModule.callRecordFile(Int32(callId!), pathToMp3File:pathToMp3File!)
            sendResult(err, result:result)
        }else{
            sendBadArguments(result:result)
        }
    }

    func handleCallStopRecordFile(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId = args[kArgCallId] as? Int
        
        if(callId != nil) {
            let err = _sipModule.callStopRecordFile(Int32(callId!))
            sendResult(err, result:result)
        }else{
            sendBadArguments(result:result)
        }
    }

    func handleCallTransferBlind(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId = args[kArgCallId] as? Int
        let toExt  = args[kArgToExt] as? String
        
        if((callId != nil) && ( toExt != nil)) {
            let err = _sipModule.callTransferBlind(Int32(callId!), toExt:toExt!)
            sendResult(err, result:result)
        }else{
            sendBadArguments(result:result)
        }
    }

    func handleCallTransferAttended(_ args : ArgsMap, result: @escaping FlutterResult) {
        let fromCallId = args[kArgFromCallId] as? Int
        let toCallId   = args[kArgToCallId] as? Int
        
        if((fromCallId != nil) && ( toCallId != nil)) {
            let err = _sipModule.callTransferAttended(Int32(fromCallId!), toCallId:Int32(toCallId!))
            sendResult(err, result:result)
        }else{
            sendBadArguments(result:result)
        }
    }

    func handleCallUpgradeToVideo(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId = args[kArgCallId] as? Int
        
        if(callId != nil) {
            let err = _sipModule.callUpgrade(toVideo:Int32(callId!))
            sendResult(err, result:result)
        }else{
            sendBadArguments(result:result)
        }
    }

    func handleCallAcceptVideoUpgrade(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId = args[kArgCallId] as? Int
        let withVideo = args[kArgWithVideo] as? Bool

        if((callId != nil)&&(withVideo != nil)) {
            let err = _sipModule.callAcceptVideoUpgrade(Int32(callId!), withVideo:withVideo!)
            sendResult(err, result:result)
        }else{
            sendBadArguments(result:result)
        }
    }

    func handleCallBye(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId = args[kArgCallId] as? Int

        if(callId == nil) {
            sendBadArguments(result:result)
            return
        }

        if(_callKitProvider == nil || !_callKitProvider!.containsCall(callId!)) {
            let err = _sipModule.callBye(Int32(callId!))
            sendResult(err, result:result)
        }else{
            let err = _callKitProvider!.cxActionEndCall(callId!)
            sendResult(err, result:result)
        }
    }
    
    func handleCallStopRingtone(_ args : ArgsMap, result: @escaping FlutterResult) {
        _sipModule.callStopRingtone()
        result(kErrorCodeEOK)
    }

    ////////////////////////////////////////////////////////////////////////////////////////
    //SipConnect Mixer methods implementation

    func handleMixerSwitchToCall(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId = args[kArgCallId] as? Int

        if(_callKitProvider == nil || !_callKitProvider!.containsCall(callId!) || !_callKitProvider!.contains2Calls()) {
            let err = _sipModule.mixerSwitchCall(Int32(callId!))
            sendResult(err, result:result)
        }else{
            let err = _callKitProvider!.cxActionSwitchToCall(callId!)
            sendResult(err, result:result)
        }
    }

    func handleMixerMakeConference(_ args : ArgsMap, result: @escaping FlutterResult) {
        if(_callKitProvider == nil || !_callKitProvider!.contains2Calls()) {
            let err = _sipModule.mixerMakeConference()
            sendResult(err, result:result)
        }else{
            let err = _callKitProvider!.cxActionGroupCall()
            sendResult(err, result:result)
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////
    //SipConnect messages

    func handleMessageSend(_ args : ArgsMap, result: @escaping FlutterResult) {
        //Get arguments from map
        let msgData = SipCoreMsgData()
        
        let toExt = args["extension"] as? String
        if(toExt != nil) { msgData.toExt = toExt! }
        
        let fromAccId = args[kArgAccId] as? Int
        if(fromAccId != nil) { msgData.fromAccId = Int32(fromAccId!) }

        let contentType = args["contentType"] as? String
        if(contentType != nil) { msgData.contentType = contentType! }
       
        let body = args[kBody] as? String
        if(body != nil) { msgData.body = body! }

        let err = _sipModule.messageSend(msgData)
        if(err == kErrorCodeEOK){
            result(msgData.myMessageId)
        }else{
            result(FlutterError(code: String(err), message: _sipModule.getErrorText(err), details: nil))
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////
    //SipConnect subscriptions

    func handleSubscriptionAdd(_ args : ArgsMap, result: @escaping FlutterResult) {
        //Get arguments from map
        let subscrData = SipCoreSubscrData()
        
        let toExt = args["extension"] as? String
        if(toExt != nil) { subscrData.toExt = toExt! }
        
        let fromAccId = args[kArgAccId] as? Int
        if(fromAccId != nil) { subscrData.fromAccId = Int32(fromAccId!) }

        let expireTime = args["expireTime"] as? Int
        if(expireTime != nil) { subscrData.expireTime = NSNumber(value:expireTime!) }
        
        let mimeSubType = args["mimeSubType"] as? String
        if(mimeSubType != nil) { subscrData.mimeSubtype = mimeSubType! }

        let eventType = args["eventType"] as? String
        if(eventType != nil) { subscrData.eventType = eventType! }

        let body = args["body"] as? String
        if(body != nil) { subscrData.body = body! }

        let err = _sipModule.subscrCreate(subscrData)
        if(err == kErrorCodeEOK){
            result(subscrData.mySubscrId)
        }else{
            result(FlutterError(code: String(err), message: _sipModule.getErrorText(err), details: subscrData.mySubscrId))
        }
    }

    func handleSubscriptionDelete(_ args : ArgsMap, result: @escaping FlutterResult) {
        let subscrId = args[kArgSubscrId] as? Int

        if(subscrId != nil) {
            let err = _sipModule.subscrDestroy(Int32(subscrId!))
            sendResult(err, result:result)
        }else{
            sendBadArguments(result:result)
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////
    //SipConnect PushKit implementation
    
    func handleDvcGetPushkitToken(_ args : ArgsMap, result: @escaping FlutterResult) {
        result(_pushKitProvider?.getToken())
    }
    
    func handleDvcUpdCallKitDetails(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callKit_callUUID = args[kArgCallKitUuid] as? String
        let localizedName = args[kArgPushName] as? String
        let genericHandle = args[kArgPushHandle] as? String
        let withVideo = args[kArgWithVideo] as? Bool
        let callId   = args[kArgCallId] as? Int
        
        //Check argument
        let uuid = (callKit_callUUID != nil) ? UUID(uuidString: callKit_callUUID!) : nil
        if(uuid==nil) {
            sendBadArguments(result:result)
        }
        else {
            //Call exist update details
            _callKitProvider?.sipAppUpdateCallDetails(uuid!, callId:callId,
                            localizedName:localizedName, genericHandle:genericHandle, withVideo:withVideo)
        }
        sendResult(kErrorCodeEOK, result:result)
    }

    func handleDvcGetCallKitUUID(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId   = args[kArgCallId] as? Int

        if(callId != nil) {
            result(_callKitProvider?.getCallKitUUID(callId!))
        } else {
            sendBadArguments(result:result)
        }
    }

    func handleDvcEndCallKitCall(_ args : ArgsMap, result: @escaping FlutterResult) {
        let uuidStr = args[kArgCallKitUuid] as? String
        let callUuid = (uuidStr != nil) ? UUID(uuidString: uuidStr!) : nil

        if(callUuid != nil) {
            let err = (_callKitProvider != nil) ? _callKitProvider!.cxActionEndCall(callUuid!) : kErrorCodeEOK
            sendResult(err, result:result)
        } else {
            sendBadArguments(result:result)
        }
    }


    ////////////////////////////////////////////////////////////////////////////////////////
    //SipConnect Devices methods implementation
    
    func handleDvcGetPlayoutNumber(_ args : ArgsMap, result: @escaping FlutterResult) {
        //let data = SipCoreDevicesNumbData()
        //_sipModule.dvcGetPlayoutDevices(data)
        result(_devicesList.getCount())//result(data.number)
    }

    func handleDvcGetRecordNumber(_ args : ArgsMap, result: @escaping FlutterResult) {
        //let data = SipCoreDevicesNumbData()
        //_sipModule.dvcGetRecordingDevices(data)
        result(0)//result(data.number)
    }

    func handleDvcGetVideoNumber(_ args : ArgsMap, result: @escaping FlutterResult) {
        //let data = SipCoreDevicesNumbData()
        //_sipModule.dvcGetVideoDevices(data)
        result(0)//result(data.number)
    }

    func handleDvcGetPlayout(_ args : ArgsMap, result: @escaping FlutterResult) {
        //doGetDevice(DvcType.Playout, args:args, result:result)
        
        let dvcIndex = args[kArgDvcIndex] as? Int
        if(dvcIndex == nil) {
            sendBadArguments(result:result)
            return
        }
        
        var argsMap = [String:Any]()
        argsMap[kArgDvcName] = _devicesList.getName(dvcIndex!)
        argsMap[kArgDvcGuid] = String(dvcIndex!)
        result(argsMap);
    }

    func handleDvcGetRecording(_ args : ArgsMap, result: @escaping FlutterResult) {
        //Recording-device enumeration is not supported on iOS (count is always 0).
        //Return an empty descriptor rather than leaving the Dart Future pending.
        result([kArgDvcName: "", kArgDvcGuid: ""])
    }

    func handleDvcGetVideo(_ args : ArgsMap, result: @escaping FlutterResult) {
        //Video-device enumeration is not supported on iOS (count is always 0).
        result([kArgDvcName: "", kArgDvcGuid: ""])
    }



    func handleDvcSetPlayout(_ args : ArgsMap, result: @escaping FlutterResult) {
        //doGetDevice(.Playout, args:args, result:result)
        
        let dvcIndex = args[kArgDvcIndex] as? Int
        if(dvcIndex == nil) {
            sendBadArguments(result:result)
            return
        }
        
        let ret : Bool;
        switch(dvcIndex) {
            case AudioDevices.kOutSpeaker:     ret = _sipModule.overrideAudioOutput(toSpeaker: true)
            case AudioDevices.kOutEarPiece:    ret = _sipModule.overrideAudioOutput(toSpeaker: false)
            case AudioDevices.kRouteBluetooth: ret = _sipModule.routeAudioToBluetooth()
            case AudioDevices.kRouteBuildIn:   ret = _sipModule.routeAudioToBuiltIn()
            default:                           ret = false;
        }

        if (ret) { result("Success") }
        else     { result(FlutterError(code: "-", message: "Can't overrideAudioOutput/set route", details: nil)) }
    }

    func handleDvcSetRecording(_ args : ArgsMap, result: @escaping FlutterResult) {
        //Recording-device selection is a no-op on iOS; acknowledge so the Dart Future completes.
        result("Success")
    }

    func handleDvcSetVideo(_ args : ArgsMap, result: @escaping FlutterResult) {
        let err = _sipModule.switchCamera();
        sendResult(err, result:result);
    }

    func handleDvcSwitchCamera(_ args : ArgsMap, result: @escaping FlutterResult) {
        let err = _sipModule.switchCamera();
        sendResult(err, result:result);
    }

    func handleDvcSetVideoParams(_ args : ArgsMap, result: @escaping FlutterResult) {
        let vdoData = SipCoreVideoData()
        
        let noCameraImgPath = args["noCameraImgPath"] as? String
        if(noCameraImgPath != nil) { vdoData.noCameraImgPath = noCameraImgPath }
        
        let framerateFps = args["framerateFps"] as? Int
        if(framerateFps != nil) { vdoData.framerateFps = NSNumber(value: framerateFps!) }
        
        let bitrateKbps = args["bitrateKbps"] as? Int
        if(bitrateKbps != nil) { vdoData.bitrateKbps = NSNumber(value: bitrateKbps!) }
        
        let height = args["height"] as? Int
        if(height != nil) { vdoData.height = NSNumber(value: height!) }
        
        let width = args["width"] as? Int
        if(width != nil) { vdoData.width = NSNumber(value: width!) }
        
        let err = _sipModule.dvcSetVideoParams(vdoData)
        sendResult(err, result:result)
    }
    
    ////////////////////////////////////////////////////////////////////////////////////////
    //Video methods
    
    func handleVideoRendererCreate(_ args : ArgsMap, result: @escaping FlutterResult) {
        let renderer = FlutterVideoRenderer(textureRegistry:_textureRegistry)
        let textureId = renderer.registerTextureAndCreateChannel(binMessenger:_binMessenger)
        _renderers[textureId] = renderer
        result(textureId)
    }
    
    func handleVideoRendererSetSrc(_ args : ArgsMap, result: @escaping FlutterResult) {
        let callId   = args[kArgCallId] as? Int
        let textureId = args[kArgVideoTextureId] as? Int64

        if((callId == nil)||(textureId == nil)) {
            sendBadArguments(result:result)
            return
        }
        
        let renderer = _renderers[textureId!]
        if(renderer == nil) {
            result(FlutterError(code: "-", message: "Renderer for specified texture doesn't exist", details: nil))
            return
        }
        
        //Unsubscribe from previous call
        if(renderer!.srcCallId != FlutterVideoRenderer.kInvalidCallCallId) {
            _sipModule.callSetVideoRenderer(renderer!.srcCallId, renderer: nil)
        }
        
        //Set new call
        renderer!.srcCallId = Int32(callId!)
        let err = _sipModule.callSetVideoRenderer(renderer!.srcCallId, renderer: renderer)
        sendResult(err, result:result)
    }
    
    func handleVideoRendererDispose(_ args : ArgsMap, result: @escaping FlutterResult) {
        let textureId = args[kArgVideoTextureId] as? Int64
        if(textureId == nil) {
            sendBadArguments(result:result)
            return
        }
        
        let renderer = _renderers[textureId!]
        if(renderer != nil) {
            _sipModule.callSetVideoRenderer(renderer!.srcCallId, renderer: nil)
            renderer!.dispose()
            _renderers.removeValue(forKey: textureId!)
        }
        result("Success")
    }
    
    ////////////////////////////////////////////////////////////////////////////////////////
    //Helpers methods
    
    func sendResult(_ err : Int32, result: @escaping FlutterResult) {
        if (err == kErrorCodeEOK) {
            result("Success")
        } else {
            result(FlutterError(code: String(err), message: _sipModule.getErrorText(err), details: nil))
        }
    }
    
    func sendBadArguments(result: @escaping FlutterResult){
        result(FlutterError(code: "-", message: kBadArgumentsError, details: nil))
    }
    
    func setRingtonePath(_ err : Int32, assetPath: String?) {
        if (err != kErrorCodeEOK) || (assetPath == nil) || (_callKitProvider != nil) {
            return;
        }

        let exists = (FileManager.default.fileExists(atPath:assetPath!))
        if(exists) {
            _sipModule.writeLog("Ringtone path: '\(assetPath!)' - exists")
            _eventHandler.setRingTonePath(assetPath!)
            return;
        }

        let index = assetPath!.lastIndex(of: "/")
        if(index != nil) {
            let updatedPath = _sipModule.homeFolder() + assetPath!.suffix(from: index!).dropFirst()
            _sipModule.writeLog("Ringtone path updated: '\(updatedPath)'")
            _eventHandler.setRingTonePath(updatedPath)
        }
    }
    
}//SipConnectFlutterPlugin
