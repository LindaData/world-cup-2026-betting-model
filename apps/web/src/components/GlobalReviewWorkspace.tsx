import { useEffect, useMemo, useRef, useState } from "react";
import { NotebookPen } from "lucide-react";
import { useLocation, useNavigate } from "react-router-dom";
import ReviewWorkspacePanel from "./ReviewWorkspacePanel";
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
  const fileInput = useRef<HTMLInputElement>(null);
  const latest = useRef(workspace);

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
  const approvalPage = location.pathname === "/" || location.pathname === "/approval";

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

  return (
    <div lang={locale}>
      {!expanded && (
        <button
          type="button"
          onClick={() => { setExpanded(true); setTab("current"); }}
          aria-label={text.expand}
          className={`review-notes-launcher fixed right-3 lg:right-6 lg:bottom-6 z-[60] min-h-12 px-4 rounded-full border border-primary/40 bg-primary text-primary-foreground shadow-2xl flex items-center gap-2 font-semibold ${
            approvalPage ? "bottom-[calc(8.75rem+env(safe-area-inset-bottom))]" : "bottom-[calc(4.75rem+env(safe-area-inset-bottom))]"
          }`}
        >
          <NotebookPen className="w-5 h-5" /> {text.notes}
          {noteCount > 0 && <span className="min-w-6 h-6 px-1.5 rounded-full bg-black/20 text-xs flex items-center justify-center">{noteCount}</span>}
        </button>
      )}

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
