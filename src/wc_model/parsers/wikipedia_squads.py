from __future__ import annotations

import re
from datetime import date
from typing import Iterable


def clean_wiki_text(value: str) -> str:
    value = value.replace("\n", " ").strip()
    value = re.sub(r"<ref[^>]*>.*?</ref>", "", value)
    value = re.sub(r"<ref[^/]*/>", "", value)
    value = value.replace("'''", "").replace("''", "")
    value = re.sub(r"\{\{!\}\}", "|", value)
    value = re.sub(r"\{\{[^{}]*\}\}", "", value)

    def replace_link(match: re.Match[str]) -> str:
        inner = match.group(1)
        if "|" in inner:
            return inner.split("|")[-1]
        return inner

    value = re.sub(r"\[\[([^\]]+)\]\]", replace_link, value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def wiki_link_target(value: str) -> str:
    match = re.search(r"\[\[([^\]|]+)", value)
    return match.group(1).strip() if match else ""


def split_top_level_pipe(text: str) -> list[str]:
    parts: list[str] = []
    current: list[str] = []
    curly_depth = 0
    square_depth = 0
    i = 0
    while i < len(text):
        two = text[i : i + 2]
        if two == "{{":
            curly_depth += 1
            current.append(two)
            i += 2
            continue
        if two == "}}" and curly_depth > 0:
            curly_depth -= 1
            current.append(two)
            i += 2
            continue
        if two == "[[":
            square_depth += 1
            current.append(two)
            i += 2
            continue
        if two == "]]" and square_depth > 0:
            square_depth -= 1
            current.append(two)
            i += 2
            continue
        if text[i] == "|" and curly_depth == 0 and square_depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(text[i])
        i += 1
    parts.append("".join(current))
    return parts


def parse_template(template: str) -> dict[str, str]:
    body = template.strip()
    if body.startswith("{{"):
        body = body[2:]
    if body.endswith("}}"):
        body = body[:-2]
    parts = split_top_level_pipe(body)
    values: dict[str, str] = {"template": parts[0].strip() if parts else ""}
    for part in parts[1:]:
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def birth_date_from_age_template(value: str) -> str:
    match = re.search(r"birth date and age2\|(\d{4})\|(\d{1,2})\|(\d{1,2})\|(\d{4})\|(\d{1,2})\|(\d{1,2})", value)
    if not match:
        return ""
    year, month, day = int(match.group(4)), int(match.group(5)), int(match.group(6))
    return date(year, month, day).isoformat()


def age_years_on(value: str) -> int | None:
    match = re.search(r"birth date and age2\|(\d{4})\|(\d{1,2})\|(\d{1,2})\|(\d{4})\|(\d{1,2})\|(\d{1,2})", value)
    if not match:
        return None
    as_of = date(int(match.group(1)), int(match.group(2)), int(match.group(3)))
    born = date(int(match.group(4)), int(match.group(5)), int(match.group(6)))
    return as_of.year - born.year - ((as_of.month, as_of.day) < (born.month, born.day))


def find_template_end(text: str, start: int) -> int:
    depth = 0
    i = start
    while i < len(text):
        two = text[i : i + 2]
        if two == "{{":
            depth += 1
            i += 2
            continue
        if two == "}}":
            depth -= 1
            i += 2
            if depth == 0:
                return i
            continue
        i += 1
    return len(text)


def iter_player_templates(wikitext: str) -> Iterable[tuple[int, str]]:
    marker = "{{nat fs g player"
    start = 0
    while True:
        index = wikitext.find(marker, start)
        if index == -1:
            return
        end = find_template_end(wikitext, index)
        yield index, wikitext[index:end]
        start = end


def context_for_index(prefix: str) -> tuple[str, str]:
    group_matches = list(re.finditer(r"^==\s*(Group [A-L])\s*==\s*$", prefix, re.MULTILINE))
    team_matches = list(re.finditer(r"^===\s*([^=]+?)\s*===\s*$", prefix, re.MULTILINE))
    group = group_matches[-1].group(1).strip() if group_matches else ""
    team = team_matches[-1].group(1).strip() if team_matches else ""
    return group, team


def to_int(value: str) -> int | None:
    value = clean_wiki_text(value)
    if not value:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def parse_squads(wikitext: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for index, template in iter_player_templates(wikitext):
        group, team = context_for_index(wikitext[:index])
        values = parse_template(template)
        age_raw = values.get("age", "")
        rows.append(
            {
                "group_name": group,
                "team": team,
                "shirt_number": to_int(values.get("no", "")),
                "position": clean_wiki_text(values.get("pos", "")),
                "player_name": clean_wiki_text(values.get("name", "")),
                "player_wiki_title": wiki_link_target(values.get("name", "")),
                "sort_name": clean_wiki_text(values.get("sortname", "")),
                "birth_date": birth_date_from_age_template(age_raw),
                "age_years_as_of_2026_06_11": age_years_on(age_raw),
                "caps_before_tournament": to_int(values.get("caps", "")),
                "goals_before_tournament": to_int(values.get("goals", "")),
                "club": clean_wiki_text(values.get("club", "")),
                "club_wiki_title": wiki_link_target(values.get("club", "")),
                "club_country_code": clean_wiki_text(values.get("clubnat", "")),
                "notes": clean_wiki_text(values.get("other", "")),
                "is_captain": "captain" in clean_wiki_text(values.get("other", "")).lower(),
            }
        )
    return rows

