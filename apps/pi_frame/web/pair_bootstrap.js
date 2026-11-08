(function () {
  'use strict';

  var TOKEN_KEY = 'pcp_device_token';
  var isItalian = /^it/i.test(navigator.language || '');
  var T = isItalian
    ? {
        pairingTitle: 'Associa di nuovo il dispositivo',
        pairingBody:
          "Questo telefono non è (più) associato al tuo computer. Apri PiFrame sul desktop, vai in Impostazioni → Connessione remota e inquadra il nuovo codice QR.",
        pairFailedTitle: 'Associazione non riuscita',
        pairFailedBody:
          'Il codice QR è scaduto o è già stato usato. Genera un nuovo codice QR da PiFrame sul desktop e riprova.',
        offlineTitle: 'Computer non raggiungibile',
        offlineBody:
          'Controlla che PiFrame sia aperto sul computer, che la connessione remota sia attiva e che Tailscale sia connesso anche su questo telefono. Riprovo automaticamente…',
        stuckTitle: 'Caricamento troppo lungo',
        stuckBody:
          "L'app non si è avviata. Premi Ricarica per svuotare la cache locale e riprovare.",
        retry: 'Riprova',
        reload: 'Ricarica'
      }
    : {
        pairingTitle: 'Pair this device again',
        pairingBody:
          'This phone is no longer paired with your computer. Open PiFrame on the desktop, go to Settings → Remote connection and scan the new QR code.',
        pairFailedTitle: 'Pairing failed',
        pairFailedBody:
          'The QR code expired or was already used. Generate a new QR code in PiFrame on the desktop and try again.',
        offlineTitle: 'Computer unreachable',
        offlineBody:
          'Make sure PiFrame is open on your computer, remote connection is on, and Tailscale is connected on this phone too. Retrying automatically…',
        stuckTitle: 'Taking too long to load',
        stuckBody: 'The app did not start. Tap Reload to clear the local cache and try again.',
        retry: 'Retry',
        reload: 'Reload'
      };

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  function isLoopback() {
    var h = window.location.hostname;
    return h === 'localhost' || h === '127.0.0.1' || h === '[::1]' || h === '::1';
  }

  function storeToken(token) {
    if (!token) return;
    try {
      localStorage.setItem(TOKEN_KEY, token);
    } catch (e) {}
    try {
      sessionStorage.setItem(TOKEN_KEY, token);
    } catch (e) {}
  }

  function readToken() {
    try {
      return localStorage.getItem(TOKEN_KEY) || sessionStorage.getItem(TOKEN_KEY) || null;
    } catch (e) {
      return null;
    }
  }

  function clearToken() {
    try {
      localStorage.removeItem(TOKEN_KEY);
    } catch (e) {}
    try {
      sessionStorage.removeItem(TOKEN_KEY);
    } catch (e) {}
  }

  /** The web app has no service worker: remove any installed by older builds (stale app shell). */
  function dropLegacyCaches() {
    try {
      if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) {
        navigator.serviceWorker.getRegistrations().then(function (regs) {
          regs.forEach(function (r) {
            r.unregister();
          });
        });
      }
      if (window.caches && caches.keys) {
        caches.keys().then(function (keys) {
          keys.forEach(function (k) {
            caches.delete(k);
          });
        });
      }
    } catch (e) {}
  }

  function fetchWithTimeout(url, options, ms) {
    var ctrl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    var timer = ctrl
      ? setTimeout(function () {
          ctrl.abort();
        }, ms)
      : null;
    options = options || {};
    if (ctrl) options.signal = ctrl.signal;
    return fetch(url, options).then(
      function (res) {
        if (timer) clearTimeout(timer);
        return res;
      },
      function (err) {
        if (timer) clearTimeout(timer);
        throw err;
      }
    );
  }

  // ---------------------------------------------------------------------------
  // Status panel (shown instead of an empty page)
  // ---------------------------------------------------------------------------

  var statusEl = null;

  function hideStatus() {
    if (statusEl && statusEl.parentNode) statusEl.parentNode.removeChild(statusEl);
    statusEl = null;
  }

  function showStatus(title, body, buttonLabel, onButton, showSpinner) {
    hideStatus();
    var splash = document.getElementById('pf-splash');
    if (splash) splash.style.display = 'none';
    statusEl = document.createElement('div');
    statusEl.id = 'pf-status';
    if (showSpinner) {
      var sp = document.createElement('div');
      sp.className = 'pf-spinner';
      statusEl.appendChild(sp);
    }
    var h = document.createElement('h1');
    h.textContent = title;
    var p = document.createElement('p');
    p.textContent = body;
    statusEl.appendChild(h);
    statusEl.appendChild(p);
    if (buttonLabel) {
      var b = document.createElement('button');
      b.textContent = buttonLabel;
      b.addEventListener('click', onButton);
      statusEl.appendChild(b);
    }
    document.body.appendChild(statusEl);
  }

  function hideSplash() {
    var splash = document.getElementById('pf-splash');
    if (!splash) return;
    splash.classList.add('pf-hide');
    setTimeout(function () {
      if (splash.parentNode) splash.parentNode.removeChild(splash);
    }, 400);
  }

  // ---------------------------------------------------------------------------
  // iOS viewport pinning: keep touch coordinates aligned with what is drawn
  // ---------------------------------------------------------------------------

  function pinViewport() {
    function resetScroll() {
      if (window.pageXOffset || window.pageYOffset) window.scrollTo(0, 0);
      if (document.scrollingElement) {
        document.scrollingElement.scrollTop = 0;
        document.scrollingElement.scrollLeft = 0;
      }
    }
    window.addEventListener('scroll', resetScroll, { passive: true });
    window.addEventListener('orientationchange', function () {
      setTimeout(resetScroll, 300);
    });
    window.addEventListener('focusout', function () {
      // iOS leaves the page scrolled after the keyboard closes; that shifts every later tap.
      setTimeout(resetScroll, 50);
      setTimeout(resetScroll, 350);
      setTimeout(resetZoomIfNeeded, 400);
    });
    if (window.visualViewport) {
      var vv = window.visualViewport;
      var onVv = function () {
        if (vv.offsetTop !== 0 || vv.offsetLeft !== 0 || window.pageYOffset) resetScroll();
        if (vv.scale > 1.01) resetZoomIfNeeded();
      };
      vv.addEventListener('resize', onVv);
      vv.addEventListener('scroll', onVv);
    }
    // No pinch / double-tap zoom: a zoomed visual viewport also breaks hit-testing.
    ['gesturestart', 'gesturechange', 'gestureend'].forEach(function (name) {
      document.addEventListener(
        name,
        function (e) {
          e.preventDefault();
        },
        { passive: false }
      );
    });
    document.addEventListener(
      'touchmove',
      function (e) {
        if (e.touches && e.touches.length > 1) e.preventDefault();
      },
      { passive: false }
    );
  }

  // ---------------------------------------------------------------------------
  // iOS focus zoom
  // ---------------------------------------------------------------------------

  /**
   * iOS Safari zooms the whole page when an editable element with a font size below 16px gets
   * focus (the composer uses 14.5px: exactly the ~10% "zoomed UI" that cut the header and pushed
   * the button row off screen). Flutter's hidden text-editing element lives inside the glass pane's
   * shadow root, so the rule has to be injected there as well as in the document.
   */
  var NO_ZOOM_CSS =
    'input, textarea, [contenteditable], .flt-text-editing { font-size: 16px !important; }';

  function addNoZoomStyle(root) {
    if (!root || root.querySelector('style[data-pf-nozoom]')) return;
    var st = document.createElement('style');
    st.setAttribute('data-pf-nozoom', '1');
    st.textContent = NO_ZOOM_CSS;
    root.appendChild(st);
  }

  function preventFocusZoom() {
    addNoZoomStyle(document.head);
    function attach() {
      var pane = document.querySelector('flt-glass-pane');
      if (pane && pane.shadowRoot) {
        addNoZoomStyle(pane.shadowRoot);
        return true;
      }
      return false;
    }
    if (attach()) return;
    var obs = new MutationObserver(function () {
      if (attach()) obs.disconnect();
    });
    obs.observe(document.body, { childList: true, subtree: true });
  }

  /** Snaps the page back to 100% if the visual viewport ended up zoomed anyway. */
  function resetZoomIfNeeded() {
    var vv = window.visualViewport;
    if (!vv || vv.scale <= 1.01) return;
    var meta = document.querySelector('meta[name=viewport]');
    if (!meta) return;
    var original = meta.getAttribute('content');
    meta.setAttribute('content', original + ', minimum-scale=1.0');
    setTimeout(function () {
      meta.setAttribute('content', original);
      window.scrollTo(0, 0);
    }, 250);
  }

  // ---------------------------------------------------------------------------
  // Optional on-device diagnostics: open the app with ?pfdebug=1
  // ---------------------------------------------------------------------------

  function viewportDebug() {
    var box = document.createElement('pre');
    box.style.cssText =
      'position:fixed;left:0;right:0;bottom:0;z-index:99999;margin:0;padding:6px 8px;' +
      'font:10px/1.3 monospace;color:#0f0;background:rgba(0,0,0,.78);pointer-events:none;white-space:pre-wrap';
    document.body.appendChild(box);
    var last = 'no touch yet';
    document.addEventListener(
      'pointerdown',
      function (e) {
        last = 'client=' + Math.round(e.clientX) + ',' + Math.round(e.clientY) +
          ' page=' + Math.round(e.pageX) + ',' + Math.round(e.pageY) +
          ' screen=' + Math.round(e.screenX) + ',' + Math.round(e.screenY);
      },
      true
    );
    function render() {
      var vv = window.visualViewport;
      var pane = document.querySelector('flt-glass-pane');
      var r = pane ? pane.getBoundingClientRect() : null;
      box.textContent =
        'standalone=' + (window.navigator.standalone === true) +
        ' dpr=' + window.devicePixelRatio + '\n' +
        'inner=' + window.innerWidth + 'x' + window.innerHeight +
        ' screen=' + screen.width + 'x' + screen.height + '\n' +
        (vv ? 'vv=' + Math.round(vv.width) + 'x' + Math.round(vv.height) +
          ' off=' + Math.round(vv.offsetLeft) + ',' + Math.round(vv.offsetTop) +
          ' scale=' + vv.scale + '\n' : '') +
        'scrollY=' + window.pageYOffset + ' glassPane=' +
        (r ? Math.round(r.left) + ',' + Math.round(r.top) + ' ' + Math.round(r.width) + 'x' + Math.round(r.height) : 'n/a') +
        '\n' + last;
    }
    setInterval(render, 400);
    render();
  }

  // ---------------------------------------------------------------------------
  // Flutter startup
  // ---------------------------------------------------------------------------

  var flutterStarted = false;
  var firstFrame = false;

  function onFirstFrame() {
    if (firstFrame) return;
    firstFrame = true;
    hideStatus();
    hideSplash();
  }
  window.addEventListener('flutter-first-frame', onFirstFrame);
  document.addEventListener('flutter-first-frame', onFirstFrame);

  function hardReload() {
    dropLegacyCaches();
    setTimeout(function () {
      window.location.reload();
    }, 250);
  }

  function startFlutter() {
    if (flutterStarted) return;
    flutterStarted = true;
    var script = document.createElement('script');
    script.src = 'flutter_bootstrap.js';
    script.async = true;
    script.onerror = function () {
      showStatus(T.stuckTitle, T.stuckBody, T.reload, hardReload, false);
    };
    document.body.appendChild(script);

    // Watchdog: never leave the user on an empty background.
    setTimeout(function () {
      if (!firstFrame) showStatus(T.stuckTitle, T.stuckBody, T.reload, hardReload, true);
    }, 30000);
  }

  /**
   * Checks the stored credential BEFORE downloading the ~10MB app. Distinguishes "needs pairing"
   * from "computer unreachable" and shows a real message instead of a blank page.
   */
  function preflight() {
    var token = readToken();
    var headers = {};
    if (token) headers['Authorization'] = 'Bearer ' + token;
    fetchWithTimeout(
      '/api/session-bootstrap',
      { credentials: 'same-origin', cache: 'no-store', headers: headers },
      8000
    )
      .then(function (res) {
        if (res.status === 200) {
          return res.json().then(function (data) {
            // Refresh the stored copy (the cookie may have outlived a purged localStorage).
            if (data && data.token) storeToken(data.token);
            hideStatus();
            startFlutter();
          });
        }
        if (res.status === 401 || res.status === 403) {
          if (token) clearToken();
          showStatus(T.pairingTitle, T.pairingBody, null, null, false);
          return;
        }
        throw new Error('HTTP ' + res.status);
      })
      .catch(function () {
        showStatus(T.offlineTitle, T.offlineBody, T.retry, preflight, true);
        retryTimer = setTimeout(preflight, 5000);
      });
    if (retryTimer) {
      clearTimeout(retryTimer);
      retryTimer = null;
    }
  }
  var retryTimer = null;

  function pairWith(secret) {
    fetchWithTimeout(
      '/api/remote/pair',
      {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pairingSecret: secret })
      },
      15000
    )
      .then(function (res) {
        return res.json().catch(function () {
          return {};
        });
      })
      .then(function (data) {
        if (data && data.deviceToken) {
          storeToken(data.deviceToken);
          startFlutter();
        } else if (readToken()) {
          // Stale/used QR link, but this device may already hold a valid credential.
          preflight();
        } else {
          showStatus(T.pairFailedTitle, T.pairFailedBody, null, null, false);
        }
      })
      .catch(function () {
        showStatus(T.offlineTitle, T.offlineBody, T.retry, function () {
          pairWith(secret);
        }, true);
      });
  }

  // ---------------------------------------------------------------------------
  // Entry point
  // ---------------------------------------------------------------------------

  dropLegacyCaches();
  pinViewport();
  preventFocusZoom();
  if (/[?&]pfdebug=1/.test(window.location.search)) viewportDebug();

  try {
    var hash = window.location.hash || '';
    if (hash.charAt(0) === '#') hash = hash.slice(1);
    var pairSecret = new URLSearchParams(hash).get('pair');

    if (pairSecret) {
      // Wipe the sensitive secret from browser history and URL bar immediately (M2)
      window.history.replaceState(null, '', window.location.pathname + window.location.search);
      pairWith(pairSecret);
      return;
    }

    if (isLoopback()) {
      // Local desktop browser: authenticated by the loopback cookie, nothing to pre-check.
      startFlutter();
      return;
    }

    preflight();
    return;
  } catch (e) {
    console.warn('[PairBootstrap] Error during bootstrap:', e);
  }

  startFlutter();
})();
