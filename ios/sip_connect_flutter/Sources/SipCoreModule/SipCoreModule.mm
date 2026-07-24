//
//  SipCoreModule.mm
//
//  PJSIP(pjsua2)-backed implementation of SipCoreModule.h.
//  All ObjC entry points are expected on the platform (main) thread — the
//  thread that called -initialize owns the pjsua2 endpoint. pjsua2 callbacks
//  arrive on PJSIP worker threads and are re-dispatched to the main queue
//  before touching the delegate.
//

#import "SipCoreModule.h"

#include <pjsua2.hpp>
#include <deque>
#include <map>
#include <string>

using namespace pj;

////////////////////////////////////////////////////////////////////////////////
// Trivial data holders

@implementation SipCoreIniData
@end
@implementation SipCoreAccData
- (instancetype)init { self = [super init]; _sipServer=@""; _sipExtension=@""; _sipPassword=@""; _transport=SipTransportUdp; return self; }
@end
@implementation SipCoreDestData
- (instancetype)init { self = [super init]; _toExt=@""; return self; }
@end
@implementation SipCoreSubscrData
- (instancetype)init { self = [super init]; _toExt=@""; _mimeSubtype=@""; _eventType=@""; return self; }
@end
@implementation SipCoreMsgData
- (instancetype)init { self = [super init]; _toExt=@""; _body=@""; return self; }
@end
@implementation SipCoreHoldData
@end
@implementation SipCoreVideoStateData
@end
@implementation SipCoreVideoData
@end
@implementation SipCorePlayerData
@end
@implementation SipCoreDevicesNumbData
@end
@implementation SipCoreDeviceData
- (instancetype)init { self = [super init]; _name=@""; _guid=@""; return self; }
@end

////////////////////////////////////////////////////////////////////////////////
// C++ engine

typedef id<SipCoreEventDelegate> SCDelegate;

static NSString* str(const std::string &s) { return [NSString stringWithUTF8String:s.c_str()]; }
static std::string cpp(NSString * _Nullable s) { return s ? std::string([s UTF8String]) : std::string(); }

// pjlib aborts when called from a thread it has never seen. Entry points are
// normally on the main thread (registered at libCreate), but CallKit delivers
// CXCallController.request completions on a private queue, and those log via
// writeLog. The descriptor must outlive the thread, hence thread_local.
static void ensurePjThreadRegistered() {
    if (pj_thread_is_registered()) return;
    static thread_local pj_thread_desc desc;
    static thread_local pj_thread_t *thread = nullptr;
    pj_thread_register("sc-ext", desc, &thread);
}

struct Engine;

static void emitOn(Engine *eng, void(^block)(SCDelegate));

struct CoreAccount : public Account {
    Engine *eng;
    int wireId;
    std::string server;
    CoreAccount(Engine *e, int id) : eng(e), wireId(id) {}
    void onRegState(OnRegStateParam &prm) override;
    void onIncomingCall(OnIncomingCallParam &iprm) override;
    void onInstantMessage(OnInstantMessageParam &prm) override;
    void onInstantMessageStatus(OnInstantMessageStatusParam &prm) override;
};

struct CoreCall : public Call {
    Engine *eng;
    int accWireId;
    // Wire callId exposed to Dart = pjsua callId + 1. The Dart layer uses 0 as
    // its "no call" sentinel (kEmptyCallId), but pjsua2 call ids are 0-based —
    // so id 0 must never reach Dart. Set at creation; used for all map keys and
    // events. See CallsModel.kEmptyCallId.
    int wireId = -1;
    std::string inviteMsg;
    bool localHold = false;
    bool remoteHold = false;
    bool muted = false;
    bool videoActive = false;
    bool wasConnected = false;
    bool proceedingFired = false;
    CoreCall(Engine *e, Account &acc, int callId = PJSUA_INVALID_ID)
        : Call(acc, callId), eng(e) {}
    int holdStateValue() const {
        return (localHold ? 1 : 0) | (remoteHold ? 2 : 0);
    }
    void onCallState(OnCallStateParam &prm) override;
    void onCallTsxState(OnCallTsxStateParam &prm) override;
    void onCallMediaState(OnCallMediaStateParam &prm) override;
    void onDtmfDigit(OnDtmfDigitParam &prm) override;
    void onCallTransferStatus(OnCallTransferStatusParam &prm) override;
};

struct CorePlayer : public AudioMediaPlayer {
    Engine *eng;
    int wireId;
    CorePlayer(Engine *e, int id) : eng(e), wireId(id) {}
    void onEof2() override;
};

struct CoreBuddy : public Buddy {
    Engine *eng;
    int subscrId;
    bool created = false;
    CoreBuddy(Engine *e, int id) : eng(e), subscrId(id) {}
    void onBuddyState() override;
};

struct Engine {
    Endpoint *ep = nullptr;
    __weak id<SipCoreEventDelegate> delegate = nil;
    bool initialized = false;
    bool callKitEnabled = false;
    bool tlsAvailable = false;
    std::string lastError;
    std::string home;

    std::map<int, CoreAccount*> accounts;
    std::map<int, CoreCall*> calls;
    std::map<int, CorePlayer*> players;
    std::map<int, AudioMediaRecorder*> recorders;
    std::map<int, CoreBuddy*> buddies;
    std::map<int, __strong UIView*> callViews;
    std::deque<int> pendingMsgIds;
    int nextAccId = 1;
    int nextPlayerId = 1;
    int nextSubscrId = 1;
    int nextMsgId = 1;
    int switchedCallId = -1;

