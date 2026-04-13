import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
}

func listAudioDevices() -> [AudioDevice] {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress, 0, nil, &dataSize
    )
    guard status == noErr else { return [] }

    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
    status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress, 0, nil, &dataSize, &deviceIDs
    )
    guard status == noErr else { return [] }

    return deviceIDs.compactMap { deviceID -> AudioDevice? in
        // Get device name
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameRef: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let nameStatus = AudioObjectGetPropertyData(
            deviceID, &nameAddress, 0, nil, &nameSize, &nameRef
        )
        guard nameStatus == noErr, let name = nameRef?.takeUnretainedValue() else { return nil }

        let hasInput = channelCount(deviceID: deviceID, scope: kAudioObjectPropertyScopeInput) > 0
        let hasOutput = channelCount(deviceID: deviceID, scope: kAudioObjectPropertyScopeOutput) > 0

        guard hasInput || hasOutput else { return nil }

        return AudioDevice(
            id: deviceID,
            name: name as String,
            hasInput: hasInput,
            hasOutput: hasOutput
        )
    }
}

private func channelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
    guard status == noErr, dataSize > 0 else { return 0 }

    let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
    defer { bufferListPointer.deallocate() }
    let getStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer)
    guard getStatus == noErr else { return 0 }

    let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
    return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
}
