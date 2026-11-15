//
//  Theme.swift
//  WeReadLike
//
//  视觉规范：对齐微信读书的克制风格
//

import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

enum WD {
    static let accent = Color(hex: 0x1E7BE0)
    static let background = Color(hex: 0xF7F7F7)
    static let card = Color.white
    static let text = Color(hex: 0x1B1B1B)
    static let subtext = Color(hex: 0x9C9C9C)
    static let line = Color(hex: 0xEFEFEF)
    static let chip = Color(hex: 0xF2F2F2)
}

// MARK: - 阅读主题

struct ReadingTheme: Identifiable, Hashable {
    let id: Int
    let name: String
    let bg: Color
    let text: Color
    let secondary: Color

    static let all: [ReadingTheme] = [
        ReadingTheme(id: 0, name: "白", bg: Color(hex: 0xFFFFFF), text: Color(hex: 0x2B2B2B), secondary: Color(hex: 0x9A9A9A)),
        ReadingTheme(id: 1, name: "米黄", bg: Color(hex: 0xF6F0E0), text: Color(hex: 0x3A3327), secondary: Color(hex: 0x9C937F)),
        ReadingTheme(id: 2, name: "护眼", bg: Color(hex: 0xDDE8D6), text: Color(hex: 0x2F3A2A), secondary: Color(hex: 0x84907A)),
        ReadingTheme(id: 3, name: "夜间", bg: Color(hex: 0x121212), text: Color(hex: 0x9C9C9C), secondary: Color(hex: 0x606060))
    ]

    static func theme(_ index: Int) -> ReadingTheme {
        all.first { $0.id == index } ?? all[1]
    }
}

// MARK: - 常用组件

struct CoverImage: View {
    let url: String
    var corner: CGFloat = 4

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(Color(hex: 0xEDEDED))
            Text("书")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Color(hex: 0xC8C8C8))

            if let u = URL(string: url), !url.isEmpty {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.clear
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay(
            RoundedRectangle(cornerRadius: corner)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
        )
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .medium))
                }
                Text(title).font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(WD.accent)
            .clipShape(Capsule())
        }
    }
}

struct LoadingOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(Color.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

extension View {
    func toast(_ message: String?) -> some View {
        overlay(alignment: .bottom) {
            if let m = message {
                Text(m)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.bottom, 90)
                    .transition(.opacity)
            }
        }
    }
}


// MARK: - 自适应布局（iPhone Duo 折叠 / iPad / 分屏）

/// 读取视图实际可用宽度。按窗口排版，而不是按屏幕排版——
/// 折叠机展开、分屏、旋转都会改变窗口宽度，屏幕宽度却不一定变。
struct WDWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func readAvailableWidth(_ action: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: WDWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(WDWidthKey.self) { action($0) }
    }
}

enum WDLayout {
    /// 超过这个宽度改用侧边竖排导航（Duo 内屏、iPad、横屏）
    static let railBreakpoint: CGFloat = 700
    /// 正文可读宽度上限，防止宽屏出现超长行
    static let readableWidth: CGFloat = 760
    /// 列表页内容宽度上限
    static let contentWidth: CGFloat = 980
}
