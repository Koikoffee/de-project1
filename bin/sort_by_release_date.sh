#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# --- Paths & params ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFILE="${1:-$PROJECT_ROOT/data/tmdb-movies.csv}"
OUTFILE="${2:-$PROJECT_ROOT/out/movies_sorted_by_release_date.csv}"
WITH_BOM="${WITH_BOM:-0}"  # set 1 to prepend UTF-8 BOM for Excel
mkdir -p "$PROJECT_ROOT/out" "$PROJECT_ROOT/logs"

command -v gawk >/dev/null || { echo "Missing command: gawk" >&2; exit 1; }
[[ -f "$INFILE" ]] || { echo "Input file not found: $INFILE" >&2; exit 1; }

# --- Optional BOM for better Excel UTF-8 detection ---
if [[ "$WITH_BOM" -eq 1 ]]; then
  printf '\xEF\xBB\xBF' > "$OUTFILE"
else
  : > "$OUTFILE"
fi

# --- Multiline-safe CSV sorting done entirely in gawk ---
gawk '
  BEGIN {
    # CSV field tokenizer: commas outside of double quotes
    FPAT = "([^,]*)|(\"([^\"]|\"\")*\")"
  }

  # Return 1 if CSV record has balanced quotes (handles doubled quotes "")
  function csv_record_complete(s, t, q) {
    t = s
    gsub(/""/, "", t)      # remove escaped quotes
    q = gsub(/"/, "", t)   # count remaining quotes
    return (q % 2 == 0)
  }

  # Convert various date formats to YYYYMMDD numeric key
  function date_key(d,    a, yy, y) {
    gsub(/^"|"$/, "", d)
    if (d == "" || d == "NA") return 0
    if (d ~ /^[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{4}$/) {              # mm/dd/yyyy
      split(d, a, "/"); return sprintf("%04d%02d%02d", a[3], a[1], a[2])
    }
    if (d ~ /^[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{2}$/) {              # mm/dd/yy
      split(d, a, "/"); yy = a[3]+0; y = (yy >= 30 ? 1900+yy : 2000+yy)
      return sprintf("%04d%02d%02d", y, a[1], a[2])
    }
    if (d ~ /^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$/) {                # yyyy-mm-dd
      split(d, a, "-"); return sprintf("%04d%02d%02d", a[1], a[2], a[3])
    }
    return 0
  }

  # Accumulate physical lines into one logical CSV record
  {
    line = $0
    sub(/\r$/, "", line)                # normalize CRLF -> LF
    if (rec == "") rec = line; else rec = rec "\n" line
    if (!csv_record_complete(rec)) next

    # rec now holds a full CSV record (may contain inner newlines)
    $0 = rec                              # re-scan fields using FPAT
    rec = ""                              # reset buffer

    if (!seen_header) {
      header = $0
      header_nf = NF
      # find release_date column index dynamically
      for (i=1; i<=NF; i++) { t = $i; gsub(/^"|"$/, "", t); if (tolower(t) == "release_date") col = i }
      if (!col) { print "ERROR: release_date column not found" > "/dev/stderr"; exit 2 }
      seen_header = 1
      next
    }

    # Skip empty logical rows
    if ($0 ~ /^[[:space:]]*$/) next

    # If schema mismatch, still keep row but push to bottom by key=0
    k = (NF == header_nf) ? date_key($col) : 0

    n += 1
    rows[n] = $0    # store original record, including inner newlines
    keys[n] = k     # numeric key for sorting
  }

  END {
    print header
    # sort indices by keys (values) numeric descending
    m = asorti(keys, idx, "@val_num_desc")
    for (j=1; j<=m; j++) {
      i = idx[j]
      print rows[i]
    }
  }
' "$INFILE" >> "$OUTFILE"

echo "Done -> $OUTFILE"
echo "If Excel shows weird characters, import as UTF-8 or run WITH_BOM=1."

