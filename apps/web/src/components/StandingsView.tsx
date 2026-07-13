import { useMemo, useState } from "react";
import { cn } from "@/lib/utils";
import type { StandingRow } from "@/types";

export function StandingsView({ rows }: { rows: StandingRow[] }) {
  const groups = useMemo(() => {
    const s = new Set<string>();
    rows.forEach((r) => r.group && s.add(r.group));
    return Array.from(s).sort();
  }, [rows]);
  const [group, setGroup] = useState<string>("all");

  // "All" never interleaves independent rank sequences: it renders one block
  // per group (with a header) so ranks always read within their own group.
  const sections = useMemo<{ label: string | null; rows: StandingRow[] }[]>(() => {
    const byPosition = (list: StandingRow[]) =>
      [...list].sort((a, b) => Number(a.position) - Number(b.position));
    if (group !== "all") {
      return [{ label: null, rows: byPosition(rows.filter((r) => r.group === group)) }];
    }
    if (groups.length <= 1) return [{ label: null, rows: byPosition(rows) }];
    return groups.map((g) => ({
      label: g,
      rows: byPosition(rows.filter((r) => r.group === g)),
    }));
  }, [rows, group, groups]);

  // Football feeds carry points/draws; NBA/MLB carry win percentage.
  const isFootball = useMemo(() => rows.some((r) => r.points), [rows]);
  // Rows always render either under a group section header ("All" view) or a
  // single-group filter, so a per-row group label would state the group a
  // second (or third) time. A future flat/sortable view without section
  // headers can reintroduce the column.
  // Football drops the FORM column: "WWD" strings are insider shorthand, not
  // model output — and the model is the product.
  const columnCount = isFootball ? 8 : 6;

  return (
    <div className="space-y-3">
      {groups.length > 0 && (
        <div className="flex flex-wrap gap-1" role="group" aria-label="Filter by group">
          <GroupChip active={group === "all"} onClick={() => setGroup("all")}>
            All
          </GroupChip>
          {groups.map((g) => (
            <GroupChip key={g} active={group === g} onClick={() => setGroup(g)}>
              {g}
            </GroupChip>
          ))}
        </div>
      )}

      {/* Mobile cards */}
      <div className="space-y-2 md:hidden">
        {sections.map((section) => (
          <div key={section.label ?? "single"} className="space-y-2">
            {section.label && <div className="label-mono px-1 pt-1">{section.label}</div>}
            {section.rows.map((r) => (
              <div
                key={`${r.group}-${r.team_id}`}
                className="surface-card flex items-center gap-3 p-3"
              >
                <div className="w-6 text-center text-sm font-semibold tabular-nums text-muted-foreground">
                  {r.position}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-semibold text-card-foreground">
                    {r.team}
                  </div>
                </div>
                <div className="text-right">
                  {isFootball ? (
                    <>
                      <div className="text-lg font-extrabold leading-none tabular-nums text-card-foreground">
                        {r.points}
                        <span className="label-mono ml-1">pts</span>
                      </div>
                      <div className="label-mono mt-1 tabular-nums">
                        {r.wins}W-{r.draws}D-{r.losses}L · {formatGoalDiff(r.goal_difference)}
                      </div>
                    </>
                  ) : (
                    <>
                      <div className="text-lg font-extrabold leading-none tabular-nums text-card-foreground">
                        {r.wins}-{r.losses}
                      </div>
                      <div className="label-mono mt-1 tabular-nums">{r.percentage}</div>
                    </>
                  )}
                </div>
              </div>
            ))}
          </div>
        ))}
      </div>

      {/* Desktop table — football keeps P/W/D/L/GD/Pts */}
      <div className="surface-card hidden overflow-x-auto md:block">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border">
              <Th>#</Th>
              <Th>Team</Th>
              {isFootball && <Th right>P</Th>}
              <Th right>W</Th>
              {isFootball && <Th right>D</Th>}
              <Th right>L</Th>
              {isFootball ? (
                <>
                  <Th right>GD</Th>
                  <Th right>Pts</Th>
                </>
              ) : (
                <>
                  <Th right>Pct</Th>
                  <Th>Form</Th>
                </>
              )}
            </tr>
          </thead>
          <tbody>
            {sections.map((section) => [
              section.label ? (
                <tr key={`header-${section.label}`} className="border-b border-border">
                  <td colSpan={columnCount} className="label-mono bg-muted/40 px-3 py-2">
                    {section.label}
                  </td>
                </tr>
              ) : null,
              ...section.rows.map((r) => (
              <tr
                key={`${r.group}-${r.team_id}`}
                className="border-b border-border/60 text-card-foreground last:border-0"
              >
                <td className="px-3 py-2 tabular-nums text-muted-foreground">{r.position}</td>
                <td className="px-3 py-2 font-semibold">{r.team}</td>
                {isFootball && <td className="px-3 py-2 text-right tabular-nums">{r.played}</td>}
                <td className="px-3 py-2 text-right tabular-nums">{r.wins}</td>
                {isFootball && <td className="px-3 py-2 text-right tabular-nums">{r.draws}</td>}
                <td className="px-3 py-2 text-right tabular-nums">{r.losses}</td>
                {isFootball ? (
                  <>
                    <td className="px-3 py-2 text-right tabular-nums">{r.goal_difference}</td>
                    <td className="px-3 py-2 text-right font-extrabold tabular-nums">
                      {r.points}
                    </td>
                  </>
                ) : (
                  <>
                    <td className="px-3 py-2 text-right tabular-nums">{r.percentage}</td>
                    <td className="label-mono px-3 py-2">{r.form}</td>
                  </>
                )}
              </tr>
              )),
            ])}
          </tbody>
        </table>
        {/* Spell the abbreviations out once — a first-time reader should never
            have to decode P/W/D/L/GD. */}
        {isFootball && (
          <p className="label-mono border-t border-border px-3 py-2">
            P played · W wins · D draws · L losses · GD goal difference
          </p>
        )}
      </div>
    </div>
  );
}

function Th({ children, right }: { children: React.ReactNode; right?: boolean }) {
  return (
    <th className={cn("label-mono px-3 py-2.5 font-medium", right ? "text-right" : "text-left")}>
      {children}
    </th>
  );
}

function GroupChip({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      aria-pressed={active}
      onClick={onClick}
      className={cn(
        // 44px touch targets, and a visible border/background on every chip
        // so unselected filters still read as interactive.
        "chip min-h-11 border px-3 transition-colors",
        active
          ? "border-border bg-muted text-foreground"
          : "border-border/60 bg-card text-muted-foreground hover:text-foreground",
      )}
    >
      {children}
    </button>
  );
}
