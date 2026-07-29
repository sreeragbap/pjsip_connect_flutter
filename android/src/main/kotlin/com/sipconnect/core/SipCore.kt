@file:Suppress("SpellCheckingInspection", "unused")
package com.sipconnect.core

import android.content.Context
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Surface
import org.pjsip.pjsua2.Account
import org.pjsip.pjsua2.AccountConfig
import org.pjsip.pjsua2.AudDevManager
import org.pjsip.pjsua2.AudioMedia
import org.pjsip.pjsua2.AudioMediaPlayer
import org.pjsip.pjsua2.AudioMediaRecorder
import org.pjsip.pjsua2.AuthCredInfo
import org.pjsip.pjsua2.Buddy
import org.pjsip.pjsua2.BuddyConfig
import org.pjsip.pjsua2.Call
import org.pjsip.pjsua2.CallOpParam
import org.pjsip.pjsua2.CallSendDtmfParam
import org.pjsip.pjsua2.CallVidSetStreamParam
import org.pjsip.pjsua2.Endpoint
import org.pjsip.pjsua2.EpConfig
import org.pjsip.pjsua2.IpChangeParam
import org.pjsip.pjsua2.OnCallMediaStateParam
import org.pjsip.pjsua2.OnCallStateParam
import org.pjsip.pjsua2.OnCallTsxStateParam
import org.pjsip.pjsua2.OnCallTransferStatusParam
import org.pjsip.pjsua2.OnDtmfDigitParam
import org.pjsip.pjsua2.OnIncomingCallParam
import org.pjsip.pjsua2.OnInstantMessageParam
import org.pjsip.pjsua2.OnInstantMessageStatusParam
import org.pjsip.pjsua2.OnRegStateParam
import org.pjsip.pjsua2.SendInstantMessageParam
import org.pjsip.pjsua2.SipHeader
import org.pjsip.pjsua2.SrtpOpt
import org.pjsip.pjsua2.IntVector
import org.pjsip.pjsua2.pjmedia_srtp_keying_method
import org.pjsip.pjsua2.ToneDigit
import org.pjsip.pjsua2.ToneDigitVector
import org.pjsip.pjsua2.ToneGenerator
import org.pjsip.pjsua2.TransportConfig
import org.pjsip.pjsua2.VideoWindow
import org.pjsip.pjsua2.VideoWindowHandle
import org.pjsip.pjsua2.pj_qos_type
import org.pjsip.pjsua2.pjmedia_type
import org.pjsip.pjsua2.pjsip_inv_state
import org.pjsip.pjsua2.pjsip_role_e
import org.pjsip.pjsua2.pjsip_status_code
import org.pjsip.pjsua2.pjsip_transport_type_e
import org.pjsip.pjsua2.pjsua_call_flag
import org.pjsip.pjsua2.pjsua_call_media_status
import org.pjsip.pjsua2.pjsua_call_vid_strm_op
import org.pjsip.pjsua2.pjsua_dtmf_method
import java.io.File
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch

/** Video sink the engine pushes decoded remote video into (implemented by the
 *  plugin's Flutter-texture renderer; keeps core independent of Flutter). */
interface IVideoRenderer {
  /** Returns the Surface to render into, sized w x h. */
  fun acquireSurface(width: Int, height: Int): Surface?
  fun onVideoSize(width: Int, height: Int, rotation: Int)
  fun releaseSurface()
}

/**
 * PJSIP(pjsua2)-backed engine with the same API surface the plugin classes
 * were originally written against.
 *
 * Threading: every public method runs synchronously on a dedicated worker
 * thread that owns the pjsua2 Endpoint (pjsua2 requires registered threads).
 * pjsua2 callbacks arrive on PJSIP's own threads and are forwarded to the
 * listeners on the main looper.
 */
class SipCore(private val appContext: Context) {

  enum class DtmfMethod(val value: Int) {
    Rtp(0), Info(1);
    companion object { fun fromInt(v: Int) = if (v == 1) Info else Rtp }
  }
  enum class HoldState(val value: Int) {
    None(0), Local(1), Remote(2), LocalAndRemote(3);
    companion object { fun fromInt(v: Int) = entries.firstOrNull { it.value == v } ?: None }
  }
  enum class PlayerState(val value: Int) {
    Started(0), Stopped(1), Failed(2)
  }
  enum class NetworkState(val value: Int) {
    Lost(0), Restored(1), Switched(2)
  }
  enum class AudioDevice { None, Earpiece, Speakerphone, WiredHeadset, Bluetooth }

  class IdOutArg { var value: Int = 0 }

  companion object {
    private const val TAG = "SipCore"
    const val kErrorCodeEOK = 0
    const val kErrorCode = -1

    init {
      try {
        System.loadLibrary("pjsua2")
      } catch (e: UnsatisfiedLinkError) {
        Log.e(TAG, "Can't load libpjsua2.so: $e")
      }
    }
  }

  // ---------------------------------------------------------------- state --

  private val worker = HandlerThread("SipCoreWorker").apply { start() }
  private val workerHandler = Handler(worker.looper)
  private val mainHandler = Handler(Looper.getMainLooper())

  private var ep: Endpoint? = null
  private var iniData: IniData? = null
  // Routes PJSIP's log to logcat (default writer prints to stdout, which
  // Android discards). Kept as a field: pjsua2 holds only a weak director ref.
  private var logWriter: org.pjsip.pjsua2.LogWriter? = null
  @Volatile var isInitialized: Boolean = false
    private set
  private var lastErrText: String = ""

  private var modelListener: ISipModelListener? = null
  private var serviceListener: ISipServiceListener? = null

  // Thread-safe: mutated from both PJSIP callback threads (director callbacks
  // like onCallState/onIncomingCall) and the worker thread (exec{} handlers).
  // Plain HashMaps here would race and corrupt under concurrent modification.
  private val accounts = java.util.concurrent.ConcurrentHashMap<Int, PjAccount>()      // wire accId -> account
  private val calls = java.util.concurrent.ConcurrentHashMap<Int, PjCall>()            // wire callId -> call
  private val players = java.util.concurrent.ConcurrentHashMap<Int, PjPlayer>()        // wire playerId -> player
  private val recorders = java.util.concurrent.ConcurrentHashMap<Int, AudioMediaRecorder>() // callId -> recorder
  private val buddies = java.util.concurrent.ConcurrentHashMap<Int, PjBuddy>()         // wire subscrId -> buddy
  private val renderers = java.util.concurrent.ConcurrentHashMap<Int, IVideoRenderer>()// callId -> renderer
  private var nextAccId = 1
  private var nextPlayerId = 1
  private var nextSubscrId = 1
  private var nextMsgId = 1
  private var switchedCallId = -1

