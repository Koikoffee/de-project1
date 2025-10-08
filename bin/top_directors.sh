#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# --- Paths & params ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFILE="${1:-$PROJECT_ROOT/data/tmdb-movies.csv}"
OUTFILE="${2:-$PROJECT_ROOT/out/top10_directors.csv}"
TOP_K="${TOP_K:-10}"
WITH_BOM="${WITH_BOM:-0}"
mkdir -p "$PROJECT_ROOT/out" "$PROJECT_ROOT/logs"

command -v gawk >/dev/null || { echo "Missing command: gawk" >&2; exit 1; }
[[ -f "$INFILE" ]] || { echo "Input file not found: $INFILE" >&2; exit 1; }

# Optional BOM (Excel-friendly)
if [[ "$WITH_BOM" -eq 1 ]]; then printf '\xEF\xBB\xBF' > "$OUTFILE"; else : > "$OUTFILE"; fi

gawk -v K="$TOP_K" '
  BEGIN{
    FPAT="([^,]*)|(\"([^\"]|\"\")*\")"
  }
  function csvok(s,t,q){ t=s; gsub(/""/,"",t); q=gsub(/"/,"",t); return q%2==0 }
  function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }

  # custom comparator: value desc, then key asc
  function by_count_then_name(i1,v1,i2,v2){ return (v1==v2 ? (i1<i2?-1:(i1>i2?1:0)) : (v1>v2?-1:1)) }

  {
    line=$0; sub(/\r$/,"",line)
    rec = (rec?rec"\n":"") line
    if(!csvok(rec)) next
    $0=rec; rec=""

    if(!seen){
      seen=1; hnf=NF; dcol=0
      for(i=1;i<=NF;i++){t=$i; gsub(/^"|"$/,"",t); if(tolower(t)=="director") dcol=i}
      if(!dcol){print "ERROR: director column not found" > "/dev/stderr"; exit 2}
      next
    }

    if(NF!=hnf) next
    dir=$dcol; gsub(/^"|"$/,"",dir)
    if(dir=="") next

    # split directors by |
    n=split(dir, A, /\|/)
    delete seen_name
    for(i=1;i<=n;i++){
      name=trim(A[i])
      if(name=="") continue
      if(!seen_name[name]){ cnt[name]++; seen_name[name]=1 }
    }
  }
  END{
    print "name,count"
    if(length(cnt)==0) exit
    m=asorti(cnt, idx, "by_count_then_name")
    if(K<1) K=1; if(K>m) K=m
    for(j=1;j<=K;j++){ k=idx[j]; print k "," cnt[k]+0 }
  }
' "$INFILE" >> "$OUTFILE"

echo "Done -> $OUTFILE"

