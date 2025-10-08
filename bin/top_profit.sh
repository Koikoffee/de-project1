#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# --- Paths & params ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFILE="${1:-$PROJECT_ROOT/data/tmdb-movies.csv}"
OUTFILE="${2:-$PROJECT_ROOT/out/movies_top10_profit.csv}"
TOP_K="${TOP_K:-10}"          # change with: TOP_K=20
USE_ADJ="${USE_ADJ:-0}"       # 1 -> use revenue_adj & budget_adj if present
APPEND_PROFIT="${APPEND_PROFIT:-0}"  # 1 -> append a 'profit' column to output
WITH_BOM="${WITH_BOM:-0}"     # 1 -> prepend UTF-8 BOM (Excel friendly)
mkdir -p "$PROJECT_ROOT/out" "$PROJECT_ROOT/logs"

command -v gawk >/dev/null || { echo "Missing command: gawk" >&2; exit 1; }
[[ -f "$INFILE" ]] || { echo "Input file not found: $INFILE" >&2; exit 1; }

# --- Optional BOM for better Excel UTF-8 detection ---
if [[ "$WITH_BOM" -eq 1 ]]; then
  printf '\xEF\xBB\xBF' > "$OUTFILE"
else
  : > "$OUTFILE"
fi

# --- Multiline-safe CSV: Top-K by profit (revenue - budget) ---
gawk -v K="$TOP_K" -v USE_ADJ="$USE_ADJ" -v APPEND_PROFIT="$APPEND_PROFIT" '
  BEGIN {
    # CSV tokenizer: commas outside of double quotes
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
  function is_numeric(x) { return (x ~ /^-?[0-9]+(\.[0-9]+)?$/) }

  # Normalize numeric string -> number (strip quotes, commas, spaces)
  function num_val(s) {
    gsub(/^"|"$/, "", s)
    gsub(/[, ]/, "", s)
    return is_numeric(s) ? s+0 : ""
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

      # Find column indexes (case-insensitive)
      for (i=1; i<=NF; i++) {
        t = $i; gsub(/^"|"$/, "", t)
        lt = tolower(t)
        if (lt == "revenue")      col_rev  = i
        if (lt == "budget")       col_bud  = i
        if (lt == "revenue_adj")  col_reva = i
        if (lt == "budget_adj")   col_buda = i
      }

      # Choose raw vs adjusted columns
      use_adj = (USE_ADJ==1 && col_reva && col_buda) ? 1 : 0
      if (USE_ADJ==1 && !use_adj) {
        # Fall back silently if adj columns not found
        # (You can print a warning to stderr if needed)
        # print "WARN: *_adj not found, falling back to raw." > "/dev/stderr"
      }

      # Remember chosen column names for header printing (if appending profit)
      rev_name = use_adj ? "revenue_adj" : "revenue"
      bud_name = use_adj ? "budget_adj"  : "budget"

      seen_header = 1
      next
    }

    # Skip blank logical rows
    if ($0 ~ /^[[:space:]]*$/) next

    # Only consider rows with matching schema
    if (NF != header_nf) next

    # Extract numbers
    rv = num_val(use_adj ? $col_reva : $col_rev)
    bd = num_val(use_adj ? $col_buda : $col_bud)
    if (rv == "" || bd == "") next

    pr = rv - bd

    n += 1
    rows[n]   = $0            # keep original row
    profit[n] = pr + 0        # numeric key for sorting
  }

  END {
    if (n == 0) {
      # No data; still print header (with/without appended profit)
      if (APPEND_PROFIT==1) {
        print header ",profit"
      } else {
        print header
      }
      exit 0
    }

    # Order indices by profit DESC
    m = asorti(profit, idx, "@val_num_desc")

    # Clamp K
    if (K < 1) K = 1
    if (K > m) K = m

    # Print header (optionally append profit column)
    if (APPEND_PROFIT==1) {
      print header ",profit"
      for (j=1; j<=K; j++) {
        i = idx[j]
        print rows[i] "," profit[i]
      }
    } else {
      print header
      for (j=1; j<=K; j++) {
        i = idx[j]
        print rows[i]
      }
    }
  }
' "$INFILE" >> "$OUTFILE"

echo "Done -> $OUTFILE"
echo "USE_ADJ=1 to use inflation-adjusted columns; APPEND_PROFIT=1 to add a profit column; WITH_BOM=1 for Excel."