  private var selAudioDevice = AudioDevice.Earpiece
  private var netLost = false
  private var tlsAvailable = false

  // ------------------------------------------------------------- plumbing --

  /** Runs [block] synchronously on the worker thread that owns the endpoint. */
  private fun <T> exec(block: () -> T): T {
    if (Thread.currentThread() == worker) return block()
    val queue = ArrayBlockingQueue<Any>(1)
    workerHandler.post {
      val res: Any = try { block() as Any } catch (t: Throwable) { t }
      queue.put(res)
    }
    val res = queue.take()
    if (res is Throwable) throw res
    @Suppress("UNCHECKED_CAST")
    return res as T
  }

  /** Wraps an engine call: returns 0 on success, records error text on failure. */
  private fun run(block: () -> Unit): Int {
    return try { exec { block(); kErrorCodeEOK } }
    catch (t: Throwable) {
      lastErrText = t.message ?: t.toString()
      Log.e(TAG, "engine error: $lastErrText")
      kErrorCode
    }
  }

  private fun onMain(block: () -> Unit) { mainHandler.post(block) }

  fun setModelListener(l: ISipModelListener?) { modelListener = l }
  fun setServiceListener(l: ISipServiceListener?) { serviceListener = l }
  fun getErrText(err: Int): String = if (err == kErrorCodeEOK) "Success" else lastErrText

  // --------------------------------------------------------------- module --

  val homeFolder: String
    get() = appContext.filesDir.absolutePath + File.separator

  val version: String
    get() = try { exec { ep?.libVersion()?.full ?: "pjsip" } } catch (t: Throwable) { "pjsip" }

  val versionCode: Int
    get() = try { exec { (ep?.libVersion()?.major ?: 0) * 10000 + (ep?.libVersion()?.minor ?: 0) * 100 } }
            catch (t: Throwable) { 0 }

  fun moduleWriteLog(msg: String) {
    Log.i(TAG, msg)
    try { if (isInitialized) exec { ep?.utilLogWrite(3, "SipConnect", msg) } } catch (_: Throwable) {}
  }

  fun initialize(ini: IniData): Int {
    if (isInitialized) return kErrorCodeEOK
    iniData = ini
    val err = run {
      val endpoint = Endpoint()
      endpoint.libCreate()

      val cfg = EpConfig()
      cfg.logConfig.level = (5 - ini.logLevelFile.value).toLong().coerceIn(0, 5)
      cfg.logConfig.consoleLevel = (5 - ini.logLevelIde.value).toLong().coerceIn(0, 5)
      cfg.logConfig.filename = homeFolder + "sip_connect.log"
      logWriter = object : org.pjsip.pjsua2.LogWriter() {
        override fun write(entry: org.pjsip.pjsua2.LogEntry) {
          Log.i("pjsip", entry.msg.trimEnd())
        }
      }
      cfg.logConfig.writer = logWriter
      ini.brandName?.let { cfg.uaConfig.userAgent = it }
      if (ini.singleCallMode) cfg.uaConfig.maxCalls = 4 // still need slots for attended transfer

      endpoint.libInit(cfg)

      // Shared transports; account-selected protocol picks one of these.
      val udpCfg = TransportConfig(); udpCfg.qosType = pj_qos_type.PJ_QOS_TYPE_VOICE
      val tcpCfg = TransportConfig(); tcpCfg.qosType = pj_qos_type.PJ_QOS_TYPE_VOICE
      if (ini.rtpStartPort > 0) { /* RTP range is set per-media below */ }
      endpoint.transportCreate(pjsip_transport_type_e.PJSIP_TRANSPORT_UDP, udpCfg)
      endpoint.transportCreate(pjsip_transport_type_e.PJSIP_TRANSPORT_TCP, tcpCfg)
      tlsAvailable = try {
        val tlsCfg = TransportConfig()
        tlsCfg.qosType = pj_qos_type.PJ_QOS_TYPE_VOICE
        tlsCfg.tlsConfig.verifyServer = ini.tlsVerifyServer
        endpoint.transportCreate(pjsip_transport_type_e.PJSIP_TRANSPORT_TLS, tlsCfg)
        true
      } catch (t: Throwable) {
        Log.w(TAG, "TLS transport unavailable (engine built without OpenSSL): $t")
        false
      }

      endpoint.libStart()
      // This whole block — and every later exec{} / workerHandler.post{} — runs
      // on the single SipCoreWorker thread, which drives pjsua2 API calls and
      // the deferred Call.delete(). pjsua2 requires such external threads to be
      // registered; calling into the library from an unregistered thread is
      // undefined behavior and can corrupt internal state (later surfacing as a
      // crash in an unrelated pjsip callback). Register once here.
      try { endpoint.libRegisterThread("SipCoreWorker") }
      catch (t: Throwable) { Log.w(TAG, "libRegisterThread: $t") }
      ep = endpoint
      isInitialized = true
    }
    if (err == kErrorCodeEOK) startNetworkMonitor()
    return err
  }

  fun unInitialize(): Int {
    if (!isInitialized) return kErrorCodeEOK
    stopNetworkMonitor()
    return run {
      isInitialized = false
      calls.clear(); players.clear(); recorders.clear(); buddies.clear(); accounts.clear()
      ep?.libDestroy()
      ep?.delete()
      ep = null
    }
  }

  // ------------------------------------------------------------- accounts --

