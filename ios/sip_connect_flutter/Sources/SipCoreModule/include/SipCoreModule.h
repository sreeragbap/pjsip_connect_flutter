//
//  SipCoreModule.h
//
//  PJSIP(pjsua2)-backed engine for sip_connect_flutter.
//  Mirrors the ObjC API surface the Swift bridge was originally written
//  against (formerly siprix.framework's Siprix.h) — same selectors, same
//  enum values (pinned by the Dart wire protocol), SipCore* class prefix.
//

#ifndef SipCoreModule_h
#define SipCoreModule_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger, SipTransport) {
    SipTransportUdp=0,
    SipTransportTcp,
    SipTransportTls
};

typedef NS_ENUM(NSInteger, RegState) {
    RegStateSuccess=0,
    RegStateFailed,
    RegStateRemoved,
    RegStateInProgress
};

typedef NS_ENUM(NSInteger, SubscrState) {
    SubscrCreated = 0,
    SubscrUpdated,
    SubscrDestroyed
};

typedef NS_ENUM(NSInteger, NetworkState) {
    NetworkStateLost = 0,
    NetworkStateRestored,
    NetworkStateSwitched,
};

typedef NS_ENUM(NSInteger, PlayerState) {
    PlayerStateStarted = 0,
    PlayerStateStopped,
    PlayerStateFailed,
};

typedef NS_ENUM(NSInteger, HoldState) {
    HoldStateNone = 0,
    HoldStateLocal = 1,
    HoldStateRemote = 2,
    HoldStateLocalAndRemote = 3
};

typedef NS_ENUM(NSInteger, LogLevel) {
    LogLevelStack=0,
    LogLevelDebug=1,
    LogLevelInfo=2,
    LogLevelWarning=3,
    LogLevelError=4,
    LogLevelNoLog=5
};

typedef NS_ENUM(NSInteger, DtmfMethod) {
    DtmfMethodRtp=0,
    DtmfMethodInfo=1
};

typedef NS_ENUM(NSInteger, SecureMedia) {
    SecureMediaDisabled=0,
    SecureMediaSdesSrtp,
    SecureMediaDtlsSrtp,
};

typedef NS_ENUM(NSInteger, AudioCodecs) {
    AudioCodecsOpus   = 65,
    AudioCodecsISAC16 = 66,
    AudioCodecsISAC32 = 67,
    AudioCodecsG722   = 68,
    AudioCodecsILBC   = 69,
    AudioCodecsPCMU   = 70,
    AudioCodecsPCMA   = 71,
    AudioCodecsDTMF   = 72,
    AudioCodecsCN     = 73,
    AudioCodecsG729   = 74,
};

typedef NS_ENUM(NSInteger, VideoCodecs) {
    VideoCodecsH264 = 80,
    VideoCodecsVP8  = 81,
    VideoCodecsVP9  = 82,
    VideoCodecsAV1  = 83
};

typedef NS_ENUM(NSInteger, VideoFrameRotation) {
    VideoFrameRotationRotation_0 = 0,
    VideoFrameRotationRotation_90 = 90,
    VideoFrameRotationRotation_180 = 180,
    VideoFrameRotationRotation_270 = 270
};

typedef NS_ENUM(NSInteger, VideoFrameRGBType) {
    VideoFrameRGBTypeARGB,
    VideoFrameRGBTypeBGRA,
    VideoFrameRGBTypeABGR,
    VideoFrameRGBTypeRGBA
};

typedef NS_ENUM(NSInteger, UpgradeToVideoMode) {
    UpgradeToVideoModeSendRecv = 0,
    UpgradeToVideoModeRecvOnly = 1,
    UpgradeToVideoModeInactive = 2,
    UpgradeToVideoModeManual = 3
};

static const int kErrorCodeEOK = 0;
static const NSInteger kInvalidId = 0;

