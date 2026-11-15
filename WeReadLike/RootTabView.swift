//
//  RootTabView.swift
//  WeReadLike
//

import SwiftUI

struct RootTabView: View {

    @EnvironmentObject var store: LibraryStore
    @State private var selection: Int = 0

    var body: some View {
        TabView(selection: $selection) {
            BookshelfView()
                .tabItem {
                    Image(systemName: "books.vertical")
                    Text("书架")
                }
                .tag(0)

            DiscoverView()
                .tabItem {
                    Image(systemName: "safari")
                    Text("发现")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Image(systemName: "person")
                    Text("我")
                }
                .tag(2)
        }
        .background(WD.background)
        .toast(store.toast)
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