  private inner class PjAccount(val wireId: Int, var accData: AccData) : Account() {
    override fun onRegState(prm: OnRegStateParam) {
      Log.i(TAG, "onRegState acc:$wireId code:${prm.code} reason:${prm.reason}")
      val info = try { info } catch (t: Throwable) { null }
      val expiration = info?.regExpiresSec ?: 0
      val active = info?.regIsActive ?: false
      val state = when {
        prm.code / 100 == 2 && !active -> AccData.RegState.Removed
        prm.code / 100 == 2 && active && expiration > 0 -> AccData.RegState.Success
        prm.code / 100 == 2 -> AccData.RegState.Removed
        else -> AccData.RegState.Failed
      }
      val response = "${prm.code} ${prm.reason}"
      onMain { modelListener?.onAccountRegState(wireId, state, response) }
    }

    override fun onIncomingCall(prm: OnIncomingCallParam) {
      val call = PjCall(this, prm.callId)
      call.wireId = prm.callId + 1
      val wholeMsg = try { prm.rdata.wholeMsg } catch (t: Throwable) { "" }
      call.lastInviteMsg = wholeMsg
      val withVideo = wholeMsg.contains("m=video")
      calls[call.wireId] = call

      // Send 180 Ringing so the caller hears ringback while we alert the user.
      try {
        val opPrm = CallOpParam()
        opPrm.statusCode = pjsip_status_code.PJSIP_SC_RINGING
        call.answer(opPrm)
      } catch (t: Throwable) { Log.w(TAG, "ring answer: $t") }

      val ci = try { call.info } catch (t: Throwable) { null }
      val from = ci?.remoteUri ?: ""
      val to = ci?.localUri ?: ""
      val callWireId = call.wireId
      onMain {
        serviceListener?.onRingerState(true)
        serviceListener?.onCallIncoming(callWireId, wireId, withVideo, from, to)
        modelListener?.onCallIncoming(callWireId, wireId, withVideo, from, to)
      }
    }

    override fun onInstantMessage(prm: OnInstantMessageParam) {
      val msgId = nextMsgId++
      onMain {
        serviceListener?.onMessageIncoming(msgId, wireId, prm.fromUri, prm.msgBody)
        modelListener?.onMessageIncoming(msgId, wireId, prm.fromUri, prm.msgBody)
      }
    }

    override fun onInstantMessageStatus(prm: OnInstantMessageStatusParam) {
      val msgId = pendingMsgIds.poll() ?: return
      val ok = prm.code / 100 == 2
      onMain { modelListener?.onMessageSentState(msgId, ok, "${prm.code} ${prm.reason}") }
    }
  }

  /** FIFO of sent-message ids awaiting onInstantMessageStatus (statuses arrive in order). */
  private val pendingMsgIds = ConcurrentLinkedQueue<Int>()

  private fun buildAccountConfig(a: AccData): AccountConfig {
    // PJSIP silently skips registration (no onRegState callback at all) when
    // the account's transport can't produce a Contact — fail loudly instead.
    if (a.transport == AccData.SipTransport.Tls && !tlsAvailable)
      throw Exception("TLS transport is not available in this engine build")
    val cfg = AccountConfig()
    val transportSuffix = when (a.transport) {
      AccData.SipTransport.Tcp -> ";transport=tcp"
      AccData.SipTransport.Tls -> ";transport=tls"
      else -> ""
    }
    // Server/destination host:port for the registrar + outbound proxy.
    // IMPORTANT: a.port is the LOCAL transport bind port (the Dart layer
    // randomizes it when unset — see AccountsModel._generateRandomLocalPort);
    // it is NOT the server port and must never go into the registrar URI, or
    // pjsip dials a random closed port and times out. The server port comes
    // from an explicit "host:port" in sipServer, else the transport's standard
    // SIP port (5061 TLS / 5060 UDP/TCP).
    val stdPort = if (a.transport == AccData.SipTransport.Tls) 5061 else 5060
    val serverHasPort = a.sipServer.substringAfterLast(':', "").toIntOrNull() != null
    val hostPort = if (serverHasPort) a.sipServer else "${a.sipServer}:$stdPort"
    cfg.idUri = if (a.displName.isNullOrEmpty()) "sip:${a.sipExtension}@${a.sipServer}"
                else "\"${a.displName}\" <sip:${a.sipExtension}@${a.sipServer}>"
    cfg.regConfig.registrarUri = "sip:$hostPort$transportSuffix"
    cfg.regConfig.timeoutSec = a.expireTime.toLong()
    cfg.regConfig.retryIntervalSec = 30

    val authId = a.sipAuthId ?: a.sipExtension
    cfg.sipConfig.authCreds.add(AuthCredInfo("digest", "*", authId, 0, a.sipPassword))
    val proxy = a.sipProxy?.takeIf { it.isNotEmpty() }
    if (proxy != null) {
      cfg.sipConfig.proxies.add("sip:$proxy$transportSuffix;lr")
    } else {
      // No explicit proxy: route all requests (INVITE/MESSAGE/SUBSCRIBE) through
      // the registrar with the account's transport. Without this, a bare
      // "sip:ext@server" target resolves to UDP:5060 and providers that only
      // answer on the registered TLS/TCP connection let the INVITE time out (408).
      cfg.sipConfig.proxies.add("sip:$hostPort$transportSuffix;lr")
    }
    a.xContactUriParams.takeIf { it.isNotEmpty() }?.let { params ->
      cfg.sipConfig.contactUriParams =
        params.entries.joinToString("") { ";${it.key}=${it.value}" }
    }
    a.instanceId?.takeIf { it.isNotEmpty() }?.let {
      cfg.regConfig.contactParams = ";+sip.instance=\"<urn:uuid:$it>\""
    }
    a.xheaders.takeIf { it.isNotEmpty() }?.let { hdrs ->
      for ((n, v) in hdrs) {
        val h = SipHeader(); h.hName = n; h.hValue = v
        cfg.regConfig.headers.add(h)
      }
    }

    // Media encryption mode (computed early so ICE can key off it). When the
    // app doesn't specify, default by transport: a TLS-signaling account usually
    // expects SRTP. An explicit choice (incl. Disabled) is always honored.
    val secure = a.secureMedia
      ?: if (a.transport == AccData.SipTransport.Tls) AccData.SecureMediaMode.SdesSrtp
         else AccData.SecureMediaMode.Disabled

    // ICE: enable when the app asks OR when media is secure. Providers that
    // bridge WebRTC-style media offer ICE + DTLS-SRTP (a=ice-ufrag / a=candidate
    // with UDP/TLS/RTP/SAVP); without ICE our engine fires the DTLS ClientHello
    // to the raw c= address, which the peer gates behind ICE connectivity checks,
    // so the handshake never completes (PJMEDIA_SRTP_EKEYNOTREADY) -> no audio.
    // ICE is additive: pjsip only activates it when the peer actually offers
    // candidates, so plain-RTP/SDES-without-ICE calls are unaffected.
    cfg.natConfig.iceEnabled = a.iceEnabled || secure != AccData.SecureMediaMode.Disabled
    cfg.natConfig.contactRewriteUse = if (a.rewriteContactIp) 2 else 0
    if (a.keepAliveTime > 0) cfg.natConfig.udpKaIntervalSec = a.keepAliveTime.toLong()
    a.turnServer?.takeIf { it.isNotEmpty() }?.let {
      cfg.natConfig.turnEnabled = true
      cfg.natConfig.turnServer = it
      cfg.natConfig.turnUserName = a.turnUser ?: ""
      cfg.natConfig.turnPasswordType = 0
      cfg.natConfig.turnPassword = a.turnPassword ?: ""
    }
    // Note: pjsua2 STUN is endpoint-level; per-account stunServer is applied by
    // enabling SIP/media STUN use when configured (server set at init in P5).

    // srtpUse OPTIONAL (1), not MANDATORY (2): OPTIONAL still offers SRTP on
    // outgoing calls, but ACCEPTS a plain-RTP *incoming* call instead of failing
    // media init with PJMEDIA_SRTP_ESDPINTRANSPORT. Mandatory left mismatched
    // incoming calls half-initialized; a retransmitted INVITE then re-entered
    // pjsua_call_on_incoming on the corrupt slot and crashed (SIGSEGV).
    cfg.mediaConfig.srtpUse = if (secure == AccData.SecureMediaMode.Disabled) 0 else 1
    // Offer crypto on outgoing even over a non-TLS-secured SDP so SRTP-requiring
    // servers still accept the offer.
    cfg.mediaConfig.srtpSecureSignaling = 0
    if (secure != AccData.SecureMediaMode.Disabled) {
      // Enable BOTH SDES (a=crypto, RTP/SAVP) and DTLS-SRTP (UDP/TLS/RTP/SAVP)
      // keying. Providers may send either; our outgoing uses SDES, but this
      // provider offers DTLS-SRTP on *incoming* calls. Without DTLS keying,
      // pjsip failed the incoming media transport (PJMEDIA_SRTP_ESDPINTRANSPORT)
      // and then crashed in pjsua_call_on_incoming. Both keyings are compiled
      // into the engine (OpenSSL DTLS present).
      val srtpOpt = SrtpOpt()
      val keyings = IntVector()
      keyings.add(pjmedia_srtp_keying_method.PJMEDIA_SRTP_KEYING_SDES)
      keyings.add(pjmedia_srtp_keying_method.PJMEDIA_SRTP_KEYING_DTLS_SRTP)
      srtpOpt.keyings = keyings
      cfg.mediaConfig.srtpOpt = srtpOpt
    }

    cfg.videoConfig.autoShowIncoming = true
    cfg.videoConfig.autoTransmitOutgoing = a.upgradeToVideo == AccData.UpgradeToVideoMode.SendRecv
    return cfg
  }

