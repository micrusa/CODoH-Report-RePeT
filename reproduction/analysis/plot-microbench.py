#!/usr/bin/env python3
"""Generate the paper-style table and latency plot for a microbenchmark run."""

import argparse
import csv
import re
from collections import defaultdict
from pathlib import Path
from statistics import median

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import ScalarFormatter


OPERATIONS = {
        "HPKE_Seal": "HPKE encrypt",
        "HPKE_Open": "HPKE decrypt",
        "AESGCM_Seal": "AES-GCM seal",
        "AESGCM_Seal_PreNonce": "AES-GCM seal (precomputed nonce)",
        "NonceGen_Only": "Nonce generation",
        "AESGCM_Open": "AES-GCM open",
        "Ed25519_Sign": "Ed25519 sign",
        "Ed25519_Verify": "Ed25519 verify",
}


def plot_crypto(ax, medians):
    for mode, label, marker in (("plain", "Plain", "o"), ("sgx", "SGX", "s")):
        values = [medians[(f"Benchmark{name}", mode)] for name in OPERATIONS]
        ax.plot(values, list(OPERATIONS.values()), linestyle="none", marker=marker, label=label)
    ax.invert_yaxis()
    ax.set_xscale("log")
    ax.set_xlabel("Median latency (µs/op)")
    ax.set_title("Cryptographic operations")


def plot_reads(ax, medians, table):
    if table == "5":
        capacities = (256, 512, 1024, 2048)
        series = (
            ("BenchmarkLRUCache_Get/N={n}", "plain", "LRU (plain)"),
            ("BenchmarkORAMCache_Get/N={n}", "plain", "ORAM (plain)"),
            ("BenchmarkORAMCache_Get/N={n}", "sgx", "ORAM (SGX)"),
        )
        ax.set_title("Cache read latency")
        ax.set_xlabel("Cache capacity (entries)")
    else:
        capacities = (256, 1024, 4096, 16384)
        series = (
            ("BenchmarkLinearScan/blocks={n}/blockSize=4096/read", "sgx", "Linear scan"),
            ("BenchmarkAccess/blocks={n}/blockSize=4096/read", "sgx", "PathORAM"),
        )
        ax.set_title("PathORAM vs. linear scan under SGX (4 KiB blocks)")
        ax.set_xlabel("Capacity (blocks)")
    for name, mode, label in series:
        values = [medians.get((name.format(n=n), mode)) for n in capacities]
        if any(value is not None for value in values):
            ax.plot(capacities, values, marker="o", label=label)
    ax.set_xscale("log", base=2)
    ax.set_xticks(capacities)
    ax.xaxis.set_major_formatter(ScalarFormatter())
    ax.set_yscale("log")
    ax.set_ylabel("Median read latency (µs/op)")


def read_medians(directory, table):
    path = directory / "medians.csv"
    if table == "6" and not path.exists():
        samples = defaultdict(list)
        pattern = re.compile(r"^(Benchmark(?:Access|LinearScan)/\S+?)-\d+\s+\d+\s+([\d.]+)\s+ns/op")
        for line in (directory / "sgx.txt").read_text().splitlines():
            match = pattern.match(line)
            if match:
                samples[(match[1], "sgx")].append(float(match[2]))
        return {key: median(values) / 1000 for key, values in samples.items() if len(values) == 3}
    with path.open(newline="") as file:
        return {
            (row["benchmark"], row["mode"]): float(row["median_us_per_op"])
            for row in csv.DictReader(file)
        }


def write_table(directory, table, medians, settings):
    def latency(value):
        return "---" if value is None else f"{value:.4g}"

    def ratio(numerator, denominator):
        return "---" if numerator is None or not denominator else rf"${numerator / denominator:.3g}\times$"

    if table == "4":
        caption = r"Per-operation cryptographic latency in ${}\mu$s."
        headers = ("Operation", "Plain", "SGX", "Overhead")
        rows = []
        for key, label in OPERATIONS.items():
            plain = medians[(f"Benchmark{key}", "plain")]
            sgx = medians[(f"Benchmark{key}", "sgx")]
            if key in {"AESGCM_Seal_PreNonce", "NonceGen_Only"}:
                label = r"\quad " + label
            rows.append((label, latency(plain), latency(sgx), ratio(sgx, plain)))
    elif table == "5":
        caption = r"Cache read latency in ${}\mu$s by cache capacity."
        headers = ("Capacity", "LRU", "ORAM (Plain)", "ORAM (SGX)", "Overhead")
        rows = []
        for n in (256, 512, 1024, 2048):
            lru = medians[(f"BenchmarkLRUCache_Get/N={n}", "plain")]
            plain = medians[(f"BenchmarkORAMCache_Get/N={n}", "plain")]
            sgx = medians[(f"BenchmarkORAMCache_Get/N={n}", "sgx")]
            rows.append((str(n), latency(lru), latency(plain), latency(sgx), ratio(sgx, plain)))
    else:
        caption = r"PathORAM and linear scan read latency under SGX in ${}\mu$s (4 KiB blocks)."
        if "linear_scan_iterations" in settings:
            caption += f" Linear scan uses {int(settings['linear_scan_iterations']):,} iterations per trial."
        headers = ("Capacity", "Linear scan", "PathORAM", "PathORAM/Linear scan")
        rows = []
        for n in (256, 1024, 4096, 16384):
            suffix = f"/blocks={n}/blockSize=4096/read"
            scan = medians.get(("BenchmarkLinearScan" + suffix, "sgx"))
            oram = medians[("BenchmarkAccess" + suffix, "sgx")]
            rows.append((str(n), latency(scan), latency(oram), ratio(oram, scan)))
        if any(row[1] == "---" for row in rows):
            caption += " Dashes indicate runs with no recorded linear-scan timing."

    columns = "l" + "r" * (len(headers) - 1)
    with (directory / f"table{table}.tex").open("w") as file:
        print(r"\begin{table}", r"\centering", rf"\begin{{tabular}}{{{columns}}}", r"\toprule", sep="\n", file=file)
        print(" & ".join(headers), r"\\", file=file)
        print(r"\midrule", file=file)
        for row in rows:
            print(" & ".join(row), r"\\", file=file)
        print(r"\bottomrule", r"\end{tabular}", rf"\caption{{{caption}}}",
              rf"\label{{tab:reproduction-table{table}}}", r"\end{table}", sep="\n", file=file)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_dir", type=Path, help="Directory containing medians.csv")
    args = parser.parse_args()
    directory = args.result_dir

    try:
        settings = dict(line.split("=", 1) for line in (directory / "parameters.txt").read_text().splitlines())
        table = settings["table"]
        if table not in {"4", "5", "6"}:
            raise ValueError(f"Unsupported table {table}")
        medians = read_medians(directory, table)
        write_table(directory, table, medians, settings)
        fig, ax = plt.subplots(figsize=(8, 4.5), layout="constrained")
        if table == "4":
            plot_crypto(ax, medians)
            ax.grid(axis="x", alpha=0.25)
        else:
            plot_reads(ax, medians, table)
            ax.grid(axis="y", alpha=0.25)
        ax.legend()
        fig.savefig(directory / "latency.pdf")
        fig.savefig(directory / "latency.png", dpi=200)
        plt.close(fig)
    except (OSError, KeyError, ValueError) as error:
        parser.exit(1, f"Could not plot microbenchmark results: {error}\n")


if __name__ == "__main__":
    main()