@interface SipCoreIniData : NSObject
@property(nonatomic, retain) NSString * _Nullable license;
@property(nonatomic, retain) NSString * _Nullable homeFolder;
@property(nonatomic, retain) NSNumber * _Nullable logLevelFile;
@property(nonatomic, retain) NSNumber * _Nullable logLevelIde;
@property(nonatomic, retain) NSNumber * _Nullable rtpStartPort;
@property(nonatomic, retain) NSNumber * _Nullable tlsVerifyServer;
@property(nonatomic, retain) NSNumber * _Nullable singleCallMode;
@property(nonatomic, retain) NSNumber * _Nullable shareUdpTransport;
@property(nonatomic, retain) NSNumber * _Nullable unregOnDestroy;
@property(nonatomic, retain) NSArray  * _Nullable dnsServers;
@property(nonatomic, retain) NSNumber * _Nullable useDnsSrv;
@property(nonatomic, retain) NSNumber * _Nullable recordStereo;
@property(nonatomic, retain) NSNumber * _Nullable enableVideoCall;
@property(nonatomic, retain) NSNumber * _Nullable transpForceIPv4;
@property(nonatomic, retain) NSNumber * _Nullable enableAes128Sha32;
@property(nonatomic, retain) NSNumber * _Nullable enableVUmeter;
@property(nonatomic, retain) NSString * _Nullable brandName;
@end

@interface SipCoreAccData : NSObject
@property(nonatomic, assign) int  myAccId;
@property(nonatomic, retain) NSString * _Nonnull sipServer;
@property(nonatomic, retain) NSString * _Nonnull sipExtension;
@property(nonatomic, retain) NSString * _Nonnull sipPassword;
@property(nonatomic, retain) NSString * _Nullable sipAuthId;
@property(nonatomic, retain) NSString * _Nullable sipProxy;
@property(nonatomic, retain) NSString * _Nullable displName;
@property(nonatomic, retain) NSString * _Nullable userAgent;
@property(nonatomic, retain) NSNumber * _Nullable expireTime;
@property(nonatomic, retain) NSNumber * _Nullable port;
@property(nonatomic, assign) SipTransport transport;
@property(nonatomic, retain) NSString * _Nullable tlsCaCertPath;
@property(nonatomic, retain) NSNumber * _Nullable tlsUseSipScheme;
@property(nonatomic, retain) NSNumber * _Nullable rtcpMuxEnabled;
@property(nonatomic, retain) NSNumber * _Nullable iceEnabled;
@property(nonatomic, retain) NSNumber * _Nullable keepAliveTime;
@property(nonatomic, retain) NSNumber * _Nullable rewriteContactIp;
@property(nonatomic, retain) NSNumber * _Nullable verifyIncomingCall;
@property(nonatomic, retain) NSNumber * _Nullable forceSipProxy;
@property(nonatomic, retain) NSNumber * _Nullable secureMedia;
@property(nonatomic, retain) NSNumber * _Nullable transpPreferIPv6;
@property(nonatomic, retain) NSString * _Nullable instanceId;
@property(nonatomic, retain) NSString * _Nullable ringTonePath;
@property(nonatomic, retain) NSString * _Nullable stunServer;
@property(nonatomic, retain) NSString * _Nullable turnServer;
@property(nonatomic, retain) NSString * _Nullable turnUser;
@property(nonatomic, retain) NSString * _Nullable turnPassword;
@property(nonatomic, retain) NSNumber * _Nullable upgradeToVideo;
@property(nonatomic, retain) NSDictionary * _Nullable xheaders;
@property(nonatomic, retain) NSDictionary * _Nullable xContactUriParams;
@property(nonatomic, retain) NSArray  * _Nullable aCodecs;
@property(nonatomic, retain) NSArray  * _Nullable vCodecs;
@end

@interface SipCoreDestData : NSObject
@property(nonatomic, assign) int myCallId;
@property(nonatomic, assign) int fromAccId;
@property(nonatomic, retain) NSString * _Nonnull toExt;
@property(nonatomic, retain) NSNumber * _Nullable withVideo;
@property(nonatomic, retain) NSNumber * _Nullable inviteTimeoutSec;
@property(nonatomic, retain) NSDictionary * _Nullable xheaders;
@property(nonatomic, retain) NSString* _Nullable displName;
@end

@interface SipCoreSubscrData : NSObject
@property(nonatomic, assign) int mySubscrId;
@property(nonatomic, assign) int fromAccId;
@property(nonatomic, retain) NSString* _Nonnull toExt;
@property(nonatomic, retain) NSString* _Nonnull mimeSubtype;
@property(nonatomic, retain) NSString* _Nonnull eventType;
@property(nonatomic, retain) NSNumber* _Nullable expireTime;
@property(nonatomic, retain) NSString* _Nullable body;
@end

