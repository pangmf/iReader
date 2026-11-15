//
//  ReaderView.swift
//  WeReadLike
//
//  阅读器：沉浸式排版、点击呼出菜单、目录、字号、主题
//

import SwiftUI
import UIKit

struct ReaderView: View {

    let book: ShelfBook
    let startIndex: Int

    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int
    @State private var content: String = ""
    @State private var loading = true
    @State private var failed = false
    @State private var showMenu = false
    @State private var showCatalog = false
    @State private var showSettings = false

    @AppStorage("reader.fontSize") private var fontSize: Double = 18
    @AppStorage("reader.lineSpacing") private var lineSpacing: Double = 9
    @AppStorage("reader.theme") private var themeIndex: Int = 1

    init(book: ShelfBook, startIndex: Int) {
        self.book = book
        self.startIndex = startIndex
        _index = State(initialValue: max(0, min(startIndex, max(0, book.chapters.count - 1))))
    }

    private var theme: ReadingTheme { ReadingTheme.theme(themeIndex) }
    private var chapterTitle: String {
        guard index >= 0, index < book.chapters.count else { return book.name }
        return book.chapters[index].title
    }

    private var paragraphs: [String] {
        content
            .components(separatedBy: "\n")
            .map { $0.trimmed() }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            ScrollViewReader { _ in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 52).id("top")

                        if loading {
                            loadingView
                        } else if failed || paragraphs.isEmpty {
                            errorView
                        } else {
                            Text(chapterTitle)
                                .font(.system(size: fontSize + 3, weight: .semibold))
                                .foregroundColor(theme.text)
                                .padding(.bottom, 22)
                                .fixedSize(horizontal: false, vertical: true)

                            VStack(alignment: .leading, spacing: lineSpacing + 7) {
                                ForEach(Array(paragraphs.enumerated()), id: \.offset) { item in
                                    Text(item.element)
                                        .font(.system(size: fontSize))
                                        .foregroundColor(theme.text)
                                        .lineSpacing(lineSpacing)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            chapterFooter
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 90)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleMenu() }
            .simultaneousGesture(
                DragGesture(minimumDistance: 26)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if abs(dx) > 90 && abs(dx) > abs(dy) * 1.8 {
                            if dx < 0 { goTo(index + 1) } else { goTo(index - 1) }
                        }
                    }
            )
        }
        .preferredColorScheme(themeIndex == 3 ? .dark : .light)
        .overlay(alignment: .top) {
            if showMenu { topBar.transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .overlay(alignment: .bottom) {
            if showMenu { bottomBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.easeInOut(duration: 0.22), value: showMenu)
        .task(id: index) { await load() }
        .sheet(isPresented: $showCatalog) {
            CatalogSheet(chapters: book.chapters, current: index) { idx in
                showCatalog = false
                goTo(idx)
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsPanel
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(theme.text)
                    .frame(width: 40, height: 40)
            }
            Spacer()
            Text(book.name)
                .font(.system(size: 14))
                .foregroundColor(theme.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                if index > 0 {
                    store.updateProgress(bookId: book.id, chapter: index)
                }
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(theme.text)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .background(theme.bg.ignoresSafeArea(edges: .top).opacity(0.98))
    }

    // MARK: 底栏

    private var bottomBar: some View {
        VStack(spacing: 14) {
            // 进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.secondary.opacity(0.2)).frame(height: 3)
                    Capsule().fill(theme.secondary)
                        .frame(width: max(3, geo.size.width * progress), height: 3)
                }
                .frame(height: 3)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 10)

            HStack {
                Text("第 \(index + 1) / \(book.chapters.count) 章")
                    .font(.system(size: 12))
                    .foregroundColor(theme.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12))
                    .foregroundColor(theme.secondary)
            }

            HStack(spacing: 0) {
                toolButton("目录", "list.bullet") { showCatalog = true }
                toolButton("上一章", "chevron.left") { goTo(index - 1) }
                toolButton(themeIndex == 3 ? "日间" : "夜间", themeIndex == 3 ? "sun.max" : "moon") {
                    withAnimation { themeIndex = themeIndex == 3 ? 1 : 3 }
                }
                toolButton("字号", "textformat.size") { showSettings = true }
                toolButton("下一章", "chevron.right") { goTo(index + 1) }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(theme.bg.ignoresSafeArea(edges: .bottom).opacity(0.98))
        .overlay(alignment: .top) {
            Divider().background(theme.secondary.opacity(0.15))
        }
    }

    private var progress: Double {
        guard !book.chapters.isEmpty else { return 0 }
        return Double(index + 1) / Double(book.chapters.count)
    }

    private func toolButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundColor(theme.text)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 状态视图

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(theme.secondary)
            Text("正在加载…")
                .font(.system(size: 13))
                .foregroundColor(theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 160)
    }

    private var errorView: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(theme.secondary)
            Text("本章加载失败")
                .font(.system(size: 15))
                .foregroundColor(theme.text)
            Text("可能是书源规则失效或网络异常")
                .font(.system(size: 12))
                .foregroundColor(theme.secondary)

            Button {
                Task { await load(force: true) }
            } label: {
                Text("重试")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 36)
                    .background(WD.accent)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 140)
    }