  private fun applyCodecPriorities(a: AccData) {
    val codecs = a.audioCodecs ?: return
    val epRef = ep ?: return
    // pjsua2 codec priorities are endpoint-wide; last added account wins.
    val idFor = mapOf(
      AccData.AudioCodec.PCMU to "PCMU/8000",
      AccData.AudioCodec.PCMA to "PCMA/8000",
      AccData.AudioCodec.G722 to "G722/16000",
      AccData.AudioCodec.ILBC to "iLBC/8000",
      AccData.AudioCodec.Opus to "opus/48000",   // built at P3
      AccData.AudioCodec.G729 to "G729/8000",    // built at P3 (license!)
    )
    try {
      for (ci in epRef.codecEnum2()) epRef.codecSetPriority(ci.codecId, 0)
      var prio: Short = 254
      for (c in codecs) {
        idFor[c]?.let {
          try { epRef.codecSetPriority(it, prio) ; prio-- } catch (_: Throwable) {}
        }
      }
      // Keep telephone-events for RFC2833 DTMF.
      try { epRef.codecSetPriority("telephone-event/8000", 200) } catch (_: Throwable) {}
    } catch (t: Throwable) { Log.w(TAG, "codec prio: $t") }
  }

  fun accountAdd(accData: AccData, outId: IdOutArg): Int {
    return try {
      exec {
        val acc = PjAccount(nextAccId, accData)
        acc.create(buildAccountConfig(accData))
        applyCodecPriorities(accData)
        accounts[acc.wireId] = acc
        outId.value = acc.wireId
        nextAccId++
        kErrorCodeEOK
      }
    } catch (t: Throwable) { lastErrText = t.message ?: "$t"; kErrorCode }
  }

  fun accountUpdate(accData: AccData, accId: Int): Int = run {
    val acc = accounts[accId] ?: throw Exception("Account $accId not found")
    acc.accData = accData
    acc.modify(buildAccountConfig(accData))
  }

  fun accountRegister(accId: Int, expireTime: Int): Int = run {
    val acc = accounts[accId] ?: throw Exception("Account $accId not found")
    acc.setRegistration(true)
  }

  fun accountUnregister(accId: Int): Int = run {
    val acc = accounts[accId] ?: throw Exception("Account $accId not found")
    acc.setRegistration(false)
  }

  fun accountDelete(accId: Int): Int = run {
    val acc = accounts.remove(accId) ?: throw Exception("Account $accId not found")
    acc.delete()
  }

  fun accountGenInstId(): String = UUID.randomUUID().toString()

  // ---------------------------------------------------------------- calls --

