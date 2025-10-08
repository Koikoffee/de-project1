#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# --- Paths & params ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFILE="${1:-$PROJECT_ROOT/data/tmdb-movies.csv}"
OUTFILE="${2:-$PROJECT_ROOT/out/genre_counts.csv}"
TOP_K="${TOP_K:-0}"          # 0 = print all; e.g., TOP_K=20 for top-20
WITH_BOM="${WITH_BOM:-0}"    # 1 = prepend UTF-8 BOM (Excel friendly)
mkdir -p "$PROJECT_ROOT/out" "$PROJECT_ROOT/logs"

command -v gawk >/dev/null || { echo "Missing command: gawk" >&2; exit 1; }
[[ -f "$INFILE" ]] || { echo "Input file not found: $INFILE" >&2; exit 1; }

# Optional BOM
if [[ "$WITH_BOM" -eq 1 ]]; then printf '\xEF\xBB\xBF' > "$OUTFILE"; else : > "$OUTFILE"; fi

gawk -v K="$TOP_K" '
  BEGIN {
    # CSV tokenizer: commas outside of quotes
    FPAT = "([^,]*)|(\"([^\"]|\"\")*\")"
  }
  function csvok(s,t,q){ t=s; gsub(/""/,"",t); q=gsub(/"/,"",t); return q%2==0 }
  function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }
  # value-desc, then key-asc comparator
  function by_count_then_name(i1,v1,i2,v2){ return (v1==v2 ? (i1<i2?-1:(i1>i2?1:0)) : (v1>v2?-1:1)) }

  {
    line=$0; sub(/\r$/,"",line)
    rec = (rec?rec"\n":"") line
    if(!csvok(rec)) next
    $0=rec; rec=""

    if(!seen){
      seen=1; hnf=NF; gcol=0
      for(i=1;i<=NF;i++){t=$i; gsub(/^"|"$/,"",t); if(tolower(t)=="genres") gcol=i}
      if(!gcol){print "ERROR: genres column not found" > "/dev/stderr"; exit 2}
      next
    }

    if(NF!=hnf) next
    gs=$gcol; gsub(/^"|"$/,"",gs)
    if(gs=="") next

    # Split genres by "|" and dedup within a movie
    n=split(gs, A, /\|/)
    delete seen_in_row
    for(i=1;i<=n;i++){
      g=trim(A[i]); if(g=="") continue
      key=tolower(g)
      if(!seen_in_row[key]){
        cnt[key]++
        # keep first seen display name for this key
        if(!(key in disp)) disp[key]=g
        seen_in_row[key]=1
      }
    }
  }
  END{
    print "genre,count"
    if(length(cnt)==0) exit
    m=asorti(cnt, idx, "by_count_then_name")
    if(K>0 && K<m) m=K
    for(j=1;j<=m;j++){ k=idx[j]; print disp[k] "," cnt[k]+0 }
  }
' "$INFILE" >> "$OUTFILE"

echo "Done -> $OUTFILE"

