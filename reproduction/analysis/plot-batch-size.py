#!/usr/bin/env python3
"""Plot C2 and C5 batch-size results from one completed sweep."""

import argparse
import csv
import json
import re
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import ScalarFormatter

RESULTS = Path(__file__).resolve().parents[1] / "results"
BATCH_SIZES = (10, 20, 50, 256)
WORKLOADS = ("cold", "zipf", "warm")
PERCENTILES = ("p50", "p95", "p99")


def read_run(run_dir, config):
    path = run_dir / "plots" / "percentiles_trimmed.json"
    data = json.loads(path.read_text())
    return {workload: data[f"{config}_{workload}"] for workload in WORKLOADS}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sweep_id", help="Sweep ID printed by batch-size.sh")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}", args.sweep_id):
        parser.error("provide the shared sweep ID without a directory or run suffix")
    sweep_id = args.sweep_id

    def run_dir(condition):
        return RESULTS / f"batch-size-{condition}-{sweep_id}"

    try:
        baseline = read_run(run_dir("c2"), "odoh")
        codoh = {
            size: read_run(run_dir(f"c5-b{size}"), "codoh-full")
            for size in BATCH_SIZES
        }
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"Could not read sweep results: {error}\n")

    output = run_dir("comparison")
    output.mkdir(exist_ok=True)
    runs = [("C2", "", baseline)]
    runs.extend(("C5", size, data) for size, data in codoh.items())
    with (output / "latency.csv").open("w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["config", "batch_size", "workload", "samples", "warmup_skip",
                         "p50_ms", "p95_ms", "p99_ms", "cache_hit_rate"])
        for config, size, measurements in runs:
            for workload, stats in measurements.items():
                writer.writerow([config, size, workload, stats["n"], stats["warmup_skip"],
                                 *(stats[key] for key in PERCENTILES), stats["hit_rate"]])

    with (output / "latency.tex").open("w") as file:
        print(r"\begin{table}", r"\centering", r"\small",
              r"\begin{tabular}{lrrrrrrrrrr}", r"\toprule", sep="\n", file=file)
        print(r"& & \multicolumn{3}{c}{Cold} & \multicolumn{3}{c}{Zipf} & \multicolumn{3}{c}{Warm} \\", file=file)
        print(" & ".join(["Configuration", "Batch size"] + list(PERCENTILES) * 3), r"\\", file=file)
        print(r"\midrule", file=file)
        for config, size, measurements in runs:
            values = [f"{measurements[workload][key]:.2f}" for workload in WORKLOADS for key in PERCENTILES]
            print(" & ".join([config, str(size or "--"), *values]), r"\\", file=file)
        print(r"\bottomrule", r"\end{tabular}",
              r"\caption{End-to-end latency in milliseconds for the ODoH baseline and CODoH batch sizes.}",
              r"\label{tab:batch-size-latency}", r"\end{table}", sep="\n", file=file)

    fig, axes = plt.subplots(3, 3, figsize=(12, 9), sharex=True, sharey="row", layout="constrained")
    for row, percentile in enumerate(PERCENTILES):
        for column, workload in enumerate(WORKLOADS):
            ax = axes[row, column]
            ax.plot(BATCH_SIZES, [codoh[size][workload][percentile] for size in BATCH_SIZES],
                    marker="o", color="#2563eb", label="C5 CODoH")
            ax.axhline(baseline[workload][percentile], color="#475569", linestyle="--",
                       label="C2 ODoH baseline")
            ax.set_xscale("log")
            ax.set_xticks(BATCH_SIZES)
            ax.xaxis.set_major_formatter(ScalarFormatter())
            ax.grid(axis="y", alpha=0.25)
            if row == 0:
                ax.set_title(workload.capitalize())
            if column == 0:
                ax.set_ylabel(f"{percentile} latency (ms)")
            if row == len(PERCENTILES) - 1:
                ax.set_xlabel("C5 batch size")
    axes[0, 0].legend()
    fig.savefig(output / "latency.pdf")
    fig.savefig(output / "latency.png", dpi=200)
    plt.close(fig)
    print(output)


if __name__ == "__main__":
    main()