  private inner class PjCall(acc: PjAccount, callId: Int = -1) : Call(acc, callId) {
    val accWireId = acc.wireId
    // Wire callId exposed to Dart = pjsua callId + 1. The Dart layer uses 0 as
    // its "no call" sentinel (kEmptyCallId), but pjsua2 call ids are 0-based —
    // so id 0 must never reach Dart. Set at creation; used for all map keys and
    // events. See CallsModel.kEmptyCallId.
    var wireId: Int = -1
    var lastInviteMsg: String = ""
    var localHold = false
    var remoteHold = false
    var muted = false
    var videoActive = false
    var wasConnected = false
    var proceedingFired = false

    private fun holdState(): HoldState = when {
      localHold && remoteHold -> HoldState.LocalAndRemote
      localHold -> HoldState.Local
      remoteHold -> HoldState.Remote
      else -> HoldState.None
    }
    fun holdStateValue(): Int = holdState().value

    override fun onCallState(prm: OnCallStateParam) {
      val ci = try { info } catch (t: Throwable) { return }
      val id = wireId
      when (ci.state) {
        pjsip_inv_state.PJSIP_INV_STATE_EARLY -> {
          // 'Proceeding' is an OUTGOING-call state (a 1xx response came back).
          // On an incoming call, EARLY is us sending 180 Ringing — firing it
          // would clobber the Dart 'ringing' state and break the incoming UI.
          // Normally onCallTsxState already fired proceeding on the earlier
          // 100 Trying; this is the fallback when no 100 preceded the 180/183.
          if (ci.role == pjsip_role_e.PJSIP_ROLE_UAC && !proceedingFired) {
            proceedingFired = true
            val response = "${ci.lastStatusCode} ${ci.lastReason}"
            onMain { modelListener?.onCallProceeding(id, response) }
          }
        }
        pjsip_inv_state.PJSIP_INV_STATE_CONFIRMED -> {
          // Fire 'connected' only on the first CONFIRMED. A later re-INVITE /
          // session refresh keeps the call CONFIRMED and must not re-emit
          // onCallConnected (it resets the Dart call's start time / duration).
          if (!wasConnected) {
            wasConnected = true
            val from = ci.remoteUri; val to = ci.localUri
            val vid = videoActive
            onMain {
              serviceListener?.onRingerState(false)
              serviceListener?.onCallConnected(id, from, to, vid)
              modelListener?.onCallConnected(id, from, to, vid)
            }
          }
        }
        pjsip_inv_state.PJSIP_INV_STATE_DISCONNECTED -> {
          val code = ci.lastStatusCode
          calls.remove(id)
          recorders.remove(id)?.let { try { it.delete() } catch (_: Throwable) {} }
          renderers.remove(id)?.releaseSurface()
          if (switchedCallId == id) {
            // Hand focus to a still-active call (if any) so the UI keeps a
            // valid switchedCall; -1 when this was the last call.
            switchedCallId = calls.keys.firstOrNull() ?: -1
            if (switchedCallId != -1) {
              val next = switchedCallId
              onMain { modelListener?.onCallSwitched(next) }
            }
          }
          onMain {
            serviceListener?.onRingerState(false)
            serviceListener?.onCallTerminated(id, code)
            modelListener?.onCallTerminated(id, code)
          }
          // pjsua2 requires explicit delete of Call objects once finished.
          workerHandler.post { try { delete() } catch (_: Throwable) {} }
        }
        else -> {}
      }
    }

    // Fire 'proceeding' as soon as the FIRST provisional (1xx) response arrives
    // on the outgoing INVITE — typically a '100 Trying' one round-trip after we
    // send the INVITE. Waiting for PJSIP_INV_STATE_EARLY instead delays it until
    // a 180/183 (an early dialog), which only comes once the far end actually
    // rings — that can be seconds later. 100 Trying is the true "Proceeding".
    override fun onCallTsxState(prm: OnCallTsxStateParam) {
      if (proceedingFired) return
      val ci = try { info } catch (t: Throwable) { return }
      if (ci.role != pjsip_role_e.PJSIP_ROLE_UAC) return
      val tsx = try { prm.e.body.tsxState.tsx } catch (t: Throwable) { return }
      if (tsx.method != "INVITE") return
      val code = tsx.statusCode
      if (code < 100 || code >= 200) return
      proceedingFired = true
      val id = wireId
      val response = "$code ${tsx.statusText}"
      onMain { modelListener?.onCallProceeding(id, response) }
    }

    override fun onCallMediaState(prm: OnCallMediaStateParam) {
      val ci = try { info } catch (t: Throwable) { return }
      val id = wireId
      var holdChanged = false
      for (i in 0 until ci.media.size) {
        val mi = ci.media[i.toInt()]
        if (mi.type == pjmedia_type.PJMEDIA_TYPE_AUDIO) {
          when (mi.status) {
            pjsua_call_media_status.PJSUA_CALL_MEDIA_ACTIVE -> {
              if (remoteHold) { remoteHold = false; holdChanged = true }
              connectAudio(this, i.toInt())
            }
            pjsua_call_media_status.PJSUA_CALL_MEDIA_REMOTE_HOLD -> {
              if (!remoteHold) { remoteHold = true; holdChanged = true }
            }
            else -> {}
          }
        } else if (mi.type == pjmedia_type.PJMEDIA_TYPE_VIDEO &&
                   mi.status == pjsua_call_media_status.PJSUA_CALL_MEDIA_ACTIVE) {
          if (!videoActive) {
            videoActive = true
            onMain { modelListener?.onCallVideoUpgraded(id, true) }
          }
          attachRenderer(id, mi.videoIncomingWindowId)
        }
      }
      if (holdChanged) {
        val hs = holdState()
        onMain { modelListener?.onCallHeld(id, hs) }
      }
    }

    override fun onDtmfDigit(prm: OnDtmfDigitParam) {
      val digit = prm.digit ?: return
      val tone = when (val c = digit.firstOrNull() ?: return) {
        in '0'..'9' -> c - '0'
        '*' -> 10; '#' -> 11
        in 'A'..'D' -> 12 + (c - 'A')
        else -> return
      }
      onMain { modelListener?.onCallDtmfReceived(wireId, tone) }
    }

    override fun onCallTransferStatus(prm: OnCallTransferStatusParam) {
      val code = prm.statusCode
      onMain { modelListener?.onCallTransferred(wireId, code) }
    }
  }

  /** Connects a call's active audio media to mic/speaker (honoring mute/switch). */
  private fun connectAudio(call: PjCall, mediaIdx: Int) {
    try {
      val aud = AudioMedia.typecastFromMedia(call.getMedia(mediaIdx.toLong())) ?: return
      val adm: AudDevManager = ep!!.audDevManager()
      aud.startTransmit(adm.playbackDevMedia)
      if (!call.muted) adm.captureDevMedia.startTransmit(aud)
    } catch (t: Throwable) { Log.w(TAG, "connectAudio: $t") }
  }

