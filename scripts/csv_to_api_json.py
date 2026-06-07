#!/usr/bin/env python3
"""
CSV → Routine JSON API Converter

Converts a class routine CSV file into the JSON payload format expected
by the CST Portal app's API (RoutineSchedulePayload).

Usage:
    python scripts/csv_to_api_json.py path/to/routine.csv [--output path/to/output.json]
    python scripts/csv_to_api_json.py                          # uses default Downloads path
    python scripts/csv_to_api_json.py --pretty                  # pretty-print the JSON

Output format:
    {
      "last_updated": "2026-05-31T12:00:00.000Z",
      "routines": [
        {
          "id": "1",
          "subject_code": "25931",
          "teacher_acronym": "PT-3",
          "day": "Sunday",
          "time": "1:30 – 2:15 PM",
          "title": "Mathematics-III",
          "description": "2306"
        },
        ...
      ],
      "skipped_records": [
        {"row": 5, "reason": "Missing required field(s): day", "raw": {...}}
      ]
    }
"""

import argparse
import csv
import json
import os
import re
import sys
from datetime import datetime, timezone


# ─── Constants (mirrors RoutineService.periodTimes + RoutineJsonParser) ────

PERIOD_TIMES = [
    "1:30 \u2013 2:15 PM",           # index 0
    "2:15 \u2013 3:00 PM",           # index 1
    "3:00 \u2013 3:45 PM",           # index 2
    "3:45 \u2013 4:30 PM",           # index 3
    "4:30 \u2013 5:15 PM",           # index 4
    "5:15 \u2013 6:00 PM",           # index 5
    "6:00 \u2013 6:45 PM",           # index 6
    # 135-minute (2h 15m) combined periods
    "1:30 \u2013 3:45 PM (2h 15m)",   # index 7
    "2:15 \u2013 4:30 PM (2h 15m)",   # index 8
    "3:00 \u2013 5:15 PM (2h 15m)",   # index 9
    "3:45 \u2013 6:00 PM (2h 15m)",   # index 10
    "4:30 \u2013 6:45 PM (2h 15m)",   # index 11
]

REGULAR_PERIOD_COUNT = 7

DAY_DISPLAY = {
    "SUN": "Sunday",
    "MON": "Monday",
    "TUE": "Tuesday",
    "WED": "Wednesday",
    "THU": "Thursday",
    "FRI": "Friday",
    "SAT": "Saturday",
}

DAY_ALIASES = {
    "SUNDAY": "SUN",
    "SUN": "SUN",
    "MONDAY": "MON",
    "MON": "MON",
    "TUESDAY": "TUE",
    "TUE": "TUE",
    "TUES": "TUE",
    "WEDNESDAY": "WED",
    "WED": "WED",
    "THURSDAY": "THU",
    "THU": "THU",
    "THURS": "THU",
    "FRIDAY": "FRI",
    "FRI": "FRI",
    "SATURDAY": "SAT",
    "SAT": "SAT",
}

# 135-minute combined period start times in minutes past midnight
COMBINED_STARTS = [810, 855, 900, 945, 990]  # 1:30 PM, 2:15 PM, 3:00 PM, 3:45 PM, 4:30 PM

# Regular 45-min period start times
PERIOD_STARTS = [810, 855, 900, 945, 990, 1035, 1080]

# ─── Column header keyword lists (mirrors _subjectCodeHeaders, etc.) ────

SUBJECT_CODE_KEYWORDS = [
    "subject code", "subject_code", "code",
    "course code", "paper code", "paper",
]

ACRONYM_KEYWORDS = [
    "teacher acronym", "teacher_acronym", "acronym",
    "teacher short", "instructor acronym",
]

DAY_KEYWORDS = ["day", "weekday", "day of week"]

TIME_KEYWORDS = [
    "time", "period", "period time",
    "class time", "slot", "schedule",
]

TITLE_KEYWORDS = [
    "title", "subject name",
    "name of the subject", "name", "course", "paper name",
]

DESCRIPTION_KEYWORDS = [
    "description", "room", "classroom",
    "venue", "details", "location", "room number",
]

TEACHER_KEYWORDS = [
    "teacher", "teacher name", "instructor",
    "faculty", "name of the teacher",
]


# ─── Helper functions ────

