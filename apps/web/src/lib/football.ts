import type { GameRow, StandingRow } from "@/types";

// Football fixtures/standings are published as JSON with numeric/null values
// (see scripts/publish_football_espn.py and publish_api_football.py at the
// repo root). GamesView/StandingsView expect the string-valued row shapes the
// CSV feeds produce, so normalize here.

type FixtureJson = Record<string, unknown>;

const s = (v: unknown): string => (v == null ? "" : String(v));

export function mapFootballGames(data: unknown): GameRow[] {
  if (!Array.isArray(data)) return [];
  return (data as FixtureJson[]).map((r) => ({
    sport: "Football",
    game_id: s(r.game_id),
    date_utc: s(r.date_utc),
    status: s(r.status),
    league_id: s(r.league_id),
    league: s(r.league),
    season: s(r.season),
    home_team_id: s(r.home_team_id),
    home_team: s(r.home_team),
    away_team_id: s(r.away_team_id),
    away_team: s(r.away_team),
    home_score: s(r.home_score),
    away_score: s(r.away_score),
  }));
}

export function mapFootballStandings(data: unknown): StandingRow[] {
  if (!Array.isArray(data)) return [];
  return (data as FixtureJson[]).map((r) => ({
    sport: "Football",
    position: s(r.position),
    group: s(r.group) || "Overall",
    team_id: s(r.team_id) || s(r.team),
    team: s(r.team),
    played: s(r.played),
    wins: s(r.wins),
    losses: s(r.losses),
    percentage: s(r.percentage),
    form: s(r.form),
    draws: s(r.draws),
    goals_for: s(r.goals_for),
    goals_against: s(r.goals_against),
    goal_difference: s(r.goal_difference),
    points: s(r.points),
  }));
}
