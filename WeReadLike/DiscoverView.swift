//
//  DiscoverView.swift
//  WeReadLike
//

import SwiftUI

// MARK: - 发现

struct DiscoverView: View {

    @EnvironmentObject var store: LibraryStore
    @State private var showSearch = false
    @State private var showSourceManager = false
    @State private var seedKeyword = ""
    @AppStorage("search_history") private var historyRaw: String = ""

    private var history: [String] {
        historyRaw.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    searchBar

                    if !history.isEmpty { historySection }

                    sourceCard

                    tips
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .background(WD.background.ignoresSafeArea())
            .navigationTitle("发现")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSearch) {
                SearchView(initialKeyword: seedKeyword)
                    .environmentObject(store)
                    .id(seedKeyword)
            }
            .sheet(isPresented: $showSourceManager) {
                SourceManagerView()
                    .environmentObject(store)
            }
        }
    }

    private var searchBar: some View {
        Button {
            seedKeyword = ""
            showSearch = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundColor(WD.subtext)
                Text("搜索书名 / 作者")
                    .font(.system(size: 15))
                    .foregroundColor(WD.subtext)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(WD.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("搜索历史")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(WD.text)
                Spacer()
                Button {
                    historyRaw = ""
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(WD.subtext)
                }
            }

            FlowChips(items: Array(history.prefix(10))) { item in
                seedKeyword = item
                showSearch = true
            }
        }
    }

    private var sourceCard: some View {
        Button { showSourceManager = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: 0xE9F0FB))
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 20))
                        .foregroundColor(WD.accent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text("书源")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(WD.text)
                    Text("已启用 \(store.enabledSources.count) / \(store.sources.count) 个")
                        .font(.system(size: 12))
                        .foregroundColor(WD.subtext)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xCCCCCC))
            }
            .padding(14)
            .background(WD.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("怎么开始")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(WD.text)
            Text("1. 打开「书源管理」，粘贴阅读3.0 书源 JSON 或输入订阅链接\n2. 回到发现页搜索书名\n3. 加入书架后即可离线缓存并阅读")
                .font(.system(size: 13))
                .foregroundColor(WD.subtext)
                .lineSpacing(5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WD.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 横向换行标签

struct FlowChips: View {
    let items: [String]
    var onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        Button {
                            onTap(item)
                        } label: {
                            Text(item)
                                .font(.system(size: 13))
                                .foregroundColor(WD.text)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(WD.chip)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var rows: [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        var width: CGFloat = 0
        for item in items {
            let w = CGFloat(item.count) * 13 + 24
            if width + w > 330 && !current.isEmpty {
                result.append(current)
                current = []
                width = 0
            }
            current.append(item)
            width += w + 8
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

// MARK: - 搜索

struct SearchView: View {

    var initialKeyword: String = ""

    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("search_history") private var historyRaw: String = ""

    @State private var keyword = ""
    @State private var results: [SearchResult] = []
    @State private var searching = false
    @State private var searched = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchField

                if searching {
                    loadingView
                } else if searched && results.isEmpty {
                    emptyView
                } else if !results.isEmpty {
                    resultList
                } else {
                    Spacer()
                }
            }
            .background(WD.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: BookDetailInput.self) { input in
                BookDetailView(input: input)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(WD.text)
                }
            }
            .onAppear {
                if !initialKeyword.isEmpty {
                    keyword = initialKeyword
                    startSearch()
                } else {
                    focused = true
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(WD.subtext)
                TextField("书名 / 作者", text: $keyword)
                    .font(.system(size: 15))
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { startSearch() }
                if !keyword.isEmpty {
                    Button { keyword = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: 0xC8C8C8))
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(WD.chip)
            .clipShape(Capsule())

            Button("搜索") { startSearch() }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(WD.accent)
                .disabled(keyword.trimmed().isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("正在 \(store.enabledSources.count) 个书源中搜索…")
                .font(.system(size: 13))
                .foregroundColor(WD.subtext)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Color(hex: 0xCFCFCF))
            Text(store.sources.isEmpty ? "还没有书源" : "没有找到这本书")
                .font(.system(size: 15))
                .foregroundColor(WD.text)
            Text(store.sources.isEmpty ? "先在「书源管理」导入书源" : "换个关键词，或在其他书源试试")
                .font(.system(size: 13))
                .foregroundColor(WD.subtext)
            Spacer()
        }
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results) { r in
                    NavigationLink(value: BookDetailInput(result: r)) {
                        resultRow(r)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 84).background(WD.line)
                }
            }
            .background(WD.card)
        }
        .navigationDestination(for: BookDetailInput.self) { input in
            BookDetailView(input: input)
        }
    }

    private func resultRow(_ r: SearchResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(url: r.coverUrl)
                .frame(width: 60, height: 82)

            VStack(alignment: .leading, spacing: 5) {
                Text(r.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(WD.text)
                    .lineLimit(1)
                Text(r.author.isEmpty ? "未知作者" : r.author)
                    .font(.system(size: 12))
                    .foregroundColor(WD.subtext)
                    .lineLimit(1)
                if !r.lastChapter.isEmpty {
                    Text("最新：\(r.lastChapter)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: 0xB5B5B5))
                        .lineLimit(1)
                }
                Text(r.sourceName)
                    .font(.system(size: 11))
                    .foregroundColor(WD.accent.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: 搜索

    private func startSearch() {
        let key = keyword.trimmed()
        guard !key.isEmpty else { return }
        focused = false
        saveHistory(key)

        let sources = store.enabledSources
        guard !sources.isEmpty else {
            searched = true
            results = []
            store.flash("没有可用书源，请先导入")
            return
        }

        searching = true
        searched = false
        results = []

        Task {
            var collected: [SearchResult] = []
            await withTaskGroup(of: [SearchResult].self) { group in
                for s in sources {
                    group.addTask {
                        await BookSourceService.shared.search(keyword: key, source: s)
                    }
                }
                for await list in group {
                    collected.append(contentsOf: list)
                }
            }
            // 同书同源去重 + 按书名合并排序
            var seen = Set<String>()
            let unique = collected.filter {
                if seen.contains($0.id) { return false }
                seen.insert($0.id)
                return true
            }
            results = unique.sorted { a, b in
                if a.name == b.name { return a.sourceName < b.sourceName }
                return a.name < b.name
            }
            searching = false
            searched = true
        }
    }

    private func saveHistory(_ key: String) {
        var list = historyRaw.components(separatedBy: "\n").filter { !$0.isEmpty }
        list.removeAll { $0 == key }
        list.insert(key, at: 0)
        historyRaw = list.prefix(20).joined(separator: "\n")
    }
}
