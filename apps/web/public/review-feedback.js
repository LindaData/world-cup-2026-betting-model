(() => {
  const STYLE_ID = "gsp-review-feedback-style";
  const LABEL_ATTR = "data-gsp-feedback-label";
  const STATUS_ATTR = "data-gsp-feedback-status";
  const PANEL_ID = "gsp-floating-notes-panel";
  const TOGGLE_ID = "gsp-floating-notes-toggle";
  const FLOATING_TEXTAREA_ID = "gsp-floating-notes-textarea";

  let originalTextarea = null;
  let saveTimer = null;
  let dragState = null;

  function addStyles() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = `
      [${LABEL_ATTR}] {
        margin-top: 0.25rem;
        padding: 0.9rem 1rem 0.65rem;
        border: 1px solid rgba(255,255,255,.14);
        border-bottom: 0;
        border-radius: 0.75rem 0.75rem 0 0;
        background: rgba(255,255,255,.045);
      }
      [${LABEL_ATTR}] strong {
        display: block;
        font-size: 0.95rem;
        line-height: 1.3;
      }
      [${LABEL_ATTR}] span {
        display: block;
        margin-top: 0.25rem;
        color: hsl(var(--muted-foreground));
        font-size: 0.75rem;
        line-height: 1.4;
      }
      textarea[data-gsp-feedback-box="true"] {
        min-height: 10rem !important;
        margin: 0 !important;
        border-radius: 0 !important;
        border-color: rgba(255,255,255,.14) !important;
        background: rgba(0,0,0,.18) !important;
        font-size: 1rem !important;
        line-height: 1.5 !important;
      }
      [${STATUS_ATTR}] {
        padding: 0.55rem 1rem 0.75rem;
        border: 1px solid rgba(255,255,255,.14);
        border-top: 0;
        border-radius: 0 0 0.75rem 0.75rem;
        background: rgba(255,255,255,.045);
        color: hsl(var(--muted-foreground));
        font-size: 0.72rem;
      }
      #${TOGGLE_ID} {
        position: fixed;
        right: 0.9rem;
        bottom: calc(9.25rem + env(safe-area-inset-bottom));
        z-index: 75;
        min-width: 6.5rem;
        min-height: 3rem;
        padding: 0.7rem 1rem;
        border: 1px solid rgba(255,255,255,.18);
        border-radius: 999px;
        background: hsl(var(--primary));
        color: hsl(var(--primary-foreground));
        font-weight: 700;
        box-shadow: 0 14px 34px rgba(0,0,0,.4);
      }
      #${TOGGLE_ID}[hidden], #${PANEL_ID}[hidden] { display: none !important; }
      #${PANEL_ID} {
        position: fixed;
        right: 0.75rem;
        bottom: calc(9.25rem + env(safe-area-inset-bottom));
        z-index: 80;
        width: min(92vw, 25rem);
        max-height: 60vh;
        overflow: hidden;
        border: 1px solid rgba(255,255,255,.18);
        border-radius: 1rem;
        background: hsl(var(--card));
        color: hsl(var(--foreground));
        box-shadow: 0 24px 60px rgba(0,0,0,.55);
      }
      #${PANEL_ID} .gsp-notes-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.75rem;
        min-height: 3.25rem;
        padding: 0.75rem 0.9rem;
        border-bottom: 1px solid rgba(255,255,255,.12);
        background: rgba(255,255,255,.045);
        cursor: grab;
        touch-action: none;
        user-select: none;
      }
      #${PANEL_ID} .gsp-notes-header:active { cursor: grabbing; }
      #${PANEL_ID} .gsp-notes-heading { min-width: 0; }
      #${PANEL_ID} .gsp-notes-heading strong {
        display: block;
        font-size: 0.95rem;
      }
      #${PANEL_ID} .gsp-notes-dataset {
        margin-top: 0.15rem;
        overflow: hidden;
        color: hsl(var(--muted-foreground));
        font-size: 0.72rem;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      #${PANEL_ID} .gsp-notes-close {
        flex: 0 0 auto;
        width: 2.4rem;
        height: 2.4rem;
        border: 0;
        border-radius: 0.65rem;
        background: rgba(255,255,255,.08);
        color: inherit;
        font-size: 1.3rem;
      }
      #${PANEL_ID} .gsp-notes-body { padding: 0.85rem; }
      #${FLOATING_TEXTAREA_ID} {
        display: block;
        width: 100%;
        min-height: 10rem;
        max-height: 34vh;
        resize: vertical;
        padding: 0.85rem;
        border: 1px solid rgba(255,255,255,.14);
        border-radius: 0.75rem;
        background: rgba(0,0,0,.2);
        color: inherit;
        font: inherit;
        font-size: 1rem;
        line-height: 1.45;
        outline: none;
      }
      #${FLOATING_TEXTAREA_ID}:focus {
        border-color: hsl(var(--primary));
        box-shadow: 0 0 0 2px hsl(var(--primary) / .2);
      }
      #${PANEL_ID} .gsp-notes-status {
        margin-top: 0.55rem;
        color: hsl(var(--muted-foreground));
        font-size: 0.72rem;
      }
      @media (min-width: 1024px) {
        textarea[data-gsp-feedback-box="true"] { min-height: 8rem !important; }
        #${TOGGLE_ID} { bottom: 1.5rem; right: 1.5rem; }
        #${PANEL_ID} { bottom: 1.5rem; right: 1.5rem; }
      }
    `;
    document.head.appendChild(style);
  }

  function findOriginalTextarea() {
    return Array.from(document.querySelectorAll("textarea")).find((textarea) => {
      const placeholder = textarea.placeholder?.toLowerCase() ?? "";
      return textarea.dataset.gspFeedbackBox === "true" || placeholder.includes("optional note");
    }) ?? null;
  }

  function getDatasetName() {
    return document.querySelector("#dataset-review h2")?.textContent?.trim() || "Current dataset";
  }

  function setNativeTextareaValue(textarea, value) {
    const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")?.set;
    if (setter) setter.call(textarea, value);
    else textarea.value = value;
  }

  function writeToOriginal(value) {
    if (!(originalTextarea instanceof HTMLTextAreaElement) || !document.contains(originalTextarea)) {
      originalTextarea = findOriginalTextarea();
    }
    if (!(originalTextarea instanceof HTMLTextAreaElement)) return;
    setNativeTextareaValue(originalTextarea, value);
    originalTextarea.dispatchEvent(new Event("input", { bubbles: true }));
  }

  function createFloatingUi() {
    if (!document.getElementById(TOGGLE_ID)) {
      const toggle = document.createElement("button");
      toggle.id = TOGGLE_ID;
      toggle.type = "button";
      toggle.textContent = "Notes";
      toggle.hidden = true;
      toggle.setAttribute("aria-controls", PANEL_ID);
      toggle.addEventListener("click", () => openPanel());
      document.body.appendChild(toggle);
    }

    if (!document.getElementById(PANEL_ID)) {
      const panel = document.createElement("section");
      panel.id = PANEL_ID;
      panel.hidden = true;
      panel.setAttribute("aria-label", "Floating feedback notes");
      panel.innerHTML = `
        <div class="gsp-notes-header">
          <div class="gsp-notes-heading">
            <strong>Feedback / notes</strong>
            <div class="gsp-notes-dataset">Current dataset</div>
          </div>
          <button type="button" class="gsp-notes-close" aria-label="Close notes">×</button>
        </div>
        <div class="gsp-notes-body">
          <textarea id="${FLOATING_TEXTAREA_ID}" placeholder="Write anything you notice while reviewing this dataset."></textarea>
          <div class="gsp-notes-status">Autosaves on this phone as you type.</div>
        </div>
      `;
      panel.querySelector(".gsp-notes-close")?.addEventListener("click", closePanel);
      panel.querySelector(`#${FLOATING_TEXTAREA_ID}`)?.addEventListener("input", (event) => {
        writeToOriginal(event.target.value);
        const status = panel.querySelector(".gsp-notes-status");
        if (status) status.textContent = "Saved automatically on this phone.";
      });
      setupDragging(panel);
      document.body.appendChild(panel);
    }
  }

  function setupDragging(panel) {
    const header = panel.querySelector(".gsp-notes-header");
    if (!header) return;

    header.addEventListener("pointerdown", (event) => {
      if (event.target.closest("button")) return;
      const rect = panel.getBoundingClientRect();
      dragState = {
        pointerId: event.pointerId,
        offsetX: event.clientX - rect.left,
        offsetY: event.clientY - rect.top,
      };
      header.setPointerCapture?.(event.pointerId);
      panel.style.right = "auto";
      panel.style.bottom = "auto";
      event.preventDefault();
    });

    header.addEventListener("pointermove", (event) => {
      if (!dragState || dragState.pointerId !== event.pointerId) return;
      const maxLeft = Math.max(8, window.innerWidth - panel.offsetWidth - 8);
      const maxTop = Math.max(8, window.innerHeight - panel.offsetHeight - 8);
      const left = Math.min(maxLeft, Math.max(8, event.clientX - dragState.offsetX));
      const top = Math.min(maxTop, Math.max(8, event.clientY - dragState.offsetY));
      panel.style.left = `${left}px`;
      panel.style.top = `${top}px`;
    });

    const endDrag = (event) => {
      if (!dragState || dragState.pointerId !== event.pointerId) return;
      dragState = null;
      header.releasePointerCapture?.(event.pointerId);
    };
    header.addEventListener("pointerup", endDrag);
    header.addEventListener("pointercancel", endDrag);
  }

  function openPanel() {
    const panel = document.getElementById(PANEL_ID);
    const toggle = document.getElementById(TOGGLE_ID);
    if (!panel || !toggle) return;
    syncFloatingUi(true);
    panel.hidden = false;
    toggle.hidden = true;
    window.setTimeout(() => document.getElementById(FLOATING_TEXTAREA_ID)?.focus(), 50);
  }

  function closePanel() {
    const panel = document.getElementById(PANEL_ID);
    const toggle = document.getElementById(TOGGLE_ID);
    if (panel) panel.hidden = true;
    if (toggle && originalTextarea) toggle.hidden = false;
  }

  function enhanceTextarea(textarea) {
    if (!(textarea instanceof HTMLTextAreaElement)) return;
    const placeholder = textarea.placeholder?.toLowerCase() ?? "";
    if (!placeholder.includes("optional note") && textarea.dataset.gspFeedbackBox !== "true") return;
    if (textarea.dataset.gspFeedbackBox === "true") return;

    textarea.dataset.gspFeedbackBox = "true";
    textarea.setAttribute("aria-label", "Feedback and notes for this dataset");
    textarea.placeholder = "Write anything you notice: missing fields, wrong values, confusing names, or why you approved it.";

    const label = document.createElement("div");
    label.setAttribute(LABEL_ATTR, "true");
    label.innerHTML = `
      <strong>Feedback / notes</strong>
      <span>Notes are attached to this dataset. Use the floating Notes button while moving around.</span>
    `;

    const status = document.createElement("div");
    status.setAttribute(STATUS_ATTR, "true");
    status.textContent = textarea.value ? "Saved notes loaded on this phone." : "Autosaves on this phone as you type.";

    textarea.insertAdjacentElement("beforebegin", label);
    textarea.insertAdjacentElement("afterend", status);
    textarea.addEventListener("input", () => {
      status.textContent = "Saved automatically on this phone.";
      syncFloatingUi(false);
    });
  }

  function cleanOrphans() {
    document.querySelectorAll(`[${LABEL_ATTR}]`).forEach((node) => {
      const next = node.nextElementSibling;
      if (!(next instanceof HTMLTextAreaElement) || next.dataset.gspFeedbackBox !== "true") node.remove();
    });
    document.querySelectorAll(`[${STATUS_ATTR}]`).forEach((node) => {
      const previous = node.previousElementSibling;
      if (!(previous instanceof HTMLTextAreaElement) || previous.dataset.gspFeedbackBox !== "true") node.remove();
    });
  }

  function syncFloatingUi(forceValueSync) {
    originalTextarea = findOriginalTextarea();
    const toggle = document.getElementById(TOGGLE_ID);
    const panel = document.getElementById(PANEL_ID);
    const floatingTextarea = document.getElementById(FLOATING_TEXTAREA_ID);
    const dataset = panel?.querySelector(".gsp-notes-dataset");

    if (!originalTextarea) {
      if (toggle) toggle.hidden = true;
      if (panel) panel.hidden = true;
      return;
    }

    if (toggle && panel?.hidden) toggle.hidden = false;
    if (dataset) dataset.textContent = getDatasetName();
    if (
      floatingTextarea instanceof HTMLTextAreaElement &&
      document.activeElement !== floatingTextarea &&
      (forceValueSync || floatingTextarea.value !== originalTextarea.value)
    ) {
      floatingTextarea.value = originalTextarea.value;
    }
  }

  function enhance() {
    addStyles();
    createFloatingUi();
    cleanOrphans();
    document.querySelectorAll("textarea").forEach(enhanceTextarea);
    syncFloatingUi(false);
  }

  const observer = new MutationObserver(() => {
    window.clearTimeout(saveTimer);
    saveTimer = window.setTimeout(enhance, 40);
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener("popstate", () => window.setTimeout(enhance, 0));
  window.addEventListener("hashchange", () => window.setTimeout(enhance, 0));
  window.addEventListener("resize", () => syncFloatingUi(false));
  document.addEventListener("DOMContentLoaded", enhance);
  window.setInterval(() => syncFloatingUi(false), 400);
  enhance();
})();
