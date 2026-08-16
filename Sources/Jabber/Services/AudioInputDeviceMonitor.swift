@preconcurrency import CoreAudio
import Foundation
import os

struct AudioInputDevice: Identifiable, Equatable, Sendable {
    let deviceID: AudioDeviceID
    let uid: String
    let name: String

    var id: String {
        uid
    }
}

/// Tracks the macOS input-device catalog and the current system default.
@MainActor
final class AudioInputDeviceMonitor {
    static let shared = AudioInputDeviceMonitor()

    var onDefaultInputDeviceChange: (() -> Void)?
    var onDeviceListChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?

    private(set) var devices: [AudioInputDevice] = []
    private(set) var defaultDeviceID: AudioDeviceID?

    var defaultInputDevice: AudioInputDevice? {
        devices.first { $0.deviceID == defaultDeviceID }
    }

    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "AudioInputDeviceMonitor")
    nonisolated(unsafe) private var defaultInputListener: AudioObjectPropertyListenerBlock?
    nonisolated(unsafe) private var deviceListListener: AudioObjectPropertyListenerBlock?

    private init() {
        registerListeners()
        refreshDevices(notify: false)
        refreshDefaultInput(notify: false)
    }

    deinit {
        removeListeners()
    }

    func deviceID(forUID uid: String) -> AudioDeviceID? {
        Self.deviceID(forUID: uid, in: devices)
    }

    nonisolated static func deviceID(
        forUID uid: String,
        in devices: [AudioInputDevice]
    ) -> AudioDeviceID? {
        devices.first { $0.uid == uid }?.deviceID
    }

    func selectionDidChange() {
        onSelectionChange?()
    }

    nonisolated private static var defaultInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    nonisolated private static var deviceListAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func registerListeners() {
        var defaultAddress = Self.defaultInputAddress
        let defaultListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDefaultInput(notify: true)
            }
        }
        let defaultStatus = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            .main,
            defaultListener
        )
        if defaultStatus == noErr {
            defaultInputListener = defaultListener
        } else {
            logger.error("Could not observe the default input device: OSStatus \(defaultStatus)")
        }

        var listAddress = Self.deviceListAddress
        let listListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshDevices(notify: true)
                self.refreshDefaultInput(notify: true)
            }
        }
        let listStatus = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &listAddress,
            .main,
            listListener
        )
        if listStatus == noErr {
            deviceListListener = listListener
        } else {
            logger.error("Could not observe audio device connections: OSStatus \(listStatus)")
        }
    }

    nonisolated private func removeListeners() {
        if let defaultInputListener {
            var address = Self.defaultInputAddress
            let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                .main,
                defaultInputListener
            )
            if status != noErr {
                logger.error("Could not remove default input listener: OSStatus \(status)")
            }
        }

        if let deviceListListener {
            var address = Self.deviceListAddress
            let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                .main,
                deviceListListener
            )
            if status != noErr {
                logger.error("Could not remove audio device listener: OSStatus \(status)")
            }
        }
    }

    private func refreshDevices(notify: Bool) {
        guard let deviceIDs = allDeviceIDs() else { return }

        let refreshed = deviceIDs.compactMap { deviceID -> AudioInputDevice? in
            guard hasInputStreams(deviceID),
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, deviceID: deviceID),
                  let name = stringProperty(kAudioObjectPropertyName, deviceID: deviceID) else { return nil }
            return AudioInputDevice(deviceID: deviceID, uid: uid, name: name)
        }
        .sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        guard refreshed != devices else { return }
        devices = refreshed
        guard notify else { return }

        logger.notice("Audio input device list changed")
        NotificationCenter.default.post(name: Constants.Notifications.audioInputDevicesDidChange, object: nil)
        onDeviceListChange?()
    }

    private func refreshDefaultInput(notify: Bool) {
        var address = Self.defaultInputAddress
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr else {
            logger.error("Could not read the default input device: OSStatus \(status)")
            return
        }

        let refreshed = deviceID == kAudioObjectUnknown ? nil : deviceID
        guard refreshed != defaultDeviceID else { return }
        defaultDeviceID = refreshed
        guard notify else { return }

        logger.notice("Default audio input changed")
        NotificationCenter.default.post(name: Constants.Notifications.audioInputDevicesDidChange, object: nil)
        onDefaultInputDeviceChange?()
    }

    private func allDeviceIDs() -> [AudioDeviceID]? {
        var address = Self.deviceListAddress
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard sizeStatus == noErr else {
            logger.error("Could not size the audio device list: OSStatus \(sizeStatus)")
            return nil
        }

        var deviceIDs = [AudioDeviceID](
            repeating: kAudioObjectUnknown,
            count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        guard !deviceIDs.isEmpty else { return [] }
        let status = deviceIDs.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                baseAddress
            )
        }
        guard status == noErr else {
            logger.error("Could not read the audio device list: OSStatus \(status)")
            return nil
        }
        return deviceIDs
    }

    private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        if status != noErr {
            logger.error("Could not inspect input streams for device \(deviceID): OSStatus \(status)")
            return false
        }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private func stringProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            logger.error("Could not read property \(selector) for device \(deviceID): OSStatus \(status)")
            return nil
        }
        return value?.takeUnretainedValue() as String?
    }
}
