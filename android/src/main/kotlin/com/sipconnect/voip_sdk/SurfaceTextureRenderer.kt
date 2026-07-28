@file:Suppress("SpellCheckingInspection", "UNUSED_PARAMETER")
package com.sipconnect.voip_sdk

import android.view.Surface
import com.sipconnect.core.IVideoRenderer
import io.flutter.view.TextureRegistry.SurfaceProducer

/** Events the Flutter side listens to on the per-texture EventChannel. */
interface VideoRendererEvents {
  fun onFrameResolutionChanged(videoWidth: Int, videoHeight: Int, rotation: Int)
  fun onFirstFrameRendered()
}

/**
 * Bridges the engine's decoded video to a Flutter texture.
 *
 * Keeps the Flutter-texture plumbing of the original (webrtc-based)
 * renderer, but the frame source is now the PJSIP video window, which renders
 * directly into the SurfaceProducer's Surface (no GL pipeline of our own).
 */
class SurfaceTextureRenderer(name: String?) : IVideoRenderer {
  private var rendererEvents: VideoRendererEvents? = null
  private var producer: SurfaceProducer? = null
  private var surface: Surface? = null
  private var firstFrameReported = false

  fun init(rendererEvents: VideoRendererEvents?) {
    this.rendererEvents = rendererEvents
  }

  fun surfaceCreated(producer: SurfaceProducer) {
    this.producer = producer
    producer.setCallback(object : SurfaceProducer.Callback {
      override fun onSurfaceAvailable() {}
      override fun onSurfaceCleanup() { surfaceDestroyed() }
    })
  }

  fun surfaceDestroyed() {
    surface = null
  }

  fun release() {
    surface = null
    producer = null
    rendererEvents = null
  }

  // IVideoRenderer — called by SipCore when incoming video becomes active.

  override fun acquireSurface(width: Int, height: Int): Surface? {
    val p = producer ?: return null
    if (width > 0 && height > 0) p.setSize(width, height)
    surface = p.surface
    if (!firstFrameReported) {
      firstFrameReported = true
      rendererEvents?.onFirstFrameRendered()
    }
    return surface
  }

  override fun onVideoSize(width: Int, height: Int, rotation: Int) {
    rendererEvents?.onFrameResolutionChanged(width, height, rotation)
  }

  override fun releaseSurface() {
    surface = null
  }
}
