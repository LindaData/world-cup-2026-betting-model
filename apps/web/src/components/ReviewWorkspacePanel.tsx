import { Check, ChevronDown, Clipboard, Download, FileUp, Globe2, NotebookPen, Trash2 } from "lucide-react";
import type { ReviewLocale, ReviewNote, ReviewWorkspace } from "@/lib/reviewWorkspace";
import { reviewLocaleOptions, type ReviewMessages } from "@/lib/reviewLocales";

type Tab = "current" | "global" | "all";

type Props = {
  workspace: ReviewWorkspace;
  locale: ReviewLocale;
  text: ReviewMessages;
  contextLabel: string;
  currentText: string;
  currentUpdatedAt: string | null;
  datasetMode: boolean;
  tab: Tab;
  notice: string;
  onTab: (tab: Tab) => void;
  onMinimize: () => void;
  onCurrentChange: (value: string) => void;
  onGlobalChange: (value: string) => void;
  onClearCurrent: () => void;
  onOpenNote: (note: ReviewNote) => void;
  onDeleteNote: (key: string, note: ReviewNote) => void;
  onCopyNote: (value: string) => void;
  onExport: () => void;
  onCopyAll: () => void;
  onRestore: () => void;
  onLocale: (locale: ReviewLocale) => void;
};

