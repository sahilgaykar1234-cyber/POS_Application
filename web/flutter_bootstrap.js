{{flutter_js}}
{{flutter_build_config}}

(function () {
  // 1) Remove the old (deprecated) Flutter service worker and its caches.
  //    A phone that opened an older version could otherwise keep serving
  //    stale files and show a blank page.
  try {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistrations().then(function (regs) {
        regs.forEach(function (r) { r.unregister(); });
      }).catch(function () {});
    }
    if (window.caches && caches.keys) {
      caches.keys().then(function (keys) {
        keys.forEach(function (k) { caches.delete(k); });
      }).catch(function () {});
    }
  } catch (e) {}

  // 2) Load the rendering engine from this site (build/web/canvaskit/), not
  //    from gstatic.com, which some iPhones/networks/blockers stop.
  //    No serviceWorkerSettings: no new service worker is registered.
  function start() {
    try {
      _flutter.loader.load({
        config: { canvasKitBaseUrl: 'canvaskit/' },
      }).catch(function (e) {
        if (window.cafePosStartupError) window.cafePosStartupError(e);
      });
    } catch (e) {
      if (window.cafePosStartupError) window.cafePosStartupError(e);
    }
  }

  // 3) Start once the self-hosted Firebase SDK is ready (see index.html);
  //    never wait more than 15 s for it.
  var started = false;
  function once() { if (!started) { started = true; start(); } }
  (window.cafePosFirebaseReady || Promise.resolve()).then(once, once);
  setTimeout(once, 15000);
})();
