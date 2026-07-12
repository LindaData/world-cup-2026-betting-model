import { SportPage } from "@/components/SportPage";

export default function MLB() {
  return (
    <SportPage
      title="MLB"
      subtitle="Recent games, standings, and season results. Not betting advice."
      liveKey="mlb_live"
      gamesKey="baseball_games"
      standingsKey="baseball_standings"
      copy={{
        liveTitle: "Recent games",
        gamesTitle: "Schedule & Results",
        emptyLive:
          "No games in progress. On game days, scores tick here through the final out.",
        emptyStandings:
          "Division standings appear here once the standings feed publishes.",
        emptyGames:
          "The season schedule and final scores land here once the games feed connects.",
        offlineLive:
          "Feed offline — final scores from recent games land back here once it reconnects.",
        offlineStandings:
          "Feed offline — division tables with W-L records return here once it reconnects.",
        offlineGames:
          "Feed offline — the season schedule and final scores return here once it reconnects.",
      }}
    />
  );
}
