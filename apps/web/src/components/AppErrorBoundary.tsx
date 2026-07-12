import { Component, type ErrorInfo, type ReactNode } from "react";

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
}

export default class AppErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("Game Stat Pulse failed to render", error, info);
  }

  render() {
    if (!this.state.hasError) return this.props.children;

    return (
      <main className="min-h-screen bg-background text-foreground px-5 py-16 flex items-center justify-center">
        <section className="w-full max-w-md rounded-2xl border border-white/15 bg-card text-card-foreground p-6 shadow-2xl">
          <div className="text-xs uppercase tracking-widest text-primary">Game Stat Pulse</div>
          <h1 className="mt-2 text-2xl font-bold">The review page did not load correctly</h1>
          <p className="mt-3 text-sm text-muted-foreground">
            Your saved review notes remain on this device. Reload the page to try again.
          </p>
          <button
            type="button"
            onClick={() => window.location.reload()}
            className="mt-6 min-h-12 w-full rounded-xl bg-primary px-4 font-semibold text-primary-foreground"
          >
            Reload review page
          </button>
        </section>
      </main>
    );
  }
}
