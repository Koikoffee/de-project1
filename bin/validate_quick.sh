#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Quick validators (lightweight sanity checks).
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IN="${1:-$ROOT/data/tmdb-movies.csv}"

ok(){ echo "✓ $*"; }
fail(){ echo "✗ $*" >&2; exit 1; }

# 0) Helper: strip CR + optional BOM from a line
strip_bom_cr(){ awk '{sub(/^\xEF\xBB\xBF/,""); gsub(/\r/,""); print}' ; }

# 1) Sorted by release_date DESC
diff <(head -n1 "$IN" | tr -d '\r') \
     <(head -n1 "$ROOT/out/movies_sorted_by_release_date.csv" | strip_bom_cr) >/dev/null || fail "Header mismatch (sorted)"
gawk -v FPAT='([^,]*)|(\"([^\"]|\"\")*\")' '
  NR==1{for(i=1;i<=NF;i++){t=$i; gsub(/^"|"$/,"",t); if(tolower(t)=="release_date") c=i} last=99999999; next}
  {
    d=$c; gsub(/^"|"$/,"",d)
    if(d=="") key=0
    else if(d~/^[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{4}$/){split(d,a,"/"); key=sprintf("%04d%02d%02d",a[3],a[1],a[2])}
    else if(d~/^[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{2}$/){split(d,a,"/"); yy=a[3]+0; y=(yy>=30?1900+yy:2000+yy); key=sprintf("%04d%02d%02d",y,a[1],a[2])}
    else if(d~/^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$/){split(d,a,"-"); key=sprintf("%04d%02d%02d",a[1],a[2],a[3])}
    else key=0
    if(key>last){print "NOT DESC at line",NR; exit 2} last=key
  } END{print "OK"}
' "$ROOT/out/movies_sorted_by_release_date.csv" | grep -q OK && ok "Sorted by release_date DESC"

# 2) vote_average > 7.5
gawk -v FPAT='([^,]*)|(\"([^\"]|\"\")*\")' -v TH=7.5 '
  NR==1{for(i=1;i<=NF;i++){t=$i; gsub(/^"|"$/,"",t); if(tolower(t)=="vote_average") c=i; hnf=NF; next}}
  NF==hnf{v=$c; gsub(/^"|"$/,"",v); if(!(v ~ /^-?[0-9]+(\.[0-9]+)?$/) || v+0<=TH){print "BAD"; exit 2}}
  END{print "OK"}
' "$ROOT/out/movies_vote_avg_gt_7_5.csv" | grep -q OK && ok "All rows vote_average > 7.5"

# 3) Revenue extremes cover only max/min
# --- compute MAX & MIN from IN (robust) ---
read MAX MIN < <(gawk '
  BEGIN{FPAT="([^,]*)|(\"([^\"]|\"\")*\")"}
  function csvok(s,t,q){t=s; gsub(/""/,"",t); q=gsub(/"/,"",t); return q%2==0}
  function isnum(x){return (x ~ /^-?[0-9]+(\.[0-9]+)?$/)}
  function val(s){gsub(/^"|"$/,"",s); gsub(/[, ]/,"",s); return isnum(s)? s+0 : ""}
  { line=$0; sub(/\r$/,"",line); rec=(rec?rec"\n":"") line; if(!csvok(rec)) next
    $0=rec; rec=""
    if(!seen){seen=1;hnf=NF;for(i=1;i<=NF;i++){u=$i; gsub(/^"|"$/,"",u); if(tolower(u)=="revenue") c=i}; next}
    if(NF!=hnf) next
    v=val($c); if(v=="") next
    if(++n==1 || v>mx) mx=v
    if(n==1 || v<mn) mn=v
  }
  END{printf "%s %s\n", mx+0, mn+0}
' "$IN")

# --- verify OUT only contains rows with revenue == MAX or MIN ---
gawk -v MX="$MAX" -v MN="$MIN" '
  BEGIN{FPAT="([^,]*)|(\"([^\"]|\"\")*\")"}
  NR==1{for(i=1;i<=NF;i++){t=$i; gsub(/^"|"$/,"",t); if(tolower(t)=="revenue") c=i}; next}
  {v=$c; gsub(/^"|"$/,"",v); gsub(/[, ]/,"",v); if(v=="") next
   if(v+0!=MX && v+0!=MN){print "BAD"; exit 2}}
  END{print "OK"}
' "$ROOT/out/movies_revenue_extremes.csv" | grep -q OK && ok "Revenue extremes only {max,min}"

# 4) Sum revenue matches
expected=$(gawk '
  BEGIN{FPAT="([^,]*)|(\"([^\"]|\"\")*\")"}
  function csvok(s,t,q){t=s; gsub(/""/,"",t); q=gsub(/"/,"",t); return q%2==0}
  function isnum(x){return (x ~ /^-?[0-9]+(\.[0-9]+)?$/)}
  function val(s){gsub(/^"|"$/,"",s); gsub(/[, ]/,"",s); return isnum(s)? s+0 : ""}
  { line=$0; sub(/\r$/,"",line); rec=(rec?rec"\n":"") line; if(!csvok(rec)) next
    $0=rec; rec=""
    if(!seen){seen=1;hnf=NF;for(i=1;i<=NF;i++){u=$i; gsub(/^"|"$/,"",u); if(tolower(u)=="revenue") c=i}; next}
    if(NF!=hnf) next
    v=val($c); if(v!="") S+=v
  } END{print (S==int(S)?sprintf("%d",S):S)}
' "$IN")
actual=$(tail -n1 "$ROOT/out/total_revenue.csv" | tr -d '\r')
[[ "$expected" == "$actual" ]] && ok "Total revenue matches" || fail "Total revenue mismatch"

# 5) Genre counts monotonic desc
awk -F, 'NR==1{next} {if(prev!="" && $2>prev){print "BAD"; exit} prev=$2} END{print "OK"}' \
  "$ROOT/out/genre_counts.csv" | grep -q OK && ok "Genre counts DESC"

# 6) Top lists headers & basic shape
grep -q '^name,count$' "$ROOT/out/top10_directors.csv" && ok "Directors header ok" || fail "Directors header"
grep -q '^name,count$' "$ROOT/out/top10_actors.csv"    && ok "Actors header ok"    || fail "Actors header"

echo "DONE."

