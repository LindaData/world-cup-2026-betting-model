import { useMemo, useState } from "react";
import type { StandingRow } from "@/types";

export function StandingsView({ rows }: { rows: StandingRow[] }) {
  const groups = useMemo(() => {
    const s = new Set<string>();
    rows.forEach((r) => r.group && s.add(r.group));
    return Array.from(s).sort();
  }, [rows]);
  const [group, setGroup] = useState<string>("all");

  const filtered = useMemo(
    () =>
      (group === "all" ? rows : rows.filter((r) => r.group === group)).sort(
        (a, b) => Number(a.position) - Number(b.position),
      ),
    [rows, group],
  );

  // Football feeds carry points/draws; NBA/MLB carry win percentage.
  const isFootball = useMemo(() => rows.some((r) => r.points), [rows]);

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        <Chip active={group === "all"} onClick={() => setGroup("all")}>
          All
        </Chip>
        {groups.map((g) => (
          <Chip key={g} active={group === g} onClick={() => setGroup(g)}>
            {g}
          </Chip>
        ))}
      </div>

      <div className="md:hidden space-y-2">
        {filtered.map((r) => (
          <div key={`${r.group}-${r.team_id}`} className="surface-card p-3 flex items-center gap-3">
            <div className="w-7 text-center font-bold text-primary">{r.position}</div>
            <div className="flex-1 min-w-0">
              <div className="font-medium text-card-foreground truncate">{r.team}</div>
              <div className="text-[11px] text-muted-foreground">{r.group}</div>
            </div>
            <div className="text-right">
              <div className="font-semibold tabular-nums text-card-foreground">
                {isFootball ? `${r.wins}-${r.draws}-${r.losses}` : `${r.wins}-${r.losses}`}
              </div>
              <div className="text-[11px] text-muted-foreground tabular-nums">
                {isFootball ? `${r.points} pts` : r.percentage}
              </div>
            </div>
          </div>
        ))}
      </div>

      <div className="hidden md:block surface-card overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-muted/40 text-card-foreground">
            <tr>
              <th className="px-3 py-2 text-left font-medium">#</th>
              <th className="px-3 py-2 text-left font-medium">Team</th>
              <th className="px-3 py-2 text-left font-medium">Group</th>
              {isFootball && <th className="px-3 py-2 text-right font-medium">P</th>}
              <th className="px-3 py-2 text-right font-medium">W</th>
              {isFootball && <th className="px-3 py-2 text-right font-medium">D</th>}
              <th className="px-3 py-2 text-right font-medium">L</th>
              {isFootball ? (
                <>
                  <th className="px-3 py-2 text-right font-medium">GD</th>
                  <th className="px-3 py-2 text-right font-medium">Pts</th>
                </>
              ) : (
                <th className="px-3 py-2 text-right font-medium">Pct</th>
              )}
              <th className="px-3 py-2 text-left font-medium">Form</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((r) => (
              <tr key={`${r.group}-${r.team_id}`} className="border-t border-black/5 text-card-foreground">
                <td className="px-3 py-2 font-semibold text-primary">{r.position}</td>
                <td className="px-3 py-2 font-medium">{r.team}</td>
                <td className="px-3 py-2 text-muted-foreground">{r.group}</td>
                {isFootball && <td className="px-3 py-2 text-right tabular-nums">{r.played}</td>}
                <td className="px-3 py-2 text-right tabular-nums">{r.wins}</td>
                {isFootball && <td className="px-3 py-2 text-right tabular-nums">{r.draws}</td>}
                <td className="px-3 py-2 text-right tabular-nums">{r.losses}</td>
                {isFootball ? (
                  <>
                    <td className="px-3 py-2 text-right tabular-nums">{r.goal_difference}</td>
                    <td className="px-3 py-2 text-right tabular-nums font-semibold">{r.points}</td>
                  </>
                ) : (
                  <td className="px-3 py-2 text-right tabular-nums">{r.percentage}</td>
                )}
                <td className="px-3 py-2 text-muted-foreground tracking-wider">{r.form}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function Chip({
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
      onClick={onClick}
      className={`chip transition ${
        active
          ? "bg-primary text-primary-foreground"
          : "bg-white/5 text-foreground/70 hover:bg-white/10 border border-white/10"
      }`}
    >
      {children}
    </button>
  );
}
