import Foundation
import WebKit

/// Drives a YouTube player inside a WKWebView.
///
/// The page is loaded with a youtube.com base URL, so the YouTube embed iframe is same-origin
/// and the page script can reach its `<video>` element directly ("precise mode"): exact
/// `currentTime` seeks, any playback rate (0.1×), and the real frame rate measured with
/// `requestVideoFrameCallback`. If the element can't be reached it falls back to the official
/// IFrame API ("basic mode": seeks to the nearest frame YouTube gives, rates down to 0.25×).
@MainActor
final class PlayerController: NSObject, ObservableObject {
    @Published private(set) var videoID: String?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var rate: Double = 1
    @Published private(set) var detectedFPS: Double?
    @Published var fpsOverride: Double? { didSet { saveFPS() } }
    @Published private(set) var preciseMode = false
    @Published private(set) var ready = false
    @Published private(set) var errorMessage: String?
    @Published var muted = false { didSet { js("ptMute(\(muted))") } }

    @Published var loopA: Double?
    @Published var loopB: Double?
    @Published var loopOn = false

    /// Called with (videoID, position) when it's worth remembering where we are.
    var onSavePosition: ((String, Double) -> Void)?
    var onSaveFPS: ((String, Double?) -> Void)?

    var fps: Double { fpsOverride ?? detectedFPS ?? 30 }
    var frameDuration: Double { 1 / fps }
    var currentFrame: Int { Int((currentTime * fps).rounded(.down)) }

