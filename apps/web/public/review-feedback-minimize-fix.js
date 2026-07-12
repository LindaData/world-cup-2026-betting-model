(() => {
  const PANEL_ID = "gsp-floating-notes-panel";
  const TOGGLE_ID = "gsp-floating-notes-toggle";
  const STYLE_ID = "gsp-notes-minimize-fix-style";

  function addStyles() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = `
      #${PANEL_ID}.gsp-notes-minimized {
        max-height: none !important;
      }
      #${PANEL_ID}.gsp-notes-minimized .gsp-notes-body {
        display: none !important;
      }
      #${PANEL_ID}.gsp-notes-minimized .gsp-notes-header {
        border-bottom: 0 !important;
        cursor: pointer !important;
      }
      #${PANEL_ID}.gsp-notes-minimized .gsp-notes-close {
        background: hsl(var(--primary)) !important;
        color: hsl(var(--primary-foreground)) !important;
      }
    `;
    document.head.appendChild(style);
  }

  function panel() {
    return document.getElementById(PANEL_ID);
  }

  function toggle() {
    return document.getElementById(TOGGLE_ID);
  }

  function minimize() {
    const notesPanel = panel();
    if (!notesPanel) return;
    notesPanel.hidden = false;
    notesPanel.classList.add("gsp-notes-minimized");

    const button = notesPanel.querySelector(".gsp-notes-close");
    if (button) {
      button.textContent = "⌃";
      button.setAttribute("aria-label", "Expand notes");
      button.setAttribute("title", "Expand notes");
    }

    const notesToggle = toggle();
    if (notesToggle) notesToggle.hidden = true;
  }

  function expand() {
    const notesPanel = panel();
    if (!notesPanel) return;
    notesPanel.hidden = false;
    notesPanel.classList.remove("gsp-notes-minimized");

    const button = notesPanel.querySelector(".gsp-notes-close");
    if (button) {
      button.textContent = "−";
      button.setAttribute("aria-label", "Minimize notes");
      button.setAttribute("title", "Minimize notes");
    }

    const notesToggle = toggle();
    if (notesToggle) notesToggle.hidden = true;
  }

  function preparePanel() {
    addStyles();
    const notesPanel = panel();
    if (!notesPanel) return;

    const button = notesPanel.querySelector(".gsp-notes-close");
    if (button && !notesPanel.classList.contains("gsp-notes-minimized")) {
      button.textContent = "−";
      button.setAttribute("aria-label", "Minimize notes");
      button.setAttribute("title", "Minimize notes");
    }
  }

  document.addEventListener(
    "click",
    (event) => {
      const notesPanel = panel();
      if (!notesPanel) return;

      const closeButton = event.target.closest?.(".gsp-notes-close");
      if (closeButton && notesPanel.contains(closeButton)) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (notesPanel.classList.contains("gsp-notes-minimized")) expand();
        else minimize();
        return;
      }

      const header = event.target.closest?.(".gsp-notes-header");
      if (
        header &&
        notesPanel.contains(header) &&
        notesPanel.classList.contains("gsp-notes-minimized")
      ) {
        event.preventDefault();
        event.stopImmediatePropagation();
        expand();
      }
    },
    true,
  );

  const observer = new MutationObserver(preparePanel);
  observer.observe(document.documentElement, { childList: true, subtree: true });
  document.addEventListener("DOMContentLoaded", preparePanel);
  window.setInterval(preparePanel, 500);
  preparePanel();
})();
