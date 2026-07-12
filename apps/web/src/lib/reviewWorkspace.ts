export const REVIEW_WORKSPACE_STORAGE_KEY = "gsp:review-workspace:v2";
export const APPROVAL_STORAGE_KEY = "gsp:data-approval:v1";
export const REVIEW_WORKSPACE_EVENT = "gsp:review-workspace-updated";

export type ReviewLocale = "en-US" | "en-GB" | "en-AU" | "es" | "fr";

export type ReviewContext = {
  key: string;
  label: string;
  route: string;
  datasetId?: string;
};

export type ReviewNote = {
  text: string;
  label: string;
  route: string;
  datasetId?: string;
  updatedAt: string;
};

export type ReviewWorkspace = {
  version: 2;
  locale: ReviewLocale;
  globalText: string;
  globalUpdatedAt: string | null;
  notes: Record<string, ReviewNote>;
};

type ApprovalReview = {
  decision?: "pending" | "approved" | "changes_requested";
  notes?: string;
  reviewed_at_utc?: string | null;
};

const routeLabels: Record<string, string> = {
  "/approval": "Data approval",
  "/datasets": "Dataset catalog",
  "/coverage": "Coverage",
  "/dictionary": "Dictionary",
  "/quality": "Data quality",
  "/basket": "Flagged rows",
  "/explore": "Data explorer",
  "/nba": "NBA",
  "/mlb": "MLB",
  "/status": "System status",
};

export function detectReviewLocale(language?: string): ReviewLocale {
  const value = (language ?? (typeof navigator !== "undefined" ? navigator.language : "en-US")).toLowerCase();
  if (value.startsWith("fr")) return "fr";
  if (value.startsWith("es")) return "es";
  if (value === "en-gb") return "en-GB";
  if (value === "en-au") return "en-AU";
  return "en-US";
}

export function emptyReviewWorkspace(locale = detectReviewLocale()): ReviewWorkspace {
  return {
    version: 2,
    locale,
    globalText: "",
    globalUpdatedAt: null,
    notes: {},
  };
}