def clean_cell(value: str) -> str:
    """Strip control characters and normalize whitespace (matches _cleanCell)."""
    text = str(value)
    text = re.sub(r"[\u0000-\u001F\u007F]", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def find_column(headers: list[str], keywords: list[str]) -> int:
    """Find the first header column matching any keyword (case-insensitive partial match)."""
    for i, h in enumerate(headers):
        for kw in keywords:
            if kw in h:
                return i
    return -1


def normalize_day(raw: str) -> str:
    """Convert a day string to its 3-letter code (SUN/MON/...). Returns empty string on failure."""
    cleaned = clean_cell(raw).upper()
    return DAY_ALIASES.get(cleaned, "")


def period_index_from_time(time_str: str) -> int:
    """
    Resolve a time string to a period index.
    Matches the Dart RoutineJsonParser.periodIndexFromTime logic exactly.
    """
    cleaned = clean_cell(time_str)

    # 1. Exact match against known period times (en-dash or hyphen)
    for i, pt in enumerate(PERIOD_TIMES):
        if pt == cleaned:
            return i

    # 2. Detect time ranges (e.g., "1:30 – 3:45 PM" or "1:30 - 3:45 PM")
    #    Matches both en-dash (–) and regular hyphen (-) and "to"
    range_match = re.search(
        r"(\d{1,2}):(\d{2})\s*(?:\u2013|-|to)\s*(\d{1,2}):(\d{2})",
        cleaned,
        re.IGNORECASE,
    )
    if range_match:
        sh, sm, eh, em = map(int, range_match.groups())
        s_min = (sh + 12 if sh < 7 else sh) * 60 + sm
        e_min = (eh + 12 if eh < 7 else eh) * 60 + em
        dur = e_min - s_min

        # Map 135-minute combined periods (indices 7-11)
        if dur == 135:
            for i in range(len(COMBINED_STARTS) - 1, -1, -1):
                if s_min >= COMBINED_STARTS[i]:
                    return i + REGULAR_PERIOD_COUNT

    # 3. Integer parse (e.g., "0", "3")
    try:
        return int(cleaned)
    except ValueError:
        pass

    # 4. "Period X" pattern (e.g., "period 3", "p 5")
    period_match = re.search(r"(?:period|p)\s*(\d+)", cleaned, re.IGNORECASE)
    if period_match:
        num = int(period_match.group(1))
        return num - 1 if num > 0 else 0

    # 5. Single time (e.g., "1:30", "14:15") — map to the nearest earlier period
    time_match = re.search(r"(\d{1,2}):(\d{2})", cleaned)
    if time_match:
        hour = int(time_match.group(1))
        minute = int(time_match.group(2))
        minutes = hour * 60 + minute
        for i in range(len(PERIOD_STARTS) - 1, -1, -1):
            if minutes >= PERIOD_STARTS[i]:
                return i

    return 0


def resolve_time_string(raw: str) -> str:
    """Resolve a raw time string to its canonical display form.
    Mirrors _resolveTimeString in the Dart parser."""
    cleaned = clean_cell(raw)
    if not cleaned:
        return ""

    # If it contains a time or a dash, return as-is (it will be resolved on import)
    if re.search(r"\d{1,2}:\d{2}", cleaned) or "\u2013" in cleaned or "-" in cleaned:
        return cleaned

    idx = period_index_from_time(cleaned)
    if 0 <= idx < len(PERIOD_TIMES):
        return PERIOD_TIMES[idx]

    return cleaned


def _iso_timestamp() -> str:
    """Return ISO 8601 UTC timestamp matching Dart's DateTime.toIso8601String() format."""
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"


def parse_csv(filepath: str) -> dict:
    """
    Parse a CSV file into the RoutineSchedulePayload JSON format.
    Returns: {
        "last_updated": "...",
        "routines": [...],
        "skipped_records": [...]
    }
    """
    with open(filepath, "r", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        rows = list(reader)

    if not rows:
        print("ERROR: File is empty", file=sys.stderr)
        sys.exit(1)

    # Find header row (look for known keywords in first 15 rows)
    header_idx = 0
    for i, row in enumerate(rows[:15]):
        joined = " ".join(row).lower()
        if any(kw in joined for kw in ["subject", "day", "time", "code"]):
            header_idx = i
            break

    headers = [clean_cell(c) for c in rows[header_idx]]
    header_lower = [h.lower() for h in headers]

    # Detect columns
    code_col = find_column(header_lower, SUBJECT_CODE_KEYWORDS)
    acronym_col = find_column(header_lower, ACRONYM_KEYWORDS)
    day_col = find_column(header_lower, DAY_KEYWORDS)
    time_col = find_column(header_lower, TIME_KEYWORDS)
    title_col = find_column(header_lower, TITLE_KEYWORDS)
    # Fallback: exact match for bare "Subject" header (not "subject code")
    if title_col < 0:
        for i, h in enumerate(header_lower):
            if h == "subject" and i != code_col:
                title_col = i
                break
    desc_col = find_column(header_lower, DESCRIPTION_KEYWORDS)
    teacher_col = -1
    if acronym_col < 0:
        teacher_col = find_column(header_lower, TEACHER_KEYWORDS)

    if code_col < 0 and title_col < 0:
        print(
            f"ERROR: Could not find Subject Code or Title column.\n"
            f"  Headers: {', '.join(headers)}",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"  Detected columns: code={code_col}  day={day_col}  time={time_col}  "
          f"title={title_col}  acronym={acronym_col}  teacher={teacher_col}  room={desc_col}")

    routines = []
    skipped = []
    seq = 1

    for i, row in enumerate(rows[header_idx + 1 :], start=header_idx + 2):
        if all(clean_cell(c) == "" for c in row):
            continue

        raw_map = {headers[j]: clean_cell(row[j]) for j in range(min(len(headers), len(row))) if clean_cell(row[j])}

        subject_code = clean_cell(row[code_col]).upper() if code_col >= 0 and code_col < len(row) else ""
        day_raw = clean_cell(row[day_col]) if day_col >= 0 and day_col < len(row) else ""
        time_raw = clean_cell(row[time_col]) if time_col >= 0 and time_col < len(row) else ""
        title = clean_cell(row[title_col]) if title_col >= 0 and title_col < len(row) else ""
        description = clean_cell(row[desc_col]) if desc_col >= 0 and desc_col < len(row) else ""

        acronym = ""
        if acronym_col >= 0 and acronym_col < len(row):
            acronym = clean_cell(row[acronym_col]).upper()
        if not acronym and teacher_col >= 0 and teacher_col < len(row):
            acronym = clean_cell(row[teacher_col]).upper()

        day_norm = normalize_day(day_raw)
        day_display = DAY_DISPLAY.get(day_norm, day_raw)
        time_resolved = resolve_time_string(time_raw)

        missing = []
        if not subject_code:
            missing.append("subject_code")
        if not day_norm:
            missing.append("day")
        if not time_resolved:
            missing.append("time")

        if missing:
            skipped.append({
                "row": i,
                "reason": f"Missing required field(s): {', '.join(missing)}",
                "raw": raw_map,
            })
            continue

        routines.append({
            "id": str(seq),
            "subject_code": subject_code,
            "teacher_acronym": acronym,
            "day": day_display,
            "time": time_resolved,
            "title": title if title else subject_code,
            "description": description,
        })
        seq += 1

    payload = {
        "last_updated": _iso_timestamp(),
        "routines": routines,
    }

    if skipped:
        payload["skipped_records"] = skipped

    return payload


# ─── Main ────

def main():
    parser = argparse.ArgumentParser(
        description="Convert a class routine CSV to the app's JSON API format.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python scripts/csv_to_api_json.py
      Uses default path: C:/Users/<user>/Downloads/class_routine_3rd_semester.csv

  python scripts/csv_to_api_json.py path/to/routine.csv
      Writes JSON to routine.json alongside the CSV

  python scripts/csv_to_api_json.py path/to/routine.csv --output output.json
      Writes JSON to output.json

  python scripts/csv_to_api_json.py --pretty
      Pretty-prints the JSON to stdout
        """,
    )
    parser.add_argument("input", nargs="?", help="Path to the CSV file")
    parser.add_argument("--output", "-o", help="Output JSON file path (default: <input>.json)")
    parser.add_argument("--pretty", "-p", action="store_true", help="Pretty-print JSON output")

    args = parser.parse_args()

    # Determine input path
    if args.input:
        csv_path = args.input
    else:
        # Default: Downloads folder
        home = os.path.expanduser("~")
        csv_path = os.path.join(home, "Downloads", "class_routine_3rd_semester.csv")

    if not os.path.exists(csv_path):
        print(f"ERROR: File not found: {csv_path}", file=sys.stderr)
        print(f"  Pass the CSV path as an argument, e.g.:")
        print(f"    python scripts/csv_to_api_json.py path/to/your_file.csv")
        sys.exit(1)

    print(f"Reading: {csv_path}")
    payload = parse_csv(csv_path)

    routines_count = len(payload["routines"])
    skipped_count = len(payload.get("skipped_records", []))

    # Count combined (2h 15m) entries
    combined_count = sum(
        1 for r in payload["routines"]
        if "(2h 15m)" in r["time"]
    )

    print(f"\nParsed {routines_count} routines" +
          (f", {skipped_count} skipped" if skipped_count else "") +
          f"  ({combined_count} combined 135-min periods)")

    # Determine output path
    if args.output:
        output_path = args.output
    else:
        base, _ = os.path.splitext(csv_path)
        output_path = f"{base}.json"

    # Write JSON
    json_kwargs = {"ensure_ascii": False}
    if args.pretty:
        json_kwargs["indent"] = 2

    json_str = json.dumps(payload, **json_kwargs)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(json_str)

    # Print formatted output to stdout when --pretty is used without --output
    if args.pretty and not args.output:
        print(f"\n{json_str}")

    # Summary
    print(f"\nOutput: {output_path}")
    print(f"   Size: {len(json_str):,} bytes")

    # Show routine summary by day
    day_order = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday"]
    by_day: dict[str, list] = {}
    for r in payload["routines"]:
        by_day.setdefault(r["day"], []).append(r)

    print(f"\nDaily breakdown:")
    for day in day_order:
        slots = by_day.get(day, [])
        if not slots:
            continue
        slots.sort(key=lambda s: period_index_from_time(s["time"]))
        combined = sum(1 for s in slots if "(2h 15m)" in s["time"])
        print(f"   {day[:3]}: {len(slots)} classes ({combined} combined)")


if __name__ == "__main__":
    main()
