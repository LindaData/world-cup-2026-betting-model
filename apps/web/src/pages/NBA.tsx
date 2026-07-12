import { SportPage } from "@/components/SportPage";

export default function NBA() {
  return (
    <SportPage
      title="NBA"
      liveKey="nba_live"
      gamesKey="basketball_games"
      standingsKey="basketball_standings"
    />
  );
}
