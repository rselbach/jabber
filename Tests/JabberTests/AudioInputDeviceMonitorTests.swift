import XCTest
@testable import Jabber

final class AudioInputDeviceMonitorTests: XCTestCase {
    func testDeviceIDResolvesPersistentUID() {
        let devices = [
            AudioInputDevice(deviceID: 7, uid: "troy-desk-mic", name: "Troy's Desk Mic"),
            AudioInputDevice(deviceID: 42, uid: "greendale-podcast", name: "Greendale Podcast Mic")
        ]

        XCTAssertEqual(
            AudioInputDeviceMonitor.deviceID(forUID: "greendale-podcast", in: devices),
            42
        )
        XCTAssertNil(AudioInputDeviceMonitor.deviceID(forUID: "study-room-mic", in: devices))
    }
}
