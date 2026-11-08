/**
 * PiFrame — Editorial Showcase JavaScript Engine
 * Strictly zero external dependencies • Accessible • Theme Switcher • Performance-Optimized Video Loading
 */

document.addEventListener('DOMContentLoaded', () => {
  initThemeSwitcher();
  initOsDetectionAndReleaseApi();
  initHeroVideo();
  initChapterVideos();
  initLightbox();
  initMobileMenu();
  initClipboardHandlers();
  initHeaderScroll();
});

/* ==========================================================================
   1. 3-STATE THEME SWITCHER (Light / Auto / Dark)
   ========================================================================== */
function initThemeSwitcher() {
  const root = document.documentElement;
  const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');

  function getSavedPref() {
    try {
      return localStorage.getItem('piframe-theme-pref') || 'auto';
    } catch (e) {
      return 'auto';
    }
  }

  function applyTheme(pref) {
    let effective = pref;
    if (pref === 'auto') {
      effective = mediaQuery.matches ? 'dark' : 'light';
    }
    root.setAttribute('data-theme', effective);
    root.setAttribute('data-theme-pref', pref);

    try {
      localStorage.setItem('piframe-theme-pref', pref);
    } catch (e) {}

    // Update all theme buttons in header and mobile drawer
    document.querySelectorAll('.theme-opt').forEach((btn) => {
      const val = btn.getAttribute('data-theme-set');
      const isSelected = val === pref;
      btn.classList.toggle('active', isSelected);
      btn.setAttribute('aria-checked', isSelected ? 'true' : 'false');
    });
  }

  // Bind click handlers to theme buttons
  document.querySelectorAll('.theme-opt').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const targetPref = btn.getAttribute('data-theme-set');
      if (targetPref) {
        applyTheme(targetPref);
      }
    });

    // Keyboard support (Space / Enter)
    btn.addEventListener('keydown', (e) => {
      if (e.key === ' ' || e.key === 'Enter') {
        e.preventDefault();
        const targetPref = btn.getAttribute('data-theme-set');
        if (targetPref) {
          applyTheme(targetPref);
        }
      }
    });
  });

  // Listen for system theme changes when pref is 'auto'
  mediaQuery.addEventListener('change', (e) => {
    if (getSavedPref() === 'auto') {
      root.setAttribute('data-theme', e.matches ? 'dark' : 'light');
    }
  });

  // Ensure UI reflects current state on load
  applyTheme(getSavedPref());
}

/* ==========================================================================
   2. OS DETECTION & PROGRESSIVE ENHANCEMENT VIA GITHUB RELEASES API
   ========================================================================== */