    private var chapterFooter: some View {
        HStack(spacing: 0) {
            Button { goTo(index - 1) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 12))
                    Text("上一章").font(.system(size: 13))
                }
                .foregroundColor(WD.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .disabled(index <= 0)

            Divider().frame(height: 18)

            Button { goTo(index + 1) } label: {
                HStack(spacing: 4) {
                    Text("下一章").font(.system(size: 13))
                    Image(systemName: "chevron.right").font(.system(size: 12))
                }
                .foregroundColor(WD.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .disabled(index >= book.chapters.count - 1)
        }
        .background(theme.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.secondary.opacity(0.2), lineWidth: 0.6)
        )
        .padding(.top, 34)
    }

    // MARK: 设置面板

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Text("字号")
                    .font(.system(size: 13))
                    .foregroundColor(WD.subtext)
                    .frame(width: 34, alignment: .leading)

                HStack(spacing: 0) {
                    Button { fontSize = max(12, fontSize - 1) } label: {
                        Text("A").font(.system(size: 13))
                            .frame(width: 44, height: 34)
                    }
                    Divider().frame(height: 18)
                    Text("\(Int(fontSize))")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 52)
                    Divider().frame(height: 18)
                    Button { fontSize = min(30, fontSize + 1) } label: {
                        Text("A").font(.system(size: 19))
                            .frame(width: 44, height: 34)
                    }
                }
                .foregroundColor(WD.text)
                .background(WD.chip)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 16) {
                Text("行距")
                    .font(.system(size: 13))
                    .foregroundColor(WD.subtext)
                    .frame(width: 34, alignment: .leading)
                Slider(value: $lineSpacing, in: 2...20, step: 1)
                    .tint(WD.accent)
            }

            HStack(spacing: 16) {
                Text("背景")
                    .font(.system(size: 13))
                    .foregroundColor(WD.subtext)
                    .frame(width: 34, alignment: .leading)

                HStack(spacing: 14) {
                    ForEach(ReadingTheme.all) { t in
                        Button {
                            withAnimation { themeIndex = t.id }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(t.bg)
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.6))
                                if themeIndex == t.id {
                                    Circle()
                                        .stroke(WD.accent, lineWidth: 2)
                                        .frame(width: 40, height: 40)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.ignoresSafeArea())
    }

    // MARK: 逻辑

    private func toggleMenu() {
        withAnimation(.easeInOut(duration: 0.2)) { showMenu.toggle() }
    }

    private func goTo(_ i: Int) {
        guard i >= 0, i < book.chapters.count else {
            store.flash(i < 0 ? "已经是第一章" : "已经是最后一章")
            return
        }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        index = i
        store.updateProgress(bookId: book.id, chapter: i)
    }

    private func load(force: Bool = false) async {
        loading = true
        failed = false
        content = ""

        guard index >= 0, index < book.chapters.count else {
            failed = true
            loading = false
            return
        }
        let url = book.chapters[index].url
        if !force, let cached = store.cachedContent(for: url) {
            content = cached
            loading = false
            return
        }
        let text = await store.chapterContent(book: book, index: index)
        content = text
        failed = text.trimmed().isEmpty || text.contains("本章内容获取失败")
        loading = false

        store.updateProgress(bookId: book.id, chapter: index)
    }
}
