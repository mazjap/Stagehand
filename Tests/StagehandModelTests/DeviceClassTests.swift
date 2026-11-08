import Foundation
import StagehandModel
import Testing

@Suite struct DeviceClassTests {
    @Test func theDuoFallsBackToTheIPad() {
        #expect(DeviceClass.duoOuter.layoutFallbackChain == [.duoOuter, .duoInner, .pad])
        #expect(DeviceClass.duoInner.layoutFallbackChain == [.duoInner, .pad])
    }
    
    @Test(arguments: [DeviceClass.phone, .pad, .mac, .watch])
    func otherClassesHaveNoFallback(deviceClass: DeviceClass) {
        #expect(deviceClass.layoutFallbackChain == [deviceClass])
    }
    
    @Test func dictionariesKeyedByClassEncodeAsObjects() throws {
        let data = try JSONEncoder().encode([DeviceClass.phone: 1])
        #expect(String(decoding: data, as: UTF8.self) == #"{"phone":1}"#)
    }
}
