import Flutter
import UIKit
import CallKit
import PushKit
#if canImport(SipCoreModule)
import SipCoreModule
#endif

///////////////////////////////////////////////////////////////////////////////////////
//FlutterVideoRenderer

class FlutterVideoRenderer : NSObject, SipCoreVideoRendererDelegate, FlutterTexture, FlutterStreamHandler {
    struct EventData {
        var width: Int32 = 0
        var height: Int32 = 0
        var rotation: VideoFrameRotation = .rotation_0
    }
    var _eventData = EventData()
    var _textureRegistry : FlutterTextureRegistry
    var _eventChannel : FlutterEventChannel?
    var _eventSink : FlutterEventSink?
    var _pixelBuffer : CVPixelBuffer? = nil
    var _pixelBufferWidth = 0
    var _pixelBufferHeight = 0
    var _textureId : Int64 = 0
    
    static let kInvalidCallCallId : Int32 = -1
    public var srcCallId : Int32 = kInvalidCallCallId
            
    init(textureRegistry:FlutterTextureRegistry) {
        self._textureRegistry = textureRegistry
    }
    
    deinit {
        dispose()
    }

    public func registerTextureAndCreateChannel(binMessenger : FlutterBinaryMessenger) -> Int64 {
        _textureId = _textureRegistry.register(self)

        _eventChannel = FlutterEventChannel(name:"SipConnect/Texture\(_textureId)", binaryMessenger:binMessenger)
        _eventChannel?.setStreamHandler(self)
        return _textureId
    }

    //Releases the Flutter texture and tears down the per-texture event channel.
    //Safe to call more than once (dispose handler + deinit).
    public func dispose() {
        _eventChannel?.setStreamHandler(nil)
        _eventChannel = nil
        _eventSink = nil
        if(_textureId != 0) {
            _textureRegistry.unregisterTexture(_textureId)
            _textureId = 0
        }
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self._eventSink = events
        return nil
    }
       
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self._eventSink = nil
        return nil
    }
    
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
      if (_pixelBuffer != nil) {
        return Unmanaged<CVPixelBuffer>.passRetained(_pixelBuffer!)
      }
      return nil
    }

    func copyFrameToCVPixelBuffer(frame : SipCoreVideoFrame) {
        if (_pixelBufferWidth != frame.width() || _pixelBufferHeight != frame.height()) {
            _pixelBufferWidth  = Int(frame.width())
            _pixelBufferHeight = Int(frame.height())
            print("sipconnect: Got new video frame \(_pixelBufferWidth)x\(_pixelBufferHeight) \(frame.rotation()) textureId:\(_textureId)")
            
            let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                         kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
                         kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue] as CFDictionary
            
            CVPixelBufferCreate(nil, _pixelBufferWidth, _pixelBufferHeight,
                                kCVPixelFormatType_32BGRA, attrs, &_pixelBuffer)
        }
        
        CVPixelBufferLockBaseAddress(_pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(_pixelBuffer!)
        if let baseAddress = CVPixelBufferGetBaseAddress(_pixelBuffer!) {
            let buf = baseAddress.assumingMemoryBound(to: UInt8.self)
            frame.convert(toARGB: .ARGB, dstBuffer: buf, 
                          dstWidth: frame.width(), dstHeight: frame.height(),
                          dstStride: Int32(bytesPerRow))
        }
        CVPixelBufferUnlockBaseAddress(_pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
    }
        
    public func onFrame(_ videoFrame : SipCoreVideoFrame) {
        copyFrameToCVPixelBuffer(frame:videoFrame)
        sendEvent(frame:videoFrame)
        DispatchQueue.main.async {
            self._textureRegistry.textureFrameAvailable(self._textureId)
        }
    }
    
    func degrees(_ rotation : VideoFrameRotation) -> Int32 {
        switch(rotation) {
            case VideoFrameRotation.rotation_90: return 90
            case VideoFrameRotation.rotation_180: return 180
            case VideoFrameRotation.rotation_270: return 270
            default: return 0
        }
    }

    func sendEvent(frame : SipCoreVideoFrame) {
        if(_eventData.rotation != frame.rotation()) {
            _eventData.rotation = frame.rotation()
            if(_eventSink != nil) {
                var argsMap = [String:Any]()
                argsMap["event"]  = "didTextureChangeRotation"
                argsMap["id"]     = _textureId
                argsMap["rotation"]  = degrees(_eventData.rotation)
                DispatchQueue.main.async {
                    self._eventSink!(argsMap)
                }
            }
        }
        
        if(_eventData.width != frame.width() || _eventData.height != frame.height()) {
            _eventData.width = frame.width()
            _eventData.height = frame.height()
            if(_eventSink != nil) {
                var argsMap = [String:Any]()
                argsMap["event"]  = "didTextureChangeVideoSize"
                argsMap["id"]     = _textureId
                argsMap["width"]  = _eventData.width
                argsMap["height"] = _eventData.height
                DispatchQueue.main.async {
                    self._eventSink!(argsMap)
                }
            }
        }
    }//sendEvent
    
}//FlutterVideoRenderer

