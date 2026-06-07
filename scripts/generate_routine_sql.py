#!/usr/bin/env python3
"""
Generate an SQL INSERT script from the class routine JSON file.
Output: SQL script to run in Supabase SQL Editor.

Usage:
    python scripts/generate_routine_sql.py
    python scripts/generate_routine_sql.py path/to/routine.json
"""

import json
import os
import re
import sys


def period_index_from_time(time_str: str) -> int:
    """Mirrors RoutineJsonParser.periodIndexFromTime."""
    cleaned = time_str.strip()
    period_times = [
        "1:30 - 2:15 PM",              # 0
        "2:15 - 3:00 PM",              # 1
        "3:00 - 3:45 PM",              # 2
        "3:45 - 4:30 PM",              # 3
        "4:30 - 5:15 PM",              # 4
        "5:15 - 6:00 PM",              # 5
        "6:00 - 6:45 PM",              # 6
        "1:30 - 3:45 PM (2h 15m)",     # 7
        "2:15 - 4:30 PM (2h 15m)",     # 8
        "3:00 - 5:15 PM (2h 15m)",     # 9
        "3:45 - 6:00 PM (2h 15m)",     # 10
        "4:30 - 6:45 PM (2h 15m)",     # 11
    ]

    # Step 1: exact match
    for i, pt in enumerate(period_times):
        if pt == cleaned:
            return i

    # Step 2: range match (135-min combined periods)
    m = re.search(
        r"(\d{1,2}):(\d{2})\s*(?:–|-|to)\s*(\d{1,2}):(\d{2})",
        cleaned, re.IGNORECASE
    )
    if m:
        sh, sm, eh, em = map(int, [m.group(1), m.group(2), m.group(3), m.group(4)])
        s_min = (sh + 12 if sh < 7 else sh) * 60 + sm
        e_min = (eh + 12 if eh < 7 else eh) * 60 + em
        dur = e_min - s_min
        if dur == 135:
            combined_starts = [810, 855, 900, 945, 990]
            for i in range(len(combined_starts) - 1, -1, -1):
                if s_min >= combined_starts[i]:
                    return i + 7

    # Step 3: integer parse
    try:
        return int(cleaned)
    except ValueError:
        pass

    # Step 4: "Period X" pattern
    pm = re.search(r"(?:period|p)\s*(\d+)", cleaned, re.IGNORECASE)
    if pm:
        num = int(pm.group(1))
        return num - 1 if num > 0 else 0

    # Step 5: single time match
    tm = re.search(r"(\d{1,2}):(\d{2})", cleaned)
    if tm:
        h, m2 = int(tm.group(1)), int(tm.group(2))
        mins = h * 60 + m2
        starts = [810, 855, 900, 945, 990, 1035, 1080]
        for i in range(len(starts) - 1, -1, -1):
            if mins >= starts[i]:
                return i

    return 0


def normalize_day(day: str) -> str:
    mapping = {
        "Sunday": "SUN", "Monday": "MON", "Tuesday": "TUE",
        "Wednesday": "WED", "Thursday": "THU", "Friday": "FRI", "Saturday": "SAT",
    }
    return mapping.get(day, day[:3].upper())


def esc(val: str) -> str:
    if not val:
        return "NULL"
    escaped = val.replace("'", "''")
    return f"'{escaped}'"


def main():
    # Determine input path
    if len(sys.argv) > 1:
        json_path = sys.argv[1]
    else:
        home = os.path.expanduser("~")
        json_path = os.path.join(home, "Downloads", "class_routine_3rd_semester.json")

    if not os.path.exists(json_path):
        print(f"ERROR: File not found: {json_path}", file=sys.stderr)
        sys.exit(1)

    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    output_path = os.path.splitext(json_path)[0] + "_insert.sql"

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("-- ============================================================\n")
        f.write("--  CST PORTAL - INSERT CLASS ROUTINE SLOTS\n")
        f.write(f"--  Source: {os.path.basename(json_path)}\n")
        f.write(f"--  Generated: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        f.write(f"--  Total entries: {len(data['routines'])}\n")
        f.write("--  Run this in Supabase Dashboard \u2192 SQL Editor\n")
        f.write("-- ============================================================\n\n")

        f.write("-- Clear existing 3rd-semester routines before inserting\n")
        f.write("DELETE FROM public.class_routine_slots WHERE semester = 3;\n\n")

        f.write("-- Insert routine slots\n")

        combined_count = 0
        for r in data["routines"]:
            day_code = normalize_day(r["day"])
            pidx = period_index_from_time(r["time"])
            acronym = r["teacher_acronym"] or ""
            subject = r["title"]
            code = r["subject_code"]
            room = r["description"] or ""

            if "(2h 15m)" in r["time"]:
                combined_count += 1

            sql = (
                f"INSERT INTO public.class_routine_slots "
                f"(semester, day, period_index, subject, subject_code, acronym, room) "
                f"VALUES (3, {esc(day_code)}, {pidx}, {esc(subject)}, "
                f"{esc(code)}, {esc(acronym)}, {esc(room)});\n"
            )
            f.write(sql)

        f.write("\n-- Verify the inserted data\n")
        f.write("SELECT day, period_index, subject, subject_code, acronym, room \n")
        f.write("FROM public.class_routine_slots \n")
        f.write("WHERE semester = 3 \n")
        f.write("ORDER BY day, period_index;\n")

    total = len(data["routines"])
    print(f"SQL script written to: {output_path}")
    print(f"  {total} routine entries ({combined_count} combined 135-min periods)")
    print(f"\nTo upload:")
    print("  1. Go to Supabase Dashboard -> SQL Editor")
    print("  2. Open and paste the contents of this file")
    print("  3. Click 'Run'")
    print("  4. The app will automatically detect the changes via its real-time subscription")


if __name__ == "__main__":
    main()
