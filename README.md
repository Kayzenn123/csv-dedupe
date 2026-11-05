# csv-dedupe

> Deduplicate CSV rows from the CLI with a human/JSON duplicate report. Daily Tools #30.

## Why

Exported CSVs — order lists, subscriber lists, scraped tables — almost always
contain duplicate rows from double exports or sloppy data entry. The closest
existing tool, `dedupeio/csvdedupe`, is a Python package with heavy
dependencies; `csvkit`/`miller` are full toolkits you must install first.
`csv-dedupe` is one self-contained bash script with zero dependencies that
runs anywhere (Linux, macOS, Termux), sniffs the delimiter, understands quoted
fields, and — instead of silently dropping rows — prints a readable duplicate
report (table for humans, `--json` for scripts) showing exactly what was
removed and why.

## Install

```bash
git clone https://github.com/Kayzenn123/csv-dedupe.git
cd csv-dedupe
chmod +x csv-dedupe
# optional: put it on your PATH
sudo cp csv-dedupe /usr/local/bin/
```

Requires: Bash 4+ and any POSIX awk (gawk, mawk, or busybox awk). No other
dependencies. Works offline.

## Usage

```bash
csv-dedupe [OPTIONS] [FILE|-]
```

| Flag | Purpose | Default |
| --- | --- | --- |
| `-k, --key COLS` | key columns: header names or 1-based indexes, comma-separated | whole row |
| `--keep MODE` | keep `first` or `last` occurrence of each key | `first` |
| `-n, --normalize` | fold text before comparing (lowercase, trim/collapse spaces) | off |
| `--no-header` | input has no header row (`--key` uses indexes) | off |
| `-d, --delimiter C` | field delimiter | auto-detect `,` `;` TAB `|` |
| `-o, --output FILE` | write deduplicated CSV to a new file | off |
| `--print` | print deduplicated CSV to stdout instead of the report | off |
| `-q, --quiet` | suppress the report | off |
| `--in-place` | rewrite the input file (requires `--yes`) | off |
| `--force` | allow `--output` to overwrite an existing file | off |
| `--json` | print the report as JSON | table |
| `--no-color` | disable colors | auto (TTY only) |

Exit codes: `0` ok, `1` runtime error (missing file, ragged rows, empty
input), `2` bad usage. Errors go to stderr; `NO_COLOR` is honored.

By default nothing is written — you only get the report. Files are only
touched via explicit `--output` (new file), `--print` (stdout), or
`--in-place --yes`.

## Example output

Command (real run on a 137-row Indonesian order export with double-exported rows):

```bash
csv-dedupe --key order_id orders.csv
```

Output (real, copied from an actual run):

```text
csv-dedupe duplicate report
  input       : orders.csv
  delimiter   : ;
  columns     : 6 (order_id,tanggal,item,qty,total,kota)
  key         : order_id
  keep        : first
  normalize   : no
  rows        : 137
  unique      : 120
  duplicates  : 17 (12.41%)
  key histogram: 1x: 103 keys, 2x: 17 keys, 3x+: 0 keys
  duplicate samples (up to 5):
    [2x] key=ORD-2026-0034
      first: ORD-2026-0034;08/10/2026;Mie Sedaap 5pcs;1;16.000;Medan
      dup:   ORD-2026-0034;08/10/2026;Mie Sedaap 5pcs;1;16.000;Medan
    [2x] key=ORD-2026-0007
      first: ORD-2026-0007;03/10/2026;Gula Pasir 1kg;1;17.500;Yogyakarta
      dup:   ORD-2026-0007;03/10/2026;Gula Pasir 1kg;1;17.500;Yogyakarta
```

Near-duplicates (case/whitespace differences) with normalization, writing the
cleaned file:

```bash
csv-dedupe --key email --normalize --output subs-clean.csv subs.csv
```

```text
csv-dedupe duplicate report
  input       : subs.csv
  delimiter   : ,
  columns     : 3 (email,nama,bergabung)
  key         : email
  keep        : first
  normalize   : yes
  rows        : 8
  unique      : 5
  duplicates  : 3 (37.50%)
  key histogram: 1x: 2 keys, 2x: 3 keys, 3x+: 0 keys
  duplicate samples (up to 5):
    [2x] key=ANI.PRATAMA@GMAIL.COM
      first: ani.pratama@gmail.com,Ani Pratama,2026-01-12
      dup:   ANI.PRATAMA@GMAIL.COM,ani pratama,2026-03-01
```

## How it works

1. Reads the first row, sniffs the delimiter (`,`, `;`, TAB, `|`) by picking
   the candidate that yields the most fields, and parses the header (unless
   `--no-header`).
2. A small embedded awk program parses each row with a quote-aware splitter
   (`"a,b"` stays one field, `""` unescapes to `"`), builds a comparison key
   from the `--key` columns (optionally text-folded by `--normalize`), and
   hashes it. `--keep last` buffers the latest row per key; `--keep first`
   streams kept rows out immediately.
3. At the end it writes a stats file (counts, key-occurrence histogram, up to
   5 duplicate samples); bash formats it as a table or JSON.

Repository layout: `csv-dedupe` (the tool, bash + embedded awk), `test.sh`
(29 tests), `test/fixtures/` (generated fixtures), `LICENSE`, `.gitignore`.

## Limitations

- One hash entry per unique key is kept in memory; extremely large files
  (tens of millions of unique rows) can use significant RAM. 10k rows run in
  ~0.1s.
- Quoted fields spanning multiple lines are not supported (line-based
  streaming); such rows are parsed as separate broken rows and will likely
  fail the field-count check with a clear error.
- `--normalize` only folds case and whitespace — it does not equate
  `1.250.000` with `1250000` or different date spellings.
- Delimiter sniffing looks at the first row only; files whose delimiter
  changes mid-file are not supported.
- Duplicate sample keys are shown from raw (unfolded) values for readability.

## Development

```bash
bash test.sh   # 29 tests, must pass twice in a row (flaky check)
```

## License

MIT

---
Ringkasan (Bahasa Indonesia): csv-dedupe menghapus baris duplikat dari file
CSV lewat terminal dan menampilkan laporan duplikat yang mudah dibaca (atau
JSON dengan `--json`). Cukup satu file bash tanpa dependensi, bisa baca dari
file atau pipe, otomatis mendeteksi pemisah kolom, mendukung kolom kunci,
normalisasi teks, dan mode aman — tanpa `--output`/`--in-place`, tidak ada
file yang diubah. Batasan utama: butuh memori untuk tiap kunci unik dan
field ber-quote yang melewati banyak baris tidak didukung.