    CoreCall* findCall(int id) {
        auto it = calls.find(id);
        return it == calls.end() ? nullptr : it->second;
    }
    AudioMedia* activeAudio(CoreCall *call) {
        try {
            CallInfo ci = call->getInfo();
            for (unsigned i = 0; i < ci.media.size(); ++i) {
                if (ci.media[i].type == PJMEDIA_TYPE_AUDIO &&
                    (ci.media[i].status == PJSUA_CALL_MEDIA_ACTIVE ||
                     ci.media[i].status == PJSUA_CALL_MEDIA_REMOTE_HOLD)) {
                    return static_cast<AudioMedia*>(call->getMedia(i));
                }
            }
        } catch (Error &) {}
        return nullptr;
    }
    void connectAudio(CoreCall *call, unsigned mediaIdx) {
        try {
            AudioMedia *aud = static_cast<AudioMedia*>(call->getMedia(mediaIdx));
            if (!aud) return;
            AudDevManager &adm = ep->audDevManager();
            aud->startTransmit(adm.getPlaybackDevMedia());
            if (!call->muted) adm.getCaptureDevMedia().startTransmit(*aud);
        } catch (Error &err) { lastError = err.info(); }
    }
    void attachVideoView(CoreCall *call, int windowId) {
        auto it = callViews.find(call->wireId);  // callViews keyed by wire id
        if (it == callViews.end() || windowId < 0) return;
        try {
            VideoWindow win(windowId);
            VideoWindowHandle handle;
            handle.type = PJMEDIA_VID_DEV_HWND_TYPE_IOS;
            handle.handle.window = (__bridge void*)it->second;
            win.setWindow(handle);
        } catch (Error &err) { lastError = err.info(); }
    }
};

static void emitOn(Engine *eng, void(^block)(SCDelegate)) {
    SCDelegate d = eng->delegate;
    if (!d) return;
    dispatch_async(dispatch_get_main_queue(), ^{ block(d); });
}

////////////////////////////////////////////////////////////////////////////////
// Account callbacks

void CoreAccount::onRegState(OnRegStateParam &prm) {
    bool active = false; long expires = 0;
    try { AccountInfo info = getInfo(); active = info.regIsActive; expires = info.regExpiresSec; }
    catch (Error &) {}
    RegState state;
    if (prm.code / 100 == 2) state = (active && expires > 0) ? RegStateSuccess : RegStateRemoved;
    else state = RegStateFailed;
    NSString *response = str(std::to_string(prm.code) + " " + prm.reason);
    NSInteger accId = wireId;
    emitOn(eng, ^(SCDelegate d) {
        [d onAccountRegState:accId regState:state response:response];
    });
}

void CoreAccount::onIncomingCall(OnIncomingCallParam &iprm) {
    CoreCall *call = new CoreCall(eng, *this, iprm.callId);
    call->accWireId = wireId;
    call->wireId = iprm.callId + 1;
    call->inviteMsg = iprm.rdata.wholeMsg;
    bool withVideo = call->inviteMsg.find("m=video") != std::string::npos;
    eng->calls[call->wireId] = call;

    try {
        CallOpParam prm;
        prm.statusCode = PJSIP_SC_RINGING;
        call->answer(prm);
    } catch (Error &) {}

    std::string from, to;
    try { CallInfo ci = call->getInfo(); from = ci.remoteUri; to = ci.localUri; } catch (Error &) {}
    NSInteger callId = call->wireId, accId = wireId;
    NSString *f = str(from), *t = str(to);
    emitOn(eng, ^(SCDelegate d) {
        [d onRingerState:YES];
        [d onCallIncoming:callId accId:accId withVideo:withVideo hdrFrom:f hdrTo:t];
    });
}

void CoreAccount::onInstantMessage(OnInstantMessageParam &prm) {
    NSInteger msgId = eng->nextMsgId++, accId = wireId;
    NSString *from = str(prm.fromUri), *body = str(prm.msgBody);
    emitOn(eng, ^(SCDelegate d) {
        [d onMessageIncoming:msgId accId:accId hdrFrom:from body:body];
    });
}

void CoreAccount::onInstantMessageStatus(OnInstantMessageStatusParam &prm) {
    if (eng->pendingMsgIds.empty()) return;
    NSInteger msgId = eng->pendingMsgIds.front();
    eng->pendingMsgIds.pop_front();
    BOOL ok = (prm.code / 100 == 2);
    NSString *response = str(std::to_string(prm.code) + " " + prm.reason);
    emitOn(eng, ^(SCDelegate d) {
        [d onMessageSentState:msgId success:ok response:response];
    });
}

////////////////////////////////////////////////////////////////////////////////
// Call callbacks

void CoreCall::onCallState(OnCallStateParam &prm) {
    CallInfo ci;
    try { ci = getInfo(); } catch (Error &) { return; }
    NSInteger callId = wireId;
    switch (ci.state) {
    case PJSIP_INV_STATE_EARLY: {
        // 'Proceeding' is an OUTGOING-call state (a 1xx response came back). On
        // an incoming call, EARLY is us sending 180 Ringing — firing it would
        // clobber the Dart 'ringing' state and break the incoming UI.
        // Normally onCallTsxState already fired proceeding on the earlier
        // 100 Trying; this is the fallback when no 100 preceded the 180/183.
        if (ci.role == PJSIP_ROLE_UAC && !proceedingFired) {
            proceedingFired = true;
            NSString *response = str(std::to_string(ci.lastStatusCode) + " " + ci.lastReason);
            emitOn(eng, ^(SCDelegate d) { [d onCallProceeding:callId response:response]; });
        }
        break;
    }
    case PJSIP_INV_STATE_CONFIRMED: {
        // Fire 'connected' only on the first CONFIRMED. A later re-INVITE /
        // session refresh keeps the call CONFIRMED and must not re-emit
        // onCallConnected (it resets the Dart call's start time / duration).
        if (!wasConnected) {
            wasConnected = true;
            NSString *from = str(ci.remoteUri), *to = str(ci.localUri);
            BOOL vid = videoActive;
            emitOn(eng, ^(SCDelegate d) {
                [d onRingerState:NO];
                [d onCallConnected:callId hdrFrom:from hdrTo:to withVideo:vid];
            });
        }
        break;
    }
    case PJSIP_INV_STATE_DISCONNECTED: {
        NSInteger code = ci.lastStatusCode;
        eng->calls.erase((int)callId);
        auto rec = eng->recorders.find((int)callId);
        if (rec != eng->recorders.end()) { delete rec->second; eng->recorders.erase(rec); }
        eng->callViews.erase((int)callId);
        emitOn(eng, ^(SCDelegate d) {
            [d onRingerState:NO];
            [d onCallTerminated:callId statusCode:code];
        });
        // Hand focus to a still-active call (if any) so the UI keeps a valid
        // switchedCall; -1 when this was the last call.
        if (eng->switchedCallId == (int)callId) {
            eng->switchedCallId = eng->calls.empty() ? -1 : eng->calls.begin()->first;
            if (eng->switchedCallId != -1) {
                NSInteger next = eng->switchedCallId;
                emitOn(eng, ^(SCDelegate d) { [d onCallSwitched:next]; });
            }
        }
        CoreCall *self_ = this;
        dispatch_async(dispatch_get_main_queue(), ^{ delete self_; });
        break;
    }
    default: break;
    }
}

