//
//  RootTabView.swift
//  WeReadLike
//

import SwiftUI

struct RootTabView: View {

    @EnvironmentObject var store: LibraryStore
    @State private var selection: Int = 0

    private let items: [(icon: String, active: String, title: String)] = [
        ("books.vertical", "books.vertical.fill", "书架"),
        ("safari", "safari.fill", "发现"),
        ("person", "person.fill", "我")
    ]

    var body: some View {
        GeometryReader { proxy in
            let useRail = proxy.size.width >= WDLayout.railBreakpoint
            if useRail {
                HStack(spacing: 0) {
                    rail
                    pages
                }
                .background(WD.background.ignoresSafeArea())
            } else {
                pages.safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            }
        }
        .toast(store.toast)
    }

    /// 三个页面常驻，切换只改可见性，保住各自的滚动位置与导航栈
    private var pages: some View {
        ZStack {
            BookshelfView().opacity(selection == 0 ? 1 : 0).allowsHitTesting(selection == 0)
            DiscoverView().opacity(selection == 1 ? 1 : 0).allowsHitTesting(selection == 1)
            ProfileView().opacity(selection == 2 ? 1 : 0).allowsHitTesting(selection == 2)
        }
    }

    /// 宽窗口：竖排侧栏（折叠机内屏、iPad、横屏）
    private var rail: some View {
        VStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                Button {
                    selection = idx
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: selection == idx ? item.active : item.icon)
                            .font(.system(size: 19, weight: selection == idx ? .semibold : .regular))
                        Text(item.title)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(selection == idx ? WD.accent : WD.subtext)
                    .frame(width: 76, height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selection == idx ? Color(hex: 0xE9F1FC) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 14)
        .frame(width: 88)
        .frame(maxHeight: .infinity)
        .background(WD.card)
        .overlay(alignment: .trailing) {
            Rectangle().fill(WD.line).frame(width: 0.5)
        }
    }

    /// 窄窗口：底部标签栏
    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                Button {
                    selection = idx
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selection == idx ? item.active : item.icon)
                            .font(.system(size: 20))
                        Text(item.title)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(selection == idx ? WD.accent : WD.subtext)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(WD.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(WD.line).frame(height: 0.5)
        }
    }
}

// MARK: - 我

struct ProfileView: View {

    @EnvironmentObject var store: LibraryStore
    @State private var showSourceManager = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    card {
                        row(icon: "externaldrive.badge.plus", title: "书源管理",
                            detail: "\(store.sources.count) 个") {
                            showSourceManager = true
                        }
                        divider
                        row(icon: "book.closed", title: "书架藏书",
                            detail: "\(store.books.count) 本") {}
                        divider
                        row(icon: "memorychip", title: "阅读引擎",
                            detail: "Legado 规则") {}
                    }

                    card {
                        row(icon: "questionmark.circle", title: "如何导入书源", detail: "") {
                            store.flash("在「书源管理」中粘贴 JSON 或输入链接")
                        }
                        divider
                        row(icon: "info.circle", title: "版本", detail: "iReader 1.0.0") {}
                    }

                    Text("本书架仅用于阅读你拥有合法访问权限的内容")
                        .font(.system(size: 12))
                        .foregroundColor(WD.subtext)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(WD.background.ignoresSafeArea())
            .navigationTitle("我")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSourceManager) {
                SourceManagerView()
                    .environmentObject(store)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color(hex: 0xE9EFF8))
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundColor(WD.accent)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text("阅读者")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(WD.text)
                Text("书架与书源均保存在本机")
                    .font(.system(size: 12))
                    .foregroundColor(WD.subtext)
            }
            Spacer()
        }
        .padding(16)
        .background(WD.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(WD.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var divider: some View {
        Divider().padding(.leading, 52).background(WD.line)
    }

    private func row(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(WD.accent)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(WD.text)
                Spacer()
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(WD.subtext)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: 0xCCCCCC))
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
        .buttonStyle(.plain)
    }
}
