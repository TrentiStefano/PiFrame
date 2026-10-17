(function () {
  function startFlutter() {
    var script = document.createElement('script');
    script.src = 'flutter_bootstrap.js';
    script.async = true;
    document.body.appendChild(script);
  }

  try {
    var hash = window.location.hash || '';
    if (hash.startsWith('#')) {
      hash = hash.slice(1);
    }
    var params = new URLSearchParams(hash);
    var pairSecret = params.get('pair');

    if (pairSecret) {
      // Wipe the sensitive secret from browser history and URL bar immediately (M2)
      window.history.replaceState(null, '', window.location.pathname);

      fetch('/api/remote/pair', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pairingSecret: pairSecret })
      })
        .then(function (res) {
          return res.json();
        })
        .catch(function (err) {
          console.warn('[PairBootstrap] Failed to pair device:', err);
        })
        .finally(function () {
          startFlutter();
        });
      return;
    }
  } catch (e) {
    console.warn('[PairBootstrap] Error during bootstrap:', e);
  }

  startFlutter();
})();
