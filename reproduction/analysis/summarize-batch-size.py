#!/usr/bin/env python3
"""Collect per-trial timings and calculate variability for a completed batch-size sweep."""

import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path
from statistics import median, stdev

RESULTS = Path(__file__).resolve().parents[1] / "results"
BATCH_SIZES = (10, 20, 50, 256)
WORKLOADS = ("cold", "zipf", "warm")
PERCENTILES = ("p50", "p95", "p99")


def write_csv(path, headers, rows):
    with path.open("w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(headers)
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sweep_id", help="Sweep ID printed by the runner")
    parser.add_argument("--experiment", choices=("batch-size", "batch-size-plus-probability"),
                        default="batch-size")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}", args.sweep_id):
        parser.error("provide the shared sweep ID")

    trials = []
    measurements = defaultdict(list)
    try:
        for batch_size in BATCH_SIZES:
            probability = 1 / batch_size if args.experiment == "batch-size-plus-probability" else 0.1
            for trial in range(1, 6):
                run_id = f"{args.experiment}-c5-b{batch_size}-trial{trial}-{args.sweep_id}"
                directory = RESULTS / run_id
                parameters = dict(line.split("=", 1) for line in (directory / "parameters.txt").read_text().splitlines())
                if float(parameters["CODOH_BATCH_COMMIT_PROB"]) != probability:
                    raise ValueError(f"{run_id}: expected commit probability {probability}")
                data = json.loads((directory / "percentiles_trimmed.json").read_text())
                for workload in WORKLOADS:
                    stats = data[f"codoh-full_{workload}"]
                    values = [stats[key] for key in PERCENTILES]
                    trials.append(("C5", batch_size, probability, workload, trial, run_id,
                                   stats["n"], stats["warmup_skip"], *values, stats["hit_rate"]))
                    measurements[("C5", batch_size, probability, workload)].append(values)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"Could not read all sweep trials: {error}\n")

    output = RESULTS / f"{args.experiment}-comparison-{args.sweep_id}"
    output.mkdir(exist_ok=True)
    write_csv(
        output / "trials.csv",
        ("config", "batch_size", "commit_probability", "workload", "trial", "run_id", "samples", "warmup_skip",
         "p50_ms", "p95_ms", "p99_ms", "cache_hit_rate"),
        trials,
    )
    rows = []
    for condition, values in measurements.items():
        statistics = [stat for samples in zip(*values) for stat in (median(samples), stdev(samples))]
        rows.append((*condition, len(values), *statistics))
    write_csv(
        output / "summary.csv",
        ("config", "batch_size", "commit_probability", "workload", "trials", "p50_median_ms", "p50_stddev_ms",
         "p95_median_ms", "p95_stddev_ms", "p99_median_ms", "p99_stddev_ms"),
        rows,
    )
    print(output)


if __name__ == "__main__":
    main()
