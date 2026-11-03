import CoreGraphics
import Foundation

/// 面板是否固定，以及固定后浮动窗口的位置。和计薪存档分开，避免搅进月薪计算。
struct StoredPanelFrame: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var encoded: String {
        [x, y, width, height]
            .map { value in
                String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
            }
            .joined(separator: ",")
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: ",")
        guard parts.count == 4 else { return nil }
        let numbers = parts.compactMap { Double(String($0)) }
        guard numbers.count == 4, numbers.allSatisfy(\.isFinite) else { return nil }
        let width = numbers[2]
        let height = numbers[3]
        guard width >= 200, height >= 80, width <= 2000, height <= 2000 else { return nil }
        self.init(x: numbers[0], y: numbers[1], width: width, height: height)
    }
}

enum PanelPinStore {
    static let pinnedKey = "com.sung1011.idea8progress.panelPinned"
    static let frameKey = "com.sung1011.idea8progress.pinnedPanelFrame"

    static func loadPinned(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pinnedKey)
    }

    static func savePinned(_ pinned: Bool, defaults: UserDefaults) {
        defaults.set(pinned, forKey: pinnedKey)
    }

    static func loadFrame(defaults: UserDefaults = .standard) -> StoredPanelFrame? {
        guard let text = defaults.string(forKey: frameKey) else { return nil }
        return StoredPanelFrame(encoded: text)
    }

    static func saveFrame(_ frame: StoredPanelFrame?, defaults: UserDefaults) {
        if let frame {
            defaults.set(frame.encoded, forKey: frameKey)
        } else {
            defaults.removeObject(forKey: frameKey)
        }
    }
}
