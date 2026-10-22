/**
 * PiFrame Showcase — Fast, Native Interactive Engine
 * Zero scroll hijacking • Native 120Hz smooth scrolling • Real UI Tabs
 */

document.addEventListener('DOMContentLoaded', () => {
  initThemeToggle();
  initOsDetection();
  initRealUiTabs();
  initSpotlightEffect();
  initMagneticButtons();
  initClipboardHandlers();
  initMobileMenu();
  init3DTilt();
});

/* ==========================================================================
   1. OS DETECTION FOR DOWNLOAD CTA
   ========================================================================== */
function initOsDetection() {
  const osLabel = document.getElementById('detectedOsLabel');
  const userAgent = window.navigator.userAgent || '';
  const platform = window.navigator.platform || '';

  let badgeText = 'Download for Windows (x64)';

  if (/Mac|iPhone|iPod|iPad/i.test(platform) || /Macintosh/i.test(userAgent)) {
    badgeText = 'Download for macOS (arm64 / x64)';
  } else if (/Linux/i.test(platform) || /X11/i.test(userAgent)) {
    badgeText = 'Download for Linux (.deb)';
  }

  if (osLabel) {
    osLabel.textContent = badgeText;
  }
}

/* ==========================================================================
   2. REAL APPLICATION UI TABS
   ========================================================================== */
function initRealUiTabs() {
  const tabs = document.querySelectorAll('.win-tab[data-ui-target]');
  const views = document.querySelectorAll('.ui-view-wrapper');

  tabs.forEach((tab) => {
    tab.addEventListener('click', () => {
      const targetId = tab.getAttribute('data-ui-target');
      if (!targetId) return;

      tabs.forEach((t) => {
        t.classList.remove('active');
        t.setAttribute('aria-selected', 'false');
      });
      views.forEach((v) => v.classList.remove('active'));

      tab.classList.add('active');
      tab.setAttribute('aria-selected', 'true');

      const targetView = document.getElementById(targetId);
      if (targetView) {
        targetView.classList.add('active');
      }
    });
  });
}

/* ==========================================================================
   3. 3D TILT ON MOUSEMOVE
   ========================================================================== */
function init3DTilt() {
  const heroFrame = document.getElementById('heroWindowFrame');
  const stage = document.querySelector('.centerpiece-stage');

  if (heroFrame && stage && window.matchMedia('(min-width: 1024px)').matches) {
    stage.addEventListener('mousemove', (e) => {
      const rect = stage.getBoundingClientRect();
      const x = e.clientX - rect.left - rect.width / 2;
      const y = e.clientY - rect.top - rect.height / 2;

      const tiltX = (y / (rect.height / 2)) * -3.5;
      const tiltY = (x / (rect.width / 2)) * 3.5;

      heroFrame.style.transform = `perspective(1200px) rotateX(${tiltX}deg) rotateY(${tiltY}deg) translateY(-2px)`;
    });

    stage.addEventListener('mouseleave', () => {
      heroFrame.style.transform = 'perspective(1200px) rotateX(0deg) rotateY(0deg) translateY(0px)';
    });
  }
}

/* ==========================================================================
   4. CARD SPOTLIGHT HOVER EFFECT
   ========================================================================== */
function initSpotlightEffect() {
  const cards = document.querySelectorAll('.spotlight-card');

  cards.forEach((card) => {
    card.addEventListener('mousemove', (e) => {
      const rect = card.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;

      card.style.setProperty('--mouse-x', `${x}px`);
      card.style.setProperty('--mouse-y', `${y}px`);
    });
  });
}

/* ==========================================================================
   5. MAGNETIC BUTTONS (Awwwards-tier micro-interaction)
   ========================================================================== */
function initMagneticButtons() {
  const magneticEls = document.querySelectorAll('.magnetic');

  if (window.matchMedia('(pointer: fine)').matches) {
    magneticEls.forEach((el) => {
      el.addEventListener('mousemove', (e) => {
        const rect = el.getBoundingClientRect();
        const x = e.clientX - rect.left - rect.width / 2;
        const y = e.clientY - rect.top - rect.height / 2;

        el.style.transform = `translate(${x * 0.22}px, ${y * 0.22}px)`;
      });

      el.addEventListener('mouseleave', () => {
        el.style.transform = 'translate(0px, 0px)';
        el.style.transition = 'transform 0.3s cubic-bezier(0.16, 1, 0.3, 1)';
      });

      el.addEventListener('mouseenter', () => {
        el.style.transition = 'transform 0.08s ease-out';
      });
    });
  }
}

/* ==========================================================================
   6. COPY TO CLIPBOARD & TOAST SYSTEM
   ========================================================================== */
