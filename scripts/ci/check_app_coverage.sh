#!/bin/sh
# Coverage gate for the app's ViewModels.
# PT: Gate de cobertura dos ViewModels do app.
#
# Usage: check_app_coverage.sh <lcov file> <min percent>
# Reads only the records (SF ... end_of_record) whose path ends with _view_model.dart, adds up
# LF (lines found) and LH (lines hit), prints each file and the total, and exits 1 when the
# total is under the minimum or when no ViewModel is found. Why only ViewModels:
# docs/code-notes/ci.md#coverage
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <lcov file> <min percent>" >&2
  exit 2
fi

lcov_file=$1
min=$2

# A typo such as "9o" would read as 0 in awk and silently open the gate.
# PT: Um erro de digitação como "9o" viraria 0 no awk e abriria o gate sem aviso.
case $min in
  ""|*[!0-9.]*) echo "min must be a number: $min" >&2; exit 2 ;;
esac

if [ ! -f "$lcov_file" ]; then
  echo "lcov file not found: $lcov_file" >&2
  exit 2
fi

awk -v min="$min" '
  /^SF:/ {
    path = substr($0, 4)
    keep = (path ~ /_view_model\.dart$/)
    # Only safe characters reach the Markdown job summary (a crafted file name cannot close the fence).
    # PT: Só caracteres seguros chegam ao resumo em Markdown (um nome de arquivo forjado não fecha o bloco).
    gsub(/[^A-Za-z0-9_.\/-]/, "?", path)
    lf = 0
    lh = 0
  }
  /^LF:/ { lf = substr($0, 4) + 0 }
  /^LH:/ { lh = substr($0, 4) + 0 }
  /^end_of_record/ {
    if (keep) {
      files++
      total_lf += lf
      total_lh += lh
      printf "%6.2f%%  %4d/%-4d  %s\n", (lf > 0 ? 100 * lh / lf : 100), lh, lf, path
    }
    keep = 0
  }
  END {
    if (files == 0 || total_lf == 0) {
      print "No ViewModel files (*_view_model.dart) found in the lcov file."
      exit 1
    }
    pct = 100 * total_lh / total_lf
    printf "ViewModel line coverage: %.2f%% (%d/%d lines, %d files), minimum %s%%\n", pct, total_lh, total_lf, files, min
    if (pct + 0 < min + 0) {
      print "FAILED: coverage is under the minimum."
      exit 1
    }
    print "OK"
  }
' "$lcov_file"
