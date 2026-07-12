import { SportPage } from "@/components/SportPage";

export default function MLB() {
  return (
    <SportPage
      title="MLB"
      liveKey="mlb_live"
      gamesKey="baseball_games"
      standingsKey="baseball_standings"
    />
  );
}