  private fun activeAudioMedia(call: Call): AudioMedia? {
    return try {
      val ci = call.info
      for (i in 0 until ci.media.size) {
        val mi = ci.media[i.toInt()]
        if (mi.type == pjmedia_type.PJMEDIA_TYPE_AUDIO &&
            (mi.status == pjsua_call_media_status.PJSUA_CALL_MEDIA_ACTIVE ||
             mi.status == pjsua_call_media_status.PJSUA_CALL_MEDIA_REMOTE_HOLD)) {
          return AudioMedia.typecastFromMedia(call.getMedia(i.toLong()))
        }
      }
      null
    } catch (t: Throwable) { null }
  }

  fun callInvite(dest: DestData, outId: IdOutArg): Int {
    return try {
      exec {
        val acc = accounts[dest.accId] ?: accounts.values.firstOrNull()
          ?: throw Exception("No account for call")
        val call = PjCall(acc)
        val prm = CallOpParam(true)
        prm.opt.audioCount = 1
        prm.opt.videoCount = if (dest.withVideo) 1L else 0L
        for ((n, v) in dest.xheaders) {
          val h = SipHeader(); h.hName = n; h.hValue = v
          prm.txOption.headers.add(h)
        }
        val server = acc.accData.sipServer
        val uri = if (dest.toExt.contains("@")) "sip:${dest.toExt}" else "sip:${dest.toExt}@$server"
        call.makeCall(uri, prm)
        call.wireId = call.info.id + 1
        val id = call.wireId
        calls[id] = call
        outId.value = id
        // Match the previous engine: a newly created outgoing call becomes the
        // active ("switched") call, so the Dart layer's switchedCall() resolves.
        switchedCallId = id
        onMain { modelListener?.onCallSwitched(id) }
        kErrorCodeEOK
      }
    } catch (t: Throwable) { lastErrText = t.message ?: "$t"; kErrorCode }
  }

  fun callReject(callId: Int, statusCode: Int = 486): Int = run {
    val call = calls[callId] ?: throw Exception("Call $callId not found")
    val prm = CallOpParam()
    prm.statusCode = statusCode
    call.hangup(prm)
  }

  fun callAccept(callId: Int, withVideo: Boolean): Int = run {
    val call = calls[callId] ?: throw Exception("Call $callId not found")
    val prm = CallOpParam()
    prm.statusCode = pjsip_status_code.PJSIP_SC_OK
    prm.opt.audioCount = 1
    prm.opt.videoCount = if (withVideo) 1L else 0L
    call.answer(prm)
  }

  fun callBye(callId: Int): Int = run {
    val call = calls[callId] ?: throw Exception("Call $callId not found")
    call.hangup(CallOpParam())
  }

  fun callHold(callId: Int): Int = run {
    val call = calls[callId] ?: throw Exception("Call $callId not found")
    if (!call.localHold) {
      call.setHold(CallOpParam())
      call.localHold = true
    } else {
      val prm = CallOpParam(true)
      prm.opt.flag = prm.opt.flag or pjsua_call_flag.PJSUA_CALL_UNHOLD.toLong()
      call.reinvite(prm)
      call.localHold = false
    }
    val hs = HoldState.fromInt(call.holdStateValue())
    onMain { modelListener?.onCallHeld(callId, hs) }
  }

  fun callGetHoldState(callId: Int, out: IdOutArg): Int = run {
    val call = calls[callId] ?: throw Exception("Call $callId not found")
    out.value = call.holdStateValue()
  }

  fun callGetSipHeader(callId: Int, hdrName: String): String {
    val call = calls[callId] ?: return ""
    val msg = call.lastInviteMsg
    val prefix = "$hdrName:"
    for (line in msg.lineSequence()) {
      if (line.startsWith(prefix, ignoreCase = true)) return line.substring(prefix.length).trim()
    }
    return ""
  }

  fun callGetStats(callId: Int): String {
    return try { exec { calls[callId]?.dump(true, "  ") ?: "" } }
    catch (t: Throwable) { "" }
  }

  fun callMuteMic(callId: Int, mute: Boolean): Int = run {
    val call = calls[callId] ?: throw Exception("Call $callId not found")
    val aud = activeAudioMedia(call) ?: throw Exception("No active audio")
    val cap = ep!!.audDevManager().captureDevMedia
    if (mute) cap.stopTransmit(aud) else cap.startTransmit(aud)
    call.muted = mute
  }

  fun callMuteCam(callId: Int, mute: Boolean): Int = run {
    val call = calls[callId] ?: throw Exception("Call $callId not found")
    val op = if (mute) pjsua_call_vid_strm_op.PJSUA_CALL_VID_STRM_STOP_TRANSMIT
             else pjsua_call_vid_strm_op.PJSUA_CALL_VID_STRM_START_TRANSMIT
    call.vidSetStream(op, CallVidSetStreamParam())
  }

  fun callSendDtmf(callId: Int, dtmfs: String, durationMs: Int, interToneGapMs: Int, method: DtmfMethod): Int = run {
    val call = calls[callId] ?: throw Exception("Call $callId not found")
    val prm = CallSendDtmfParam()
    prm.digits = dtmfs
    prm.duration = durationMs.toLong()
    prm.method = if (method == DtmfMethod.Info) pjsua_dtmf_method.PJSUA_DTMF_METHOD_SIP_INFO
                 else pjsua_dtmf_method.PJSUA_DTMF_METHOD_RFC2833
    call.sendDtmf(prm)
  }

  // -------------------------------------------------------- players/tones --

  private inner class PjPlayer(val id: Int, val callId: Int) : AudioMediaPlayer() {
    override fun onEof2() {
      players.remove(id)
      onMain { modelListener?.onPlayerState(id, PlayerState.Stopped) }
      workerHandler.post { try { delete() } catch (_: Throwable) {} }
    }
  }

  fun callPlayFile(callId: Int, path: String, loop: Boolean, outId: IdOutArg): Int {
    return try {
      exec {
        val call = calls[callId] ?: throw Exception("Call $callId not found")
        val aud = activeAudioMedia(call) ?: throw Exception("No active audio")
        val player = PjPlayer(nextPlayerId, callId)
        // 1 == PJMEDIA_FILE_NO_LOOP
        player.createPlayer(path, if (loop) 0L else 1L)
        player.startTransmit(aud)
        players[player.id] = player
        outId.value = player.id
        nextPlayerId++
        onMain { modelListener?.onPlayerState(player.id, PlayerState.Started) }
        kErrorCodeEOK
      }
    } catch (t: Throwable) { lastErrText = t.message ?: "$t"; kErrorCode }
  }

