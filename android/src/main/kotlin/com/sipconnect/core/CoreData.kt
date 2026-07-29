@file:Suppress("SpellCheckingInspection", "unused")
package com.sipconnect.core

/*
 * Data holders + enums for the PJSIP-backed engine.
 *
 * These classes mirror the API surface the plugin classes were written
 * against. All integer values are pinned by the Dart
 * wire protocol (lib/sip_connect.dart constants) — do not renumber.
 */

////////////////////////////////////////////////////////////////////////////////////////
// Listener interfaces

interface ISipModelListener {
  fun onTrialModeNotified()
  fun onDevicesAudioChanged()
  fun onAccountRegState(accId: Int, regState: AccData.RegState, response: String?)
  fun onSubscriptionState(subscrId: Int, state: SubscrData.SubscrState, response: String?)
  fun onNetworkState(name: String?, state: SipCore.NetworkState?)
  fun onPlayerState(playerId: Int, state: SipCore.PlayerState?)
  fun onCallProceeding(callId: Int, response: String?)
  fun onCallTerminated(callId: Int, statusCode: Int)
  fun onCallConnected(callId: Int, hdrFrom: String?, hdrTo: String?, withVideo: Boolean)
  fun onCallIncoming(callId: Int, accId: Int, withVideo: Boolean, hdrFrom: String?, hdrTo: String?)
  fun onCallDtmfReceived(callId: Int, tone: Int)
  fun onCallTransferred(callId: Int, statusCode: Int)
  fun onCallRedirected(origCallId: Int, relatedCallId: Int, referTo: String?)
  fun onCallVideoUpgraded(callId: Int, withVideo: Boolean)
  fun onCallVideoUpgradeRequested(callId: Int)
  fun onCallHeld(callId: Int, state: SipCore.HoldState?)
  fun onCallSwitched(callId: Int)
  fun onMessageSentState(messageId: Int, success: Boolean, response: String?)
  fun onMessageIncoming(messageId: Int, accId: Int, hdrFrom: String?, body: String?)
  fun onSipNotify(accId: Int, hdrEvent: String?, body: String?)
  fun onVuMeterLevel(micLevel: Int, spkLevel: Int)
}

/** Subset of events the background service reacts to (ringer + notifications). */
interface ISipServiceListener {
  fun onRingerState(start: Boolean)
  fun onCallTerminated(callId: Int, statusCode: Int)
  fun onCallConnected(callId: Int, hdrFrom: String?, hdrTo: String?, withVideo: Boolean)
  fun onCallIncoming(callId: Int, accId: Int, withVideo: Boolean, hdrFrom: String, hdrTo: String)
  fun onMessageIncoming(messageId: Int, accId: Int, hdrFrom: String?, body: String?)
}

interface ISipRinger {
  fun start()
  fun stop()
}

////////////////////////////////////////////////////////////////////////////////////////
// Module init settings

class IniData {
  enum class LogLevel(val value: Int) {
    Stack(0), Debug(1), Info(2), Warning(3), Error(4), None(5);
    companion object { fun fromInt(v: Int) = entries.firstOrNull { it.value == v } ?: Info }
  }

  @JvmField var license: String? = null;            fun setLicense(v: String) { license = v }
  @JvmField var brandName: String? = null;          fun setBrandName(v: String) { brandName = v }
  @JvmField var logLevelFile: LogLevel = LogLevel.Info;  fun setLogLevelFile(v: LogLevel) { logLevelFile = v }
  @JvmField var logLevelIde: LogLevel = LogLevel.Info;   fun setLogLevelIde(v: LogLevel) { logLevelIde = v }
  @JvmField var rtpStartPort: Int = 0;              fun setRtpStartPort(v: Int) { rtpStartPort = v }
  @JvmField var tlsVerifyServer: Boolean = false;   fun setTlsVerifyServer(v: Boolean) { tlsVerifyServer = v }
  @JvmField var singleCallMode: Boolean = false;    fun setSingleCallMode(v: Boolean) { singleCallMode = v }
  @JvmField var shareUdpTransport: Boolean = true;  fun setShareUdpTransport(v: Boolean) { shareUdpTransport = v }
  @JvmField var unregOnDestroy: Boolean = true;     fun setUnregOnDestroy(v: Boolean) { unregOnDestroy = v }
  @JvmField var useDnsSrv: Boolean = false;         fun setUseDnsSrv(v: Boolean) { useDnsSrv = v }
  @JvmField var recordStereo: Boolean = false;      fun setRecordStereo(v: Boolean) { recordStereo = v }
  @JvmField var enableVideoCall: Boolean = true;    fun setEnableVideoCall(v: Boolean) { enableVideoCall = v }
  @JvmField var transpForceIPv4: Boolean = false;   fun setTranspForceIPv4(v: Boolean) { transpForceIPv4 = v }
  @JvmField var enableAes128Sha32: Boolean = false; fun setEnableAes128Sha32(v: Boolean) { enableAes128Sha32 = v }
  @JvmField var enableVUmeter: Boolean = false;     fun setEnableVUmeter(v: Boolean) { enableVUmeter = v }
  @JvmField var useTelState: Boolean = false;       fun setUseTelState(v: Boolean) { useTelState = v }
  @JvmField var useVolChange: Boolean = false;      fun setUseVolChange(v: Boolean) { useVolChange = v }
  @JvmField var use16kHzAudio: Boolean = false;     fun setUse16kHzAudio(v: Boolean) { use16kHzAudio = v }
  @JvmField var useExternalRinger: Boolean = false; fun setUseExternalRinger(v: Boolean) { useExternalRinger = v }
}

