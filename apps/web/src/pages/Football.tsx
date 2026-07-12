import { SportPage } from "@/components/SportPage";
import { mapFootballGames, mapFootballStandings } from "@/lib/football";

export default function Football() {
  return (
    <SportPage
      title="World Cup 2026"
      subtitle="Fixtures, results, and group standings. Not betting advice."
      liveKey="football_live"
      gamesKey="football_fixtures"
      standingsKey="football_standings"
      mapGames={mapFootballGames}
      mapStandings={mapFootballStandings}
    />
  );
}