// Fire 'proceeding' as soon as the FIRST provisional (1xx) response arrives on
// the outgoing INVITE — typically a '100 Trying' one round-trip after we send
// the INVITE. Waiting for PJSIP_INV_STATE_EARLY instead delays it until a
// 180/183 (an early dialog), which only comes once the far end actually rings —
// that can be seconds later. 100 Trying is the true "Proceeding".
void CoreCall::onCallTsxState(OnCallTsxStateParam &prm) {
    if (proceedingFired) return;
    CallInfo ci;
    try { ci = getInfo(); } catch (Error &) { return; }
    if (ci.role != PJSIP_ROLE_UAC) return;
    if (prm.e.type != PJSIP_EVENT_TSX_STATE) return;
    SipTransaction &tsx = prm.e.body.tsxState.tsx;
    if (tsx.method != "INVITE") return;
    int code = tsx.statusCode;
    if (code < 100 || code >= 200) return;
    proceedingFired = true;
    NSInteger callId = wireId;
    NSString *response = str(std::to_string(code) + " " + tsx.statusText);
    emitOn(eng, ^(SCDelegate d) { [d onCallProceeding:callId response:response]; });
}

void CoreCall::onCallMediaState(OnCallMediaStateParam &prm) {
    CallInfo ci;
    try { ci = getInfo(); } catch (Error &) { return; }
    NSInteger callId = wireId;
    bool holdChanged = false;
    for (unsigned i = 0; i < ci.media.size(); ++i) {
        const CallMediaInfo &mi = ci.media[i];
        if (mi.type == PJMEDIA_TYPE_AUDIO) {
            if (mi.status == PJSUA_CALL_MEDIA_ACTIVE) {
                if (remoteHold) { remoteHold = false; holdChanged = true; }
                eng->connectAudio(this, i);
            } else if (mi.status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
                if (!remoteHold) { remoteHold = true; holdChanged = true; }
            }
        } else if (mi.type == PJMEDIA_TYPE_VIDEO && mi.status == PJSUA_CALL_MEDIA_ACTIVE) {
            if (!videoActive) {
                videoActive = true;
                emitOn(eng, ^(SCDelegate d) { [d onCallVideoUpgraded:callId withVideo:YES]; });
            }
            eng->attachVideoView(this, mi.videoIncomingWindowId);
        }
    }
    if (holdChanged) {
        HoldState hs = (HoldState)holdStateValue();
        emitOn(eng, ^(SCDelegate d) { [d onCallHeld:callId holdState:hs]; });
    }
}

void CoreCall::onDtmfDigit(OnDtmfDigitParam &prm) {
    if (prm.digit.empty()) return;
    char c = prm.digit[0];
    NSInteger tone;
    if (c >= '0' && c <= '9') tone = c - '0';
    else if (c == '*') tone = 10;
    else if (c == '#') tone = 11;
    else if (c >= 'A' && c <= 'D') tone = 12 + (c - 'A');
    else return;
    NSInteger callId = wireId;
    emitOn(eng, ^(SCDelegate d) { [d onCallDtmfReceived:callId tone:tone]; });
}

void CoreCall::onCallTransferStatus(OnCallTransferStatusParam &prm) {
    NSInteger callId = wireId;
    NSInteger code = prm.statusCode;
    emitOn(eng, ^(SCDelegate d) { [d onCallTransferred:callId statusCode:code]; });
}

void CorePlayer::onEof2() {
    eng->players.erase(wireId);
    NSInteger playerId = wireId;
    emitOn(eng, ^(SCDelegate d) { [d onPlayerState:playerId playerState:PlayerStateStopped]; });
    CorePlayer *self_ = this;
    dispatch_async(dispatch_get_main_queue(), ^{ delete self_; });
}

void CoreBuddy::onBuddyState() {
    std::string note;
    try { note = getInfo().presStatus.note; } catch (Error &) {}
    SubscrState state = created ? SubscrUpdated : SubscrCreated;
    created = true;
    NSInteger sid = subscrId;
    NSString *response = str(note);
    emitOn(eng, ^(SCDelegate d) {
        [d onSubscriptionState:sid subscrState:state response:response];
    });
}

////////////////////////////////////////////////////////////////////////////////
// SipCoreModule

@implementation SipCoreModule {
    Engine *_eng;
}

- (instancetype)init {
    self = [super init];
    _eng = new Engine();
    return self;
}

- (void)dealloc {
    [self unInitialize];
    delete _eng;
}

#define GUARD_INIT() if (!_eng->initialized) { _eng->lastError = "Not initialized"; return -1; }

- (int)initialize:(id<SipCoreEventDelegate>)delegate iniData:(SipCoreIniData*)iniData {
    if (_eng->initialized) return kErrorCodeEOK;
    _eng->delegate = delegate;
    try {
        Endpoint *ep = new Endpoint();
        ep->libCreate();

        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        _eng->home = cpp([paths.firstObject stringByAppendingString:@"/"]);
        if (iniData.homeFolder) _eng->home = cpp(iniData.homeFolder);

        EpConfig cfg;
        int lvlFile = iniData.logLevelFile ? iniData.logLevelFile.intValue : 2;
        int lvlIde  = iniData.logLevelIde  ? iniData.logLevelIde.intValue  : 2;
        cfg.logConfig.level = MAX(0, 5 - lvlFile);
        cfg.logConfig.consoleLevel = MAX(0, 5 - lvlIde);
        cfg.logConfig.filename = _eng->home + "sip_connect.log";
        if (iniData.brandName) cfg.uaConfig.userAgent = cpp(iniData.brandName);
        ep->libInit(cfg);

        TransportConfig udpCfg, tcpCfg;
        udpCfg.qosType = PJ_QOS_TYPE_VOICE;
        tcpCfg.qosType = PJ_QOS_TYPE_VOICE;
        ep->transportCreate(PJSIP_TRANSPORT_UDP, udpCfg);
        ep->transportCreate(PJSIP_TRANSPORT_TCP, tcpCfg);
        try {
            TransportConfig tlsCfg;
            tlsCfg.qosType = PJ_QOS_TYPE_VOICE;
            tlsCfg.tlsConfig.verifyServer = iniData.tlsVerifyServer.boolValue;
            ep->transportCreate(PJSIP_TRANSPORT_TLS, tlsCfg);
            _eng->tlsAvailable = true;
        } catch (Error &err) {
            NSLog(@"[SipCore] TLS transport unavailable (built without OpenSSL): %s", err.info().c_str());
            _eng->tlsAvailable = false;
        }

        ep->libStart();
        _eng->ep = ep;
        _eng->initialized = true;

        // With CallKit the sound device is opened from activateSession:.
        if (_eng->callKitEnabled) ep->audDevManager().setNoDev();
        return kErrorCodeEOK;
    } catch (Error &err) {
        _eng->lastError = err.info();
        return -1;
    }
}