@interface SipCoreMsgData : NSObject
@property(nonatomic, assign) int myMessageId;
@property(nonatomic, assign) int fromAccId;
@property(nonatomic, retain) NSString* _Nonnull toExt;
@property(nonatomic, retain) NSString* _Nonnull body;
@property(nonatomic, retain) NSString* _Nullable contentType;
@end

@interface SipCoreHoldData : NSObject
@property(nonatomic, assign) HoldState holdState;
@end

@interface SipCoreVideoStateData : NSObject
@property(nonatomic, assign) BOOL hasVideo;
@end

@interface SipCoreVideoData : NSObject
@property(nonatomic, retain) NSString* _Nullable noCameraImgPath;
@property(nonatomic, retain) NSNumber* _Nullable framerateFps;
@property(nonatomic, retain) NSNumber* _Nullable bitrateKbps;
@property(nonatomic, retain) NSNumber* _Nullable height;
@property(nonatomic, retain) NSNumber* _Nullable width;
@end

@interface SipCorePlayerData : NSObject
@property(nonatomic, assign) int playerId;
@end

@interface SipCoreDevicesNumbData : NSObject
@property(nonatomic, assign) int number;
@end

@interface SipCoreDeviceData : NSObject
@property(nonatomic, retain) NSString * _Nonnull name;
@property(nonatomic, retain) NSString * _Nonnull guid;
@end


@protocol SipCoreVideoFrame <NSObject>
@required
- (int) width;
- (int) height;
- (VideoFrameRotation) rotation;
- (void)convertToARGB:(VideoFrameRGBType)type dstBuffer:(uint8_t* _Nonnull)dstBuffer
                    dstWidth:(int)dstWidth dstHeight:(int)dstHeight dstStride:(int)dstStride;
@end


@protocol SipCoreVideoRendererDelegate <NSObject>
@required
- (void)onFrame:(id<SipCoreVideoFrame> _Nonnull) videoFrame;
@end


@protocol SipCoreEventDelegate <NSObject>
@required
- (void)onTrialModeNotified;
- (void)onDevicesAudioChanged;

- (void)onAccountRegState:(NSInteger)accId
            regState:(RegState)regState
            response:(NSString * _Nonnull)response;
- (void)onSubscriptionState:(NSInteger)subscrId
            subscrState:(SubscrState)subscrState
            response:(NSString * _Nonnull)response;
- (void)onNetworkState:(NSString * _Nonnull)name
              netState:(NetworkState)netState;
- (void)onPlayerState:(NSInteger)playerId
             playerState:(PlayerState)playerState;

- (void)onRingerState:(BOOL) started;

- (void)onCallProceeding:(NSInteger)callId
            response:(NSString * _Nonnull)response;

- (void)onCallTerminated:(NSInteger)callId
            statusCode:(NSInteger)statusCode;

- (void)onCallConnected:(NSInteger)callId
            hdrFrom:(NSString * _Nonnull)hdrFrom
            hdrTo:(NSString * _Nonnull)hdrTo
            withVideo:(BOOL)withVideo;

- (void)onCallIncoming:(NSInteger)callId accId:(NSInteger)accId
            withVideo:(BOOL)withVideo
            hdrFrom:(NSString * _Nonnull)from
            hdrTo:(NSString * _Nonnull)to;

- (void)onCallDtmfReceived:(NSInteger)callId
            tone:(NSInteger)tone;

- (void) onCallSwitched:(NSInteger)callId;

- (void)onCallTransferred:(NSInteger)callId
            statusCode:(NSInteger)statusCode;

- (void)onCallRedirected:(NSInteger)origCallId
          relatedCallId:(NSInteger)relatedCallId
          referTo:(NSString * _Nonnull)referTo;

- (void)onCallVideoUpgraded:(NSInteger) callId
          withVideo:(BOOL)withVideo;
- (void)onCallVideoUpgradeRequested:(NSInteger) callId;

- (void)onCallHeld:(NSInteger)callId
          holdState:(HoldState)holdState;

- (void)onMessageSentState:(NSInteger)messageId success:(BOOL)success
          response:(NSString * _Nonnull)response;
- (void)onMessageIncoming:(NSInteger)messageId accId:(NSInteger)accId
          hdrFrom:(NSString * _Nonnull)hdrFrom
          body:(NSString * _Nonnull)body;

- (void)onSipNotify:(NSInteger)accId
          hdrEvent:(NSString * _Nonnull)hdrFrom
          body:(NSString * _Nonnull)body;