function initClipboardHandlers() {
  const copyButtons = document.querySelectorAll('.btn-copy');

  copyButtons.forEach((btn) => {
    btn.addEventListener('click', () => {
      const targetId = btn.getAttribute('data-copy-target');
      const directText = btn.getAttribute('data-copy');
      let textToCopy = '';

      if (targetId) {
        const el = document.getElementById(targetId);
        if (el) textToCopy = el.textContent || '';
      } else if (directText) {
        textToCopy = directText;
      }

      if (textToCopy) {
        const cleanText = textToCopy.trim();
        const markSuccess = () => {
          btn.classList.add('copied');
          showToast(`Copied to clipboard: ${cleanText}`);
          setTimeout(() => {
            btn.classList.remove('copied');
          }, 2000);
        };

        if (navigator.clipboard && window.isSecureContext) {
          navigator.clipboard.writeText(cleanText)
            .then(markSuccess)
            .catch(() => {
              fallbackCopy(cleanText);
              markSuccess();
            });
        } else {
          fallbackCopy(cleanText);
          markSuccess();
        }
      }
    });
  });
}

function fallbackCopy(text) {
  try {
    const textArea = document.createElement('textarea');
    textArea.value = text;
    textArea.style.position = 'fixed';
    textArea.style.left = '-9999px';
    textArea.style.top = '-9999px';
    textArea.setAttribute('readonly', '');
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();
    document.execCommand('copy');
    document.body.removeChild(textArea);
  } catch (err) {
    console.warn('Fallback copy error:', err);
  }
}

function showToast(message) {
  const container = document.getElementById('toastContainer');
  if (!container) return;

  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.innerHTML = `<span>✔</span> <span>${message}</span>`;
  container.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(8px)';
    toast.style.transition = 'all 0.3s ease';
    setTimeout(() => toast.remove(), 300);
  }, 2600);
}

/* ==========================================================================
   7. MOBILE NAVIGATION DRAWER
   ========================================================================== */
function initMobileMenu() {
  const toggle = document.getElementById('mobileToggle');
  const menu = document.getElementById('mobileMenu');
  const links = document.querySelectorAll('.mobile-link, .mobile-actions a');

  if (toggle && menu) {
    toggle.addEventListener('click', () => {
      const isOpen = menu.classList.toggle('open');
      toggle.setAttribute('aria-expanded', String(isOpen));
    });

    links.forEach((l) => {
      l.addEventListener('click', () => {
        menu.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
      });
    });
  }
}

/* ==========================================================================
   8. THEME TOGGLE (PIFRAME DARK & LIGHT)
   ========================================================================== */
function initThemeToggle() {
  const desktopBtn = document.getElementById('themeToggleBtn');
  const mobileBtn = document.getElementById('mobileThemeToggleBtn');
  
  const getPreferredTheme = () => {
    const saved = localStorage.getItem('piframe-theme');
    if (saved === 'dark' || saved === 'light') return saved;
    return window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
  };

  const applyTheme = (theme, notify = false) => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('piframe-theme', theme);

    if (desktopBtn) {
      desktopBtn.setAttribute('title', `Active: PiFrame ${theme === 'light' ? 'Light' : 'Dark'} (Click to switch)`);
      desktopBtn.setAttribute('aria-label', `Active: PiFrame ${theme === 'light' ? 'Light' : 'Dark'} (Click to switch)`);
    }

    if (notify) {
      showToast(`PiFrame ${theme === 'light' ? 'Light' : 'Dark'} theme applied`);
    }

    // Synchronize centerpiece tab if viewing Bento tabs
    const activeTab = document.querySelector('.win-tab.active[data-ui-target]');
    if (activeTab) {
      const activeTarget = activeTab.getAttribute('data-ui-target');
      if (theme === 'light' && activeTarget === 'ui-bento-dark') {
        const lightTab = document.querySelector('.win-tab[data-ui-target="ui-bento-light"]');
        if (lightTab) lightTab.click();
      } else if (theme === 'dark' && activeTarget === 'ui-bento-light') {
        const darkTab = document.querySelector('.win-tab[data-ui-target="ui-bento-dark"]');
        if (darkTab) darkTab.click();
      }
    }
  };

  const initialTheme = getPreferredTheme();
  applyTheme(initialTheme, false);

  const toggleHandler = () => {
    const currentTheme = document.documentElement.getAttribute('data-theme') || 'dark';
    const nextTheme = currentTheme === 'light' ? 'dark' : 'light';
    applyTheme(nextTheme, true);
  };

  if (desktopBtn) {
    desktopBtn.addEventListener('click', toggleHandler);
  }
  if (mobileBtn) {
    mobileBtn.addEventListener('click', toggleHandler);
  }
}

