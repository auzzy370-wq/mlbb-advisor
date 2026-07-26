import SwiftUI

extension Color {
    static let hayaGold = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let hayaBlue = Color(red: 0.2, green: 0.6, blue: 1.0)
    static let hayaDark = Color(red: 0.05, green: 0.05, blue: 0.1)
    static let hayaCardBackground = Color(red: 0.1, green: 0.1, blue: 0.18)
    static let hayaGradientTop = Color(red: 0.05, green: 0.07, blue: 0.15)
    static let hayaGradientBottom = Color(red: 0.03, green: 0.04, blue: 0.09)
}

extension ShapeStyle where Self == Color {
    static var hayaGold: Color { .hayaGold }
    static var hayaBlue: Color { .hayaBlue }
}
