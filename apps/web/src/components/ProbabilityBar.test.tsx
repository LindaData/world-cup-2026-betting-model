import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { ProbabilityBar } from "./ProbabilityBar";

describe("ProbabilityBar", () => {
  it("renders three segments with widths proportional to probabilities", () => {
    render(<ProbabilityBar probs={{ home: 0.5, draw: 0.2, away: 0.3 }} />);

    expect(screen.getByTestId("prob-segment-home").style.width).toBe("50%");
    expect(screen.getByTestId("prob-segment-draw").style.width).toBe("20%");
    expect(screen.getByTestId("prob-segment-away").style.width).toBe("30%");
  });

  it("shows percent labels inside segments", () => {
    render(<ProbabilityBar probs={{ home: 0.64, draw: 0.22, away: 0.14 }} />);

    expect(screen.getByText("64%")).toBeInTheDocument();
    expect(screen.getByText("22%")).toBeInTheDocument();
    expect(screen.getByText("14%")).toBeInTheDocument();
  });

  it("normalizes inputs that do not sum to 1", () => {
    render(<ProbabilityBar probs={{ home: 50, draw: 25, away: 25 }} />);

    expect(screen.getByTestId("prob-segment-home").style.width).toBe("50%");
    expect(screen.getByTestId("prob-segment-draw").style.width).toBe("25%");
    expect(screen.getByTestId("prob-segment-away").style.width).toBe("25%");
  });

  it("omits the market bar when marketProbs is absent", () => {
    render(<ProbabilityBar probs={{ home: 0.4, draw: 0.3, away: 0.3 }} />);
    expect(screen.queryByTestId("market-bar")).toBeNull();
  });

  it("renders a second thinner bar for market probabilities", () => {
    render(
      <ProbabilityBar
        probs={{ home: 0.5, draw: 0.2, away: 0.3 }}
        marketProbs={{ home: 0.45, draw: 0.25, away: 0.3 }}
      />,
    );

    expect(screen.getByTestId("market-bar")).toBeInTheDocument();
    expect(screen.getByTestId("market-segment-home").style.width).toBe("45%");
    expect(screen.getByTestId("market-segment-draw").style.width).toBe("25%");
    expect(screen.getByTestId("market-segment-away").style.width).toBe("30%");
  });

  it("uses team labels in the accessible name", () => {
    render(
      <ProbabilityBar
        probs={{ home: 0.64, draw: 0.22, away: 0.14 }}
        labels={{ home: "France", away: "Brazil" }}
      />,
    );

    expect(
      screen.getByRole("img", { name: /Model: France 64%, Draw 22%, Brazil 14%/i }),
    ).toBeInTheDocument();
  });
});