- (int)unInitialize {
    if (!_eng->initialized) return kErrorCodeEOK;
    try {
        _eng->initialized = false;
        _eng->calls.clear();
        _eng->players.clear();
        _eng->recorders.clear();
        _eng->buddies.clear();
        _eng->accounts.clear();
        _eng->callViews.clear();
        _eng->ep->libDestroy();
        delete _eng->ep;
        _eng->ep = nullptr;
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (BOOL)isInitialized { return _eng->initialized; }

- (NSString*)version {
    try { return _eng->ep ? str(_eng->ep->libVersion().full) : @"pjsip"; }
    catch (Error &) { return @"pjsip"; }
}

- (int)versionCode {
    try {
        if (!_eng->ep) return 0;
        pj::Version v = _eng->ep->libVersion();
        return v.major * 10000 + v.minor * 100;
    } catch (Error &) { return 0; }
}

- (NSString*)homeFolder { return str(_eng->home); }

- (void)writeLog:(NSString*)msg {
    NSLog(@"[SipCore] %@", msg);
    if (_eng->initialized) {
        ensurePjThreadRegistered();
        try { _eng->ep->utilLogWrite(3, "SipConnect", cpp(msg)); } catch (Error &) {}
    }
}

- (NSString*)getErrorText:(int)errCode {
    return errCode == kErrorCodeEOK ? @"Success" : str(_eng->lastError);
}

////////////////////////////////////////////////////// audio session / CallKit

- (void)enableCallKit:(BOOL)enable {
    _eng->callKitEnabled = enable;
    if (_eng->initialized && enable) {
        try { _eng->ep->audDevManager().setNoDev(); } catch (Error &) {}
    }
}

- (void)activateSession:(AVAudioSession*)session {
    if (!_eng->initialized) return;
    try {
        AudDevManager &adm = _eng->ep->audDevManager();
        adm.setCaptureDev(PJMEDIA_AUD_DEFAULT_CAPTURE_DEV);
        adm.setPlaybackDev(PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV);
    } catch (Error &err) { _eng->lastError = err.info(); }
}

- (void)deactivateSession:(AVAudioSession*)session {
    if (!_eng->initialized || !_eng->callKitEnabled) return;
    try { _eng->ep->audDevManager().setNoDev(); } catch (Error &err) { _eng->lastError = err.info(); }
}

- (BOOL)overrideAudioOutputToSpeaker:(BOOL)on {
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session overrideOutputAudioPort:(on ? AVAudioSessionPortOverrideSpeaker
                                         : AVAudioSessionPortOverrideNone)
                               error:&error];
    return error == nil;
}

- (BOOL)routeAudioToBluetooth {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    for (AVAudioSessionPortDescription *input in session.availableInputs) {
        if ([input.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
            return [session setPreferredInput:input error:nil];
        }
    }
    return NO;
}

- (BOOL)routeAudioToBuiltIn {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    for (AVAudioSessionPortDescription *input in session.availableInputs) {
        if ([input.portType isEqualToString:AVAudioSessionPortBuiltInMic]) {
            return [session setPreferredInput:input error:nil];
        }
    }
    return NO;
}

- (void)handleIncomingPush {
    // PushKit-triggered re-registration lands at P5; nothing engine-side yet.
    [self writeLog:@"handleIncomingPush: PJSIP engine P5 pending"];
}

////////////////////////////////////////////////////////////////////// accounts

static AccountConfig buildAccountConfig(SipCoreAccData *a) {
    AccountConfig cfg;
    std::string server = cpp(a.sipServer);
    std::string ext = cpp(a.sipExtension);
    std::string transportSuffix;
    if (a.transport == SipTransportTcp) transportSuffix = ";transport=tcp";
    else if (a.transport == SipTransportTls) transportSuffix = ";transport=tls";
    // Server/destination host:port for the registrar + outbound proxy.
    // IMPORTANT: a.port is the LOCAL transport bind port (the Dart layer
    // randomizes it when unset — see AccountsModel._generateRandomLocalPort);
    // it is NOT the server port and must never go into the registrar URI, or
    // pjsip dials a random closed port and times out. The server port comes
    // from an explicit "host:port" in sipServer, else the transport's standard
    // SIP port (5061 TLS / 5060 UDP/TCP).
    int stdPort = (a.transport == SipTransportTls) ? 5061 : 5060;
    bool serverHasPort = server.find(':') != std::string::npos;
    std::string hostPort = serverHasPort ? server : server + ":" + std::to_string(stdPort);

    if (a.displName.length) cfg.idUri = "\"" + cpp(a.displName) + "\" <sip:" + ext + "@" + server + ">";
    else cfg.idUri = "sip:" + ext + "@" + server;
    cfg.regConfig.registrarUri = "sip:" + hostPort + transportSuffix;
    cfg.regConfig.timeoutSec = a.expireTime ? a.expireTime.intValue : 300;
    cfg.regConfig.retryIntervalSec = 30;

    std::string authId = a.sipAuthId.length ? cpp(a.sipAuthId) : ext;
    cfg.sipConfig.authCreds.push_back(AuthCredInfo("digest", "*", authId, 0, cpp(a.sipPassword)));
    if (a.sipProxy.length) {
        cfg.sipConfig.proxies.push_back("sip:" + cpp(a.sipProxy) + transportSuffix + ";lr");
    } else {
        // No explicit proxy: route all requests (INVITE/MESSAGE/SUBSCRIBE) through
        // the registrar with the account's transport. Without this, a bare
        // "sip:ext@server" target resolves to UDP:5060 and providers that only
        // answer on the registered TLS/TCP connection let the INVITE time out (408).
        cfg.sipConfig.proxies.push_back("sip:" + hostPort + transportSuffix + ";lr");
    }

    if (a.xContactUriParams.count) {
        std::string params;
        for (NSString *key in a.xContactUriParams) {
            id val = a.xContactUriParams[key];
            if ([val isKindOfClass:[NSString class]])
                params += ";" + cpp(key) + "=" + cpp(val);
        }
        cfg.sipConfig.contactUriParams = params;
    }
    if (a.instanceId.length)
        cfg.regConfig.contactParams = ";+sip.instance=\"<urn:uuid:" + cpp(a.instanceId) + ">\"";
    if (a.xheaders.count) {
        for (NSString *key in a.xheaders) {
            id val = a.xheaders[key];
            if (![val isKindOfClass:[NSString class]]) continue;
            SipHeader h; h.hName = cpp(key); h.hValue = cpp(val);
            cfg.regConfig.headers.push_back(h);
        }
    }

    // Media encryption mode (computed early so ICE can key off it). TLS-signaling
    // accounts default to SRTP; an explicit choice (incl. Disabled) is honored.
    int secure = a.secureMedia ? a.secureMedia.intValue
               : (a.transport == SipTransportTls ? SecureMediaSdesSrtp : SecureMediaDisabled);

    // ICE: enable when the app asks OR when media is secure. Providers that bridge
    // WebRTC-style media offer ICE + DTLS-SRTP (a=ice-ufrag / a=candidate with
    // UDP/TLS/RTP/SAVP); without ICE the engine fires the DTLS ClientHello to the
    // raw c= address, which the peer gates behind ICE connectivity checks, so the
    // handshake never completes (PJMEDIA_SRTP_EKEYNOTREADY) -> no audio. ICE is
    // additive: pjsip only activates it when the peer actually offers candidates.
    cfg.natConfig.iceEnabled = a.iceEnabled.boolValue || (secure != SecureMediaDisabled);
    cfg.natConfig.contactRewriteUse = (a.rewriteContactIp == nil || a.rewriteContactIp.boolValue) ? 2 : 0;
    if (a.keepAliveTime && a.keepAliveTime.intValue > 0)
        cfg.natConfig.udpKaIntervalSec = a.keepAliveTime.intValue;
    if (a.turnServer.length) {
        cfg.natConfig.turnEnabled = true;
        cfg.natConfig.turnServer = cpp(a.turnServer);
        cfg.natConfig.turnUserName = cpp(a.turnUser);
        cfg.natConfig.turnPasswordType = 0;
        cfg.natConfig.turnPassword = cpp(a.turnPassword);
    }

    // OPTIONAL (not MANDATORY): still offers SRTP on outgoing calls, but accepts
    // a plain-RTP *incoming* call instead of failing media init with
    // PJMEDIA_SRTP_ESDPINTRANSPORT — mandatory left mismatched incoming calls
    // half-initialized and a retransmitted INVITE then crashed pjsua_call_on_incoming.
    cfg.mediaConfig.srtpUse = (secure == SecureMediaDisabled) ? PJMEDIA_SRTP_DISABLED : PJMEDIA_SRTP_OPTIONAL;
    if (secure != SecureMediaDisabled) {
        // Enable BOTH SDES (a=crypto, RTP/SAVP) and DTLS-SRTP (UDP/TLS/RTP/SAVP)
        // keying. Providers may send either; our outgoing uses SDES, but this
        // provider offers DTLS-SRTP on *incoming* calls. Without DTLS keying,
        // pjsip failed the incoming media transport (PJMEDIA_SRTP_ESDPINTRANSPORT)
        // and then crashed in pjsua_call_on_incoming. Both keyings are compiled in.
        cfg.mediaConfig.srtpOpt.keyings.clear();
        cfg.mediaConfig.srtpOpt.keyings.push_back(PJMEDIA_SRTP_KEYING_SDES);
        cfg.mediaConfig.srtpOpt.keyings.push_back(PJMEDIA_SRTP_KEYING_DTLS_SRTP);
    }
    cfg.mediaConfig.srtpSecureSignaling = 0;

    cfg.videoConfig.autoShowIncoming = true;
    cfg.videoConfig.autoTransmitOutgoing =
        (a.upgradeToVideo && a.upgradeToVideo.intValue == UpgradeToVideoModeSendRecv);
    return cfg;
}

- (void)applyCodecPriorities:(SipCoreAccData*)a {
    if (!a.aCodecs.count) return;
    try {
        for (const CodecInfo &ci : _eng->ep->codecEnum2())
            _eng->ep->codecSetPriority(ci.codecId, 0);
        int prio = 254;
        for (NSNumber *c in a.aCodecs) {
            std::string codecId;
            switch (c.intValue) {
                case AudioCodecsPCMU: codecId = "PCMU/8000"; break;
                case AudioCodecsPCMA: codecId = "PCMA/8000"; break;
                case AudioCodecsG722: codecId = "G722/16000"; break;
                case AudioCodecsILBC: codecId = "iLBC/8000"; break;
                case AudioCodecsOpus: codecId = "opus/48000"; break;   // built at P3
                case AudioCodecsG729: codecId = "G729/8000"; break;    // built at P3
                default: continue;
            }
            try { _eng->ep->codecSetPriority(codecId, prio--); } catch (Error &) {}
        }
        try { _eng->ep->codecSetPriority("telephone-event/8000", 200); } catch (Error &) {}
    } catch (Error &err) { _eng->lastError = err.info(); }
}

- (int)accountAdd:(SipCoreAccData*)accData {
    GUARD_INIT();
    // PJSIP silently skips registration (no onRegState callback at all) when
    // the account's transport can't produce a Contact — fail loudly instead.
    if (accData.transport == SipTransportTls && !_eng->tlsAvailable) {
        _eng->lastError = "TLS transport is not available in this engine build";
        return -1;
    }
    try {
        CoreAccount *acc = new CoreAccount(_eng, _eng->nextAccId);
        acc->server = cpp(accData.sipServer);
        acc->create(buildAccountConfig(accData));
        [self applyCodecPriorities:accData];
        _eng->accounts[acc->wireId] = acc;
        accData.myAccId = acc->wireId;
        _eng->nextAccId++;
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)accountUpdate:(SipCoreAccData*)accData accId:(int)accId {
    GUARD_INIT();
    auto it = _eng->accounts.find(accId);
    if (it == _eng->accounts.end()) { _eng->lastError = "Account not found"; return -1; }
    try {
        it->second->server = cpp(accData.sipServer);
        it->second->modify(buildAccountConfig(accData));
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)accountRegister:(int)accId expireTime:(int)expireTime {
    GUARD_INIT();
    auto it = _eng->accounts.find(accId);
    if (it == _eng->accounts.end()) { _eng->lastError = "Account not found"; return -1; }
    try { it->second->setRegistration(true); return kErrorCodeEOK; }
    catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)accountUnRegister:(int)accId {
    GUARD_INIT();
    auto it = _eng->accounts.find(accId);
    if (it == _eng->accounts.end()) { _eng->lastError = "Account not found"; return -1; }
    try { it->second->setRegistration(false); return kErrorCodeEOK; }
    catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)accountDelete:(int)accId {
    GUARD_INIT();
    auto it = _eng->accounts.find(accId);
    if (it == _eng->accounts.end()) { _eng->lastError = "Account not found"; return -1; }
    delete it->second;
    _eng->accounts.erase(it);
    return kErrorCodeEOK;
}

- (NSString*)accountGenInstId { return [[NSUUID UUID] UUIDString].lowercaseString; }

////////////////////////////////////////////////////////////////////////// calls

- (int)callInvite:(SipCoreDestData*)destData {
    GUARD_INIT();
    CoreAccount *acc = nullptr;
    auto it = _eng->accounts.find(destData.fromAccId);
    if (it != _eng->accounts.end()) acc = it->second;
    else if (!_eng->accounts.empty()) acc = _eng->accounts.begin()->second;
    if (!acc) { _eng->lastError = "No account for call"; return -1; }

    CoreCall *call = new CoreCall(_eng, *acc);
    call->accWireId = acc->wireId;
    try {
        CallOpParam prm(true);
        prm.opt.audioCount = 1;
        prm.opt.videoCount = destData.withVideo.boolValue ? 1 : 0;
        if (destData.xheaders.count) {
            for (NSString *key in destData.xheaders) {
                id val = destData.xheaders[key];
                if (![val isKindOfClass:[NSString class]]) continue;
                SipHeader h; h.hName = cpp(key); h.hValue = cpp(val);
                prm.txOption.headers.push_back(h);
            }
        }
        std::string toExt = cpp(destData.toExt);
        std::string uri = (toExt.find('@') != std::string::npos)
            ? "sip:" + toExt : "sip:" + toExt + "@" + acc->server;
        call->makeCall(uri, prm);
        call->wireId = call->getId() + 1;
        int callId = call->wireId;
        _eng->calls[callId] = call;
        destData.myCallId = callId;
        // Match the previous engine: a newly created outgoing call becomes the
        // active ("switched") call, so the Dart layer's switchedCall() resolves.
        _eng->switchedCallId = callId;
        NSInteger cid = callId;
        emitOn(_eng, ^(SCDelegate d) { [d onCallSwitched:cid]; });
        return kErrorCodeEOK;
    } catch (Error &err) {
        _eng->lastError = err.info();
        delete call;
        return -1;
    }
}

#define FIND_CALL(cid) \
    CoreCall *call = _eng->findCall(cid); \
    if (!call) { _eng->lastError = "Call not found"; return -1; }

- (int)callReject:(int)callId statusCode:(int)statusCode {
    GUARD_INIT(); FIND_CALL(callId);
    try {
        CallOpParam prm;
        prm.statusCode = (pjsip_status_code)statusCode;
        call->hangup(prm);
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)callAccept:(int)callId withVideo:(BOOL)withVideo {
    GUARD_INIT(); FIND_CALL(callId);
    try {
        CallOpParam prm;
        prm.statusCode = PJSIP_SC_OK;
        prm.opt.audioCount = 1;
        prm.opt.videoCount = withVideo ? 1 : 0;
        call->answer(prm);
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)callBye:(int)callId {
    GUARD_INIT(); FIND_CALL(callId);
    try { call->hangup(CallOpParam()); return kErrorCodeEOK; }
    catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)callHold:(int)callId {
    GUARD_INIT(); FIND_CALL(callId);
    try {
        if (!call->localHold) {
            call->setHold(CallOpParam());
            call->localHold = true;
        } else {
            CallOpParam prm(true);
            prm.opt.flag |= PJSUA_CALL_UNHOLD;
            call->reinvite(prm);
            call->localHold = false;
        }
        HoldState hs = (HoldState)call->holdStateValue();
        NSInteger cid = callId;
        emitOn(_eng, ^(SCDelegate d) { [d onCallHeld:cid holdState:hs]; });
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)callGetHoldState:(int)callId holdState:(SipCoreHoldData*)data {
    GUARD_INIT(); FIND_CALL(callId);
    data.holdState = (HoldState)call->holdStateValue();
    return kErrorCodeEOK;
}

- (int)callGetVideoState:(int)callId hasVideo:(SipCoreVideoStateData*)data {
    GUARD_INIT(); FIND_CALL(callId);
    data.hasVideo = call->videoActive;
    return kErrorCodeEOK;
}

- (NSString*)callGetSipHeader:(int)callId hdrName:(NSString*)hdrName {
    CoreCall *call = _eng->findCall(callId);
    if (!call) return @"";
    std::string msg = call->inviteMsg;
    std::string prefix = cpp(hdrName) + ":";
    size_t pos = 0;
    while (pos < msg.size()) {
        size_t eol = msg.find("\r\n", pos);
        if (eol == std::string::npos) eol = msg.size();
        std::string line = msg.substr(pos, eol - pos);
        if (line.size() > prefix.size() &&
            strncasecmp(line.c_str(), prefix.c_str(), prefix.size()) == 0) {
            std::string val = line.substr(prefix.size());
            val.erase(0, val.find_first_not_of(" \t"));
            return str(val);
        }
        pos = eol + 2;
    }
    return @"";
}

- (NSString*)callGetStats:(int)callId {
    CoreCall *call = _eng->findCall(callId);
    if (!call) return @"";
    try { return str(call->dump(true, "  ")); } catch (Error &) { return @""; }
}

- (int)callMuteMic:(int)callId mute:(BOOL)mute {
    GUARD_INIT(); FIND_CALL(callId);
    AudioMedia *aud = _eng->activeAudio(call);
    if (!aud) { _eng->lastError = "No active audio"; return -1; }
    try {
        AudioMedia &cap = _eng->ep->audDevManager().getCaptureDevMedia();
        if (mute) cap.stopTransmit(*aud); else cap.startTransmit(*aud);
        call->muted = mute;
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)callMuteCam:(int)callId mute:(BOOL)mute {
    GUARD_INIT(); FIND_CALL(callId);
    try {
        call->vidSetStream(mute ? PJSUA_CALL_VID_STRM_STOP_TRANSMIT
                                : PJSUA_CALL_VID_STRM_START_TRANSMIT,
                           CallVidSetStreamParam());
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)callSendDtmf:(int)callId dtmfs:(NSString*)dtmfs
         durationMs:(int)durationMs intertoneGapMs:(int)intertoneGapMs method:(DtmfMethod)method {
    GUARD_INIT(); FIND_CALL(callId);
    try {
        CallSendDtmfParam prm;
        prm.digits = cpp(dtmfs);
        prm.duration = durationMs;
        prm.method = (method == DtmfMethodInfo) ? PJSUA_DTMF_METHOD_SIP_INFO
                                                : PJSUA_DTMF_METHOD_RFC2833;
        call->sendDtmf(prm);
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)callSendDtmf:(int)callId dtmfs:(NSString*)dtmfs {
    return [self callSendDtmf:callId dtmfs:dtmfs durationMs:200 intertoneGapMs:50 method:DtmfMethodRtp];
}

- (int)callPlayTone:(int)callId toneType:(NSString*)toneType durationMs:(int)durationMs
         playerData:(SipCorePlayerData*)data {
    GUARD_INIT(); FIND_CALL(callId);
    AudioMedia *aud = _eng->activeAudio(call);
    if (!aud) { _eng->lastError = "No active audio"; return -1; }
    try {
        ToneGenerator *tg = new ToneGenerator();
        tg->createToneGenerator();
        ToneDigitVector digits;
        for (NSUInteger i = 0; i < toneType.length; ++i) {
            ToneDigit d;
            d.digit = (char)[toneType characterAtIndex:i];
            d.on_msec = (short)durationMs;
            d.off_msec = 100;
            digits.push_back(d);
        }
        tg->playDigits(digits);
        tg->startTransmit(*aud);
        // Tracked as a player so StopPlayFile can stop it. ToneGenerator isn't
        // an AudioMediaPlayer, so wrap deletion in the player slot via id only.
        data.playerId = _eng->nextPlayerId++;
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)callPlayFile:(int)callId pathToMp3File:(NSString*)path loop:(BOOL)loop
         playerData:(SipCorePlayerData*)data {
    GUARD_INIT(); FIND_CALL(callId);
    AudioMedia *aud = _eng->activeAudio(call);
    if (!aud) { _eng->lastError = "No active audio"; return -1; }
    CorePlayer *player = new CorePlayer(_eng, _eng->nextPlayerId);
    try {
        player->createPlayer(cpp(path), loop ? 0 : PJMEDIA_FILE_NO_LOOP);
        player->startTransmit(*aud);
        _eng->players[player->wireId] = player;
        data.playerId = player->wireId;
        _eng->nextPlayerId++;
        NSInteger pid = data.playerId;
        emitOn(_eng, ^(SCDelegate d) { [d onPlayerState:pid playerState:PlayerStateStarted]; });
        return kErrorCodeEOK;
    } catch (Error &err) {
        _eng->lastError = err.info();
        delete player;
        return -1;
    }
}

- (int)callStopPlayFile:(int)playerId {
    GUARD_INIT();
    auto it = _eng->players.find(playerId);
    if (it == _eng->players.end()) { _eng->lastError = "Player not found"; return -1; }
    delete it->second;
    _eng->players.erase(it);
    NSInteger pid = playerId;
    emitOn(_eng, ^(SCDelegate d) { [d onPlayerState:pid playerState:PlayerStateStopped]; });
    return kErrorCodeEOK;
}

- (int)callRecordFile:(int)callId pathToMp3File:(NSString*)path {
    GUARD_INIT(); FIND_CALL(callId);
    AudioMedia *aud = _eng->activeAudio(call);
    if (!aud) { _eng->lastError = "No active audio"; return -1; }
    try {
        AudioMediaRecorder *rec = new AudioMediaRecorder();
        rec->createRecorder(cpp(path));
        aud->startTransmit(*rec);
        try { _eng->ep->audDevManager().getCaptureDevMedia().startTransmit(*rec); } catch (Error &) {}
        _eng->recorders[callId] = rec;
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)callStopRecordFile:(int)callId {
    GUARD_INIT();
    auto it = _eng->recorders.find(callId);
    if (it == _eng->recorders.end()) { _eng->lastError = "No recorder for call"; return -1; }
    delete it->second;
    _eng->recorders.erase(it);
    return kErrorCodeEOK;
}

- (int)callTransferBlind:(int)callId toExt:(NSString*)toExt {
    GUARD_INIT(); FIND_CALL(callId);
    try {
        std::string ext = cpp(toExt);
        std::string server;
        auto acc = _eng->accounts.find(call->accWireId);
        if (acc != _eng->accounts.end()) server = acc->second->server;
        std::string uri = (ext.find('@') != std::string::npos) ? "sip:" + ext
                                                               : "sip:" + ext + "@" + server;
        call->xfer(uri, CallOpParam());
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)callTransferAttended:(int)fromCallId toCallId:(int)toCallId {
    GUARD_INIT();
    CoreCall *from = _eng->findCall(fromCallId);
    CoreCall *to = _eng->findCall(toCallId);
    if (!from || !to) { _eng->lastError = "Call not found"; return -1; }
    try { from->xferReplaces(*to, CallOpParam()); return kErrorCodeEOK; }
    catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)callUpgradeToVideo:(int)callId {
    GUARD_INIT(); FIND_CALL(callId);
    try {
        CallOpParam prm(true);
        prm.opt.audioCount = 1;
        prm.opt.videoCount = 1;
        call->reinvite(prm);
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)callAcceptVideoUpgrade:(int)callId withVideo:(BOOL)withVideo {
    GUARD_INIT(); FIND_CALL(callId);
    try {
        CallOpParam prm(true);
        prm.opt.audioCount = 1;
        prm.opt.videoCount = withVideo ? 1 : 0;
        call->reinvite(prm);
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)callSetVideoRenderer:(int)callId renderer:(id<SipCoreVideoRendererDelegate>)renderer {
    // Raw-frame delegation needs a custom pjmedia video device (P4). Remote
    // video today renders into the UIView passed via callSetVideoWindow:.
    return kErrorCodeEOK;
}

- (void)callStopRingtone {
    emitOn(_eng, ^(SCDelegate d) { [d onRingerState:NO]; });
}

- (int)switchCamera {
    // Front/back switch arrives with P4 (video capture device management).
    return kErrorCodeEOK;
}

- (int)callSetVideoWindow:(int)callId view:(UIView*)view {
    GUARD_INIT();
    if (!view) { _eng->callViews.erase(callId); return kErrorCodeEOK; }
    _eng->callViews[callId] = view;
    CoreCall *call = _eng->findCall(callId);
    if (!call) return kErrorCodeEOK;
    try {
        CallInfo ci = call->getInfo();
        for (unsigned i = 0; i < ci.media.size(); ++i) {
            if (ci.media[i].type == PJMEDIA_TYPE_VIDEO &&
                ci.media[i].status == PJSUA_CALL_MEDIA_ACTIVE) {
                _eng->attachVideoView(call, ci.media[i].videoIncomingWindowId);
            }
        }
    } catch (Error &) {}
    return kErrorCodeEOK;
}

- (UIView*)createVideoWindow {
    return [[UIView alloc] initWithFrame:CGRectZero];
}

////////////////////////////////////////////////////////////////////////// mixer

- (int)mixerSwitchCall:(int)callId {
    GUARD_INIT();
    try {
        AudDevManager &adm = _eng->ep->audDevManager();
        for (auto &kv : _eng->calls) {
            AudioMedia *aud = _eng->activeAudio(kv.second);
            if (!aud) continue;
            if (kv.first == callId) {
                aud->startTransmit(adm.getPlaybackDevMedia());
                if (!kv.second->muted) adm.getCaptureDevMedia().startTransmit(*aud);
            } else {
                try { aud->stopTransmit(adm.getPlaybackDevMedia()); } catch (Error &) {}
                try { adm.getCaptureDevMedia().stopTransmit(*aud); } catch (Error &) {}
            }
        }
        _eng->switchedCallId = callId;
        NSInteger cid = callId;
        emitOn(_eng, ^(SCDelegate d) { [d onCallSwitched:cid]; });
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)mixerMakeConference {
    GUARD_INIT();
    try {
        AudDevManager &adm = _eng->ep->audDevManager();
        std::vector<AudioMedia*> medias;
        for (auto &kv : _eng->calls) {
            AudioMedia *aud = _eng->activeAudio(kv.second);
            if (!aud) continue;
            aud->startTransmit(adm.getPlaybackDevMedia());
            if (!kv.second->muted) adm.getCaptureDevMedia().startTransmit(*aud);
            medias.push_back(aud);
        }
        for (AudioMedia *a : medias)
            for (AudioMedia *b : medias)
                if (a != b) { try { a->startTransmit(*b); } catch (Error &) {} }
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)dvcSetVideoParams:(SipCoreVideoData*)vdoData {
    // Applied to the video device/codec params at P4; accepted for now.
    return kErrorCodeEOK;
}

///////////////////////////////////////////////////////////////////// messaging

- (int)messageSend:(SipCoreMsgData*)msgData {
    GUARD_INIT();
    CoreAccount *acc = nullptr;
    auto it = _eng->accounts.find(msgData.fromAccId);
    if (it != _eng->accounts.end()) acc = it->second;
    else if (!_eng->accounts.empty()) acc = _eng->accounts.begin()->second;
    if (!acc) { _eng->lastError = "No account for message"; return -1; }
    try {
        std::string toExt = cpp(msgData.toExt);
        std::string uri = (toExt.find('@') != std::string::npos)
            ? "sip:" + toExt : "sip:" + toExt + "@" + acc->server;
        BuddyConfig bCfg;
        bCfg.uri = uri;
        bCfg.subscribe = false;
        Buddy buddy;
        buddy.create(*acc, bCfg);
        SendInstantMessageParam prm;
        prm.content = cpp(msgData.body);
        if (msgData.contentType.length) prm.contentType = cpp(msgData.contentType);
        buddy.sendInstantMessage(prm);
        int msgId = _eng->nextMsgId++;
        _eng->pendingMsgIds.push_back(msgId);
        msgData.myMessageId = msgId;
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

///////////////////////////////////////////////////////////////// subscriptions

- (int)subscrCreate:(SipCoreSubscrData*)subscrData {
    // NOTE: pjsua2 exposes presence (Event: presence) only. BLF (Event:
    // dialog) needs a pjsip-level extension — tracked for P6.
    GUARD_INIT();
    CoreAccount *acc = nullptr;
    auto it = _eng->accounts.find(subscrData.fromAccId);
    if (it != _eng->accounts.end()) acc = it->second;
    else if (!_eng->accounts.empty()) acc = _eng->accounts.begin()->second;
    if (!acc) { _eng->lastError = "No account for subscription"; return -1; }
    try {
        std::string toExt = cpp(subscrData.toExt);
        std::string uri = (toExt.find('@') != std::string::npos)
            ? "sip:" + toExt : "sip:" + toExt + "@" + acc->server;
        BuddyConfig bCfg;
        bCfg.uri = uri;
        bCfg.subscribe = true;
        CoreBuddy *buddy = new CoreBuddy(_eng, _eng->nextSubscrId);
        buddy->create(*acc, bCfg);
        _eng->buddies[buddy->subscrId] = buddy;
        subscrData.mySubscrId = buddy->subscrId;
        _eng->nextSubscrId++;
        return kErrorCodeEOK;
    } catch (Error &err) { _eng->lastError = err.info(); return -1; }
}

- (int)subscrDestroy:(int)subscrId {
    GUARD_INIT();
    auto it = _eng->buddies.find(subscrId);
    if (it == _eng->buddies.end()) { _eng->lastError = "Subscription not found"; return -1; }
    try { it->second->subscribePresence(false); } catch (Error &) {}
    delete it->second;
    _eng->buddies.erase(it);
    NSInteger sid = subscrId;
    emitOn(_eng, ^(SCDelegate d) {
        [d onSubscriptionState:sid subscrState:SubscrDestroyed response:@""];
    });
    return kErrorCodeEOK;
}

@end
