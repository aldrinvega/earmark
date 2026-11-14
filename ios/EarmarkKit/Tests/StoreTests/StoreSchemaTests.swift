import SwiftData
import Testing
@testable import Store

@Suite struct StoreSchemaTests {
    @Test func startsAtVersionOne() {
        #expect(StoreSchema.currentVersion == Schema.Version(1, 0, 0))
    }
}