  fun callStopPlayFile(playerId: Int): Int = run {
    val player = players.remove(playerId) ?: throw Exception("Player $playerId not found")
    try { player.delete() } catch (_: Throwable) {}
    onMain { modelListener?.onPlayerState(playerId, PlayerState.Stopped) }
  }

  fun callPlayTone(callId: Int, toneType: String, durationMs: Int, outId: IdOutArg): Int {
    return try {
      exec {
        val call = calls[callId] ?: throw Exception("Call $callId not found")
        val aud = activeAudioMedia(call) ?: throw Exception("No active audio")
        val tg = ToneGenerator()
        tg.createToneGenerator()
        val digits = ToneDigitVector()
        for (c in toneType) {
          val d = ToneDigit()
          d.digit = c
          d.on_msec = durationMs.toShort()
          d.off_msec = 100
          digits.add(d)
        }
        tg.playDigits(digits)
        tg.startTransmit(aud)
        // Tone generators are treated as players so StopPlayFile can stop them.
        val player = PjPlayer(nextPlayerId, callId)
        players[player.id] = player
        outId.value = nextPlayerId
        nextPlayerId++
        kErrorCodeEOK
      }
    } catch (t: Throwable) { lastErrText = t.message ?: "$t"; kErrorCode }
  }

  fun callRecordFile(callId: Int, path: String): Int = run {
    val call = calls[callId] ?: throw Exception("Call $callId not found")
    val aud = activeAudioMedia(call) ?: throw Exception("No active audio")
    val rec = AudioMediaRecorder()
    rec.createRecorder(path)
    aud.startTransmit(rec)
    if (iniData?.recordStereo != true) {
      try { ep!!.audDevManager().captureDevMedia.startTransmit(rec) } catch (_: Throwable) {}
    }
    recorders[callId] = rec
  }

  fun callStopRecordFile(callId: Int): Int = run {
    val rec = recorders.remove(callId) ?: throw Exception("No recorder for call $callId")
    try { rec.delete() } catch (_: Throwable) {}
  }

  // ------------------------------------------------------------ transfers --

  fun callTransferBlind(callId: Int, toExt: String): Int = run {
    val call = calls[callId] ?: throw Exception("Call $callId not found")
    val server = accounts[call.accWireId]?.accData?.sipServer ?: ""
    val uri = if (toExt.contains("@")) "sip:$toExt" else "sip:$toExt@$server"
    call.xfer(uri, CallOpParam())
  }

  fun callTransferAttended(fromCallId: Int, toCallId: Int): Int = run {
    val from = calls[fromCallId] ?: throw Exception("Call $fromCallId not found")
    val to = calls[toCallId] ?: throw Exception("Call $toCallId not found")
    from.xferReplaces(to, CallOpParam())
  }

  // ---------------------------------------------------------------- video --

  fun callUpgradeToVideo(callId: Int): Int = run {
    val call = calls[callId] ?: throw Exception("Call $callId not found")
    val prm = CallOpParam(true)
    prm.opt.audioCount = 1
    prm.opt.videoCount = 1
    call.reinvite(prm)
  }

  fun callAcceptVideoUpgrade(callId: Int, withVideo: Boolean): Int = run {
    val call = calls[callId] ?: throw Exception("Call $callId not found")
    val prm = CallOpParam(true)
    prm.opt.audioCount = 1
    prm.opt.videoCount = if (withVideo) 1L else 0L
    call.reinvite(prm)
  }

  fun callSetVideoRenderer(callId: Int, renderer: IVideoRenderer?): Int {
    if (renderer == null) { renderers.remove(callId)?.releaseSurface(); return kErrorCodeEOK }
    renderers[callId] = renderer
    // If the call already has active incoming video, attach right away.
    return run {
      val call = calls[callId] ?: return@run
      val ci = call.info
      for (i in 0 until ci.media.size) {
        val mi = ci.media[i.toInt()]
        if (mi.type == pjmedia_type.PJMEDIA_TYPE_VIDEO &&
            mi.status == pjsua_call_media_status.PJSUA_CALL_MEDIA_ACTIVE) {
          attachRenderer(callId, mi.videoIncomingWindowId)
        }
      }
    }
  }

  private fun attachRenderer(callId: Int, windowId: Int) {
    val renderer = renderers[callId] ?: return
    if (windowId < 0) return
    try {
      val win = VideoWindow(windowId)
      val info = win.info
      val w = info.size.w.toInt(); val h = info.size.h.toInt()
      val surface = renderer.acquireSurface(w, h) ?: return
      val handle = VideoWindowHandle()
      handle.handle.setWindow(surface)
      win.setWindow(handle)
      renderer.onVideoSize(w, h, 0)
    } catch (t: Throwable) { Log.w(TAG, "attachRenderer: $t") }
  }

  fun callStopRingtone() {
    onMain { serviceListener?.onRingerState(false) }
  }

  // ---------------------------------------------------------------- mixer --

  fun mixerSwitchToCall(callId: Int): Int = run {
    val target = calls[callId] ?: throw Exception("Call $callId not found")
    val adm = ep!!.audDevManager()
    for ((id, call) in calls) {
      val aud = activeAudioMedia(call) ?: continue
      if (id == callId) {
        aud.startTransmit(adm.playbackDevMedia)
        if (!call.muted) adm.captureDevMedia.startTransmit(aud)
      } else {
        try { aud.stopTransmit(adm.playbackDevMedia) } catch (_: Throwable) {}
        try { adm.captureDevMedia.stopTransmit(aud) } catch (_: Throwable) {}
      }
    }
    switchedCallId = callId
    onMain { modelListener?.onCallSwitched(callId) }
  }

  fun mixerMakeConference(): Int = run {
    val adm = ep!!.audDevManager()
    val medias = calls.values.mapNotNull { c -> activeAudioMedia(c)?.also {
      it.startTransmit(adm.playbackDevMedia)
      if (!c.muted) adm.captureDevMedia.startTransmit(it)
    } }
    // Full mesh so every participant hears every other one.
    for (a in medias) for (b in medias) {
      if (a !== b) try { a.startTransmit(b) } catch (_: Throwable) {}
    }
    switchedCallId = -1
  }

  // ------------------------------------------------------------- messages --

