//
//  BookshelfView.swift
//  WeReadLike
//

import SwiftUI

struct BookshelfView: View {

    @EnvironmentObject var store: LibraryStore
    @State private var showSearch = false
    @State private var showSourceManager = false
    @State private var selectedGroup: String = "全部"
    @State private var sortByRecent = true

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    topBar
                    if !store.books.isEmpty { filterBar }
                    content
                }
                .padding(.bottom, 24)
            }
            .background(WD.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: BookDetailInput.self) { input in
                BookDetailView(input: input)
            }
            .sheet(isPresented: $showSearch) {
                SearchView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showSourceManager) {
                SourceManagerView()
                    .environmentObject(store)
            }
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 18) {
            Text("书架")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(WD.text)

            Spacer()

            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(WD.text)
            }

            Menu {
                Button {
                    sortByRecent.toggle()
                } label: {
                    Label(sortByRecent ? "按添加时间排序" : "按最近阅读排序",
                          systemImage: "arrow.up.arrow.down")
                }
                Button { showSourceManager = true } label: {
                    Label("书源管理", systemImage: "externaldrive")
                }
                Button { showSearch = true } label: {
                    Label("搜索新书", systemImage: "magnifyingglass")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(WD.text)
                    .rotationEffect(.degrees(90))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: 分组

    private var groups: [String] {
        var set: Set<String> = ["全部"]
        for b in store.books where !b.sourceName.isEmpty { set.insert(b.sourceName) }
        return ["全部"] + set.subtracting(["全部"]).sorted()
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groups, id: \.self) { g in
                    Button {
                        selectedGroup = g
                    } label: {
                        Text(g)
                            .font(.system(size: 13))
                            .foregroundColor(selectedGroup == g ? WD.accent : WD.subtext)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedGroup == g
                                ? WD.accent.opacity(0.08)
                                : Color.clear
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    // MARK: 内容

    private var displayBooks: [ShelfBook] {
        var list = store.books
        if selectedGroup != "全部" {
            list = list.filter { $0.sourceName == selectedGroup }
        }
        return sortByRecent
            ? list.sorted { $0.lastReadAt > $1.lastReadAt }
            : list.sorted { $0.addedAt > $1.addedAt }
    }

    @ViewBuilder
    private var content: some View {
        if store.books.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                ForEach(displayBooks) { book in
                    NavigationLink(value: BookDetailInput(book: book)) {
                        bookCell(book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            store.updateProgress(bookId: book.id, chapter: book.currentChapter)
                        } label: { Label("继续阅读", systemImage: "book") }
                        Button {
                            store.removeFromShelf(book)
                            store.flash("已从书架移除")
                        } label: { Label("移出书架", systemImage: "trash") }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func bookCell(_ book: ShelfBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImage(url: book.coverUrl, corner: 5)
                .aspectRatio(0.72, contentMode: .fit)
                .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.name)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(WD.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(book.progressText)
                    .font(.system(size: 11))
                    .foregroundColor(WD.subtext)
                    .lineLimit(1)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer().frame(height: 70)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: 0xEDEDED))
                    .frame(width: 96, height: 128)
                    .rotationEffect(.degrees(-6))
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: 0xE2E2E2))
                    .frame(width: 96, height: 128)
                    .rotationEffect(.degrees(6))
                Image(systemName: "book.closed")
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(Color(hex: 0xB0B0B0))
            }

            VStack(spacing: 6) {
                Text("书架空空如也")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(WD.text)
                Text(store.sources.isEmpty
                     ? "先导入阅读3.0 书源，再搜索并添加图书"
                     : "去搜索一本想读的书吧")
                    .font(.system(size: 13))
                    .foregroundColor(WD.subtext)
                    .multilineTextAlignment(.center)
            }

            Button {
                if store.sources.isEmpty {
                    showSourceManager = true
                } else {
                    showSearch = true
                }
            } label: {
                Text(store.sources.isEmpty ? "导入书源" : "去发现")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 34)
                    .frame(height: 40)
                    .background(WD.accent)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 详情页入参

struct BookDetailInput: Hashable {
    var sourceUrl: String
    var bookUrl: String
    var name: String
    var author: String
    var coverUrl: String
    var intro: String

    init(sourceUrl: String, bookUrl: String, name: String, author: String, coverUrl: String, intro: String) {
        self.sourceUrl = sourceUrl
        self.bookUrl = bookUrl
        self.name = name
        self.author = author
        self.coverUrl = coverUrl
        self.intro = intro
    }

    init(book: ShelfBook) {
        self.sourceUrl = book.sourceUrl
        self.bookUrl = book.id
        self.name = book.name
        self.author = book.author
        self.coverUrl = book.coverUrl
        self.intro = book.intro
    }

    init(result: SearchResult) {
        self.sourceUrl = result.sourceUrl
        self.bookUrl = result.bookUrl
        self.name = result.name
        self.author = result.author
        self.coverUrl = result.coverUrl
        self.intro = result.intro
    }
}
