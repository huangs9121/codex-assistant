import AppKit
import SwiftUI
import CodexQuotaCore

@MainActor
final class NodeScoreModel: ObservableObject {
    @Published var records: [NodeScore] = []
    @Published var selected: UUID?
    @Published var name = ""
    @Published var running = false
    @Published var status = "选择历史节点或输入新节点名称"
    @Published var progress = 0.0
    @Published var sort = 0
    @Published var current: NodeScore?
    @Published var video: NodeVideoProbe?
    private var task: Task<Void, Never>?
    private var writable = true
    private let file: URL
    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexQuota/node-tests.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let decoded = try JSONDecoder().decode([NodeScore].self, from: Data(contentsOf: file))
                guard decoded.allSatisfy({ $0.metrics.count == 7 }) else { throw URLError(.cannotParseResponse) }
                records = decoded

            }
            catch { writable = false; status = "历史文件读取失败，原文件已保留：\(error.localizedDescription)" }
        } else { records = [] }
        selected = records.max { $0.date < $1.date }?.id
        name = records.first { $0.id == selected }?.name ?? ""
    }
    var result: NodeScore? { current ?? records.first { $0.id == selected } }
    var history: [NodeScore] { records.filter { $0.name == result?.name }.sorted { $0.date > $1.date } }
    var ranking: [NodeScore] {
        let sorting = sort
        let latest = Dictionary(grouping: records, by: \.name).compactMap { $0.value.sorted { $0.date > $1.date }.first }
        return latest.sorted { a, b in
            func value(_ r: NodeScore) -> Double {
                switch sorting {
                case 1: return r.version == 1 ? r.metrics[0].score ?? -1 : -1
                case 2: return r.downloadMB ?? -1
                case 3: return r.metrics[6].score ?? -1
                default: return r.version == 1 ? r.total ?? -1 : -1
                }
            }
            return value(a) == value(b) ? a.name < b.name : value(a) > value(b)
        }
    }
    func choose(_ r: NodeScore) { guard !running else { return }; current = nil; selected = r.id; name = r.name }
    func deleteNode(_ label: String) {
        guard !running, writable else { return }
        let removed = records.filter { $0.name == label }
        guard !removed.isEmpty else { return }
        let remaining = records.filter { $0.name != label }
        let deletingSelection = result?.name == label
        do {
            let archive = file.deletingLastPathComponent().appendingPathComponent("deleted-node-tests")
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
            try JSONEncoder().encode(removed).write(to: archive.appendingPathComponent("\(UUID().uuidString).json"), options: .atomic)
            try JSONEncoder().encode(remaining).write(to: file, options: .atomic)
            records = remaining
            if deletingSelection {
                current = nil
                selected = remaining.max { $0.date < $1.date }?.id
                name = result?.name ?? ""
            }
            status = "已删除 \(label) 的 \(removed.count) 条记录 · 恢复备份已保留"
        } catch { status = "删除失败，原记录保留：\(error.localizedDescription)" }
    }
    func save() {
        guard writable else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: file, options: .atomic)
        } catch { status = "保存失败：\(error.localizedDescription)" }
    }
    func stop() { task?.cancel(); status = "正在停止…" }
    func start() {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !running, !label.isEmpty, writable else { return }
        running = true; progress = 0; current = NodeScore(name: label); status = "识别出口…"
        task = Task { [weak self] in await self?.probe() }
    }
    private func request(_ url: String, method: String = "GET") async throws -> (Data, Int, Double) {
        try Task.checkCancellation()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        if method == "POST" { request.httpBody = Data("{}".utf8); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let start = Date()
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        let http = response as? HTTPURLResponse
        return (data, http?.statusCode ?? 0, Date().timeIntervalSince(start))
    }
    private func trace() async throws -> String {
        let (data, code, _) = try await request("https://www.cloudflare.com/cdn-cgi/trace")
        guard code == 200 else { throw URLError(.badServerResponse) }
        return String(data: data, encoding: .utf8) ?? ""
    }
    private func probe() async {
        defer { running = false; task = nil }
        do {
            var firstTrace = ""
            do { firstTrace = try await trace(); current?.evidence += firstTrace + "\n" }
            catch { try Task.checkCancellation(); current?.evidence += "出口查询失败：\(error.localizedDescription)\n" }
            current?.evidence += "评分规则v1.1：已移除ChatGPT网页探测；六项按45:10:15:10:5:5归一化。\n"
            let endpoints = [("https://api.openai.com/v1/models", "GET", [200,401]), ("https://api.anthropic.com/v1/messages", "POST", [400,401])]
            for (index, endpoint) in endpoints.enumerated() {
                var successes = 0; var times: [Double] = []; var codes: [Int] = []
                for attempt in 1...3 {
                    status = "\(NodeScore.labels[index]) · \(attempt)/3"
                    do {
                        let (_, code, seconds) = try await request(endpoint.0, method: endpoint.1)
                        codes.append(code); times.append(seconds)
                        if endpoint.2.contains(code) { successes += 1 }
                    } catch { try Task.checkCancellation(); codes.append(0); times.append(20); current?.evidence += "\(endpoint.0)：\(error.localizedDescription)\n" }
                }
                let average = times.isEmpty ? 20 : times.reduce(0,+) / Double(times.count)
                current?.metrics[index] = NodeMetric(NodeScore.connectionScore(success: successes, count: 3, seconds: average), String(format: "%d/3 · %.2fs",successes,average))
                current?.evidence += "\(NodeScore.labels[index]) HTTP \(codes)；仅基础网络，未验证推理\n"
                progress = Double(index + 1) / 6
            }
            for (index, url) in [(3,"https://speed.cloudflare.com/__down?bytes=5000000"),(4,"https://registry.npmjs.org/typescript/-/typescript-5.9.2.tgz")] {
                status = "\(NodeScore.labels[index]) · 下载中"
                do {
                    let (data, code, seconds) = try await request(url)
                    guard code == 200, data.count > 1_000_000 else { throw URLError(.badServerResponse) }
                    let speed = Double(data.count) / max(seconds,0.001) / 1_000_000
                    current?.metrics[index] = NodeMetric(min(10,speed * 2),String(format:"%.2f MB/s",speed))
                    if index == 3 { current?.downloadMB = speed }
                    current?.evidence += "\(url)：\(data.count)字节 / \(seconds)秒；单次完整下载\n"
                } catch { try Task.checkCancellation(); current?.metrics[index] = NodeMetric(nil,"失败 / 未评分"); current?.evidence += "下载失败：\(error.localizedDescription)\n" }
                progress = Double(index) / 6
            }
            status = "YouTube · 实际播放采样"
            let videoProbe = NodeVideoProbe()
            video = videoProbe
            current?.metrics[5] = await videoProbe.run()
            current?.evidence += "YouTube IFrame官方示例视频M7lc1UVf-VE：\(current?.metrics[5].detail ?? "未测")；15秒播放进度/墙钟时间计流畅度，清晰度为本次自动档，不代表最高支持档。\n"
            video = nil
            progress = 5.0 / 6
            try Task.checkCancellation()
            status = "查询 IP 信誉…"
            let ip = firstTrace.split(separator:"\n").first { $0.hasPrefix("ip=") }.map { String($0.dropFirst(3)) }
            if let ip, let escaped = ip.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                do {
                    let (data, code, _) = try await request("https://api.ipapi.is/?q=\(escaped)")
                    let object = try JSONSerialization.jsonObject(with: data) as? [String:Any]
                    if code == 200, let object, let vpn = object["is_vpn"] as? Bool, let proxy = object["is_proxy"] as? Bool, let hosting = object["is_datacenter"] as? Bool, let abuser = object["is_abuser"] as? Bool {
                        let score = abuser ? 2.0 : (vpn || proxy ? 4.0 : (hosting ? 6.0 : 8.0))
                        current?.metrics[6] = NodeMetric(score,"单来源 · \(hosting ? "机房" : "非机房")")
                        current?.evidence += "IPAPI.is：\(String(data:data,encoding:.utf8) ?? "")\n信誉为单来源启发式，不代表封号概率或VPN服务商安全。\n"
                    } else { current?.metrics[6] = NodeMetric(nil,"来源不可用") }
                } catch { try Task.checkCancellation(); current?.metrics[6] = NodeMetric(nil,"查询失败") }
                do {
                    let (data, code, _) = try await request("https://api.ipquery.io/\(escaped)")
                    let object = try JSONSerialization.jsonObject(with:data) as? [String:Any]
                    if code == 200, let risk = object?["risk"] as? [String:Any],
                       let vpn = risk["is_vpn"] as? Bool, let proxy = risk["is_proxy"] as? Bool,
                       let hosting = risk["is_datacenter"] as? Bool {
                        let second = vpn || proxy ? 4.0 : (hosting ? 6.0 : 8.0)
                        let first = current?.metrics[6].score
                        current?.metrics[6] = NodeMetric(min(first ?? second, second), first == nil ? "单来源 · IPQuery" : (first == second ? "双来源一致" : "来源分歧 · 保守分"))
                        current?.evidence += "IPQuery：\(String(data:data,encoding:.utf8) ?? "")\n"
                    }
                } catch { try Task.checkCancellation(); current?.evidence += "IPQuery未取得有效结果\n" }
            }
            if let last = try? await trace() {
                let lastIP = last.split(separator:"\n").first { $0.hasPrefix("ip=") }.map { String($0.dropFirst(3)) }
                if ip != lastIP { current?.evidence += "警告：测试前后出口变化，本次不参与综合排行。\n"; current?.cancelled = true }
            }
            try Task.checkCancellation()
            progress = 1; status = "测试完成 · 已保存本地"
        } catch {
            current?.cancelled = true; status = "已停止 · 部分结果已保存"
        }
        if let item = current { records.append(item); selected = item.id; save() }
    }
}

