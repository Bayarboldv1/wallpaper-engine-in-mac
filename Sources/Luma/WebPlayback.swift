import Foundation

/// Common playback control for the desktop and preview web renderers.
/// rAF, CSS animations, and media pause in place; arbitrary timers and workers
/// remain under the imported page's control.
enum WebPlayback {
    static func updateScript(paused: Bool, muted: Bool) -> String {
        "window.__lumaSetPlayback && window.__lumaSetPlayback(\(paused), \(muted));"
    }

    static let bootstrap = #"""
    (() => {
      if (window.__lumaSetPlayback) return;
      let paused = false, muted = true, nextID = 0;
      const requests = new Map();
      const resumeMedia = new WeakSet();
      const raf = window.requestAnimationFrame.bind(window);
      const cancel = window.cancelAnimationFrame.bind(window);
      function schedule(id, entry) {
        entry.nativeID = raf(now => {
          entry.nativeID = null;
          if (paused) return;
          requests.delete(id);
          entry.callback(now);
        });
      }
      window.requestAnimationFrame = callback => {
        const id = ++nextID, entry = { callback, nativeID: null };
        requests.set(id, entry);
        if (!paused) schedule(id, entry);
        return id;
      };
      window.cancelAnimationFrame = id => {
        const entry = requests.get(id);
        if (entry && entry.nativeID !== null) cancel(entry.nativeID);
        requests.delete(id);
      };
      function updateMedia() {
        document.querySelectorAll('video, audio').forEach(media => {
          media.muted = muted;
          if (paused && !media.paused) {
            resumeMedia.add(media);
            media.pause();
          } else if (!paused && resumeMedia.has(media)) {
            resumeMedia.delete(media);
            const result = media.play();
            if (result && result.catch) result.catch(() => {});
          }
        });
      }
      function updateStyle() {
        let style = document.getElementById('__luma_pause_style');
        if (paused && !style && document.documentElement) {
          style = document.createElement('style');
          style.id = '__luma_pause_style';
          style.textContent = '*, *::before, *::after { animation-play-state: paused !important; }';
          (document.head || document.documentElement).appendChild(style);
        } else if (!paused && style) {
          style.remove();
        }
      }
      function updateFrames() {
        document.querySelectorAll('iframe').forEach(frame => {
          try {
            if (frame.contentWindow.__lumaSetPlayback) frame.contentWindow.__lumaSetPlayback(paused, muted);
          } catch (_) {}
        });
      }
      window.__lumaSetPlayback = (nextPaused, nextMuted) => {
        const wasPaused = paused;
        paused = !!nextPaused;
        muted = !!nextMuted;
        if (paused) {
          requests.forEach(entry => {
            if (entry.nativeID !== null) cancel(entry.nativeID);
            entry.nativeID = null;
          });
        }
        try {
          if (typeof window.wallpaperSetPaused === 'function') window.wallpaperSetPaused(paused);
          if (typeof window.wallpaperSetMuted === 'function') window.wallpaperSetMuted(muted);
        } catch (_) {}
        if (wasPaused && !paused) requests.forEach((entry, id) => {
          if (entry.nativeID === null) schedule(id, entry);
        });
        updateStyle();
        updateMedia();
        updateFrames();
      };
      document.addEventListener('play', event => {
        if (!(event.target instanceof HTMLMediaElement)) return;
        event.target.muted = muted;
        if (paused) { resumeMedia.add(event.target); event.target.pause(); }
      }, true);
      document.addEventListener('DOMContentLoaded', () => {
        updateStyle();
        updateMedia();
        updateFrames();
        new MutationObserver(() => {
          updateStyle(); updateMedia(); updateFrames();
        }).observe(document.documentElement, { childList: true, subtree: true });
      });
    })();
    """#
}