- (void)onVuMeterLevel:(NSInteger)micLevel spkLevel:(NSInteger)spkLevel;

@end


@interface SipCoreModule : NSObject
- (int)initialize:(id<SipCoreEventDelegate> _Nonnull)delegate
            iniData:(SipCoreIniData* _Nonnull)iniData;
- (int)unInitialize;
- (BOOL)isInitialized;
- (NSString* _Nonnull) version;
- (NSString* _Nonnull) homeFolder;
- (int) versionCode;
- (void)writeLog:(NSString * _Nonnull)str;

- (void)enableCallKit:(BOOL)enable;
- (void)activateSession:(AVAudioSession* _Nonnull)session;
- (void)deactivateSession:(AVAudioSession* _Nonnull)session;
- (BOOL)overrideAudioOutputToSpeaker:(BOOL)on;
- (BOOL)routeAudioToBluetooth;
- (BOOL)routeAudioToBuiltIn;
- (void)handleIncomingPush;

- (int)accountAdd:(SipCoreAccData* _Nonnull)accData;
- (int)accountUpdate:(SipCoreAccData* _Nonnull)accData accId:(int)accId;
- (int)accountRegister:(int)accId expireTime:(int)expireTime;
- (int)accountUnRegister:(int)accId;
- (int)accountDelete:(int)accId;
- (NSString * _Nonnull)accountGenInstId;

- (int)callInvite:(SipCoreDestData* _Nonnull)destData;
- (int)callReject:(int)callId statusCode:(int)statusCode;
- (int)callAccept:(int)callId withVideo:(BOOL)withVideo;
- (int)callHold:(int)callId;
- (int)callGetHoldState:(int)callId holdState:(SipCoreHoldData* _Nonnull)data;
- (int)callGetVideoState:(int)callId hasVideo:(SipCoreVideoStateData * _Nonnull) data;
- (int)callMuteMic:(int)callId mute:(BOOL)mute;
- (int)callMuteCam:(int)callId mute:(BOOL)mute;
- (int)callSendDtmf:(int)callId dtmfs:(NSString* _Nonnull)dtmfs
         durationMs:(int)durationMs intertoneGapMs:(int)intertoneGapMs method:(DtmfMethod)method;
- (int)callSendDtmf:(int)callId dtmfs:(NSString* _Nonnull)dtmfs;
- (int)callPlayTone:(int)callId toneType:(NSString * _Nonnull)toneType durationMs:(int)durationMs
                                     playerData : (SipCorePlayerData * _Nonnull)data;
- (int)callPlayFile:(int)callId pathToMp3File:(NSString* _Nonnull)pathToMp3File loop:(BOOL)loop
                                     playerData:(SipCorePlayerData* _Nonnull)data;
- (int)callStopPlayFile:(int)playerId;
- (int)callRecordFile:(int)callId pathToMp3File : (NSString * _Nonnull)pathToMp3File;
- (int)callStopRecordFile:(int)callId;
- (int)callTransferBlind:(int)callId toExt:(NSString* _Nonnull)toExt;
- (int)callTransferAttended:(int)fromCallId toCallId:(int)toCallId;
- (int)callAcceptVideoUpgrade:(int)callId withVideo:(BOOL)withVideo;
- (int)callUpgradeToVideo:(int)callId;
- (int)callBye:(int)callId;

- (int)callSetVideoRenderer:(int)callId renderer:(id<SipCoreVideoRendererDelegate> _Nullable) renderer;
- (NSString* _Nonnull)callGetSipHeader:(int)callId hdrName:(NSString * _Nonnull)hdrName;
- (NSString* _Nonnull)callGetStats:(int)callId;
- (void)callStopRingtone;

- (int)switchCamera;
- (int)callSetVideoWindow:(int)callId view : (UIView * _Nullable) view;
- (UIView* _Nonnull)createVideoWindow;

- (int)mixerSwitchCall:(int)callId;
- (int)mixerMakeConference;

- (int)dvcSetVideoParams:(SipCoreVideoData* _Nonnull)vdoData;

- (int)subscrCreate:(SipCoreSubscrData * _Nonnull)subscrData;
- (int)subscrDestroy:(int)subscrId;

- (int)messageSend:(SipCoreMsgData * _Nonnull)msgData;

- (NSString* _Nonnull)getErrorText:(int)errCode;
@end

#endif /* SipCoreModule_h */
