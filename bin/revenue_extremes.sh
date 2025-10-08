#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# --- Paths & params ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFILE="${1:-$PROJECT_ROOT/data/tmdb-movies.csv}"
OUTFILE="${2:-$PROJECT_ROOT/out/movies_revenue_extremes.csv}"
WITH_BOM="${WITH_BOM:-0}"          # set 1 to prepend UTF-8 BOM for Excel
MIN_IGNORE_ZERO="${MIN_IGNORE_ZERO:-0}"  # set 1 to ignore zero when picking MIN
mkdir -p "$PROJECT_ROOT/out" "$PROJECT_ROOT/logs"

command -v gawk >/dev/null || { echo "Missing command: gawk" >&2; exit 1; }
[[ -f "$INFILE" ]] || { echo "Input file not found: $INFILE" >&2; exit 1; }

# --- Optional BOM for better Excel UTF-8 detection ---
if [[ "$WITH_BOM" -eq 1 ]]; then
  printf '\xEF\xBB\xBF' > "$OUTFILE"
else
  : > "$OUTFILE"
fi

# --- Multiline-safe CSV: pick ALL rows with max revenue and ALL rows with min revenue ---
gawk -v MIN_IGNORE_ZERO="$MIN_IGNORE_ZERO" '
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

  # Is numeric? (integer or decimal)
  function is_numeric(x) {
    return (x ~ /^-?[0-9]+(\.[0-9]+)?$/)
  }

  # Normalize revenue string -> numeric (strip quotes, commas, spaces)
  function revenue_val(s, v) {
    gsub(/^"|"$/, "", s)           # drop wrapping quotes
    gsub(/[, ]/, "", s)            # remove thousand separators / spaces
    if (is_numeric(s)) return s+0  # numeric
    return ""                      # not numeric -> skip
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
      # find revenue column index dynamically
      for (i=1; i<=NF; i++) {
        t = $i; gsub(/^"|"$/, "", t)
        if (tolower(t) == "revenue") col = i
      }
      if (!col) { print "ERROR: revenue column not found" > "/dev/stderr"; exit 2 }
      seen_header = 1
      next
    }

    # Skip empty logical rows
    if ($0 ~ /^[[:space:]]*$/) next

    # Only consider rows with matching schema
    if (NF != header_nf) next

    vraw = $col
    v = revenue_val(vraw)
    if (v == "") next

    n += 1
    rows[n] = $0
    vals[n] = v + 0

    # Update MAX
    if (n == 1 || v > max_val) max_val = v

    # Update MIN (optionally ignore zeros)
    if (MIN_IGNORE_ZERO == 1) {
      if (v > 0 && (!min_set || v < min_val)) { min_val = v; min_set = 1 }
    } else {
      if (!min_set || v < min_val) { min_val = v; min_set = 1 }
    }
  }

  END {
    print header
    if (n == 0) exit 0

    # Print all rows with MAX revenue (in original order)
    for (i=1; i<=n; i++) if (vals[i] == max_val) print rows[i]

    # Print all rows with MIN revenue (avoid duplicates if min == max)
    if (min_set && min_val != max_val) {
      for (i=1; i<=n; i++) if (vals[i] == min_val) print rows[i]
    }
  }
' "$INFILE" >> "$OUTFILE"

echo "Done -> $OUTFILE"
echo "Use MIN_IGNORE_ZERO=1 to ignore zeros when picking the minimum; WITH_BOM=1 for Excel."