  fun messageSend(msg: MsgData, outId: IdOutArg): Int {
    return try {
      exec {
        val acc = accounts[msg.accId] ?: accounts.values.firstOrNull()
          ?: throw Exception("No account for message")
        val server = acc.accData.sipServer
        val uri = if (msg.toExt.contains("@")) "sip:${msg.toExt}" else "sip:${msg.toExt}@$server"
        val bCfg = BuddyConfig()
        bCfg.uri = uri
        bCfg.subscribe = false
        val buddy = Buddy()
        buddy.create(acc, bCfg)
        val prm = SendInstantMessageParam()
        prm.content = msg.body
        msg.contentType?.let { prm.contentType = it }
        buddy.sendInstantMessage(prm)
        val msgId = nextMsgId++
        pendingMsgIds.add(msgId)
        outId.value = msgId
        // Buddy object can be released once the request is queued; pjsip keeps
        // the transaction alive and reports through Account.onInstantMessageStatus.
        workerHandler.post { try { buddy.delete() } catch (_: Throwable) {} }
        kErrorCodeEOK
      }
    } catch (t: Throwable) { lastErrText = t.message ?: "$t"; kErrorCode }
  }

  // -------------------------------------------------------- subscriptions --

  private inner class PjBuddy(val subscrId: Int) : Buddy() {
    var created = false
    override fun onBuddyState() {
      val note = try { info.presStatus.note } catch (t: Throwable) { "" }
      val state = if (created) SubscrData.SubscrState.Updated else SubscrData.SubscrState.Created
      created = true
      onMain { modelListener?.onSubscriptionState(subscrId, state, note) }
    }
  }

  fun subscrCreate(data: SubscrData, outId: IdOutArg): Int {
    // NOTE: pjsua2 exposes presence (SUBSCRIBE Event: presence) only. BLF
    // (Event: dialog) needs a custom SWIG extension — tracked for P6.
    return try {
      exec {
        val acc = accounts[data.accId] ?: accounts.values.firstOrNull()
          ?: throw Exception("No account for subscription")
        val server = acc.accData.sipServer
        val uri = if (data.toExt.contains("@")) "sip:${data.toExt}" else "sip:${data.toExt}@$server"
        val bCfg = BuddyConfig()
        bCfg.uri = uri
        bCfg.subscribe = true
        val buddy = PjBuddy(nextSubscrId)
        buddy.create(acc, bCfg)
        buddies[buddy.subscrId] = buddy
        outId.value = buddy.subscrId
        nextSubscrId++
        kErrorCodeEOK
      }
    } catch (t: Throwable) { lastErrText = t.message ?: "$t"; kErrorCode }
  }

  fun subscrDestroy(subscrId: Int): Int = run {
    val buddy = buddies.remove(subscrId) ?: throw Exception("Subscription $subscrId not found")
    val id = buddy.subscrId
    try { buddy.subscribePresence(false) } catch (_: Throwable) {}
    buddy.delete()
    onMain { modelListener?.onSubscriptionState(id, SubscrData.SubscrState.Destroyed, "") }
  }

  // -------------------------------------------------------------- devices --

  private fun audioManager() = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

  private fun availableAudioDevices(): List<AudioDevice> {
    val am = audioManager()
    val list = mutableListOf(AudioDevice.Earpiece, AudioDevice.Speakerphone)
    if (Build.VERSION.SDK_INT >= 23) {
      val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
      if (devices.any { it.type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                        it.type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES })
        list.add(AudioDevice.WiredHeadset)
      if (devices.any { it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO })
        list.add(AudioDevice.Bluetooth)
    }
    return list
  }

  fun dvcGetAudioDevices(): Int = availableAudioDevices().size

  fun dvcGetAudioDevice(index: Int): AudioDevice =
    availableAudioDevices().getOrElse(index) { AudioDevice.None }

  fun dvcGetSelAudioDevice(): AudioDevice = selAudioDevice

  fun dvcSetAudioDevice(device: AudioDevice) {
    val am = audioManager()
    am.mode = AudioManager.MODE_IN_COMMUNICATION
    when (device) {
      AudioDevice.Speakerphone -> { stopBluetooth(am); am.isSpeakerphoneOn = true }
      AudioDevice.Bluetooth -> { am.isSpeakerphoneOn = false; am.startBluetoothSco(); am.isBluetoothScoOn = true }
      else -> { stopBluetooth(am); am.isSpeakerphoneOn = false }
    }
    selAudioDevice = device
    onMain { modelListener?.onDevicesAudioChanged() }
  }

  private fun stopBluetooth(am: AudioManager) {
    if (am.isBluetoothScoOn) { am.stopBluetoothSco(); am.isBluetoothScoOn = false }
  }

  fun dvcSwitchCamera() {
    // Front/back switch lands with P4 (video capture); no-op until then.
    moduleWriteLog("dvcSwitchCamera: video capture arrives at P4")
  }

  fun dvcSetVideoParams(v: VideoData): Int {
    // Applied to VidDevManager/codec params at P4; accepted (not yet applied).
    moduleWriteLog("dvcSetVideoParams(${v.width}x${v.height}@${v.framerateFps}) deferred to P4")
    return kErrorCodeEOK
  }

  // -------------------------------------------------------------- network --

  private var netCallback: ConnectivityManager.NetworkCallback? = null

  private fun startNetworkMonitor() {
    if (Build.VERSION.SDK_INT < 24 || netCallback != null) return
    try {
      val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
      val cb = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
          val wasLost = netLost
          netLost = false
          if (wasLost) {
            try { exec { ep?.handleIpChange(IpChangeParam()) } } catch (t: Throwable) { Log.w(TAG, "ipChange: $t") }
            onMain { modelListener?.onNetworkState("default", NetworkState.Restored) }
          }
        }
        override fun onLost(network: Network) {
          netLost = true
          onMain { modelListener?.onNetworkState("default", NetworkState.Lost) }
        }
      }
      cm.registerDefaultNetworkCallback(cb)
      netCallback = cb
    } catch (t: Throwable) { Log.w(TAG, "network monitor: $t") }
  }

  private fun stopNetworkMonitor() {
    val cb = netCallback ?: return
    netCallback = null
    try {
      val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
      cm.unregisterNetworkCallback(cb)
    } catch (_: Throwable) {}
  }
}
