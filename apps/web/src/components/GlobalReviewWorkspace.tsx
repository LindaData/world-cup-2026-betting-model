import { useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { NotebookPen } from "lucide-react";
import { useLocation, useNavigate } from "react-router-dom";
import ReviewWorkspacePanel from "./ReviewWorkspacePanel";
import { NOTES_LAUNCHER_SLOT_ID } from "./Layout";
import {
  REVIEW_WORKSPACE_EVENT,
  type ReviewContext,
  type ReviewLocale,
  type ReviewNote,
  downloadReviewWorkspace,
  getReviewContext,
  importReviewWorkspace,
  persistContextNote,
  persistGlobalNote,
  persistReviewLocale,
  readApprovalNote,
  readReviewWorkspace,
  reviewWorkspaceToMarkdown,
  writeReviewWorkspace,
} from "@/lib/reviewWorkspace";
import { reviewMessages } from "@/lib/reviewLocales";
import "@/review-workspace.css";

type Tab = "current" | "global" | "all";

export default function GlobalReviewWorkspace() {
  const location = useLocation();
  const navigate = useNavigate();
  const [workspace, setWorkspace] = useState(readReviewWorkspace);
  const [expanded, setExpanded] = useState(false);
  const [tab, setTab] = useState<Tab>("current");
  const [notice, setNotice] = useState("");
  const [launcherSlot, setLauncherSlot] = useState<HTMLElement | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);
  const latest = useRef(workspace);

  // The launcher lives in the top nav bar as a quiet icon button (never a
  // floating FAB competing with each screen's one primary action). This
  // component mounts outside the route Suspense, so the slot may not exist
  // yet on first render (the lazy route tree can still be on its fallback):
  // watch the DOM until the slot appears, and re-run the lookup on route
  // changes in case the tree was swapped out.
  useEffect(() => {
    const find = () => {
      const el = document.getElementById(NOTES_LAUNCHER_SLOT_ID);
      setLauncherSlot(el);
      return el;
    };
    if (find()) return;
    const observer = new MutationObserver(() => {
      if (find()) observer.disconnect();
    });
    observer.observe(document.body, { childList: true, subtree: true });
    return () => observer.disconnect();
  }, [location.pathname]);

  const context = useMemo(
    () => getReviewContext(location.pathname, location.search),
    [location.pathname, location.search],
  );
  const locale = workspace.locale;
  const text = reviewMessages[locale];
  const savedNote = workspace.notes[context.key];
  const oldNote = context.datasetId ? readApprovalNote(context.datasetId) : "";
  const currentText = savedNote?.text ?? oldNote;
  const label = visibleLabel(context);
  const noteCount = Object.keys(workspace.notes).length + (workspace.globalText.trim() ? 1 : 0);

  useEffect(() => {
    latest.current = workspace;
  }, [workspace]);

  useEffect(() => {
    const refresh = () => setWorkspace(readReviewWorkspace());
    const onStorage = (event: StorageEvent) => {
      if (!event.key || event.key === "gsp:review-workspace:v2" || event.key === "gsp:data-approval:v1") refresh();
    };
    window.addEventListener(REVIEW_WORKSPACE_EVENT, refresh);
    window.addEventListener("storage", onStorage);
    return () => {
      window.removeEventListener(REVIEW_WORKSPACE_EVENT, refresh);
      window.removeEventListener("storage", onStorage);
    };
  }, []);

  useEffect(() => {
    if (!context.datasetId || savedNote || !oldNote.trim()) return;
    setWorkspace(persistContextNote(context, oldNote, label));
  }, [context, label, oldNote, savedNote]);

  useEffect(() => {
    const flush = () => writeReviewWorkspace(latest.current);
    const onVisibility = () => document.visibilityState === "hidden" && flush();
    window.addEventListener("pagehide", flush);
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      window.removeEventListener("pagehide", flush);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  const saveCurrent = (value: string) => {
    setWorkspace(persistContextNote(context, value, visibleLabel(context)));
    setNotice(text.saved);
  };
  const saveGlobal = (value: string) => {
    setWorkspace(persistGlobalNote(value));
    setNotice(text.saved);
  };
  const changeLocale = (value: ReviewLocale) => setWorkspace(persistReviewLocale(value));
  const clearCurrent = () => window.confirm(text.clearConfirm) && saveCurrent("");
  const deleteNote = (key: string, note: ReviewNote) => {
    if (!window.confirm(text.deleteConfirm)) return;
    setWorkspace(persistContextNote({ key, label: note.label, route: note.route, datasetId: note.datasetId }, "", note.label));
  };
  const copyValue = async (value: string) => {
    await navigator.clipboard.writeText(value);
    setNotice(text.copied);
  };
  const restore = async (file?: File) => {
    if (!file) return;
    try {
      const next = importReviewWorkspace(JSON.parse(await file.text()));
      setWorkspace(next);
      setNotice(reviewMessages[next.locale].restored);
    } catch {
      setNotice(text.restoreFailed);
    }
    if (fileInput.current) fileInput.current.value = "";
  };

  // Quiet ghost icon button in the top nav bar: the green accent stays
  // reserved for each screen's one true primary action, and nothing floats
  // over inputs or cards on mobile.
  const launcher = !expanded && (
    <button
      type="button"
      onClick={() => { setExpanded(true); setTab("current"); }}
      aria-label={text.expand}
      title={text.notes}
      className="review-notes-launcher relative flex min-h-11 min-w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-card hover:text-foreground"
    >
      <NotebookPen className="h-5 w-5" aria-hidden="true" />
      {noteCount > 0 && (
        <span className="absolute right-0.5 top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-muted px-1 text-[10px] font-semibold tabular-nums text-muted-foreground">
          {noteCount}
        </span>
      )}
    </button>
  );

  return (
    <div lang={locale}>
      {/* Portal-only: while the slot is missing we render nothing, so the
          button never ends up as stray debris after <main>. */}
      {launcher && launcherSlot && createPortal(launcher, launcherSlot)}

      {expanded && (
        <ReviewWorkspacePanel
          workspace={workspace}
          locale={locale}
          text={text}
          contextLabel={label}
          currentText={currentText}
          currentUpdatedAt={savedNote?.updatedAt ?? null}
          datasetMode={Boolean(context.datasetId)}
          tab={tab}
          notice={notice || text.saved}
          onTab={setTab}
          onMinimize={() => setExpanded(false)}
          onCurrentChange={saveCurrent}
          onGlobalChange={saveGlobal}
          onClearCurrent={clearCurrent}
          onOpenNote={(note) => { navigate(note.route); setTab("current"); }}
          onDeleteNote={deleteNote}
          onCopyNote={(value) => void copyValue(value)}
          onExport={() => downloadReviewWorkspace(latest.current)}
          onCopyAll={() => void copyValue(reviewWorkspaceToMarkdown(latest.current))}
          onRestore={() => fileInput.current?.click()}
          onLocale={changeLocale}
        />
      )}

      <input ref={fileInput} type="file" accept="application/json,.json" onChange={(event) => void restore(event.target.files?.[0])} className="sr-only" />
    </div>
  );
}

function visibleLabel(context: ReviewContext): string {
  if (context.datasetId) {
    const heading = document.querySelector("#dataset-review h2")?.textContent?.trim();
    if (heading) return heading;
  }
  return context.label;
}
