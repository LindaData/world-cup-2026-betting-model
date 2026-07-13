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
      copy={{
        emptyLive: "Nothing is live right now. Live scores appear here on match days.",
        emptyStandings:
          "Group tables appear here after the first matchday, then update after every result.",
        emptyGames:
          "The full match schedule — with final scores and the model's win probabilities — loads here once the fixture feed connects.",
      }}
      mapGames={mapFootballGames}
      mapStandings={mapFootballStandings}
    />
  );
}
