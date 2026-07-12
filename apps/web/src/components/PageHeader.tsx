import type { ReactNode } from "react";

/**
 * Shared masthead: letterspaced mono eyebrow + 28-32px page title. Every
 * route uses this rhythm so the desk pages read as the same app as the
 * public pages.
 */
export function PageHeader({
  eyebrow,
  title,
  subtitle,
  badge,
  actions,
}: {
  /** Optional: omitted when a sub-nav under the title carries the context. */
  eyebrow?: string;
  title: string;
  subtitle?: string;
  /** Small chip rendered inline next to the title (e.g. a Demo chip), never
      detached at the far margin. */
  badge?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div>
        {eyebrow && <p className="label-mono">{eyebrow}</p>}
        <div className={`flex flex-wrap items-center gap-2 ${eyebrow ? "mt-1" : ""}`}>
          <h1 className="text-2xl font-bold tracking-tight md:text-3xl">{title}</h1>
          {badge}
        </div>
        {subtitle && <p className="mt-1 text-sm text-muted-foreground">{subtitle}</p>}
      </div>
      {actions}
    </div>
  );
}

export default PageHeader;