////////////////////////////////////////////////////////////////////////////////////////
// Account settings

class AccData {
  enum class RegState(val value: Int) {
    Success(0), Failed(1), Removed(2);
    companion object { fun fromInt(v: Int) = entries.firstOrNull { it.value == v } ?: Failed }
  }
  enum class SipTransport(val value: Int) {
    Udp(0), Tcp(1), Tls(2);
    companion object { fun fromInt(v: Int) = entries.firstOrNull { it.value == v } ?: Udp }
  }
  enum class SecureMediaMode(val value: Int) {
    Disabled(0), SdesSrtp(1), DtlsSrtp(2);
    companion object { fun fromInt(v: Int) = entries.firstOrNull { it.value == v } ?: Disabled }
  }
  enum class UpgradeToVideoMode(val value: Int) {
    SendRecv(0), RecvOnly(1), Inactive(2), Manual(3);
    companion object { fun fromInt(v: Int) = entries.firstOrNull { it.value == v } ?: RecvOnly }
  }
  enum class AudioCodec(val value: Int) {
    Opus(65), ISAC16(66), ISAC32(67), G722(68), ILBC(69), PCMU(70), PCMA(71), DTMF(72), CN(73), G729(74);
    companion object { fun fromInt(v: Int) = entries.firstOrNull { it.value == v } ?: PCMU }
  }
  enum class VideoCodec(val value: Int) {
    H264(80), VP8(81), VP9(82), AV1(83);
    companion object { fun fromInt(v: Int) = entries.firstOrNull { it.value == v } ?: H264 }
  }

  @JvmField var sipServer: String = "";        fun setSipServer(v: String) { sipServer = v }
  @JvmField var sipExtension: String = "";     fun setSipExtension(v: String) { sipExtension = v }
  @JvmField var sipPassword: String = "";      fun setSipPassword(v: String) { sipPassword = v }
  @JvmField var sipAuthId: String? = null;     fun setSipAuthId(v: String) { sipAuthId = v }
  @JvmField var sipProxy: String? = null;      fun setSipProxyServer(v: String) { sipProxy = v }
  @JvmField var displName: String? = null;     fun setDisplayName(v: String) { displName = v }
  @JvmField var userAgent: String? = null;     fun setUserAgent(v: String) { userAgent = v }
  @JvmField var expireTime: Int = 300;         fun setExpireTime(v: Int) { expireTime = v }
  @JvmField var transport: SipTransport = SipTransport.Udp; fun setTranspProtocol(v: SipTransport) { transport = v }
  @JvmField var port: Int = 0;                 fun setTranspPort(v: Int) { port = v }
  @JvmField var tlsCaCertPath: String? = null; fun setTranspTlsCaCert(v: String) { tlsCaCertPath = v }
  @JvmField var tlsUseSipScheme: Boolean = false; fun setUseSipSchemeForTls(v: Boolean) { tlsUseSipScheme = v }
  @JvmField var rtcpMuxEnabled: Boolean = false;  fun setRtcpMuxEnabled(v: Boolean) { rtcpMuxEnabled = v }
  @JvmField var iceEnabled: Boolean = false;   fun setIceEnabled(v: Boolean) { iceEnabled = v }
  @JvmField var instanceId: String? = null;    fun setInstanceId(v: String) { instanceId = v }
  @JvmField var ringTonePath: String? = null;  fun setRingToneFile(v: String) { ringTonePath = v }
  @JvmField var keepAliveTime: Int = 30;       fun setKeepAliveTime(v: Int) { keepAliveTime = v }
  @JvmField var rewriteContactIp: Boolean = true; fun setRewriteContactIp(v: Boolean) { rewriteContactIp = v }
  @JvmField var verifyIncomingCall: Boolean = false; fun setVerifyIncomingCall(v: Boolean) { verifyIncomingCall = v }
  @JvmField var forceSipProxy: Boolean = false;   fun setForceSipProxy(v: Boolean) { forceSipProxy = v }
  // null = not specified by the app (engine defaults it by transport); a set
  // value (including Disabled) is an explicit choice and is honored as-is.
  @JvmField var secureMedia: SecureMediaMode? = null; fun setSecureMediaMode(v: SecureMediaMode) { secureMedia = v }
  @JvmField var upgradeToVideo: UpgradeToVideoMode = UpgradeToVideoMode.RecvOnly; fun setUpgradeToVideoMode(v: UpgradeToVideoMode) { upgradeToVideo = v }
  @JvmField var stunServer: String? = null;    fun setStunServer(v: String) { stunServer = v }
  @JvmField var turnServer: String? = null;    fun setTurnServer(v: String) { turnServer = v }
  @JvmField var turnUser: String? = null;      fun setTurnUser(v: String) { turnUser = v }
  @JvmField var turnPassword: String? = null;  fun setTurnPassword(v: String) { turnPassword = v }

