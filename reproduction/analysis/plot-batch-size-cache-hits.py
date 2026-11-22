#!/usr/bin/env python3
"""Plot C5 cache hit rates by batch size with ±1 sample standard deviation error bars."""

import argparse
import csv
from collections import defaultdict
from pathlib import Path
from statistics import mean, stdev

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

BATCH_SIZES = (10, 20, 50, 256)
WORKLOADS = (("cold", "Cold"), ("zipf", "Zipf"), ("warm", "Warm"))
COLORS = ("#93c5fd", "#3b82f6", "#1d4ed8", "#1e3a8a")


def load_hit_rates(trials_csv: Path):
    grouped = defaultdict(list)
    with trials_csv.open(newline="") as file:
        for row in csv.DictReader(file):
            grouped[(int(row["batch_size"]), row["workload"])].append(float(row["cache_hit_rate"]) * 100.0)
    stats = {}
    for batch_size in BATCH_SIZES:
        for workload, _ in WORKLOADS:
            values = grouped[(batch_size, workload)]
            if len(values) < 2:
                raise ValueError(f"Expected at least 2 trials for B={batch_size}, workload={workload}")
            stats[(batch_size, workload)] = (mean(values), stdev(values))
    return stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("comparison_dir", type=Path, help="Directory containing trials.csv")
    parser.add_argument("--output-pdf", type=Path, help="Optional extra PDF output path")
    args = parser.parse_args()

    stats = load_hit_rates(args.comparison_dir / "trials.csv")

    fig, ax = plt.subplots(figsize=(8, 4.5), layout="constrained")
    x = np.arange(len(WORKLOADS))
    bar_width = 0.19
    offsets = (np.arange(len(BATCH_SIZES)) - (len(BATCH_SIZES) - 1) / 2) * bar_width

    for idx, (batch_size, color) in enumerate(zip(BATCH_SIZES, COLORS)):
        means = [stats[(batch_size, w)][0] for w, _ in WORKLOADS]
        sds = [stats[(batch_size, w)][1] for w, _ in WORKLOADS]
        positions = x + offsets[idx]
        bars = ax.bar(
            positions,
            means,
            width=bar_width * 0.92,
            yerr=sds,
            capsize=3.5,
            color=color,
            edgecolor="#1e293b",
            linewidth=0.5,
            error_kw={"ecolor": "#0f172a", "elinewidth": 1.0, "capthick": 1.0},
            label=f"B = {batch_size}",
            zorder=3,
        )
        for bar, val, err in zip(bars, means, sds):
            ax.text(
                bar.get_x() + bar.get_width() / 2,
                val + err + 1.6,
                f"{val:.1f}%",
                ha="center",
                va="bottom",
                fontsize=8,
                color="#0f172a",
            )

    ax.set_xticks(x)
    ax.set_xticklabels([label for _, label in WORKLOADS], fontsize=10)
    ax.set_xlabel("Workload")
    ax.set_ylabel("Cache hit rate (%)")
    ax.set_ylim(0, 108)
    ax.set_yticks([0, 20, 40, 60, 80, 100])
    ax.set_title("Full CODoH (C5) cache hit rate by batch size")
    ax.grid(axis="y", alpha=0.25, zorder=0)
    ax.legend(title="Batch size", frameon=True, loc="upper left")

    fig.savefig(args.comparison_dir / "cache-hit-rates.pdf")
    fig.savefig(args.comparison_dir / "cache-hit-rates.png", dpi=200)
    if args.output_pdf:
        args.output_pdf.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(args.output_pdf)
    plt.close(fig)


if __name__ == "__main__":
    main()
