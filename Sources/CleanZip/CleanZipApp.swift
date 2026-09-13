import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ZipCore

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var sources: [URL] = []
    @Published var busy = false
    @Published var progress: Double = 0
    @Published var status = "中文文件名，安心分享。"
    @Published var result: URL?
    @Published var error: String?
    var cancellation: Cancellation?
    func add(_ urls: [URL]) {
        guard !busy else { return }
        for url in urls where url.isFileURL {
            let url = url.standardizedFileURL
            if !sources.contains(url) { sources.append(url) }
        }
        result = nil; status = "中文文件名，安心分享。"
    }
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.allowsMultipleSelection = true; panel.prompt = "添加"
        if panel.runModal() == .OK { add(panel.urls) }
    }
    func compress() {
        guard !busy, !sources.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]; panel.canCreateDirectories = true
        panel.nameFieldStringValue = sources.count == 1 ? sources[0].lastPathComponent + ".zip" : "归档.zip"
        panel.directoryURL = sources.first?.deletingLastPathComponent()
        panel.prompt = "压缩"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let token = Cancellation(), inputs = sources
        cancellation = token; busy = true; progress = 0; result = nil; status = "正在检查文件…"
        Task.detached(priority: .userInitiated) {
            do {
                try ZipWriter.create(sources: inputs, destination: destination, cancellation: token) { p in
                    Task { @MainActor in
                        guard self.busy, self.cancellation === token else { return }
                        self.progress = Double(p.completed) / Double(max(p.total, 1))
                        self.status = "\(p.completed) / \(p.total) · \(p.name)"
                    }
                }
                await MainActor.run {
                    self.busy = false; self.cancellation = nil
                    self.result = destination; self.status = "压缩完成，可以分享了。"
                }
            } catch {
                await MainActor.run {
                    self.busy = false; self.cancellation = nil
                    self.status = token.isCancelled ? "已取消，原文件未改动。" : "未能完成压缩。"
                    if !token.isCancelled { self.error = error.localizedDescription }
                }
            }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func application(_ application: NSApplication, open urls: [URL]) { AppModel.shared.add(urls) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !AppModel.shared.busy { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "正在压缩"
        alert.informativeText = "请先取消压缩，完成清理后再退出。"
        alert.runModal()
        return .terminateCancel
    }
}
@main struct CleanZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        WindowGroup("CleanZip · 清简压缩") {
            ContentView(model: model).frame(width: 480, height: 510)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加文件或文件夹…") { model.choose() }.keyboardShortcut("o").disabled(model.busy)
            }
        }
    }
}
struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var targeted = false
    private let accent = Color(red: 0.12, green: 0.43, blue: 0.38)
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "archivebox.fill").font(.system(size: 25)).foregroundStyle(accent)
                    .frame(width: 48, height: 48).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("CleanZip").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("清简压缩").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Mac → Windows").font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(accent.opacity(0.08), in: Capsule())
            }
            VStack(spacing: 12) {
                Image(systemName: model.sources.isEmpty ? "plus.square.dashed" : "doc.on.doc")
                    .font(.system(size: 32, weight: .light)).foregroundStyle(accent)
                Text(model.sources.isEmpty ? "把文件拖到这里" : "已添加 \(model.sources.count) 个项目")
                    .font(.system(size: 18, weight: .medium))
                Text("文件或文件夹都可以").font(.system(size: 12)).foregroundStyle(.secondary)
                Button(model.sources.isEmpty ? "选择文件…" : "继续添加…") { model.choose() }
                    .buttonStyle(.bordered).disabled(model.busy)
            }
            .frame(maxWidth: .infinity).frame(height: 175)
            .background(targeted ? accent.opacity(0.10) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(targeted ? 0.65 : 0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
                guard !model.busy else { return false }
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in model.add([url]) } }
                    }
                }
                return true
            }
            VStack(alignment: .leading, spacing: 7) {
                if model.sources.isEmpty {
                    Label("保留中文名称，自动清理 Mac 附带文件", systemImage: "checkmark.circle")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("本地处理 · 无需联网 · 无需安装 Python")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                } else {
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(model.sources, id: \.self) { url in
                                HStack {
                                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Button { model.sources.removeAll { $0 == url }; model.result = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                                        .buttonStyle(.plain).disabled(model.busy).help("移除 \(url.lastPathComponent)")
                                }.font(.system(size: 12)).help(url.path)
                            }
                        }
                    }
                }
            }.frame(height: 63, alignment: .top)
            VStack(spacing: 10) {
                if model.busy {
                    ProgressView(value: model.progress).tint(accent)
                    Button("取消压缩") { model.cancellation?.cancel() }.buttonStyle(.bordered)
                } else if let result = model.result {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([result]) } label: {
                        Label("在 Finder 中显示", systemImage: "folder").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).tint(accent)
                    Button("再次压缩") { model.result = nil }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Button { model.compress() } label: {
                        Label("生成 ZIP", systemImage: "archivebox").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).tint(accent).disabled(model.sources.isEmpty)
                }
                Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("请检查后重试", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
