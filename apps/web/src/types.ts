export interface GameRow {
  sport: string;
  game_id: string;
  date_utc: string;
  status: string;
  league_id: string;
  league: string;
  season: string;
  home_team_id: string;
  home_team: string;
  away_team_id: string;
  away_team: string;
  home_score: string;
  away_score: string;
}

export interface StandingRow {
  sport: string;
  position: string;
  group: string;
  team_id: string;
  team: string;
  played: string;
  wins: string;
  losses: string;
  percentage: string;
  form: string;
  // Football-only columns (empty strings for NBA/MLB feeds)
  draws?: string;
  goals_for?: string;
  goals_against?: string;
  goal_difference?: string;
  points?: string;
}

export interface LiveEvent {
  event_id: string;
  date_utc: string;
  name: string;
  short_name: string;
  status: string;
  status_short: string;
  state: string;
  period: number;
  clock: string;
  home_team: string;
  away_team: string;
  home_score: string;
  away_score: string;
  home_record?: string;
  away_record?: string;
  venue?: string;
  broadcasts?: string[];
  link?: string;
}

export interface LiveFeed {
  sport: string;
  refreshed_at_utc: string;
  event_count: number;
  events: LiveEvent[];
}

export interface Manifest {
  refreshed_at_utc: string;
  sports: Record<
    string,
    {
      league_id: number;
      season: string;
      available_games: number;
      published_games: number;
      standings_rows: number;
    }
  >;
}
