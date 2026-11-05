#!/usr/bin/env bash
# test suite for csv-dedupe. Run: bash test.sh (from repo root).
set -uo pipefail

BIN="./csv-dedupe"
FIX="test/fixtures"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s\n%s\n' "$1" "$2"; }

# assert_eq <name> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: [$2] got: [$3]"; fi
}
# assert_contains <name> <haystack> <needle>
assert_contains() {
  case "$2" in *"$3"*) ok "$1";; *) bad "$1" "missing [$3] in: $2";; esac
}
# assert_exit <name> <expected-code> -- <cmd...>
assert_exit() {
  local name="$1" want="$2"; shift 2
  [ "$1" = "--" ] && shift
  set +e; out=$("$@" 2>&1); code=$?; set -e
  if [ "$code" = "$want" ]; then ok "$name"; else bad "$name" "exit=$code want=$want out=$out"; fi
}

mkdir -p "$FIX"

# ---- fixtures (generated, deterministic) ----
printf 'id,name,city\n1,Ani,Jakarta\n2,Budi,Bandung\n1,Ani,Jakarta\n3,Citra,Surabaya\n2,Budi,Bandung\n' > "$FIX/basic.csv"
printf 'email;nama\nani@x.id;Ani\nBUDI@x.id;Budi\nani@x.id ; Ani \nCITRA@x.id;Citra\n' > "$FIX/case.csv"
printf '"id","note","qty"\n1,"hello, world",2\n2,"say ""hi""",3\n1,"hello, world",2\n' > "$FIX/quoted.csv"
printf 'a\tb\n1\tx\n1\tx\n2\ty\n' > "$FIX/tabs.csv"
printf 'x,y\n1,2,3\n4,5\n' > "$FIX/ragged.csv"
printf '' > "$FIX/empty.csv"
printf 'k,v\n1,a\n2,b\n' > "$FIX/nodup.csv"

T() { NO_COLOR=1 "$BIN" "$@"; }

# 1. basic whole-row dedupe keeps first, drops 2 dups
out="$(T --print "$FIX/basic.csv")"
assert_eq "basic dedupe rows" "$(printf 'id,name,city\n1,Ani,Jakarta\n2,Budi,Bandung\n3,Citra,Surabaya')" "$out"

# 2. report counts
rep="$(T "$FIX/basic.csv")"
assert_contains "report rows" "$rep" "rows        : 5"
assert_contains "report dups" "$rep" "duplicates  : 2 (40.00%)"
assert_contains "report unique" "$rep" "unique      : 3"

# 3. --key by name
out="$(T --key id --print "$FIX/basic.csv")"
assert_eq "key by name" "$(printf 'id,name,city\n1,Ani,Jakarta\n2,Budi,Bandung\n3,Citra,Surabaya')" "$out"

# 4. --key by index
out="$(T --key 1 --print "$FIX/basic.csv")"
assert_eq "key by index" "$(printf 'id,name,city\n1,Ani,Jakarta\n2,Budi,Bandung\n3,Citra,Surabaya')" "$out"

# 5. --keep last keeps the later occurrence
printf 'id,val\n1,old\n2,x\n1,new\n' > "$FIX/keeplast.csv"
out="$(T --key id --keep last --print "$FIX/keeplast.csv")"
assert_eq "keep last" "$(printf 'id,val\n2,x\n1,new')" "$out"

# 6. --normalize folds case/whitespace
out="$(T --key email --normalize --print "$FIX/case.csv")"
assert_eq "normalize folds" "$(printf 'email;nama\nani@x.id;Ani\nBUDI@x.id;Budi\nCITRA@x.id;Citra')" "$out"

