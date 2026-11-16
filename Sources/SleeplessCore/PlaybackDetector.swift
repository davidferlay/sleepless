import CoreAudio
import Foundation
import os

/// Reports whether audio is playing.
@MainActor
public protocol PlaybackDetecting: AnyObject {
    var isPlaying: Bool { get }
    var onChange: (@MainActor (Bool) -> Void)? { get set }
    func start()
    func stop()
    /// Re-reads the current state, for example after the Mac wakes from sleep.
    func refresh()
}

/// Detects playback on the default output device through `kAudioDevicePropertyDeviceIsRunningSomewhere`.
/// Event driven: CoreAudio calls the listeners on the main queue, nothing polls.
@MainActor
public final class CoreAudioPlaybackDetector: PlaybackDetecting {
    public private(set) var isPlaying = false
    public var onChange: (@MainActor (Bool) -> Void)?

    private var deviceID = CoreAudioPlaybackDetector.unknownDevice
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var runningListener: AudioObjectPropertyListenerBlock?
    private let logger = Logger(subsystem: Log.subsystem, category: "playback")

    public init() {}

    /// True while the default-device listener and, when a device exists, its running-state listener are registered.
    public var isWatching: Bool {
        defaultDeviceListener != nil && (deviceID == Self.unknownDevice || runningListener != nil)
    }

    public func start() {
        guard defaultDeviceListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { @Sendable [weak self] _, _ in
            MainActor.assumeIsolated { self?.defaultDeviceChanged() }
        }
        var address = Self.defaultOutputDeviceAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        )
        if status == noErr {
            defaultDeviceListener = listener
        } else {
            logger.error("Could not watch the default output device (OSStatus \(status))")
        }
        defaultDeviceChanged()
    }

    public func stop() {
        removeRunningListener()
        if let listener = defaultDeviceListener {
            var address = Self.defaultOutputDeviceAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                listener
            )
            defaultDeviceListener = nil
        }
        deviceID = Self.unknownDevice
    }

    public func refresh() {
        let playing = deviceID != Self.unknownDevice && Self.isRunningSomewhere(deviceID)
        guard playing != isPlaying else { return }
        isPlaying = playing
        logger.notice("Playback detected: \(playing ? "YES" : "NO", privacy: .public)")
        onChange?(playing)
    }

    /// The current default output device, or `nil` when there is none.
    public nonisolated static func defaultOutputDevice() -> AudioObjectID? {
        var address = defaultOutputDeviceAddress
        var device = unknownDevice
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != unknownDevice else { return nil }
        return device
    }

    /// Whether any process is doing I/O on `device`.
    public nonisolated static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        guard device != unknownDevice else { return false }
        var address = runningSomewhereAddress
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    private nonisolated static let unknownDevice = AudioObjectID(kAudioObjectUnknown)

    private nonisolated static var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private nonisolated static var runningSomewhereAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func defaultDeviceChanged() {
        let newDevice = Self.defaultOutputDevice() ?? Self.unknownDevice
        if newDevice != deviceID {
            removeRunningListener()
            deviceID = newDevice
            addRunningListener()
            logger.notice("Default output device: \(newDevice)")
        }
        refresh()
    }

    private func addRunningListener() {
        guard deviceID != Self.unknownDevice else { return }
        let listener: AudioObjectPropertyListenerBlock = { @Sendable [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        var address = Self.runningSomewhereAddress
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, listener)
        if status == noErr {
            runningListener = listener
        } else {
            logger.error("Could not watch output device \(self.deviceID) (OSStatus \(status))")
        }
    }

    private func removeRunningListener() {
        guard let listener = runningListener else { return }
        var address = Self.runningSomewhereAddress
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, listener)
        runningListener = nil
    }
}
