import Foundation
import CoreMediaIO
import CoreAudio

class MeetingDetector: ObservableObject {
    @Published var isInMeeting: Bool = false
    @Published var meetingSource: String? = nil

    func check() {
        let cameraActive = checkCamera()
        let micActive = checkMicrophone()

        if cameraActive {
            isInMeeting = true
            meetingSource = "Camera in use"
        } else if micActive {
            isInMeeting = true
            meetingSource = "Microphone in use"
        } else {
            isInMeeting = false
            meetingSource = nil
        }
    }

    // MARK: - Camera Detection via CoreMediaIO

    private func checkCamera() -> Bool {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        var result = CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )

        guard result == kCMIOHardwareNoError, dataSize > 0 else { return false }

        let deviceCount = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        var devices = [CMIODeviceID](repeating: 0, count: deviceCount)
        var dataUsed: UInt32 = 0

        result = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0, nil,
            dataSize,
            &dataUsed,
            &devices
        )

        guard result == kCMIOHardwareNoError else { return false }

        for device in devices {
            if isDeviceRunning(device) {
                return true
            }
        }

        return false
    }

    private func isDeviceRunning(_ deviceID: CMIODeviceID) -> Bool {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var isRunning: UInt32 = 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)
        var dataUsed: UInt32 = 0

        let result = CMIOObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            dataSize,
            &dataUsed,
            &isRunning
        )

        guard result == kCMIOHardwareNoError else { return false }
        return isRunning != 0
    }

    // MARK: - Microphone Detection via CoreAudio

    private func checkMicrophone() -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )

        guard result == kAudioHardwareNoError, dataSize > 0 else { return false }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)

        result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &devices
        )

        guard result == kAudioHardwareNoError else { return false }

        for device in devices {
            if isInputDevice(device) && isAudioDeviceRunning(device) {
                return true
            }
        }

        return false
    }

    private func isInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let result = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize
        )

        guard result == kAudioHardwareNoError, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        var size = dataSize
        let result2 = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &size,
            bufferListPointer
        )

        guard result2 == kAudioHardwareNoError else { return false }

        let bufferList = bufferListPointer.pointee
        return bufferList.mNumberBuffers > 0
    }

    private func isAudioDeviceRunning(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let result = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &isRunning
        )

        guard result == kAudioHardwareNoError else { return false }
        return isRunning != 0
    }
}
