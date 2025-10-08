#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# --- Paths & params ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFILE="${1:-$PROJECT_ROOT/data/tmdb-movies.csv}"
OUTFILE="${2:-$PROJECT_ROOT/out/movies_vote_avg_gt_7_5.csv}"
THRESHOLD="${THRESHOLD:-7.5}"  # change with: THRESHOLD=8.0
WITH_BOM="${WITH_BOM:-0}"      # set 1 to prepend UTF-8 BOM for Excel
mkdir -p "$PROJECT_ROOT/out" "$PROJECT_ROOT/logs"

command -v gawk >/dev/null || { echo "Missing command: gawk" >&2; exit 1; }
[[ -f "$INFILE" ]] || { echo "Input file not found: $INFILE" >&2; exit 1; }

# --- Optional BOM for better Excel UTF-8 detection ---
if [[ "$WITH_BOM" -eq 1 ]]; then
  printf '\xEF\xBB\xBF' > "$OUTFILE"
else
  : > "$OUTFILE"
fi

# --- Multiline-safe CSV filtering done entirely in gawk ---
gawk -v TH="$THRESHOLD" '
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

  # Check if a string is numeric (integer or decimal)
  function is_numeric(x) {
    return (x ~ /^-?[0-9]+(\.[0-9]+)?$/)
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
      # find vote_average column index dynamically
      for (i=1; i<=NF; i++) {
        t = $i; gsub(/^"|"$/, "", t)
        if (tolower(t) == "vote_average") col = i
      }
      if (!col) { print "ERROR: vote_average column not found" > "/dev/stderr"; exit 2 }
      seen_header = 1
      next
    }

    # Skip empty logical rows
    if ($0 ~ /^[[:space:]]*$/) next

    # Skip rows with schema mismatch (cannot safely parse columns)
    if (NF != header_nf) next

    v = $col; gsub(/^"|"$/, "", v)       # strip wrapping quotes
    if (is_numeric(v) && (v + 0) > TH) {
      n += 1
      rows[n] = $0                        # store full original record
    }
  }

  END {
    print header
    for (j=1; j<=n; j++) print rows[j]
  }
' "$INFILE" >> "$OUTFILE"

echo "Done -> $OUTFILE"
echo "If Excel shows weird characters, import as UTF-8 or run WITH_BOM=1."