export function getReviewContext(pathname: string, search = ""): ReviewContext {
  const rawPath = pathname === "/" ? "/approval" : pathname;
  const path = rawPath.replace(/\/+$/, "") || "/approval";
  const params = new URLSearchParams(search);
  const datasetId = path === "/approval" ? params.get("dataset")?.trim() || undefined : undefined;

  if (datasetId) {
    return {
      key: `dataset:${datasetId}`,
      label: `Dataset · ${datasetId}`,
      route: `/approval?dataset=${encodeURIComponent(datasetId)}`,
      datasetId,
    };
  }

  return {
    key: `route:${path}`,
    label: routeLabels[path] ?? (path.replace(/^\//, "") || "Review"),
    route: path,
  };
}

export function readReviewWorkspace(): ReviewWorkspace {
  if (typeof localStorage === "undefined") return emptyReviewWorkspace();
  try {
    const raw = localStorage.getItem(REVIEW_WORKSPACE_STORAGE_KEY);
    if (!raw) return emptyReviewWorkspace();
    const parsed = JSON.parse(raw) as Partial<ReviewWorkspace>;
    return {
      version: 2,
      locale: isReviewLocale(parsed.locale) ? parsed.locale : detectReviewLocale(),
      globalText: typeof parsed.globalText === "string" ? parsed.globalText : "",
      globalUpdatedAt: typeof parsed.globalUpdatedAt === "string" ? parsed.globalUpdatedAt : null,
      notes: normalizeNotes(parsed.notes),
    };
  } catch {
    return emptyReviewWorkspace();
  }
}

export function writeReviewWorkspace(workspace: ReviewWorkspace): void {
  if (typeof localStorage === "undefined") return;
  try {
    localStorage.setItem(REVIEW_WORKSPACE_STORAGE_KEY, JSON.stringify(workspace));
  } catch {
    // The in-memory editor remains usable when browser storage is unavailable.
  }
}

export function readApprovalNote(datasetId: string): string {
  if (typeof localStorage === "undefined") return "";
  try {
    const reviews = JSON.parse(localStorage.getItem(APPROVAL_STORAGE_KEY) ?? "{}") as Record<string, ApprovalReview>;
    return typeof reviews[datasetId]?.notes === "string" ? reviews[datasetId].notes! : "";
  } catch {
    return "";
  }
}

export function setContextNote(
  workspace: ReviewWorkspace,
  context: ReviewContext,
  text: string,
  label = context.label,
  now = new Date().toISOString(),
): ReviewWorkspace {
  const notes = { ...workspace.notes };
  if (text.trim()) {
    notes[context.key] = {
      text,
      label: notes[context.key]?.label && label === context.label ? notes[context.key].label : label,
      route: context.route,
      datasetId: context.datasetId,
      updatedAt: now,
    };
  } else {
    delete notes[context.key];
  }
  return { ...workspace, notes };
}

export function setGlobalNote(
  workspace: ReviewWorkspace,
  text: string,
  now = new Date().toISOString(),
): ReviewWorkspace {
  return {
    ...workspace,
    globalText: text,
    globalUpdatedAt: text.trim() ? now : null,
  };
}

export function setReviewLocale(workspace: ReviewWorkspace, locale: ReviewLocale): ReviewWorkspace {
  return { ...workspace, locale };
}

export function persistContextNote(
  context: ReviewContext,
  text: string,
  label = context.label,
): ReviewWorkspace {
  const next = setContextNote(readReviewWorkspace(), context, text, label);
  writeReviewWorkspace(next);
  if (context.datasetId) writeApprovalNote(context.datasetId, text);
  announceWorkspaceUpdate({ contextKey: context.key, datasetId: context.datasetId });
  return next;
}

export function persistGlobalNote(text: string): ReviewWorkspace {
  const next = setGlobalNote(readReviewWorkspace(), text);
  writeReviewWorkspace(next);
  announceWorkspaceUpdate({ contextKey: "global" });
  return next;
}

export function persistReviewLocale(locale: ReviewLocale): ReviewWorkspace {
  const next = setReviewLocale(readReviewWorkspace(), locale);
  writeReviewWorkspace(next);
  announceWorkspaceUpdate({ contextKey: "settings" });
  return next;
}

export function importReviewWorkspace(value: unknown): ReviewWorkspace {
  if (!value || typeof value !== "object") throw new Error("Invalid review workspace backup.");
  const candidate = value as Partial<ReviewWorkspace>;
  const next: ReviewWorkspace = {
    version: 2,
    locale: isReviewLocale(candidate.locale) ? candidate.locale : detectReviewLocale(),
    globalText: typeof candidate.globalText === "string" ? candidate.globalText : "",
    globalUpdatedAt: typeof candidate.globalUpdatedAt === "string" ? candidate.globalUpdatedAt : null,
    notes: normalizeNotes(candidate.notes),
  };
  writeReviewWorkspace(next);
  Object.values(next.notes).forEach((note) => {
    if (note.datasetId) writeApprovalNote(note.datasetId, note.text);
  });
  announceWorkspaceUpdate({ contextKey: "import" });
  return next;
}

export function reviewWorkspaceToMarkdown(workspace: ReviewWorkspace): string {
  const sections: string[] = ["# Game Stat Pulse review notes"];
  if (workspace.globalText.trim()) {
    sections.push(`## Global scratchpad\n\n${workspace.globalText.trim()}`);
  }
  const notes = Object.values(workspace.notes).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  notes.forEach((note) => {
    sections.push(`## ${note.label}\n\nRoute: ${note.route}\nUpdated: ${note.updatedAt}\n\n${note.text.trim()}`);
  });
  return `${sections.join("\n\n")}\n`;
}

export function downloadReviewWorkspace(workspace: ReviewWorkspace): void {
  const payload = JSON.stringify(workspace, null, 2);
  const blob = new Blob([payload], { type: "application/json;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `game-stat-pulse-review-notes-${new Date().toISOString().slice(0, 10)}.json`;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

function writeApprovalNote(datasetId: string, text: string): void {
  if (typeof localStorage === "undefined") return;
  try {
    const reviews = JSON.parse(localStorage.getItem(APPROVAL_STORAGE_KEY) ?? "{}") as Record<string, ApprovalReview>;
    const current = reviews[datasetId] ?? {};
    reviews[datasetId] = {
      decision: current.decision ?? "pending",
      notes: text,
      reviewed_at_utc: current.reviewed_at_utc ?? null,
    };
    localStorage.setItem(APPROVAL_STORAGE_KEY, JSON.stringify(reviews));
  } catch {
    // Keep the workspace note even if the older approval store is unavailable.
  }
}

function announceWorkspaceUpdate(detail: { contextKey: string; datasetId?: string }): void {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new CustomEvent(REVIEW_WORKSPACE_EVENT, { detail }));
}

function normalizeNotes(value: unknown): Record<string, ReviewNote> {
  if (!value || typeof value !== "object") return {};
  const notes: Record<string, ReviewNote> = {};
  Object.entries(value as Record<string, unknown>).forEach(([key, item]) => {
    if (!item || typeof item !== "object") return;
    const note = item as Partial<ReviewNote>;
    if (typeof note.text !== "string" || !note.text.trim()) return;
    notes[key] = {
      text: note.text,
      label: typeof note.label === "string" && note.label ? note.label : key,
      route: typeof note.route === "string" && note.route ? note.route : "/",
      datasetId: typeof note.datasetId === "string" ? note.datasetId : undefined,
      updatedAt: typeof note.updatedAt === "string" ? note.updatedAt : new Date(0).toISOString(),
    };
  });
  return notes;
}

function isReviewLocale(value: unknown): value is ReviewLocale {
  return value === "en-US" || value === "en-GB" || value === "en-AU" || value === "es" || value === "fr";
}
