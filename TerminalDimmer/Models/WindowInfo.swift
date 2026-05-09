import Foundation
import CoreGraphics

struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let ownerBundleID: String
    let bounds: CGRect
    let layer: Int32
    let isOnScreen: Bool

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }
}
