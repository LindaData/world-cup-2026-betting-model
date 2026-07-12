// @vitest-environment jsdom

import { beforeEach, describe, expect, it } from "vitest";
import {
  APPROVAL_STORAGE_KEY,
  detectReviewLocale,
  getReviewContext,
  importReviewWorkspace,
  persistContextNote,
  readApprovalNote,
  readReviewWorkspace,
  reviewWorkspaceToMarkdown,
  setContextNote,
  setGlobalNote,
} from "./reviewWorkspace";

describe("review workspace", () => {
  beforeEach(() => localStorage.clear());

  it("tracks dataset and route notes separately", () => {
    expect(getReviewContext("/approval", "?dataset=teams").key).toBe("dataset:teams");
    expect(getReviewContext("/datasets").key).toBe("route:/datasets");
  });

  it("syncs dataset notes without changing approval decisions", () => {
    localStorage.setItem(APPROVAL_STORAGE_KEY, JSON.stringify({ teams: { decision: "approved" } }));
    persistContextNote(getReviewContext("/approval", "?dataset=teams"), "Check aliases");
    const approvals = JSON.parse(localStorage.getItem(APPROVAL_STORAGE_KEY) ?? "{}");
    expect(approvals.teams.decision).toBe("approved");
    expect(readApprovalNote("teams")).toBe("Check aliases");
  });

  it("exports global and contextual notes", () => {
    let workspace = readReviewWorkspace();
    workspace = setGlobalNote(workspace, "Executive summary", "2026-01-01T00:00:00.000Z");
    workspace = setContextNote(workspace, getReviewContext("/quality"), "Check nulls", "Data quality", "2026-01-02T00:00:00.000Z");
    const markdown = reviewWorkspaceToMarkdown(workspace);
    expect(markdown).toContain("Executive summary");
    expect(markdown).toContain("Check nulls");
  });

  it("restores a multilingual backup", () => {
    const restored = importReviewWorkspace({ version: 2, locale: "fr", globalText: "Review", globalUpdatedAt: null, notes: {} });
    expect(restored.locale).toBe("fr");
  });

  it("detects supported locales", () => {
    expect(detectReviewLocale("en-GB")).toBe("en-GB");
    expect(detectReviewLocale("en-AU")).toBe("en-AU");
    expect(detectReviewLocale("es-MX")).toBe("es");
    expect(detectReviewLocale("fr-CA")).toBe("fr");
  });
});
