import { SportPage } from "@/components/SportPage";

export default function NBA() {
  return (
    <SportPage
      title="NBA"
      subtitle="Recent games, standings, and season results. Not betting advice."
      liveKey="nba_live"
      gamesKey="basketball_games"
      standingsKey="basketball_standings"
      copy={{
        liveTitle: "Recent games",
        gamesTitle: "Schedule & Results",
        emptyLive:
          "No games in progress. On game nights, scores tick here through the final buzzer.",
        emptyStandings:
          "Conference standings appear here once the standings feed publishes.",
        emptyGames:
          "The season schedule and final scores land here once the games feed connects.",
        offlineLive:
          "Feed offline — final scores from recent games land back here once it reconnects.",
        offlineStandings:
          "Feed offline — conference tables with W-L records and streaks return here once it reconnects.",
        offlineGames:
          "Feed offline — the season schedule and final scores return here once it reconnects.",
      }}
    />
  );
}