function initOsDetectionAndReleaseApi() {
  const heroBtn = document.getElementById('heroDownloadBtn');
  const detectedLabel = document.getElementById('detectedOsLabel');
  const releasePill = document.getElementById('heroReleasePill');
  const winBtn = document.querySelector('#cardWindows .btn-platform-download');
  const macBtn = document.querySelector('#cardMac .btn-platform-download');
  const linuxBtn = document.querySelector('#cardLinux .btn-platform-download');

  const ua = window.navigator.userAgent || '';
  const platform = window.navigator.platform || '';
  const fullSpec = `${ua} ${platform}`;

  let osType = 'windows';
  if (/Mac|iPhone|iPod|iPad/i.test(fullSpec)) {
    osType = 'mac';
  } else if (/Linux/i.test(fullSpec) && !/Android/i.test(fullSpec)) {
    osType = 'linux';
  }

  // Default honest labels
  if (detectedLabel) {
    if (osType === 'mac') {
      detectedLabel.textContent = 'macOS disk image (.dmg) on GitHub Releases';
    } else if (osType === 'linux') {
      detectedLabel.textContent = 'Linux package (.deb) on GitHub Releases';
    } else {
      detectedLabel.textContent = 'Windows installer (.exe) on GitHub Releases';
    }
  }

  // Progressive enhancement via GitHub API
  fetch('https://api.github.com/repos/TrentiStefano/PiFrame/releases/latest', {
    headers: { 'Accept': 'application/vnd.github.v3+json' }
  })
    .then((res) => {
      if (!res.ok) throw new Error('API limit or error');
      return res.json();
    })
    .then((data) => {
      const tag = data.tag_name || 'v1.3.1';
      const assets = data.assets || [];

      if (releasePill) {
        releasePill.textContent = `${tag} · What's new`;
      }

      // Windows installer
      const winAsset = assets.find((a) => a.name.endsWith('.exe') && a.name.includes('windows'));
      if (winAsset && winBtn) {
        winBtn.href = winAsset.browser_download_url;
        const textSpan = winBtn.querySelector('span');
        if (textSpan) textSpan.textContent = `Download for Windows (${tag} .exe)`;
      }

      // macOS package
      const macArmAsset = assets.find((a) => a.name.includes('macos-arm64.dmg'));
      const macX64Asset = assets.find((a) => a.name.includes('macos-x64.dmg'));
      const macAsset = macArmAsset || macX64Asset;
      if (macAsset && macBtn) {
        macBtn.href = macAsset.browser_download_url;
        const textSpan = macBtn.querySelector('span');
        if (textSpan) textSpan.textContent = `Download for macOS (${tag} .dmg)`;
      }

      // Linux package
      const linuxAsset = assets.find((a) => a.name.endsWith('.deb'));
      if (linuxAsset && linuxBtn) {
        linuxBtn.href = linuxAsset.browser_download_url;
        const textSpan = linuxBtn.querySelector('span');
        if (textSpan) textSpan.textContent = `Download for Linux (${tag} .deb)`;
      }

      // Update primary hero CTA based on user OS
      if (heroBtn && detectedLabel) {
        if (osType === 'mac' && macAsset) {
          heroBtn.href = macAsset.browser_download_url;
          detectedLabel.textContent = `Download for macOS (${tag} .dmg)`;
        } else if (osType === 'linux' && linuxAsset) {
          heroBtn.href = linuxAsset.browser_download_url;
          detectedLabel.textContent = `Download for Linux (${tag} .deb)`;
        } else if (winAsset) {
          heroBtn.href = winAsset.browser_download_url;
          detectedLabel.textContent = `Download for Windows (${tag} .exe)`;
        }
      }
    })
    .catch(() => {
      // Graceful silent fallback to default honest links
    });
}

/* ==========================================================================
   3. HERO PROMO VIDEO LIFECYCLE & PERFORMANCE
   Poster first • Load on interaction / idle • Tap-to-play on mobile/slow data
   ========================================================================== */
function initHeroVideo() {
  const heroVideo = document.getElementById('heroPromoVideo');
  if (!heroVideo) return;

  const frame = heroVideo.closest('.showcase-media-frame') || heroVideo.parentElement;
  const playBtn = frame ? frame.querySelector('.ctrl-play') : null;
  const muteBtn = frame ? frame.querySelector('.ctrl-mute') : null;
  const muteLabel = frame ? frame.querySelector('.mute-label') : null;

  const isMobile = window.innerWidth <= 768;
  const connection = navigator.connection || navigator.mozConnection || navigator.webkitConnection;
  const isDataSaver = connection && (connection.saveData || /2g|3g/.test(connection.effectiveType || ''));
  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  let isLoaded = false;

  function loadSources() {
    if (isLoaded) return;
    isLoaded = true;
    const sources = heroVideo.querySelectorAll('source[data-src]');
    sources.forEach((source) => {
      source.src = source.getAttribute('data-src');
    });
    heroVideo.load();
  }

  // Play/pause button synchronization
  heroVideo.addEventListener('play', () => {
    if (playBtn) playBtn.classList.add('playing');
  });

  heroVideo.addEventListener('pause', () => {
    if (playBtn) playBtn.classList.remove('playing');
  });

  // Play button click handler
  if (playBtn) {
    playBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      loadSources();
      if (heroVideo.paused) {
        heroVideo.play().catch(() => {});
      } else {
        heroVideo.pause();
      }
    });
  }

  // Direct video click to toggle
  heroVideo.addEventListener('click', () => {
    loadSources();
    if (heroVideo.paused) {
      heroVideo.play().catch(() => {});
    } else {
      heroVideo.pause();
    }
  });

  // Mute / sound toggle (starts muted by default)
  if (muteBtn) {
    muteBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      heroVideo.muted = !heroVideo.muted;
      muteBtn.classList.toggle('muted', heroVideo.muted);
      if (muteLabel) {
        muteLabel.textContent = heroVideo.muted ? 'Unmute' : 'Mute';
      }
    });
  }

  // Conditional loading strategy:
  // On mobile, data-saver, slow network, or reduced motion -> poster + tap to play only
  if (isMobile || isDataSaver || prefersReducedMotion) {
    return;
  }

  // On desktop: load video on first user interaction (scroll, pointerdown, mousemove, or hover over stage)
  function triggerLazyLoad() {
    loadSources();
    heroVideo.play().catch(() => {});
    window.removeEventListener('scroll', triggerLazyLoad);
    window.removeEventListener('pointerdown', triggerLazyLoad);
    frame.removeEventListener('mouseenter', triggerLazyLoad);
  }

  window.addEventListener('scroll', triggerLazyLoad, { passive: true, once: true });
  window.addEventListener('pointerdown', triggerLazyLoad, { passive: true, once: true });
  if (frame) {
    frame.addEventListener('mouseenter', triggerLazyLoad, { passive: true, once: true });
  }
}

