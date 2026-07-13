import type { ReviewLocale } from "../reviewWorkspace";
import us from "./en-US";
import es from "./es";
import fr from "./fr";
import type { ReviewMessages } from "./types";

export const reviewMessages: Record<ReviewLocale, ReviewMessages> = {
  "en-US": us,
  "en-GB": { ...us, minimize: "Minimise notebook" },
  "en-AU": { ...us, minimize: "Minimise notebook" },
  es,
  fr,
};

export const reviewLocaleOptions: Array<{ value: ReviewLocale; label: string }> = [
  { value: "en-US", label: "English (US)" },
  { value: "en-GB", label: "English (UK)" },
  { value: "en-AU", label: "English (Australia)" },
  { value: "es", label: "Español" },
  { value: "fr", label: "Français" },
];

export type { ReviewMessages } from "./types";
