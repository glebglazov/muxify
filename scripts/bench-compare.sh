#!/usr/bin/env bash
# Prints the runs that scripts/bench.sh recorded side by side: grid size, idle
# CPU and the median milliseconds of each vtebench benchmark, lower is better.
# Compares every run in build/bench, or only the .dat files given as arguments.
set -euo pipefail
shopt -s inherit_errexit

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/bench"

if (($# == 0)); then
    # runs.tsv lists the runs in the order they ran.
    mapfile -t dats < <(cut -f5 "$OUT/runs.tsv" | sed "s#^#$OUT/#")
else
    dats=("$@")
fi
((${#dats[@]} > 0)) || { echo "error: no runs in $OUT; run make bench first" >&2; exit 1; }

# One column per run. vtebench writes one column per benchmark and one row per
# sample, with "_" where a benchmark has fewer samples than the others.
awk -v runs="$OUT/runs.tsv" '
    BEGIN {
        while ((getline line < runs) > 0) {
            split(line, f, "\t")
            app[f[5]] = f[2]; grid[f[5]] = f[3]; cpu[f[5]] = f[4]; stamp[f[5]] = f[1]
        }
    }
    FNR == 1 {
        run++
        name = FILENAME; sub(/.*\//, "", name); file[run] = name
        for (i = 1; i <= NF; i++) { bench[i] = $i; n[run, i] = 0 }
        nbench = NF
        next
    }
    {
        for (i = 1; i <= NF; i++) if ($i != "_") samples[run, i, ++n[run, i]] = $i
    }
    function median(r, b,    m, k, j, t, v) {
        m = n[r, b]
        if (m == 0) return "-"
        for (k = 1; k <= m; k++) v[k] = samples[r, b, k]
        for (k = 2; k <= m; k++) for (j = k; j > 1 && v[j - 1] > v[j]; j--) { t = v[j]; v[j] = v[j - 1]; v[j - 1] = t }
        return (m % 2) ? v[(m + 1) / 2] : (v[m / 2] + v[m / 2 + 1]) / 2
    }
    END {
        row("", "app"); row("run", "stamp"); row("grid", "grid"); row("idle CPU %", "cpu")
        printf "median ms (lower is better)\n"
        for (b = 1; b <= nbench; b++) {
            printf "  %-30s", bench[b]
            for (r = 1; r <= run; r++) printf "%16s", median(r, b)
            printf "\n"
        }
        for (r = 2; r <= run; r++) if (grid[file[r]] != grid[file[1]]) {
            printf "\nwarning: the runs have different grid sizes, so the times are not comparable.\n"
            break
        }
    }
    function row(label, key,    r, v) {
        printf "%-32s", label
        for (r = 1; r <= run; r++) {
            v = (key == "app") ? app[file[r]] : (key == "stamp") ? stamp[file[r]] : (key == "grid") ? grid[file[r]] : cpu[file[r]]
            printf "%16s", (v == "" ? "?" : v)
        }
        printf "\n"
    }
' "${dats[@]}"