export default function ReviewWorkspacePanel(props: Props) {
  const notes = Object.entries(props.workspace.notes).sort(([, a], [, b]) => b.updatedAt.localeCompare(a.updatedAt));

  return (
    <section
      id="global-review-workspace"
      role="complementary"
      aria-label={props.text.notebook}
      className="fixed left-2 right-2 bottom-[calc(4.75rem+env(safe-area-inset-bottom))] lg:left-auto lg:right-6 lg:bottom-6 lg:w-[430px] z-[70] max-h-[72vh] overflow-hidden rounded-2xl border border-white/15 bg-[hsl(var(--card))] shadow-2xl flex flex-col"
    >
      <header className="min-h-14 px-3 py-2.5 border-b border-white/10 bg-white/[0.035] flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-primary/15 text-primary flex items-center justify-center shrink-0">
          <NotebookPen className="w-5 h-5" />
        </div>
        <div className="min-w-0 flex-1">
          <h2 className="font-semibold leading-tight truncate">{props.text.notebook}</h2>
          <div className="text-[11px] text-muted-foreground truncate">{props.contextLabel}</div>
        </div>
        <button
          type="button"
          onClick={props.onMinimize}
          aria-label={props.text.minimize}
          className="w-11 h-11 rounded-xl bg-white/5 flex items-center justify-center active:bg-white/10"
        >
          <ChevronDown className="w-5 h-5" />
        </button>
      </header>

      <div className="grid grid-cols-3 gap-1.5 p-2 border-b border-white/10" role="tablist">
        {([
          ["current", props.text.current],
          ["global", props.text.global],
          ["all", props.text.all],
        ] as Array<[Tab, string]>).map(([value, label]) => (
          <button
            key={value}
            type="button"
            role="tab"
            aria-selected={props.tab === value}
            onClick={() => props.onTab(value)}
            className={`min-h-11 rounded-lg px-2 text-sm font-medium ${
              props.tab === value ? "bg-primary text-primary-foreground" : "bg-white/5 text-foreground/75"
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      <div className="overflow-y-auto overscroll-contain p-3 flex-1">
        {props.tab === "current" && (
          <div className="space-y-3">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="text-sm font-semibold">{props.text.pageNote}</div>
                <div className="text-xs text-muted-foreground break-all mt-0.5">{props.contextLabel}</div>
              </div>
              {props.currentText.trim() && (
                <button type="button" onClick={props.onClearCurrent} className="min-h-11 px-3 rounded-lg bg-white/5 text-xs flex items-center gap-1.5">
                  <Trash2 className="w-4 h-4" /> {props.text.clear}
                </button>
              )}
            </div>
            <textarea
              value={props.currentText}
              onChange={(event) => props.onCurrentChange(event.target.value)}
              placeholder={props.text.pagePlaceholder}
              aria-label={props.text.pageNote}
              className="w-full min-h-[13rem] max-h-[36vh] resize-y rounded-xl border border-input bg-background p-3 text-base leading-relaxed outline-none focus:ring-2 focus:ring-primary/40"
            />
            {props.datasetMode && <p className="text-xs text-primary/90">{props.text.approvalSync}</p>}
            <SaveState text={props.notice} timestamp={props.currentUpdatedAt} locale={props.locale} updated={props.text.updated} />
          </div>
        )}

        {props.tab === "global" && (
          <div className="space-y-3">
            <div className="text-sm font-semibold">{props.text.globalNote}</div>
            <textarea
              value={props.workspace.globalText}
              onChange={(event) => props.onGlobalChange(event.target.value)}
              placeholder={props.text.globalPlaceholder}
              aria-label={props.text.globalNote}
              className="w-full min-h-[13rem] max-h-[36vh] resize-y rounded-xl border border-input bg-background p-3 text-base leading-relaxed outline-none focus:ring-2 focus:ring-primary/40"
            />
            <SaveState text={props.notice} timestamp={props.workspace.globalUpdatedAt} locale={props.locale} updated={props.text.updated} />
          </div>
        )}

        {props.tab === "all" && (
          <div className="space-y-2.5">
            {props.workspace.globalText.trim() && (
              <NoteCard
                label={props.text.globalNote}
                value={props.workspace.globalText}
                onOpen={() => props.onTab("global")}
                onCopy={() => props.onCopyNote(props.workspace.globalText)}
                openLabel={props.text.open}
              />
            )}
            {notes.map(([key, note]) => (
              <NoteCard
                key={key}
                label={note.label}
                value={note.text}
                timestamp={formatTime(note.updatedAt, props.locale)}
                onOpen={() => props.onOpenNote(note)}
                onCopy={() => props.onCopyNote(note.text)}
                onDelete={() => props.onDeleteNote(key, note)}
                openLabel={props.text.open}
              />
            ))}
            {!props.workspace.globalText.trim() && !notes.length && (
              <div className="py-10 text-center text-sm text-muted-foreground">{props.text.noNotes}</div>
            )}
          </div>
        )}
      </div>

      <footer className="border-t border-white/10 p-2.5 space-y-2 bg-white/[0.02]">
        <div className="grid grid-cols-3 gap-2">
          <FooterButton icon={Download} label={props.text.export} onClick={props.onExport} />
          <FooterButton icon={Clipboard} label={props.text.copyAll} onClick={props.onCopyAll} />
          <FooterButton icon={FileUp} label={props.text.restore} onClick={props.onRestore} />
        </div>
        <label className="min-h-11 rounded-lg border border-white/10 px-3 flex items-center gap-2">
          <Globe2 className="w-4 h-4 text-muted-foreground" />
          <span className="text-xs text-muted-foreground shrink-0">{props.text.language}</span>
          <select
            value={props.locale}
            onChange={(event) => props.onLocale(event.target.value as ReviewLocale)}
            className="min-h-10 flex-1 bg-transparent text-sm outline-none"
          >
            {reviewLocaleOptions.map((option) => (
              <option key={option.value} value={option.value} className="bg-background">{option.label}</option>
            ))}
          </select>
        </label>
        <p className="text-[10px] leading-relaxed text-muted-foreground">{props.text.storageNote}</p>
      </footer>
    </section>
  );
}

function SaveState({ text, timestamp, locale, updated }: { text: string; timestamp: string | null; locale: ReviewLocale; updated: string }) {
  return (
    <div className="min-h-6 flex items-center gap-1.5 text-xs text-muted-foreground" aria-live="polite">
      <Check className="w-3.5 h-3.5 text-primary" />
      <span>{text}</span>
      {timestamp && <span>· {updated} {formatTime(timestamp, locale)}</span>}
    </div>
  );
}

function NoteCard({ label, value, timestamp, onOpen, onCopy, onDelete, openLabel }: {
  label: string; value: string; timestamp?: string; onOpen: () => void; onCopy: () => void; onDelete?: () => void; openLabel: string;
}) {
  return (
    <article className="rounded-xl border border-white/10 bg-white/[0.025] p-3">
      <div className="font-medium text-sm break-words">{label}</div>
      <p className="text-xs text-muted-foreground mt-1 line-clamp-3 whitespace-pre-wrap">{value}</p>
      {timestamp && <div className="text-[10px] text-muted-foreground mt-2">{timestamp}</div>}
      <div className="flex gap-2 mt-3">
        <button type="button" onClick={onOpen} className="min-h-11 px-3 rounded-lg bg-primary/15 text-primary text-sm">{openLabel}</button>
        <button type="button" onClick={onCopy} className="w-11 h-11 rounded-lg bg-white/5 flex items-center justify-center" aria-label="Copy note"><Clipboard className="w-4 h-4" /></button>
        {onDelete && <button type="button" onClick={onDelete} className="w-11 h-11 rounded-lg bg-destructive/15 text-destructive flex items-center justify-center" aria-label="Delete note"><Trash2 className="w-4 h-4" /></button>}
      </div>
    </article>
  );
}

function FooterButton({ icon: Icon, label, onClick }: { icon: typeof Download; label: string; onClick: () => void }) {
  return <button type="button" onClick={onClick} className="min-h-11 rounded-lg bg-white/5 text-xs flex items-center justify-center gap-1.5"><Icon className="w-4 h-4" /> {label}</button>;
}

function formatTime(value: string, locale: ReviewLocale): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(locale, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }).format(date);
}
