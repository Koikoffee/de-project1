#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Run the whole pipeline with sane defaults.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IN="${1:-$ROOT/data/tmdb-movies.csv}"

mkdir -p "$ROOT/out" "$ROOT/logs"

echo "[1] Sort by release_date (desc)"
"$ROOT/bin/sort_by_release_date.sh" "$IN" "$ROOT/out/movies_sorted_by_release_date.csv"

echo "[2] Filter vote_average > 7.5"
"$ROOT/bin/filter_vote_average_gt_7_5.sh" "$IN" "$ROOT/out/movies_vote_avg_gt_7_5.csv"

echo "[3] Revenue extremes (max & min)"
"$ROOT/bin/revenue_extremes.sh" "$IN" "$ROOT/out/movies_revenue_extremes.csv"

echo "[4] Sum revenue"
"$ROOT/bin/sum_revenue.sh" "$IN" "$ROOT/out/total_revenue.csv"

echo "[5] Top-10 profit"
env ${TOP_K:+TOP_K=$TOP_K} ${USE_ADJ:+USE_ADJ=$USE_ADJ} ${APPEND_PROFIT:+APPEND_PROFIT=$APPEND_PROFIT} \
  "$ROOT/bin/top_profit.sh" "$IN" "$ROOT/out/movies_top10_profit.csv"

echo "[6] Top-10 directors"
env ${TOP_K:+TOP_K=$TOP_K} \
  "$ROOT/bin/top_directors.sh" "$IN" "$ROOT/out/top10_directors.csv"

echo "[7] Top-10 actors"
env ${TOP_K:+TOP_K=$TOP_K} \
  "$ROOT/bin/top_actors.sh" "$IN" "$ROOT/out/top10_actors.csv"
  
echo "[8] Genre counts (all)"
"$ROOT/bin/count_by_genre.sh" "$IN" "$ROOT/out/genre_counts.csv"

echo "ALL DONE."