/* ==========================================================================
   4. CHAPTER VIDEOS INTERSECTION OBSERVER
   preload="none" • load when approaching • pause & unload when scrolled away
   ========================================================================== */
function initChapterVideos() {
  const chapters = document.querySelectorAll('.chapter-row video.media-video');
  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (prefersReducedMotion) return;

  chapters.forEach((video) => {
    const frame = video.closest('.showcase-media-frame') || video.parentElement;
    const playBtn = frame ? frame.querySelector('.ctrl-play') : null;

    video.addEventListener('play', () => {
      if (playBtn) playBtn.classList.add('playing');
    });

    video.addEventListener('pause', () => {
      if (playBtn) playBtn.classList.remove('playing');
    });

    if (playBtn) {
      playBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        const sources = video.querySelectorAll('source[data-src]');
        sources.forEach((s) => {
          if (!s.src) s.src = s.getAttribute('data-src');
        });
        if (video.paused) {
          video.play().catch(() => {});
        } else {
          video.pause();
        }
      });
    }

    video.addEventListener('click', () => {
      if (video.paused) {
        video.play().catch(() => {});
      } else {
        video.pause();
      }
    });
  });

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        const video = entry.target;
        const sources = video.querySelectorAll('source');

        if (entry.isIntersecting) {
          let needLoad = false;
          sources.forEach((source) => {
            const dataSrc = source.getAttribute('data-src');
            if (dataSrc && !source.src) {
              source.src = dataSrc;
              needLoad = true;
            }
          });
          if (needLoad) {
            video.load();
          }
          video.play().catch(() => {});
        } else {
          // Far away: pause and unload to release memory & network
          video.pause();
          let wasLoaded = false;
          sources.forEach((source) => {
            if (source.src) {
              source.removeAttribute('src');
              wasLoaded = true;
            }
          });
          if (wasLoaded) {
            video.load();
          }
        }
      });
    },
    { rootMargin: '300px 0px' }
  );

  chapters.forEach((video) => observer.observe(video));
}

/* ==========================================================================
   5. ACCESSIBLE VIDEO LIGHTBOX (Compact Feature Grid)
   Native <dialog> • Focus Trap • Esc Closes • Returns Focus
   ========================================================================== */
