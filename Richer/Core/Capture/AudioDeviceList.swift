import AVFoundation
import CoreAudio

enum AudioDeviceList {
    struct Device: Identifiable, Hashable, Sendable {
        /// Matches both `AVCaptureDevice.uniqueID` and CoreAudio's `kAudioDevicePropertyDeviceUID`,
        /// which use the same identifier scheme on macOS.
        let uniqueID: String
        let name: String
        var id: String { uniqueID }
    }

    /// All audio input devices currently visible to the system. Order is whatever the OS
    /// returns (typically built-in first, then external in connection order).
    static func availableMicrophones() -> [Device] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.map { Device(uniqueID: $0.uniqueID, name: $0.localizedName) }
    }

    /// Convert an `AVCaptureDevice.uniqueID` to CoreAudio's `AudioDeviceID` so we can pin
    /// AVAudioEngine's input node to a specific device. Returns nil if the device is no
    /// longer present (e.g., a USB mic was unplugged between the user's pick and `start()`).
    static func audioDeviceID(for uniqueID: String) -> AudioDeviceID? {
        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &dataSize
        ) == noErr else { return nil }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return nil }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return nil }

        for deviceID in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uid: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = AudioObjectGetPropertyData(
                deviceID, &uidAddress, 0, nil, &uidSize, &uid
            )
            if status == noErr,
               let cfString = uid?.takeRetainedValue() as String?,
               cfString == uniqueID {
                return deviceID
            }
        }
        return nil
    }
}
