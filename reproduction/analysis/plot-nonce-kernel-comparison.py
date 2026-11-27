#!/usr/bin/env python3
"""Plot non-SGX nonce generation latency on Linux 6.8 vs. a newer kernel (>= 6.11) with ±1 std. dev. error bars."""

import argparse
import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def load_plain_nonce(result_dir: Path):
    kernel = (result_dir / "proxy-environment.txt").read_text().splitlines()[0].split()[2]
    with (result_dir / "medians.csv").open(newline="") as file:
        for row in csv.DictReader(file):
            if row["benchmark"] == "BenchmarkNonceGen_Only" and row["mode"] == "plain":
                return kernel, float(row["median_us_per_op"]), float(row["stddev_us_per_op"])
    raise ValueError(f"BenchmarkNonceGen_Only (plain) not found in {result_dir / 'medians.csv'}")


def short_label(kernel: str) -> str:
    major_minor = ".".join(kernel.split(".")[:2])
    return f"Linux {major_minor}\n({kernel})"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("old_result_dir", type=Path, help="Table 4 1M result directory on Linux 6.8")
    parser.add_argument("new_result_dir", type=Path, help="Table 4 1M result directory on Linux >= 6.11")
    parser.add_argument("--output-pdf", type=Path, help="Optional extra PDF output path")
    args = parser.parse_args()

    entries = [load_plain_nonce(args.old_result_dir), load_plain_nonce(args.new_result_dir)]
    labels = [short_label(kernel) for kernel, _, _ in entries]
    medians = [med for _, med, _ in entries]
    sds = [sd for _, _, sd in entries]
    colors = ("#93c5fd", "#1d4ed8")

    fig, ax = plt.subplots(figsize=(6.4, 4.2), layout="constrained")
    x = np.arange(len(entries))
    bars = ax.bar(
        x,
        medians,
        width=0.45,
        yerr=sds,
        capsize=5,
        color=colors,
        edgecolor="#1e293b",
        linewidth=0.6,
        error_kw={"ecolor": "#0f172a", "elinewidth": 1.2, "capthick": 1.2},
        zorder=3,
    )

    ymax = max(m + s for m, s in zip(medians, sds))
    for bar, val, err in zip(bars, medians, sds):
        text = f"{val:.4f} ± {err:.4f} µs" if val < 0.1 else f"{val:.3f} ± {err:.3f} µs"
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            val + err + ymax * 0.03,
            text,
            ha="center",
            va="bottom",
            fontsize=9,
            color="#0f172a",
        )

    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=10)
    ax.set_ylabel("Median latency (µs/op)")
    ax.set_ylim(0, ymax * 1.18)
    ax.set_title("Non-SGX nonce generation latency by Linux kernel (1M ops/trial)")
    ax.grid(axis="y", alpha=0.25, zorder=0)

    fig.savefig(args.new_result_dir / "nonce-gen-kernel-comparison.pdf")
    fig.savefig(args.new_result_dir / "nonce-gen-kernel-comparison.png", dpi=200)
    if args.output_pdf:
        args.output_pdf.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(args.output_pdf)
    plt.close(fig)


if __name__ == "__main__":
    main()