function initLightbox() {
  const dialog = document.getElementById('videoLightbox');
  const video = document.getElementById('lightboxVideo');
  const closeBtn = document.getElementById('lightboxCloseBtn');
  const titleEl = document.getElementById('lightboxTitle');
  const captionEl = document.getElementById('lightboxCaption');
  const srcWebm = document.getElementById('lightboxSrcWebm');
  const srcMp4 = document.getElementById('lightboxSrcMp4');

  if (!dialog || !video) return;

  let triggerElement = null;

  function openModal(slug, title, caption, trigger) {
    triggerElement = trigger;
    if (titleEl) titleEl.textContent = title;
    if (captionEl) captionEl.textContent = caption || '';

    video.poster = `./assets/showcase/${slug}/poster.webp`;
    if (srcWebm) srcWebm.src = `./assets/showcase/${slug}/clip.webm`;
    if (srcMp4) srcMp4.src = `./assets/showcase/${slug}/clip.mp4`;

    video.load();
    dialog.showModal();

    video.play().catch(() => {});
    if (closeBtn) closeBtn.focus();
  }

  function closeModal() {
    video.pause();
    if (srcWebm) srcWebm.removeAttribute('src');
    if (srcMp4) srcMp4.removeAttribute('src');
    video.load();

    if (dialog.open) {
      dialog.close();
    }

    if (triggerElement && typeof triggerElement.focus === 'function') {
      triggerElement.focus();
    }
  }

  // Bind click on card play buttons
  document.querySelectorAll('.card-play-btn').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const slug = btn.getAttribute('data-clip-slug');
      const title = btn.getAttribute('data-clip-title') || 'Feature Walkthrough';
      const caption = btn.getAttribute('data-clip-caption') || '';
      if (slug) {
        openModal(slug, title, caption, btn);
      }
    });
  });

  if (closeBtn) {
    closeBtn.addEventListener('click', (e) => {
      e.preventDefault();
      closeModal();
    });
  }

  // Backdrop click closes dialog
  dialog.addEventListener('click', (e) => {
    if (e.target === dialog) {
      closeModal();
    }
  });

  // Handle Esc key or native dialog cancel
  dialog.addEventListener('cancel', (e) => {
    e.preventDefault();
    closeModal();
  });
}

/* ==========================================================================
   6. MOBILE NAVIGATION DRAWER
   ========================================================================== */
function initMobileMenu() {
  const menuToggle = document.getElementById('menuToggle');
  const mobileNav = document.getElementById('mobileNav');
  if (!menuToggle || !mobileNav) return;

  function toggleMenu(open) {
    const isOpen = open !== undefined ? open : !mobileNav.classList.contains('open');
    mobileNav.classList.toggle('open', isOpen);
    menuToggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
    mobileNav.setAttribute('aria-hidden', isOpen ? 'false' : 'true');
  }

  menuToggle.addEventListener('click', () => toggleMenu());

  // Close when clicking any nav link
  mobileNav.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', () => toggleMenu(false));
  });

  // Close with Esc key
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && mobileNav.classList.contains('open')) {
      toggleMenu(false);
      menuToggle.focus();
    }
  });
}

/* ==========================================================================
   7. CLIPBOARD SNIPPET HANDLERS
   ========================================================================== */
function initClipboardHandlers() {
  document.querySelectorAll('.cli-copy-btn').forEach((btn) => {
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const targetId = btn.getAttribute('data-copy-target');
      const targetEl = targetId ? document.getElementById(targetId) : null;
      if (!targetEl) return;

      const text = targetEl.textContent.trim();
      try {
        await navigator.clipboard.writeText(text);
        btn.classList.add('copied');
        btn.setAttribute('aria-label', 'Copied to clipboard');
        setTimeout(() => {
          btn.classList.remove('copied');
          btn.setAttribute('aria-label', 'Copy installation command');
        }, 2200);
      } catch (err) {
        // Fallback for older browsers
        const textarea = document.createElement('textarea');
        textarea.value = text;
        textarea.style.position = 'fixed';
        textarea.style.opacity = '0';
        document.body.appendChild(textarea);
        textarea.select();
        try {
          document.execCommand('copy');
          btn.classList.add('copied');
          setTimeout(() => btn.classList.remove('copied'), 2200);
        } catch (e2) {}
        document.body.removeChild(textarea);
      }
    });
  });
}

/* ==========================================================================
   8. HEADER SCROLL SHADOW
   ========================================================================== */
function initHeaderScroll() {
  const header = document.getElementById('siteHeader');
  if (!header) return;

  function onScroll() {
    if (window.scrollY > 20) {
      header.classList.add('scrolled');
    } else {
      header.classList.remove('scrolled');
    }
  }

  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();
}
