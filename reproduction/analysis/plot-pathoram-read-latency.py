#!/usr/bin/env python3
"""Plot PathORAM vs. linear scan read latency (Table 6) as a grouped bar chart with ±1 std. dev. error bars."""

import argparse
import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

CAPACITIES = (256, 1024, 4096, 16384)
SERIES = (
    ("BenchmarkLinearScan/blocks={n}/blockSize=4096/read", "Linear scan", "#93c5fd"),
    ("BenchmarkAccess/blocks={n}/blockSize=4096/read", "PathORAM", "#1d4ed8"),
)


def load_stats(medians_csv: Path):
    stats = {}
    with medians_csv.open(newline="") as file:
        for row in csv.DictReader(file):
            if row["mode"] == "sgx":
                stats[row["benchmark"]] = (float(row["median_us_per_op"]), float(row["stddev_us_per_op"]))
    return stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_dir", type=Path, help="Directory containing medians.csv")
    parser.add_argument("--output-pdf", type=Path, help="Optional extra PDF output path")
    args = parser.parse_args()

    stats = load_stats(args.result_dir / "medians.csv")

    fig, ax = plt.subplots(figsize=(8, 4.5), layout="constrained")
    x = np.arange(len(CAPACITIES))
    bar_width = 0.34
    offsets = (-bar_width / 2, bar_width / 2)

    for (template, label, color), offset in zip(SERIES, offsets):
        medians = [stats[template.format(n=n)][0] for n in CAPACITIES]
        sds = [stats[template.format(n=n)][1] for n in CAPACITIES]
        bars = ax.bar(
            x + offset,
            medians,
            width=bar_width * 0.92,
            yerr=sds,
            capsize=4,
            color=color,
            edgecolor="#1e293b",
            linewidth=0.5,
            error_kw={"ecolor": "#0f172a", "elinewidth": 1.0, "capthick": 1.0},
            label=label,
            zorder=3,
        )
        for bar, val, err in zip(bars, medians, sds):
            text = f"{val:.3f}" if val < 1 else f"{val:.1f}"
            ax.text(
                bar.get_x() + bar.get_width() / 2,
                (val + err) * 1.25,
                text,
                ha="center",
                va="bottom",
                fontsize=8.5,
                color="#0f172a",
            )

    ax.set_yscale("log")
    ax.set_ylim(1e-2, 2.5e3)
    ax.set_xticks(x)
    ax.set_xticklabels([f"{n:,}" for n in CAPACITIES], fontsize=10)
    ax.set_xlabel("Capacity (blocks)")
    ax.set_ylabel("Median read latency (µs/op, log scale)")
    ax.set_title("PathORAM vs. linear scan read latency under SGX (4 KiB blocks)")
    ax.grid(axis="y", which="major", alpha=0.25, zorder=0)
    ax.legend(frameon=True, loc="upper center", ncol=2)

    fig.savefig(args.result_dir / "pathoram-read-latency.pdf")
    fig.savefig(args.result_dir / "pathoram-read-latency.png", dpi=200)
    if args.output_pdf:
        args.output_pdf.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(args.output_pdf)
    plt.close(fig)


if __name__ == "__main__":
    main()
