import WebKit
import SwiftUI
import CodexQuotaCore

@MainActor
final class NodeVideoProbe: NSObject, WKScriptMessageHandler {
    let view: WKWebView
    private var continuation: CheckedContinuation<NodeMetric, Never>?
    private var timeout: Task<Void, Never>?
    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = []
        view = WKWebView(frame:NSRect(x:0,y:0,width:285,height:210),configuration:config)
        super.init()
        config.userContentController.add(self,name:"result")
    }
    func run() async -> NodeMetric {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled { finish(NodeMetric(nil,"已停止")); return }
                view.loadHTMLString(Self.html,baseURL:URL(string:"https://codexquota.local/"))
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for:.seconds(35)) } catch { return }
                    self?.finish(NodeMetric(nil,"播放超时 / 未评分"))
                }
            }
        } onCancel: { Task { @MainActor in self.finish(NodeMetric(nil,"已停止")) } }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let data = message.body as? [String:Any] else { return }
        if let error = data["error"] { finish(NodeMetric(nil,"播放器错误 \(error)")); return }
        guard let elapsed = data["elapsed"] as? Double, let advanced = data["advanced"] as? Double,
              let quality = data["quality"] as? String, elapsed >= 14 else { return }
        let label = ["hd2160":"4K", "hd1440":"2K", "hd1080":"1080P", "hd720":"720P", "large":"480P", "medium":"360P", "small":"240P"][quality] ?? quality
        let ratio = min(1,max(0,advanced / elapsed))
        let base = ["hd2160":10.0,"hd1440":9.0,"hd1080":8.0,"hd720":6.0,"large":4.0,"medium":3.0,"small":2.0][quality]
        finish(NodeMetric(base.map { $0 * ratio },"\(label) · \(ratio >= 0.9 ? "流畅" : "卡顿")"))
    }
    private func finish(_ metric: NodeMetric) {
        guard let pending = continuation else { return }
        continuation = nil; timeout?.cancel(); timeout = nil
        view.stopLoading(); view.loadHTMLString("",baseURL:nil)
        view.configuration.userContentController.removeScriptMessageHandler(forName:"result")
        pending.resume(returning:metric)
    }
    private static let html = """
    <!doctype html><html><head><meta name="referrer" content="strict-origin-when-cross-origin"><style>html,body{margin:0;background:#222;}iframe{border:0;}</style></head><body><div id="player"></div>
    <script>
    var p, started=false;
    function report(data){window.webkit.messageHandlers.result.postMessage(data);}
    function onYouTubeIframeAPIReady(){p=new YT.Player('player',{width:285,height:210,videoId:'M7lc1UVf-VE',playerVars:{playsinline:1,origin:'https://codexquota.local',autoplay:1},events:{onReady:function(e){e.target.mute();e.target.playVideo();},onError:function(e){report({error:e.data});},onStateChange:function(e){if(e.data===1&&!started){started=true;var t=performance.now(),v=p.getCurrentTime();setTimeout(function(){report({elapsed:(performance.now()-t)/1000,advanced:p.getCurrentTime()-v,quality:p.getPlaybackQuality()});},15000);}}}});}
    </script><script src="https://www.youtube.com/iframe_api"></script></body></html>
    """
}

struct NodeVideoSurface: NSViewRepresentable {
    let probe: NodeVideoProbe
    func makeNSView(context: Context) -> NSView {
        // WebKit playback needs a window attachment; the opaque cover keeps video invisible.
        let host = NSView(frame:probe.view.frame)
        host.addSubview(probe.view)
        let cover = NSView(frame:probe.view.frame)
        cover.wantsLayer = true
        cover.layer?.backgroundColor = NSColor(white:0.13,alpha:1).cgColor
        host.addSubview(cover)
        return host
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
