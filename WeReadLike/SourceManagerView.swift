//
//  SourceManagerView.swift
//  WeReadLike
//
//  书源管理：导入 / 启用 / 删除
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SourceManagerView: View {

    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var showURLSheet = false
    @State private var showPasteSheet = false
    @State private var showFileImporter = false
    @State private var importing = false
    @State private var keyword = ""

    private var filtered: [BookSource] {
        guard !keyword.trimmed().isEmpty else { return store.sources }
        return store.sources.filter {
            $0.bookSourceName.localizedCaseInsensitiveContains(keyword)
            || $0.bookSourceUrl.localizedCaseInsensitiveContains(keyword)
            || $0.bookSourceGroup.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.sources.isEmpty {
                    emptyView
                } else {
                    listView
                }
            }
            .background(WD.background.ignoresSafeArea())
            .navigationTitle("书源管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundColor(WD.text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showURLSheet = true } label: {
                            Label("从链接导入", systemImage: "link")
                        }
                        Button { showPasteSheet = true } label: {
                            Label("粘贴 JSON", systemImage: "doc.on.clipboard")
                        }
                        Button { showFileImporter = true } label: {
                            Label("从文件导入", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(WD.text)
                    }
                }
            }
            .searchable(text: $keyword, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索书源")
            .sheet(isPresented: $showURLSheet) {
                ImportURLView { url in
                    try await importFrom(url: url)
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showPasteSheet) {
                ImportTextView { text in
                    let n = store.importSources(from: text)
                    store.flash(n > 0 ? "成功导入 \(n) 个书源" : "未识别到有效书源")
                    return n
                }
                .environmentObject(store)
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.json, .text, .data],
                          allowsMultipleSelection: false) { result in
                handleFile(result)
            }
            .overlay {
                if importing { LoadingOverlay(text: "正在导入…") }
            }
        }
    }

    // MARK: 列表

    private var listView: some View {
        List {
            Section {
                ForEach(filtered) { source in
                    sourceRow(source)
                }
                .onDelete { offsets in
                    let ids = offsets.map { filtered[$0].id }
                    for id in ids { store.deleteSource(id: id) }
                }
            } header: {
                Text("共 \(store.sources.count) 个 · 已启用 \(store.enabledSources.count) 个")
                    .font(.system(size: 12))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func sourceRow(_ source: BookSource) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(WD.accent.opacity(0.1))
                Text(String(source.bookSourceName.prefix(1)))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(WD.accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(source.bookSourceName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(WD.text)
                    .lineLimit(1)
                Text(source.host)
                    .font(.system(size: 11))
                    .foregroundColor(WD.subtext)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { source.enabled },
                set: { _ in store.toggleSource(id: source.id) }
            ))
            .labelsHidden()
            .tint(WD.accent)
            .scaleEffect(0.85)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteSource(id: source.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Color(hex: 0xC8C8C8))
            Text("还没有书源")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(WD.text)
            Text("支持阅读3.0（Legado）的 JSON 书源\n可粘贴文本、输入订阅链接或导入文件")
                .font(.system(size: 13))
                .foregroundColor(WD.subtext)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button { showPasteSheet = true } label: {
                Text("粘贴书源 JSON")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 40)
                    .background(WD.accent)
                    .clipShape(Capsule())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 逻辑

    @MainActor
    private func importFrom(url: String) async throws -> Int {
        importing = true
        defer { importing = false }
        let n = try await store.importSources(fromURL: url)
        store.flash(n > 0 ? "成功导入 \(n) 个书源" : "该链接未返回有效书源")
        return n
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        importing = true
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
            importing = false
        }
        guard let data = try? Data(contentsOf: url) else {
            store.flash("文件读取失败")
            return
        }
        let n = store.importSources(from: data)
        store.flash(n > 0 ? "成功导入 \(n) 个书源" : "文件中未识别到书源")
    }
}

// MARK: - 链接导入

struct ImportURLView: View {

    var onImport: (String) async throws -> Int

    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("https://example.com/sources.json", text: $url)
                    .font(.system(size: 14))
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(12)
                    .background(WD.chip)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("输入书源订阅链接，支持返回 JSON 数组或 {bookSources:[...]} 的接口。")
                    .font(.system(size: 12))
                    .foregroundColor(WD.subtext)
                    .lineSpacing(3)

                if let e = errorText {
                    Text(e)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }

                Spacer()
            }
            .padding(20)
            .background(WD.background.ignoresSafeArea())
            .navigationTitle("从链接导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.foregroundColor(WD.text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await run() }
                    } label: {
                        if busy { ProgressView() } else { Text("导入").bold() }
                    }
                    .disabled(url.trimmed().isEmpty || busy)
                }
            }
        }
    }

    @MainActor
    private func run() async {
        busy = true
        errorText = nil
        do {
            let n = try await onImport(url.trimmed())
            if n > 0 { dismiss() }
            else { errorText = "没有解析到书源，请检查链接内容" }
        } catch {
            errorText = "导入失败：\(error.localizedDescription)"
        }
        busy = false
    }
}

// MARK: - 文本导入

struct ImportTextView: View {

    var onImport: (String) -> Int

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(WD.chip)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxHeight: .infinity)

                HStack(spacing: 10) {
                    Button {
                        if let s = UIPasteboard.general.string { text = s }
                    } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                            .font(.system(size: 13))
                            .foregroundColor(WD.accent)
                    }
                    Spacer()
                    Text("\(text.count) 字符")
                        .font(.system(size: 11))
                        .foregroundColor(WD.subtext)
                }
            }
            .padding(16)
            .background(WD.background.ignoresSafeArea())
            .navigationTitle("粘贴书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.foregroundColor(WD.text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("导入") {
                        let n = onImport(text)
                        if n > 0 { dismiss() }
                    }
                    .bold()
                    .disabled(text.trimmed().isEmpty)
                }
            }
            .onAppear {
                if text.isEmpty, let s = UIPasteboard.general.string,
                   s.contains("bookSourceUrl") {
                    text = s
                }
            }
        }
    }
}
