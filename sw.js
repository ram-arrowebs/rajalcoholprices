// Service worker: makes the price list usable offline.
//
//  - App shell (this page, CSS, JS, icons) and the pinned CDN libraries are
//    cached on install. Fonts referenced from the CDN stylesheets are
//    discovered by parsing the CSS so the first visit is fully offline-capable.
//  - data/*.json is network-first: fresh prices when online, the last
//    downloaded copy when not. A fallback response carries X-Offline-Copy: 1
//    so the page can say so.
//  - Everything else on the CDN allow-list is cache-first (versions are
//    pinned, so the bytes never change).
//
// Bump CACHE whenever the shell or CDN list changes so old entries are purged.
var CACHE = "rajprices-v2";

var SHELL = [
  "./",
  "./index.html",
  "./styles.css",
  "./a2hs.js",
  "./manifest.webmanifest",
  "./qr-code.png",
  "./icon/favicon-32x32.png",
  "./icon/android-icon-192x192.png",
  "./icon/android-icon-512x512.png",
];

// Fetched best-effort: a failure here must not block install.
var OPTIONAL = [
  "./data/prices.json",
  "./data/meta.json",
  "https://code.jquery.com/jquery-3.6.0.min.js",
  "https://cdn.datatables.net/1.11.0/js/jquery.dataTables.min.js",
  "https://cdn.datatables.net/1.11.0/js/dataTables.bootstrap5.min.js",
  "https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/5.0.1/css/bootstrap.min.css",
  "https://cdn.datatables.net/1.11.0/css/dataTables.bootstrap5.min.css",
  "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.8.3/font/bootstrap-icons.css",
  "https://fonts.googleapis.com/css2?family=Roboto+Condensed:wght@400;700&display=swap",
];

var CDN_HOSTS = [
  "code.jquery.com",
  "cdn.datatables.net",
  "cdnjs.cloudflare.com",
  "cdn.jsdelivr.net",
  "fonts.googleapis.com",
  "fonts.gstatic.com",
];

// Fetch a URL and store it; returns the response text for CSS so callers can
// follow url(...) references. Never rejects.
function cacheOne(cache, url) {
  return fetch(url)
    .then(function (res) {
      if (!res.ok) throw new Error(url + " -> " + res.status);
      var copy = res.clone();
      return cache.put(url, res).then(function () {
        return /\.css(\?|$)|fonts\.googleapis/.test(url) ? copy.text() : null;
      });
    })
    .then(function (css) {
      if (!css) return;
      var fontUrls = [];
      css.replace(/url\((['"]?)([^'")]+)\1\)/g, function (_, q, ref) {
        if (ref.indexOf("data:") !== 0) fontUrls.push(new URL(ref, url).href);
      });
      return Promise.all(fontUrls.map(function (f) { return cacheOne(cache, f); }));
    })
    .catch(function (err) {
      console.warn("[sw] could not precache", url, err);
    });
}

self.addEventListener("install", function (event) {
  event.waitUntil(
    caches.open(CACHE).then(function (cache) {
      return cache.addAll(SHELL).then(function () {
        return Promise.all(OPTIONAL.map(function (u) { return cacheOne(cache, u); }));
      });
    }).then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(
        keys.filter(function (k) { return k !== CACHE; })
            .map(function (k) { return caches.delete(k); })
      );
    }).then(function () { return self.clients.claim(); })
  );
});

function withOfflineHeader(res) {
  var headers = new Headers(res.headers);
  headers.set("X-Offline-Copy", "1");
  return res.blob().then(function (body) {
    return new Response(body, { status: res.status, statusText: res.statusText, headers: headers });
  });
}

// Try the network, fall back to the cached copy (marked when `mark` is set).
function networkFirst(request, mark) {
  return caches.open(CACHE).then(function (cache) {
    return fetch(request)
      .then(function (res) {
        if (res.ok) cache.put(request, res.clone());
        return res;
      })
      .catch(function () {
        return cache.match(request).then(function (hit) {
          if (!hit) throw new Error("offline and not cached: " + request.url);
          return mark ? withOfflineHeader(hit) : hit;
        });
      });
  });
}

// Serve from cache, otherwise fetch and remember for next time.
function cacheFirst(request) {
  return caches.open(CACHE).then(function (cache) {
    return cache.match(request).then(function (hit) {
      if (hit) return hit;
      return fetch(request).then(function (res) {
        if (res.ok || res.type === "opaque") cache.put(request, res.clone());
        return res;
      });
    });
  });
}

self.addEventListener("fetch", function (event) {
  var req = event.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);

  if (req.mode === "navigate") {
    event.respondWith(
      networkFirst(req, false).catch(function () { return caches.match("./index.html"); })
    );
    return;
  }

  if (url.origin === self.location.origin) {
    var isData = /\/data\/[^/]+\.json$/.test(url.pathname);
    event.respondWith(networkFirst(req, isData));
    return;
  }

  if (CDN_HOSTS.indexOf(url.hostname) !== -1) {
    event.respondWith(cacheFirst(req));
  }
});
