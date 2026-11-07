import Foundation
import WebKit

/// Drives a YouTube player inside a WKWebView.
///
/// The page hosts YouTube's official IFrame player and identifies itself the way YouTube asks
/// apps to: its origin (and so the embed's Referer) is the app's bundle ID as a URL. Without
/// that, YouTube refuses to play (errors 152/153).
///
/// For frame precision, a small script is injected into YouTube's embed frame itself, where it
/// can drive the `<video>` element directly ("precise mode"): exact `currentTime` seeks, any
/// playback rate (0.1×), and the real frame rate from `requestVideoFrameCallback`. Commands
/// for it are evaluated in that frame. Until it reports in, everything goes through the IFrame
/// API ("basic mode": rates down to 0.25×).
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
    @Published var muted = false { didSet { js("ptMute(\(muted))"); frameJS("__pt.mute(\(muted))") } }
    /// Closed captions, remembered between launches. YouTube's own caption track, in the
    /// device language when the video has it.
    @Published var captionsOn = UserDefaults.standard.bool(forKey: "captionsOn") {
        didSet { UserDefaults.standard.set(captionsOn, forKey: "captionsOn"); applyCaptions() }
    }
    /// Whether the current video has any captions (nil until YouTube says).
    @Published private(set) var captionsAvailable: Bool?

    @Published var loopA: Double?
    @Published var loopB: Double?
    @Published var loopOn = false

    /// Called with (videoID, position) when it's worth remembering where we are.
    var onSavePosition: ((String, Double) -> Void)?
    var onSaveFPS: ((String, Double?) -> Void)?
    /// A playlist moved on to another video: (video ID, playlist ID, index). Returns that video's
    /// saved frame-rate override, if any.
    var onVideoChanged: ((String, String?, Int?) -> Double?)?

    /// The YouTube playlist being played, if any, and where in it we are (0-based).
    @Published private(set) var playlistID: String?
    @Published private(set) var playlistIndex: Int?
    @Published private(set) var playlistCount: Int?

    var fps: Double { fpsOverride ?? detectedFPS ?? 30 }
    var frameDuration: Double { 1 / fps }
    var currentFrame: Int { Int((currentTime * fps).rounded(.down)) }

    let webView: WKWebView
    private var desiredRate: Double = 1
    private var lastSaved = Date.distantPast
    /// YouTube's embed frame, once the injected script there has found the video.
    private var videoFrame: WKFrameInfo?
    /// Fallback: the embed page loaded directly (not in an iframe), so the script surely runs in it.
    private var directMode = false
    private var triedDirect = false
    private var loadedStart: Double = 0
    private var fallbackTask: Task<Void, Never>?

    /// The page's origin. YouTube asks embedding apps to send their bundle ID as the referrer.
    static let origin: String = {
        let id = Bundle.main.bundleIdentifier ?? "com.coralcoder.precisiontube"
        return "https://\(id.lowercased())"
    }()

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.frameScript, injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: false, in: .page))
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        controller.add(MessageProxy(owner: self), contentWorld: .page, name: "pt")
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }

    // MARK: Commands

    func load(videoID: String, start: Double, fpsOverride: Double? = nil, playlist: String? = nil, index: Int? = nil) {
        if let old = self.videoID, old != videoID { savePosition(force: true) }
        self.videoID = videoID
        playlistID = playlist
        playlistIndex = index
        playlistCount = nil
        captionsAvailable = nil
        currentTime = start
        duration = 0
        isPlaying = false
        ready = false
        preciseMode = false
        videoFrame = nil
        errorMessage = nil
        detectedFPS = nil
        self.fpsOverride = fpsOverride
        loopA = nil; loopB = nil; loopOn = false
        directMode = false
        triedDirect = false
        loadedStart = max(0, start)
        loadInFrame()
    }

    private func loadInFrame() {
        guard let videoID else { return }
        fallbackTask?.cancel()
        directMode = false
        videoFrame = nil
        preciseMode = false
        let html = Self.html
            .replacingOccurrences(of: "__VIDEO_ID__", with: videoID)
            .replacingOccurrences(of: "__START__", with: String(format: "%.3f", currentTime))
            .replacingOccurrences(of: "__ORIGIN__", with: Self.origin)
            .replacingOccurrences(of: "__LIST__", with: (playlistID ?? "").filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
            .replacingOccurrences(of: "__INDEX__", with: String(playlistIndex ?? -1))
        webView.loadHTMLString(html, baseURL: URL(string: Self.origin + "/"))
        // If the script inside YouTube's frame never reports in, load the embed page directly.
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, !Task.isCancelled, self.videoFrame == nil, self.ready,
                  self.errorMessage == nil, !self.triedDirect else { return }
            self.loadDirect()
        }
    }

    private func loadDirect() {
        guard let videoID else { return }
        triedDirect = true
        directMode = true
        videoFrame = nil
        var comps = URLComponents(string: "https://www.youtube.com/embed/\(videoID)")!
        comps.queryItems = [
            URLQueryItem(name: "playsinline", value: "1"), URLQueryItem(name: "controls", value: "0"),
            URLQueryItem(name: "rel", value: "0"), URLQueryItem(name: "iv_load_policy", value: "3"),
            URLQueryItem(name: "fs", value: "0"), URLQueryItem(name: "disablekb", value: "1"),
            URLQueryItem(name: "start", value: String(Int(currentTime))),
            URLQueryItem(name: "list", value: playlistID), URLQueryItem(name: "index", value: playlistIndex.map { String($0) }),
            URLQueryItem(name: "origin", value: Self.origin), URLQueryItem(name: "widget_referrer", value: Self.origin),
        ]
        comps.queryItems = comps.queryItems?.filter { $0.value != nil }
        var request = URLRequest(url: comps.url!)
        request.setValue(Self.origin + "/", forHTTPHeaderField: "Referer")
        webView.load(request)
        // Still nothing? Go back to the iframe player, which at least plays.
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled, self.directMode, self.videoFrame == nil else { return }
            self.loadInFrame()
        }
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        if directMode { frameJS("__pt.play()") } else { js("ptPlay()") }
        isPlaying = true
    }

    func pause() {
        frameJS("__pt.pause()")
        js("ptPause()")
        isPlaying = false
        savePosition(force: true)
    }

    func step(frames: Int) {
        isPlaying = false
        currentTime = max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude, currentTime + Double(frames) * frameDuration))
        if videoFrame != nil {
            js("ptPause()")
            frameJS("__pt.step(\(frames), \(fps))")
        } else {
            js("ptStep(\(frames), \(fps))")
        }
    }

    func jump(seconds: Double) { seek(to: currentTime + seconds) }

    func nextVideo() { js("ptNext()") }
    func previousVideo() { js("ptPrev()") }

    func seek(to time: Double) {
        let t = max(0, duration > 0 ? min(time, duration - 0.01) : time)
        currentTime = t
        if videoFrame != nil { frameJS("__pt.seek(\(t))") } else { js("ptSeek(\(t))") }
    }

    func setRate(_ r: Double) {
        desiredRate = r
        rate = r
        if videoFrame != nil { frameJS("__pt.rate(\(r))") } else { js("ptRate(\(r))") }
    }

    func setZoom(scale: CGFloat, offset: CGSize) {
        if directMode { frameJS("__pt.zoom(\(scale), \(offset.width), \(offset.height))") }
        else { js("ptZoom(\(scale), \(offset.width), \(offset.height))") }
    }

    func savePosition(force: Bool = false) {
        guard let id = videoID else { return }
        if force || Date().timeIntervalSince(lastSaved) > 5 {
            lastSaved = Date()
            // Finished (or nearly): next time, start from the beginning.
            let position = duration > 0 && currentTime > duration - 2 ? 0 : currentTime
            onSavePosition?(id, position)
        }
    }

    private func saveFPS() {
        if let id = videoID { onSaveFPS?(id, fpsOverride) }
    }

    private func js(_ script: String) {
        guard videoID != nil else { return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private var captionLanguage: String {
        (Locale.current.language.languageCode?.identifier ?? "en").filter { $0.isLetter }
    }

    private func applyCaptions() {
        frameJS("__pt.captions(\(captionsOn), '\(captionLanguage)')")
        js("ptCaptions(\(captionsOn), '\(captionLanguage)')")
    }

    private func frameJS(_ script: String) {
        guard let frame = videoFrame else { return }
        webView.evaluateJavaScript("window.__pt && " + script, in: frame, in: .page, completionHandler: nil)
    }

    // MARK: Messages from the page

    fileprivate func handle(_ body: Any, frame: WKFrameInfo) {
        guard let msg = body as? [String: Any], let type = msg["type"] as? String else { return }
        let fromVideoFrame = (msg["src"] as? String) == "frame"
        switch type {
        case "frame-ready":
            fallbackTask?.cancel()
            videoFrame = frame
            preciseMode = true
            frameJS("__pt.rate(\(desiredRate))")
            applyCaptions()
            if directMode {
                // No IFrame API here: show the first frame, then wait paused.
                ready = true
                let start = currentTime
                frameJS("__pt.mute(\(muted)); __pt.play(); setTimeout(function(){ __pt.pause(); __pt.seek(\(start)); }, 500)")
            }
        case "time":
            let d = (msg["d"] as? Double) ?? 0
            if d.isFinite, d > 0, !fromVideoFrame || duration == 0 { duration = d }
            // Once the video frame reports, its times are the exact ones.
            if preciseMode && !fromVideoFrame { return }
            let t = (msg["t"] as? Double) ?? currentTime
            let playing = (msg["playing"] as? Bool) ?? false
            if let r = msg["rate"] as? Double, r > 0 { rate = r }
            if t.isFinite { currentTime = t }
            if isPlaying && !playing { savePosition(force: true) }
            isPlaying = playing
            if playing { savePosition() }
            if loopOn, playing, let a = loopA, let b = loopB, b > a, t >= b { seek(to: a) }
        case "fps":
            if let raw = msg["fps"] as? Double { detectedFPS = Self.snap(fps: raw) }
        case "video":
            guard let id = msg["id"] as? String, !id.isEmpty else { break }
            if let i = msg["index"] as? Int, i >= 0 { playlistIndex = i }
            if let c = msg["count"] as? Int, c > 0 { playlistCount = c }
            guard id != videoID else { break }
            // The playlist moved on: the new video gets its own place, marks and settings.
            savePosition(force: true)
            videoID = id
            currentTime = 0
            duration = 0
            detectedFPS = nil
            loopA = nil; loopB = nil; loopOn = false
            fpsOverride = onVideoChanged?(id, playlistID, playlistIndex) ?? nil
            if desiredRate != 1 { setRate(desiredRate) }
            captionsAvailable = nil
            applyCaptions()
        case "captions":
            let n = (msg["available"] as? Int) ?? 0
            if n > 0 { captionsAvailable = true } else if captionsAvailable == nil { captionsAvailable = false }
        case "ready":
            ready = true
            applyCaptions()
            if desiredRate != 1, videoFrame == nil { js("ptRate(\(desiredRate))") }
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
        case 152, 153: return "YouTube wouldn't load the player here (error \(code)). Try again, or open it in YouTube."
        default: return "YouTube couldn't play this video (error \(code))."
        }
    }

    // MARK: Page

    /// Runs inside YouTube's embed frame (and is a no-op everywhere else).
    private static let frameScript = #"""
    (function(){
      if (!/(^|\.)youtube(-nocookie)?\.com$/.test(location.hostname) || location.pathname.indexOf('/embed/') !== 0) return;
      if (window.__pt) return;
      // Hide YouTube's own overlays (big play button, title bar, "More videos", logo, cards);
      // the app has its own controls. Errors and the loading spinner stay visible.
      var css=document.createElement('style');
      css.textContent=['.ytp-large-play-button','.ytp-chrome-top','.ytp-chrome-bottom','.ytp-gradient-top',
        '.ytp-gradient-bottom','.ytp-title','.ytp-show-cards-title','.ytp-pause-overlay','.ytp-pause-overlay-container',
        '.ytp-watermark','.ytp-youtube-button','.ytp-impression-link','.ytp-ce-element','.ytp-cards-teaser',
        '.ytp-cards-button','.ytp-paid-content-overlay','.ytp-endscreen-content','.ytp-videowall-still',
        '.ytp-cued-thumbnail-overlay','.ytp-bezel','.ytp-bezel-text-wrapper','.ytp-tooltip','.ytp-contextmenu',
        '.ytp-overflow-button','.ytp-share-button','.ytp-watch-later-button','.ytp-copylink-button',
        '.branding-img','.iv-branding','.annotation','.ytp-suggested-action','.ytp-featured-product',
        '.ytp-chapter-container','.ytp-player-content.ytp-iv-player-content',
        '.html5-video-player > *:not(.html5-video-container):not(.ytp-spinner):not(.ytp-error):not(.ytp-error-content):not(.ytp-caption-window-container)']
        .join(',');
      var rule=css.textContent+'{display:none !important;}';
      css.textContent=rule;
      // YouTube's page security policy can block an added <style>; a constructed stylesheet
      // and inline styles set from script aren't affected, so use all three.
      try{ (document.head||document.documentElement).appendChild(css); }catch(e){}
      try{ var sheet=new CSSStyleSheet(); sheet.replaceSync(rule); document.adoptedStyleSheets=document.adoptedStyleSheets.concat([sheet]); }catch(e){}
      var hideSelectors=rule.slice(0, rule.indexOf('{'));
      var captionsOn=false, captionLang='en';
      function ytPlayer(){ return document.getElementById('movie_player') || document.querySelector('.html5-video-player'); }
      function applyCaptions(tries){
        var mp=ytPlayer();
        if (captionsOn){
          document.querySelectorAll('.ytp-caption-window-container').forEach(function(el){ el.style.removeProperty('display'); });
        }
        try{
          if (!mp || !mp.loadModule){ if ((tries||0)<20) setTimeout(function(){ applyCaptions((tries||0)+1); }, 500); return; }
          if (!captionsOn){ mp.unloadModule('captions'); return; }
          mp.loadModule('captions');
          var list=(mp.getOption && mp.getOption('captions','tracklist')) || [];
          if (!list.length){
            if ((tries||0)<16){ setTimeout(function(){ applyCaptions((tries||0)+1); }, 500); return; }
            post({type:'captions', available:0}); return;
          }
          var pick=list.filter(function(t){ return (t.languageCode||'').indexOf(captionLang)===0; })[0] || list[0];
          mp.setOption('captions','track',{languageCode:pick.languageCode});
          post({type:'captions', available:list.length});
        }catch(e){}
      }
      var keepSelector='.ytp-spinner,.ytp-error,.ytp-error-content,script,style,link';
      function hideOverlays(){
        try{ document.querySelectorAll(hideSelectors).forEach(function(el){ el.style.setProperty('display','none','important'); }); }catch(e){}
        // Whatever YouTube calls its overlays: keep only the chain of elements that holds the
        // video (plus the spinner and error messages) and hide every sibling along it.
        try{
          var v=document.querySelector('video'); if (!v) return;
          var n=v;
          while (n && n.parentElement && n!==document.body && n!==document.documentElement){
            var p=n.parentElement;
            for (var c=p.firstElementChild; c; c=c.nextElementSibling){
              if (c===n || c.tagName==='VIDEO') continue;
              if (c.matches(keepSelector) || c.querySelector('.ytp-error:not([style*="display: none"]), video')) continue;
              if (captionsOn && (c.matches('.ytp-caption-window-container') || c.querySelector('.ytp-caption-window-container'))) continue;
              if (c.style.getPropertyValue('display')!=='none') c.style.setProperty('display','none','important');
            }
            n=p;
          }
        }catch(e){}
      }
      hideOverlays();
      setInterval(hideOverlays, 150);
      document.addEventListener('pause', hideOverlays, true);
      document.addEventListener('seeking', hideOverlays, true);
      document.addEventListener('seeked', hideOverlays, true);
      var vid=null, desiredRate=1, frameStart=null, pendingSeek=null, lastKey='', announced=false;
      function post(m){ m.src='frame'; try{ window.webkit.messageHandlers.pt.postMessage(m); }catch(e){} }
      function hook(v){
        if (v.__pt) return; v.__pt=true;
        v.addEventListener('seeking', function(){ frameStart=null; });
        v.addEventListener('seeked', function(){
          if (pendingSeek!==null){ var t=pendingSeek; pendingSeek=null; v.currentTime=t; }
          report(true);
        });
        var fixRate=function(){ if (Math.abs(v.playbackRate-desiredRate)>0.001) v.playbackRate=desiredRate; };
        v.addEventListener('ratechange', fixRate);
        v.addEventListener('playing', fixRate);
        if (v.requestVideoFrameCallback){
          var lastMT=-1, lastPF=-1, deltas=[];
          var cb=function(now, md){
            frameStart=md.mediaTime;
            if (!v.paused && lastPF>=0 && md.presentedFrames===lastPF+1){
              var dt=md.mediaTime-lastMT;
              if (dt>0.004 && dt<0.1){
                deltas.push(dt);
                if (deltas.length>=40){ deltas.sort(function(a,b){return a-b;}); var med=deltas[20]; deltas=[]; post({type:'fps', fps:1/med}); }
              }
            }
            lastMT=md.mediaTime; lastPF=md.presentedFrames;
            v.requestVideoFrameCallback(cb);
          };
          v.requestVideoFrameCallback(cb);
        }
      }
      function grab(){
        if (vid && vid.isConnected) return vid;
        vid=document.querySelector('video');
        if (vid){ hook(vid); if (!announced){ announced=true; post({type:'frame-ready'}); } }
        return vid;
      }
      function report(force){
        var v=grab(); if (!v) return;
        var t=(pendingSeek!==null)?pendingSeek:v.currentTime;
        var playing=!v.paused && !v.ended;
        var d=isFinite(v.duration)?v.duration:0;
        var key=t.toFixed(3)+'|'+playing+'|'+v.playbackRate;
        if (!force && key===lastKey) return;
        lastKey=key;
        post({type:'time', t:t, d:d, playing:playing, rate:v.playbackRate});
      }
      function seek(t){
        var v=grab(); if (!v) return;
        if (v.seeking) pendingSeek=t; else v.currentTime=t;
        report(true);
      }
      window.__pt={
        seek: seek,
        step: function(n, fps){
          var v=grab(); if (!v) return;
          if (!v.paused) v.pause();
          var cur=(pendingSeek!==null)?pendingSeek:v.currentTime;
          var base=(frameStart!==null && Math.abs(frameStart-cur)<1.5/fps) ? frameStart+0.2/fps : cur;
          seek(Math.max(0, base+n/fps));
        },
        rate: function(r){ desiredRate=r; var v=grab(); if (v) v.playbackRate=r; },
        pause: function(){ var v=grab(); if (v) v.pause(); },
        mute: function(m){ var v=grab(); if (v) v.muted=!!m; },
        captions: function(on, lang){ captionsOn=!!on; captionLang=lang||'en'; applyCaptions(0); },
        zoom: function(s,x,y){ var v=grab(); var t=v ? (v.closest('.html5-video-player') || document.body) : document.body;
          t.style.transformOrigin='50% 50%'; t.style.transform='translate('+x+'px,'+y+'px) scale('+s+')'; },
        play: function(){ var v=grab(); if (v) v.play(); }
      };
      setInterval(function(){ grab(); report(false); }, 66);
    })();
    """#

    private static let html = #"""
    <!DOCTYPE html>
    <html><head>
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
    <meta name="referrer" content="origin">
    <style>
      html,body{margin:0;padding:0;background:#000;width:100%;height:100%;overflow:hidden}
      #wrap{position:absolute;left:0;top:0;width:100%;height:100%;transform-origin:50% 50%}
      #player,iframe{width:100%;height:100%;border:0;display:block}
    </style></head>
    <body><div id="wrap"><div id="player"></div></div>
    <script>
    var player=null, lastKey='', lastVid='', settleUntil=0;
    var START=__START__, LIST='__LIST__', INDEX=__INDEX__, aligned=(LIST==='' || INDEX>=0);
    function post(m){ m.src='main'; try{ window.webkit.messageHandlers.pt.postMessage(m); }catch(e){} }
    function onYouTubeIframeAPIReady(){
      player=new YT.Player('player',{videoId:'__VIDEO_ID__', width:'100%', height:'100%',
        playerVars:{playsinline:1, controls:0, rel:0, fs:0, iv_load_policy:3, disablekb:1,
                    start:Math.floor(START), origin:'__ORIGIN__', widget_referrer:'__ORIGIN__'},
        events:{
          onReady:function(){
            if (LIST){
              // Play the whole playlist from this video; YouTube moves on to the next one by itself.
              try{ player.loadPlaylist({list:LIST, listType:'playlist', index:Math.max(0,INDEX), startSeconds:START}); }catch(e){}
              setTimeout(function(){ try{ if (aligned){ player.pauseVideo(); if (START>0) player.seekTo(START, true); } }catch(e){} }, 900);
            } else {
              try{ player.playVideo(); }catch(e){}
              setTimeout(function(){ try{ player.pauseVideo(); if (START>0) player.seekTo(START, true); }catch(e){} }, 400);
            }
            post({type:'ready'});
            setInterval(function(){ report(false); checkVideo(); }, 100);
          },
          onStateChange:function(){ report(true); },
          onError:function(e){ post({type:'error', code:e.data}); }
        }});
    }
    function report(force){
      if (!player || !player.getCurrentTime) return;
      var t=player.getCurrentTime(), playing=player.getPlayerState()===1, rate=player.getPlaybackRate();
      var d=player.getDuration ? player.getDuration() : 0;
      var key=t.toFixed(3)+'|'+playing+'|'+d+'|'+rate;
      if (!force && key===lastKey) return;
      lastKey=key;
      post({type:'time', t:t, d:d||0, playing:playing, rate:rate});
    }
    function checkVideo(){
      if (!player || !player.getVideoData) return;
      var pl=(player.getPlaylist && player.getPlaylist()) || [];
      if (!aligned){
        // The link had no index: find this video in the playlist and start there.
        if (!pl.length) return;
        aligned=true;
        var i=pl.indexOf('__VIDEO_ID__');
        if (i>0 && i!==player.getPlaylistIndex()){
          player.playVideoAt(i);
          settleUntil=Date.now()+2000;
          setTimeout(function(){ try{ player.pauseVideo(); if (START>0) player.seekTo(START, true); }catch(e){} }, 900);
          return;
        }
        setTimeout(function(){ try{ player.pauseVideo(); if (START>0) player.seekTo(START, true); }catch(e){} }, 300);
      }
      if (Date.now()<settleUntil) return;
      var vd=player.getVideoData(), id=vd && vd.video_id;
      if (id && id!==lastVid){
        lastVid=id;
        post({type:'video', id:id, index:(player.getPlaylistIndex ? player.getPlaylistIndex() : -1), count:pl.length});
      }
    }
    function ptNext(){ if (player && player.nextVideo) player.nextVideo(); }
    function ptPrev(){ if (player && player.previousVideo) player.previousVideo(); }
    function ptPlay(){ if (player) player.playVideo(); }
    function ptPause(){ if (player) player.pauseVideo(); }
    function ptSeek(t){ if (player){ player.seekTo(t, true); report(true); } }
    function ptStep(n, fps){ if (player){ player.pauseVideo(); player.seekTo(Math.max(0, player.getCurrentTime()+n/fps), true); report(true); } }
    function ptRate(r){ if (player) player.setPlaybackRate(Math.max(0.25, r)); }
    function ptCaptions(on, lang){
      if (!player || !player.loadModule) return;
      try{
        if (!on){ player.unloadModule('captions'); return; }
        player.loadModule('captions');
        setTimeout(function(){
          try{
            var l=player.getOption('captions','tracklist') || [];
            var p=l.filter(function(t){ return (t.languageCode||'').indexOf(lang)===0; })[0] || l[0];
            if (p) player.setOption('captions','track',{languageCode:p.languageCode});
            post({type:'captions', available:l.length});
          }catch(e){}
        }, 2000);
      }catch(e){}
    }
    function ptMute(m){ if (player){ if (m) player.mute(); else player.unMute(); } }
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
        owner?.handle(message.body, frame: message.frameInfo)
    }
}
