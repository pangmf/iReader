//
//  BookDetailView.swift
//  WeReadLike
//

import SwiftUI

struct ReadingTarget: Identifiable {
    let id = UUID()
    let book: ShelfBook
    let index: Int
}

struct BookDetailView: View {

    let input: BookDetailInput

    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var info = BookInfo()
    @State private var chapters: [Chapter] = []
    @State private var loading = true
    @State private var expanded = false
    @State private var showCatalog = false
    @State private var target: ReadingTarget?

    private var onShelf: Bool { store.isOnShelf(bookUrl: input.bookUrl) }
    private var shelfBook: ShelfBook? { store.book(id: input.bookUrl) }

    private var displayName: String {
        if !info.name.isEmpty { return info.name }
        return input.name
    }
    private var displayAuthor: String {
        if !info.author.isEmpty { return info.author }
        return input.author
    }
    private var displayCover: String {
        if !info.coverUrl.isEmpty { return info.coverUrl }
        return input.coverUrl
    }
    private var displayIntro: String {
        if !info.intro.isEmpty { return info.intro }
        return input.intro
    }

    var body: some View {
        ZStack(alignment: .top) {
            WD.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerCard
                    actionBar
                    introSection
                    catalogSection
                }
                .padding(.bottom, 40)
            }

            topBar
        }
        .navigationBarBackButtonHidden(true)
        .task { await load() }
        .sheet(isPresented: $showCatalog) {
            CatalogSheet(chapters: chapters, current: shelfBook?.currentChapter ?? 0) { idx in
                showCatalog = false
                startReading(index: idx)
            }
        }
        .fullScreenCover(item: $target) { t in
            ReaderView(book: t.book, startIndex: t.index)
                .environmentObject(store)
        }
    }

    // MARK: 顶部

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(WD.text)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Circle())
            }
            Spacer()
            Menu {
                if onShelf {
                    Button {
                        if let b = shelfBook { store.removeFromShelf(b) }
                        store.flash("已移出书架")
                    } label: { Label("移出书架", systemImage: "trash") }
                }
                Button {
                    Task { await reload() }
                } label: { Label("刷新目录", systemImage: "arrow.clockwise") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(WD.text)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: 头图

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 16) {
            CoverImage(url: displayCover, corner: 6)
                .frame(width: 104, height: 144)
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 8) {
                Text(displayName)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(WD.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(displayAuthor.isEmpty ? "未知作者" : displayAuthor)
                    .font(.system(size: 13))
                    .foregroundColor(WD.subtext)

                if !info.kind.isEmpty {
                    Text(info.kind)
                        .font(.system(size: 11))
                        .foregroundColor(WD.subtext)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 10))
                    Text(input.sourceUrl.isEmpty ? "本地" : sourceName)
                        .font(.system(size: 11))
                }
                .foregroundColor(Color(hex: 0xB0B0B0))

                Text(loading ? "正在获取目录…" : "共 \(chapters.count) 章")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0xB0B0B0))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 44)
    }

    private var sourceName: String {
        store.source(url: input.sourceUrl)?.bookSourceName ?? "未知来源"
    }

    // MARK: 操作

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                if let b = shelfBook, !b.chapters.isEmpty {
                    startReading(index: min(b.currentChapter, max(0, b.chapters.count - 1)))
                } else {
                    startReading(index: 0)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill").font(.system(size: 14))
                    Text(onShelf ? "继续阅读" : "阅读")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(WD.accent)
                .clipShape(Capsule())
            }
            .disabled(loading || chapters.isEmpty)

            if !onShelf {
                Button {
                    guard !chapters.isEmpty else { return }
                    let r = SearchResult(name: displayName, author: displayAuthor, coverUrl: displayCover,
                                         bookUrl: input.bookUrl, intro: displayIntro, kind: info.kind,
                                         lastChapter: info.lastChapter, wordCount: info.wordCount,
                                         sourceUrl: input.sourceUrl, sourceName: sourceName)
                    store.addToShelf(r, info: info, chapters: chapters)
                    store.flash("已加入书架")
                } label: {
                    Text("加入书架")
                        .font(.system(size: 15))
                        .foregroundColor(WD.accent)
                        .frame(width: 108)
                        .frame(height: 44)
                        .background(WD.accent.opacity(0.08))
                        .clipShape(Capsule())
                }
                .disabled(loading || chapters.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    // MARK: 简介

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("简介")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(WD.text)

            if displayIntro.trimmed().isEmpty {
                Text(loading ? "加载中…" : "暂无简介")
                    .font(.system(size: 14))
                    .foregroundColor(WD.subtext)
            } else {
                Text(displayIntro)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0x4A4A4A))
                    .lineSpacing(6)
                    .lineLimit(expanded ? nil : 4)

                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    Text(expanded ? "收起" : "展开")
                        .font(.system(size: 13))
                        .foregroundColor(WD.accent)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
    }

    // MARK: 目录

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("目录")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(WD.text)
                Spacer()
                Button { showCatalog = true } label: {
                    HStack(spacing: 2) {
                        Text("全部").font(.system(size: 13))
                        Image(systemName: "chevron.right").font(.system(size: 11))
                    }
                    .foregroundColor(WD.subtext)
                }
                .disabled(chapters.isEmpty)
            }
            .padding(.bottom, 6)

            if loading {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: 0xF0F0F0))
                        .frame(height: 14)
                        .padding(.vertical, 10)
                }
            } else {
                ForEach(Array(chapters.prefix(8).enumerated()), id: \.offset) { item in
                    Button {
                        startReading(index: item.offset)
                    } label: {
                        HStack {
                            Text(item.element.title)
                                .font(.system(size: 14))
                                .foregroundColor(WD.text)
                                .lineLimit(1)
                            Spacer()
                        }
                        .frame(height: 42)
                    }
                    .buttonStyle(.plain)
                    Divider().background(WD.line)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
    }

    // MARK: 逻辑

    private func load() async {
        guard let source = store.source(url: input.sourceUrl) else {
            loading = false
            store.flash("书源不存在，请重新导入")
            return
        }

        if let b = shelfBook, !b.chapters.isEmpty {
            chapters = b.chapters
            info.name = b.name
            info.author = b.author
            info.coverUrl = b.coverUrl
            info.intro = b.intro
            info.kind = b.kind
            info.lastChapter = b.lastChapter
            info.wordCount = b.wordCount
            info.tocUrl = b.tocUrl
            loading = false
            return
        }

        let i = await BookSourceService.shared.bookInfo(source: source,
                                                        bookUrl: input.bookUrl,
                                                        fallbackName: input.name)
        info = i
        let list = await BookSourceService.shared.toc(source: source, tocUrl: i.tocUrl)
        chapters = list
        loading = false

        if list.isEmpty {
            store.flash("目录获取失败，可能是书源规则不匹配")
        }
    }

    private func reload() async {
        loading = true
        chapters = []
        await load()
    }

    private func startReading(index: Int) {
        guard !chapters.isEmpty else {
            store.flash("目录为空，无法阅读")
            return
        }
        guard store.source(url: input.sourceUrl) != nil else {
            store.flash("书源缺失")
            return
        }
        let r = SearchResult(name: displayName, author: displayAuthor, coverUrl: displayCover,
                             bookUrl: input.bookUrl, intro: displayIntro, kind: info.kind,
                             lastChapter: info.lastChapter, wordCount: info.wordCount,
                             sourceUrl: input.sourceUrl, sourceName: sourceName)
        let book = store.addToShelf(r, info: info, chapters: chapters)
        let safe = max(0, min(index, chapters.count - 1))
        store.updateProgress(bookId: book.id, chapter: safe)
        var updated = book
        updated.currentChapter = safe
        target = ReadingTarget(book: updated, index: safe)
    }
}

// MARK: - 目录面板

struct CatalogSheet: View {

    let chapters: [Chapter]
    let current: Int
    var onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ascending = true
    @State private var scrollID: Int?

    private var indices: [Int] {
        let all = Array(chapters.indices)
        return ascending ? all : all.reversed()
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(indices, id: \.self) { idx in
                        Button {
                            onSelect(idx)
                        } label: {
                            HStack(spacing: 8) {
                                Text(chapters[idx].title)
                                    .font(.system(size: 14))
                                    .foregroundColor(idx == current ? WD.accent : WD.text)
                                    .lineLimit(1)
                                Spacer()
                                if idx == current {
                                    Image(systemName: "book.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(WD.accent)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.white)
                        .id(idx)
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation { proxy.scrollTo(current, anchor: .center) }
                    }
                }
            }
            .navigationTitle("目录（\(chapters.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        ascending.toggle()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(WD.text)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(WD.text)
                }
            }
        }
    }
}
