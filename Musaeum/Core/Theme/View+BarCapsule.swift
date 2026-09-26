import SwiftUI

extension View {
    /// The capsule a bar's controls sit in: the system's own glass from iOS 26,
    /// so the library's controls read like every other bar's, and a material
    /// capsule before it.
    @ViewBuilder
    func barCapsule() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }
}
