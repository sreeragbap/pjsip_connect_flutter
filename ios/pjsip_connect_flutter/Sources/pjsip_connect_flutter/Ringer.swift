import Flutter
import UIKit
import CallKit
import PushKit
#if canImport(SipCoreModule)
import SipCoreModule
#endif

///////////////////////////////////////////////////////////////////////////////////////////////////
///Ringer - plays ringtone when CallKit disabled

class Ringer {
    private var player: AVAudioPlayer?
    private var ringtonePath: String = ""
    
    public func setRingTonePath(_ path : String) {
        ringtonePath = path
    }

    deinit {
        if (player?.isPlaying == true) {
            player!.stop()
            player = nil
        }
    }

    private func enableSpeaker(_ enabled: Bool) {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        var options = session.categoryOptions

        if enabled {
            options.insert(AVAudioSession.CategoryOptions.defaultToSpeaker)
        } else {
            options.remove(AVAudioSession.CategoryOptions.defaultToSpeaker)
        }
        do {
            try session.setCategory(AVAudioSession.Category.playAndRecord, options: options)
        } catch {
            print("sipconnect: Ringer: Can't start ringer: error \(error)")
        }
        #endif
    }

    @discardableResult
    func play() -> Bool {
        if player == nil {
            let url = URL(fileURLWithPath:ringtonePath)
            player = try? AVAudioPlayer(contentsOf: url)
        }
        if player != nil {
            player?.numberOfLoops = -1
            enableSpeaker(true)
            player?.play()
            return true
        }
        return false
    }

    @discardableResult
    func stop() -> Bool {
        if (player != nil) && player!.isPlaying {
            player?.stop()
            enableSpeaker(false)
        }
        return true
    }
    
}//Ringer