# 7. quoted fields with commas and doubled quotes
out="$(T --print "$FIX/quoted.csv")"
assert_eq "quoted fields" "$(printf '"id","note","qty"\n1,"hello, world",2\n2,"say ""hi""",3')" "$out"

# 8. tab delimiter auto-detect
out="$(T --print "$FIX/tabs.csv")"
assert_eq "tab sniff" "$(printf 'a\tb\n1\tx\n2\ty')" "$out"

# 9. --no-header with index keys
printf 'a,1\nb,2\na,1\n' > "$FIX/noheader.csv"
out="$(T --no-header --key 1 --print "$FIX/noheader.csv")"
assert_eq "no-header" "$(printf 'a,1\nb,2')" "$out"

# 10. stdin via pipe
out="$(printf 'id,name,city\n1,Ani,Jakarta\n1,Ani,Jakarta\n' | T --print -)"
assert_eq "stdin pipe" "$(printf 'id,name,city\n1,Ani,Jakarta')" "$out"

# 11. --json is valid JSON with expected fields
json="$(T --json --key id "$FIX/basic.csv")"
echo "$json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['rows']==5 and d['duplicates']==2 and d['unique']==3, d
assert d['key']=='id' and d['keep']=='first', d
assert d['columns']==['id','name','city'], d['columns']
assert abs(d['duplicate_rate']-0.4)<1e-9, d
assert d['key_histogram']=={'1':1,'2':2,'3plus':0}, d
assert len(d['duplicate_samples'])==2, d
" && ok "json valid + fields" || bad "json valid + fields" "$json"

# 12. --output writes new file, refuses to overwrite
rm -f "$FIX/out.csv"
T --quiet --output "$FIX/out.csv" "$FIX/basic.csv"
assert_eq "output file rows" "4" "$(wc -l < "$FIX/out.csv" | tr -d ' ')"
assert_exit "output refuses overwrite" 1 -- T --quiet --output "$FIX/out.csv" "$FIX/basic.csv"

# 13. --in-place requires --yes, then rewrites
cp "$FIX/basic.csv" "$FIX/inplace.csv"
assert_exit "in-place needs --yes" 2 -- T --in-place "$FIX/inplace.csv"
T --quiet --in-place --yes "$FIX/inplace.csv"
assert_eq "in-place rewritten" "4" "$(wc -l < "$FIX/inplace.csv" | tr -d ' ')"
rm -f "$FIX/inplace.csv" "$FIX/out.csv" "$FIX/keeplast.csv" "$FIX/noheader.csv"

# 14. ragged rows -> runtime error exit 1
assert_exit "ragged rows" 1 -- T "$FIX/ragged.csv"

# 15. empty input -> runtime error exit 1
assert_exit "empty input" 1 -- T "$FIX/empty.csv"

# 16. missing file -> exit 1
assert_exit "missing file" 1 -- T "$FIX/does-not-exist.csv"

# 17. unknown --key column -> exit 1
assert_exit "unknown key column" 1 -- T --key nope "$FIX/basic.csv"

# 18. bad usage -> exit 2
assert_exit "bad keep value" 2 -- T --keep middle "$FIX/basic.csv"
assert_exit "unknown flag" 2 -- T --bogus "$FIX/basic.csv"
assert_exit "print+output conflict" 2 -- T --print --output /tmp/x "$FIX/basic.csv"

# 19. --help / --version exit 0
assert_exit "help" 0 -- T --help
assert_exit "version" 0 -- T --version

# 19b. --output same file as input is rejected (regression)
cp "$FIX/basic.csv" "$FIX/samefile.csv"
assert_exit "output==input rejected" 2 -- T --quiet --output "$FIX/samefile.csv" --force "$FIX/samefile.csv"
rm -f "$FIX/samefile.csv"

# 20. no duplicates -> exit 0, report shows 0
rep="$(T "$FIX/nodup.csv")"
assert_contains "zero dups" "$rep" "duplicates  : 0 (0.00%)"

# 21. NO_COLOR respected (no ESC bytes on pipe)
out="$(NO_COLOR=1 "$BIN" --print "$FIX/basic.csv" | od -c | grep -c '\\033' || true)"
assert_eq "no color codes" "0" "$out"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