    let webView: WKWebView
    private var desiredRate: Double = 1
    private var lastSaved = Date.distantPast

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        let controller = WKUserContentController()
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        controller.add(MessageProxy(owner: self), name: "pt")
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }

    // MARK: Commands

    func load(videoID: String, start: Double, fpsOverride: Double? = nil) {
        if let old = self.videoID, old != videoID { savePosition(force: true) }
        self.videoID = videoID
        currentTime = start
        duration = 0
        isPlaying = false
        ready = false
        errorMessage = nil
        detectedFPS = nil
        self.fpsOverride = fpsOverride
        loopA = nil; loopB = nil; loopOn = false
        let html = Self.html
            .replacingOccurrences(of: "__VIDEO_ID__", with: videoID)
            .replacingOccurrences(of: "__START__", with: String(format: "%.3f", max(0, start)))
            .replacingOccurrences(of: "__RATE__", with: String(desiredRate))
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com/"))
    }

    func togglePlay() { isPlaying ? pause() : play() }
    func play() { js("ptPlay()"); isPlaying = true }
    func pause() { js("ptPause()"); isPlaying = false; savePosition(force: true) }

    func step(frames: Int) {
        isPlaying = false
        currentTime = max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude, currentTime + Double(frames) * frameDuration))
        js("ptStep(\(frames), \(fps))")
    }

    func jump(seconds: Double) { seek(to: currentTime + seconds) }

    func seek(to time: Double) {
        let t = max(0, duration > 0 ? min(time, duration - 0.01) : time)
        currentTime = t
        js("ptSeek(\(t))")
    }

    func setRate(_ r: Double) {
        desiredRate = r
        rate = r
        js("ptRate(\(r))")
    }

    func setZoom(scale: CGFloat, offset: CGSize) {
        js("ptZoom(\(scale), \(offset.width), \(offset.height))")
    }

    func savePosition(force: Bool = false) {
        guard let id = videoID else { return }
        if force || Date().timeIntervalSince(lastSaved) > 5 {
            lastSaved = Date()
            onSavePosition?(id, currentTime)
        }
    }

    private func saveFPS() {
        if let id = videoID { onSaveFPS?(id, fpsOverride) }
    }

    private func js(_ script: String) {
        guard videoID != nil else { return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: Messages from the page

    fileprivate func handle(_ body: Any) {
        guard let msg = body as? [String: Any], let type = msg["type"] as? String else { return }
        switch type {
        case "time":
            let t = (msg["t"] as? Double) ?? currentTime
            let d = (msg["d"] as? Double) ?? duration
            let playing = (msg["playing"] as? Bool) ?? false
            if let r = msg["rate"] as? Double, r > 0 { rate = r }
            if d.isFinite, d > 0 { duration = d }
            if t.isFinite { currentTime = t }
            if isPlaying && !playing { savePosition(force: true) }
            isPlaying = playing
            if playing { savePosition() }
            if loopOn, playing, let a = loopA, let b = loopB, b > a, t >= b { seek(to: a) }
        case "fps":
            if let raw = msg["fps"] as? Double { detectedFPS = Self.snap(fps: raw) }
        case "mode":
            preciseMode = (msg["mode"] as? String) == "precise"
        case "ready":
            ready = true
            if desiredRate != 1 { js("ptRate(\(desiredRate))") }
            if muted { js("ptMute(true)") }
        case "error":
            let code = (msg["code"] as? Int) ?? -1
            errorMessage = Self.describe(error: code)
        default:
            break
        }
    }

    private static func snap(fps raw: Double) -> Double {
        let common: [Double] = [23.976, 24, 25, 29.97, 30, 48, 50, 59.94, 60]
        let best = common.min { abs($0 - raw) < abs($1 - raw) }!
        return abs(best - raw) / best < 0.04 ? best : raw.rounded()
    }

    private static func describe(error code: Int) -> String {
        switch code {
        case 2: return "That doesn't look like a valid YouTube video."
        case 5: return "The video couldn't be played in the player (error 5)."
        case 100: return "This video was removed or is private."
        case 101, 150: return "The video's owner doesn't allow it to be played outside YouTube. Open it in the YouTube app instead."
        default: return "YouTube couldn't play this video (error \(code))."
        }
    }

    // MARK: Page

    private static let html = #"""
    <!DOCTYPE html>
    <html><head>
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
    <style>
      html,body{margin:0;padding:0;background:#000;width:100%;height:100%;overflow:hidden}
      #wrap{position:absolute;left:0;top:0;width:100%;height:100%;transform-origin:50% 50%}
      #player,iframe{width:100%;height:100%;border:0;display:block}
    </style></head>
    <body><div id="wrap"><div id="player"></div></div>
    <script>
    var player=null, vid=null, mode='', desiredRate=__RATE__, frameStart=null, pendingSeek=null, lastKey='';
    var START=__START__;
    function post(m){try{window.webkit.messageHandlers.pt.postMessage(m)}catch(e){}}
    function onYouTubeIframeAPIReady(){
      player=new YT.Player('player',{videoId:'__VIDEO_ID__',width:'100%',height:'100%',
        playerVars:{playsinline:1,controls:0,rel:0,modestbranding:1,fs:0,iv_load_policy:3,disablekb:1,
                    start:Math.floor(START),origin:'https://www.youtube.com'},
        events:{
          onReady:function(){
            try{player.playVideo();}catch(e){}
            setTimeout(function(){try{player.pauseVideo(); if(START>0) ptSeek(START);}catch(e){}},400);
            post({type:'ready'});
            setInterval(function(){grabVid();report(false);},66);
          },
          onStateChange:function(){grabVid();report(true);},
          onError:function(e){post({type:'error',code:e.data});}
        }});
    }
    function grabVid(){
      if(vid && vid.isConnected) return vid;
      vid=null;
      try{
        var f=player && player.getIframe ? player.getIframe() : null;
        var d=f ? (f.contentDocument || (f.contentWindow && f.contentWindow.document)) : null;
        if(d) vid=d.querySelector('video');
      }catch(e){vid=null;}
      if(vid) hook(vid);
      var m=vid?'precise':'basic';
      if(m!==mode){mode=m;post({type:'mode',mode:m});}
      return vid;
    }
    function hook(v){
      if(v.__pt) return; v.__pt=true;
      v.addEventListener('seeking',function(){frameStart=null;});
      v.addEventListener('seeked',function(){
        if(pendingSeek!==null){var t=pendingSeek;pendingSeek=null;v.currentTime=t;}
        report(true);
      });
      var fixRate=function(){ if(Math.abs(v.playbackRate-desiredRate)>0.001){ v.playbackRate=desiredRate; } };
      v.addEventListener('ratechange',fixRate);
      v.addEventListener('playing',fixRate);
      fixRate();
      if(v.requestVideoFrameCallback){
        var lastMT=-1,lastPF=-1,deltas=[];
        var cb=function(now,md){
          frameStart=md.mediaTime;
          if(!v.paused && lastPF>=0 && md.presentedFrames===lastPF+1){
            var dt=md.mediaTime-lastMT;
            if(dt>0.004 && dt<0.1){
              deltas.push(dt);
              if(deltas.length>=40){deltas.sort(function(a,b){return a-b;});var med=deltas[20];deltas=[];post({type:'fps',fps:1/med});}
            }
          }
          lastMT=md.mediaTime;lastPF=md.presentedFrames;
          v.requestVideoFrameCallback(cb);
        };
        v.requestVideoFrameCallback(cb);
      }
    }
    function report(force){
      if(!player || !player.getCurrentTime) return;
      var v=grabVid(), t, playing, rate;
      if(v){ t=(pendingSeek!==null)?pendingSeek:v.currentTime; playing=!v.paused && !v.ended; rate=v.playbackRate; }
      else { t=player.getCurrentTime(); playing=player.getPlayerState()===1; rate=player.getPlaybackRate(); }
      var d=player.getDuration ? player.getDuration() : 0;
      if(!(d>0) && v && isFinite(v.duration)) d=v.duration;
      var key=t.toFixed(3)+'|'+playing+'|'+d+'|'+rate;
      if(!force && key===lastKey) return;
      lastKey=key;
      post({type:'time',t:t,d:d||0,playing:playing,rate:rate});
    }
    function ptPlay(){ if(player) player.playVideo(); }
    function ptPause(){ var v=grabVid(); if(v) v.pause(); if(player) player.pauseVideo(); }
    function ptSeek(t){
      var v=grabVid();
      if(v){ if(v.seeking){pendingSeek=t;} else {v.currentTime=t;} }
      else if(player){ player.seekTo(t,true); }
      report(true);
    }
    function ptStep(n,fps){
      var v=grabVid();
      if(v){
        if(!v.paused){ v.pause(); if(player) player.pauseVideo(); }
        var cur=(pendingSeek!==null)?pendingSeek:v.currentTime;
        var base=(frameStart!==null && Math.abs(frameStart-cur)<1.5/fps) ? frameStart+0.2/fps : cur;
        ptSeek(Math.max(0,base+n/fps));
      } else if(player){
        player.pauseVideo();
        player.seekTo(Math.max(0,player.getCurrentTime()+n/fps),true);
        report(true);
      }
    }
    function ptRate(r){
      desiredRate=r;
      var v=grabVid();
      if(v){ v.playbackRate=r; } else if(player){ player.setPlaybackRate(Math.max(0.25,r)); }
    }
    function ptMute(m){ if(player){ if(m) player.mute(); else player.unMute(); } }
    function ptZoom(s,x,y){ document.getElementById('wrap').style.transform='translate('+x+'px,'+y+'px) scale('+s+')'; }
    </script>
    <script src="https://www.youtube.com/iframe_api"></script>
    </body></html>
    """#
}

/// Breaks the WKUserContentController → handler retain cycle.
@MainActor
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: PlayerController?
    init(owner: PlayerController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.handle(message.body)
    }
}