@MainActor
final class NodeScoreWindowController {
    private let model = NodeScoreModel()
    private var window: NSWindow?
    func snapshot(to path: String) throws {
        guard let view = window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { return }
        view.cacheDisplay(in:view.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:path))
    }
    func show() {
        if window == nil {
            let panel = QuickToolsWindow(contentRect: NSRect(x:0,y:0,width:1120,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            panel.title = "节点评分"; panel.contentMinSize = NSSize(width:1000,height:700)
            panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
            panel.appearance = NSAppearance(named:.darkAqua)
            panel.contentView = NSHostingView(rootView:NodeScoreView(model:model))
            panel.center(); window = panel
        }
        NSApp.activate(ignoringOtherApps:true); window?.makeKeyAndOrderFront(nil)
    }
}

private struct NodeScoreView: View {
    @ObservedObject var model: NodeScoreModel
    @State private var details = false
    @State private var deletion: String?
    private func number(_ value: Double?) -> String { value.map { String(format:"%.1f",$0) } ?? "—" }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:16) {
                Text("节点名称")
                TextField("输入节点名称",text:$model.name).textFieldStyle(.roundedBorder).frame(width:280).disabled(model.running)
                Button { model.start() } label: { Label("开始测试",systemImage:"play.fill") }.buttonStyle(.borderedProminent).disabled(model.running || model.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).buttonHelp("测试当前网络并追加本地记录")
                Button { model.stop() } label: { Label("停止",systemImage:"stop.fill") }.disabled(!model.running).buttonHelp("停止测试并保留部分结果")
                Spacer()
                if model.running { ProgressView(value:model.progress).frame(width:130) }
            }.padding(22)
            Divider()
            HStack(alignment:.top,spacing:24) {
                VStack(alignment:.leading,spacing:14) {
                    HStack {
                        Circle().fill(model.running || model.result?.cancelled == true ? Color.orange : Color.green).frame(width:10,height:10)
                        Text(model.result?.name ?? "尚未测试").font(.system(size:19,weight:.semibold))
                        Spacer()
                        Button { details = true } label: { Label("查看检测详情",systemImage:"list.bullet") }.buttonStyle(.plain).buttonHelp("查看请求结果、来源与评分规则")
                    }
                    Text(model.running ? model.status : (model.result?.cancelled == true ? "已停止 / 结果不完整" : model.result?.source ?? model.status)).foregroundStyle(.secondary).font(.system(size:12))
                    ForEach(NodeScore.activeMetricIndices,id:\.self) { index in
                        scoreRow(NodeScore.labels[index],metric:model.result?.metrics[index] ?? NodeMetric(),blue:index == 0)
                    }
                    scoreRow("综合评分",metric:NodeMetric(model.result?.total, model.result?.version == 0 ? "旧口径 · 不混排" : "覆盖 \(Int(((model.result?.coverage ?? 0)*100).rounded()))%"),blue:false)
                }.frame(maxWidth:.infinity)
                Divider()
                VStack(alignment:.leading,spacing:14) {
                    Text("本地历史").font(.system(size:18,weight:.semibold))
                    HStack { Text("日期"); Spacer(); Text("综合评分") }.foregroundStyle(.secondary)
                    ScrollView {
                        VStack(spacing:0) {
                            ForEach(model.history) { record in
                                Button { model.choose(record) } label: {
                                    HStack {
                                        if record.date == .distantPast { Text("日期未留存") }
                                        else if record.version == 0 { Text(record.date,format:.dateTime.year().month().day()) }
                                        else { Text(record.date,format:.dateTime.month().day().hour().minute()) }
                                        Spacer()
                                        Text(record.version == 0 ? "旧记录" : number(record.total))
                                    }.padding(12).background(record.id == model.result?.id ? Color.blue.opacity(0.23) : .clear)
                                }.buttonStyle(.plain).disabled(model.running).buttonHelp("查看这次测试的评分")
                                Divider()
                            }
                        }
                    }
                }.frame(width:330)
            }.padding(22).frame(height:330)
            Divider()
            HStack {
                Text("节点历史排行").font(.system(size:20,weight:.semibold))
                Spacer()
                Picker("排序方式",selection:$model.sort) {
                    Text("综合评分（Codex优先）").tag(0); Text("Codex 评分").tag(1); Text("下载速度").tag(2); Text("风控友好度").tag(3)
                }.frame(width:310)
            }.padding(.horizontal,22).padding(.vertical,16)
            HStack { Text("#").frame(width:30); Text("节点名称").frame(width:210,alignment:.leading); Text("综合评分").frame(width:100); Text("Codex 评分").frame(width:100); Text("下载吞吐").frame(width:125); Text("测试次数").frame(width:85); Spacer(); Text("操作").frame(width:100) }.foregroundStyle(.secondary).padding(.horizontal,26)
            ScrollView {
                VStack(spacing:0) {
                    ForEach(Array(model.ranking.enumerated()),id:\.element.id) { offset, record in
                        HStack {
                            Text("\(offset+1)").frame(width:30)
                            Text(record.name).frame(width:210,alignment:.leading)
                            Text(record.version == 0 ? (record.total.map { "旧 " + number($0) } ?? "待复测") : number(record.total)).frame(width:100)
                            Text(number(record.metrics[0].score)).frame(width:100)
                            Text(record.downloadMB.map { String(format:"%.2f MB/s",$0) } ?? "未测").frame(width:125)
                            Text("\(model.records.filter { $0.name == record.name && $0.date != .distantPast }.count) 次").frame(width:85)
                            Spacer()
                            HStack(spacing:18) {
                                Button { model.choose(record); model.start() } label: { Image(systemName:"arrow.clockwise") }.buttonHelp("请先切换到此节点，再测试当前网络").accessibilityLabel("重新测试 \(record.name)")
                                Button { deletion = record.name } label: { Image(systemName:"trash") }.buttonHelp("删除此节点的全部历史记录").accessibilityLabel("删除 \(record.name)")
                            }.buttonStyle(.plain).frame(width:100).disabled(model.running)
                        }.padding(.horizontal,26).padding(.vertical,13)
                            .background(model.result?.name == record.name ? Color.blue.opacity(0.23) : .clear)
                            .contentShape(Rectangle()).onTapGesture { model.choose(record) }
                        Divider().padding(.horizontal,22)
                    }
                }
            }
            HStack { Text(model.status); Spacer(); Text("本地记录 · 评分规则 v1.1") }.font(.system(size:12)).foregroundStyle(.secondary).padding(16)
        }.font(.system(size:15)).background(Color(white:0.13)).foregroundStyle(Color(white:0.93))
        .background(alignment:.topLeading) {
            if let video = model.video {
                NodeVideoSurface(probe:video).frame(width:285,height:210).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .alert("删除历史节点？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button("取消", role:.cancel) { deletion = nil }
            Button("删除", role:.destructive) { if let label = deletion { model.deleteNode(label) }; deletion = nil }
        } message: {
            Text("将删除“\(deletion ?? "")”的全部 \(model.records.filter { $0.name == deletion }.count) 条记录，并移出排行榜。本地恢复备份会保留；不会更改 VPN。")
        }
        .sheet(isPresented:$details) {
            VStack(alignment:.leading) {
                Text("检测详情与评分依据").font(.title2)
                ScrollView { Text("当前评分规则v1.1：网页项已移除，不参与探测、评分或覆盖率。Codex、CC、下载、依赖、视频、信誉权重按45:10:15:10:5:5归一化（Codex占50%）。本机历史测次同口径重算；原始证据中的旧网页结果仅留档。\n\n" + (model.result?.evidence ?? "暂无") + "\n\n缺项按覆盖权重归一化，旧会话导入不混排。基础网络可达不代表推理成功。下载5MB/s对应10分。视频未播放不推测清晰度。") .textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
                Button("关闭") { details = false }.buttonHelp("关闭检测详情")
            }.padding(24).frame(width:720,height:480)
        }
    }
    private func scoreRow(_ title: String, metric: NodeMetric, blue: Bool) -> some View {
        HStack(spacing:12) {
            Text(title).frame(width:170,alignment:.leading)
            GeometryReader { proxy in
                ZStack(alignment:.leading) {
                    Rectangle().fill(Color.white.opacity(0.10))
                    Rectangle().fill(blue ? Color.blue : Color(white:0.9)).frame(width:proxy.size.width * (metric.score ?? 0)/10)
                    HStack(spacing:0) { ForEach(0..<10,id:\.self) { _ in Rectangle().fill(.clear).border(Color.black.opacity(0.18),width:0.5) } }
                }
            }.frame(height:17)
            Text(number(metric.score)).monospacedDigit().frame(width:32)
            Text(metric.detail == "未测" && metric.score != nil ? "" : metric.detail).font(.system(size:12)).foregroundStyle(.secondary).frame(width:130,alignment:.leading)
        }.frame(height:24)
    }
}
