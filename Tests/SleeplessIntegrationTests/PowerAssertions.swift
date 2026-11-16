import Foundation
import IOKit.pwr_mgt

struct PowerAssertion: Equatable {
    let type: String
    let name: String
}

enum PowerAssertions {
    /// Power assertions currently held by this test process, as reported by IOKit.
    static func forCurrentProcess() -> [PowerAssertion] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
            let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }
        let entries = byProcess.first(where: { $0.key.int32Value == getpid() })?.value ?? []
        return entries.map {
            PowerAssertion(
                type: $0[kIOPMAssertionTypeKey] as? String ?? "",
                name: $0[kIOPMAssertionNameKey] as? String ?? ""
            )
        }
    }
}