  val xheaders = LinkedHashMap<String, String>()
  fun addXHeader(name: String, value: String) { xheaders[name] = value }

  val xContactUriParams = LinkedHashMap<String, String>()
  fun addXContactUriParam(name: String, value: String) { xContactUriParams[name] = value }

  @JvmField var audioCodecs: MutableList<AudioCodec>? = null
  fun resetAudioCodecs() { audioCodecs = mutableListOf() }
  fun addAudioCodec(c: AudioCodec) { audioCodecs?.add(c) }

  @JvmField var videoCodecs: MutableList<VideoCodec>? = null
  fun resetVideoCodecs() { videoCodecs = mutableListOf() }
  fun addVideoCodec(c: VideoCodec) { videoCodecs?.add(c) }
}

////////////////////////////////////////////////////////////////////////////////////////
// Call destination / message / subscription / video settings

class DestData {
  @JvmField var toExt: String = "";        fun setExtension(v: String) { toExt = v }
  @JvmField var accId: Int = 0;            fun setAccountId(v: Int) { accId = v }
  @JvmField var inviteTimeout: Int = 0;    fun setInviteTimeout(v: Int) { inviteTimeout = v }
  @JvmField var withVideo: Boolean = false; fun setVideoCall(v: Boolean) { withVideo = v }
  @JvmField var displName: String? = null; fun setDisplayName(v: String) { displName = v }
  val xheaders = LinkedHashMap<String, String>()
  fun addXHeader(name: String, value: String) { xheaders[name] = value }
}

class MsgData {
  @JvmField var toExt: String = "";          fun setExtension(v: String) { toExt = v }
  @JvmField var accId: Int = 0;              fun setAccountId(v: Int) { accId = v }
  @JvmField var body: String = "";           fun setBody(v: String) { body = v }
  @JvmField var contentType: String? = null; fun setContentType(v: String) { contentType = v }
}

class SubscrData {
  enum class SubscrState(val value: Int) {
    Created(0), Updated(1), Destroyed(2);
    companion object { fun fromInt(v: Int) = entries.firstOrNull { it.value == v } ?: Updated }
  }

  @JvmField var toExt: String = "";           fun setExtension(v: String) { toExt = v }
  @JvmField var accId: Int = 0;               fun setAccountId(v: Int) { accId = v }
  @JvmField var expireTime: Int = 0;          fun setExpireTime(v: Int) { expireTime = v }
  @JvmField var mimeSubType: String? = null;  fun setMimeSubtype(v: String) { mimeSubType = v }
  @JvmField var eventType: String? = null;    fun setEventType(v: String) { eventType = v }
  @JvmField var body: String? = null;         fun setBody(v: String) { body = v }
}

class VideoData {
  @JvmField var noCameraImgPath: String? = null; fun setNoCameraImgPath(v: String) { noCameraImgPath = v }
  @JvmField var framerateFps: Int = 0;           fun setFramerate(v: Int) { framerateFps = v }
  @JvmField var bitrateKbps: Int = 0;            fun setBitrate(v: Int) { bitrateKbps = v }
  @JvmField var width: Int = 0;                  fun setWidth(v: Int) { width = v }
  @JvmField var height: Int = 0;                 fun setHeight(v: Int) { height = v }
}
