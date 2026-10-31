================================================================================
                    PiFrame - Installation & First Run Guide
================================================================================

Thank you for downloading PiFrame!
Follow these steps to install and open the application on macOS.

--------------------------------------------------------------------------------
1. INSTALLATION
--------------------------------------------------------------------------------
Drag the "PiFrame.app" icon into the "Applications" folder alias in this window.


--------------------------------------------------------------------------------
2. FIRST LAUNCH & GATEKEEPER PROMPT (Apple Developer ID)
--------------------------------------------------------------------------------
PiFrame is free and open-source software. Because Apple requires a paid annual
Apple Developer Program membership ($99 USD/year) to issue official Developer ID
notarization certificates, macOS Gatekeeper may show a warning on first launch:

  "PiFrame cannot be opened because Apple cannot check it for malicious software"
  or "Unidentified developer".

To authorize the application (required ONLY once on first launch), you can use
either of the following methods:


METHOD A: Via System Settings (Recommended, no terminal required)
-----------------------------------------------------------------
1. Try opening PiFrame from your Applications folder. When the Gatekeeper prompt
   appears, click "Cancel".
2. Open "System Settings" (from Dock or Apple menu).
3. Navigate to "Privacy & Security" in the sidebar.
4. Scroll down to the "Security" section.
5. You will see:
   "PiFrame was blocked from use because it is not from an identified developer."
6. Click the "Open Anyway" button.
7. Enter your Mac password (or Touch ID) and click "Open" on the confirmation prompt.

PiFrame will now open and can be launched normally from Spotlight, Launchpad, or Finder.


METHOD B: Via Terminal (Immediate one-liner)
-------------------------------------------
If you prefer using Terminal:
1. Open the "Terminal" app (via Spotlight or Applications > Utilities).
2. Paste the following command and press Enter:

   xattr -cr /Applications/PiFrame.app

This clears the quarantine attribute applied by your browser.
You can now open PiFrame directly with a normal double-click!


--------------------------------------------------------------------------------
3. PI CODING AGENT (CLI)
--------------------------------------------------------------------------------
PiFrame is the graphical desktop client for Pi Coding Agent (@earendil-works/pi-coding-agent).
If you do not have Pi CLI installed yet:
- PiFrame will offer to install it automatically on first launch.
- Or you can install it manually from Terminal with:

   curl -fsSL https://pi.dev/install.sh | sh

================================================================================
Documentation & support: https://github.com/TrentiStefano/piframe
================================================================================

