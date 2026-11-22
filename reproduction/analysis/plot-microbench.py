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


def crypto_operations(table):
    if table == "4-aes":
        return {key: label for key, label in OPERATIONS.items() if key.startswith(("AESGCM_", "NonceGen_"))}
    return OPERATIONS


def plot_crypto(ax, medians, table):
    operations = crypto_operations(table)
    for mode, label, marker in (("plain", "Plain", "o"), ("sgx", "SGX", "s")):
        values = [medians[(f"Benchmark{name}", mode)] for name in operations]
        ax.plot(values, list(operations.values()), linestyle="none", marker=marker, label=label)
    ax.invert_yaxis()
    ax.set_xscale("log")
    ax.set_xlabel("Median latency (µs/op)")
    ax.set_title("AES-GCM timing check (1 million operations per trial)" if table == "4-aes"
                 else "Cryptographic operations")


def plot_reads(ax, medians, deviations, table):
    if table == "5":
        capacities = (256, 512, 1024, 2048)
        series = (
            ("BenchmarkORAMCache_Get/N={n}", "plain", "ORAM (plain)"),
            ("BenchmarkORAMCache_Get/N={n}", "sgx", "ORAM (SGX)"),
        )
        ax.set_title("ORAM read latency")
        ax.set_xlabel("Cache capacity (entries)")
    else:
        capacities = (256, 1024, 4096, 16384)
        series = (
            ("BenchmarkLinearScan/blocks={n}/blockSize=4096/read", "sgx", "Linear scan"),
            ("BenchmarkAccess/blocks={n}/blockSize=4096/read", "sgx", "PathORAM"),
        )
        ax.set_title("PathORAM vs. linear scan under SGX (4 KiB blocks)")
        ax.set_xlabel("Capacity (blocks)")
    log_scale = True
    for name, mode, label in series:
        points = [(n, (name.format(n=n), mode)) for n in capacities]
        points = [(n, key) for n, key in points if key in medians]
        if not points:
            continue
        x = [n for n, _ in points]
        values = [medians[key] for _, key in points]
        errors = [deviations.get(key, float("nan")) for _, key in points]
        if any(key in deviations for _, key in points):
            ax.errorbar(x, values, yerr=errors, marker="o", linestyle="-", capsize=4, label=label)
            if any(value <= error for value, error in zip(values, errors)):
                log_scale = False
        else:
            ax.plot(x, values, marker="o", label=label)
    ax.set_xscale("log", base=2)
    ax.set_xticks(capacities)
    ax.xaxis.set_major_formatter(ScalarFormatter())
    if table == "6" and log_scale:
        ax.set_yscale("log")
    ax.set_ylabel("Median read latency (µs/op)")
    if deviations and table != "5":
        ax.set_title(ax.get_title() + "\nError bars show ±1 sample std. dev.")


def read_medians(directory, table):
    path = directory / "medians.csv"
    if table == "6" and not path.exists():
        samples = defaultdict(list)
        pattern = re.compile(r"^(Benchmark(?:Access|LinearScan)/\S+?)-\d+\s+\d+\s+([\d.]+)\s+ns/op")
        for line in (directory / "sgx.txt").read_text().splitlines():
            match = pattern.match(line)
            if match:
                samples[(match[1], "sgx")].append(float(match[2]))
        return {key: median(values) / 1000 for key, values in samples.items() if len(values) == 3}, {}
    medians = {}
    deviations = {}
    with path.open(newline="") as file:
        for row in csv.DictReader(file):
            key = (row["benchmark"], row["mode"])
            medians[key] = float(row["median_us_per_op"])
            if row.get("stddev_us_per_op"):
                deviations[key] = float(row["stddev_us_per_op"])
    return medians, deviations


def write_table(directory, table, medians, deviations, settings):
    def latency(value):
        return "---" if value is None else f"{value:.4g}"

    def ratio(numerator, denominator):
        return "---" if numerator is None or not denominator else rf"${numerator / denominator:.3g}\times$"

    def latency_columns(*keys):
        return tuple(latency(value) for key in keys for value in (medians.get(key), deviations.get(key)))

    if table in {"4", "4-aes"}:
        caption = r"Per-operation cryptographic latency in ${}\mu$s."
        if table == "4-aes":
            caption += " AES-GCM timing-resolution check with one million operations per trial."
        elif settings["iterations"] == "1000000":
            caption += " One million operations per trial."
        headers = ("Operation", "Plain", "Std. dev.", "SGX", "Std. dev.", "Overhead")
        rows = []
        for key, label in crypto_operations(table).items():
            plain = (f"Benchmark{key}", "plain")
            sgx = (f"Benchmark{key}", "sgx")
            if key in {"AESGCM_Seal_PreNonce", "NonceGen_Only"}:
                label = r"\quad " + label
            rows.append((label, *latency_columns(plain, sgx), ratio(medians[sgx], medians[plain])))
    elif table == "5":
        caption = r"Cache read latency in ${}\mu$s by cache capacity."
        headers = ("Capacity", "LRU", "Std. dev.", "ORAM (Plain)", "Std. dev.",
                   "ORAM (SGX)", "Std. dev.", "Overhead")
        rows = []
        for n in (256, 512, 1024, 2048):
            lru = (f"BenchmarkLRUCache_Get/N={n}", "plain")
            plain = (f"BenchmarkORAMCache_Get/N={n}", "plain")
            sgx = (f"BenchmarkORAMCache_Get/N={n}", "sgx")
            rows.append((str(n), *latency_columns(lru, plain, sgx), ratio(medians[sgx], medians[plain])))
    else:
        caption = r"PathORAM and linear scan read latency under SGX in ${}\mu$s (4 KiB blocks)."
        if "pathoram_lookup_cycle" in settings:
            caption += (
                f" Both methods use {int(settings['iterations']):,} iterations per trial,"
                f" repeating the first {int(settings['pathoram_lookup_cycle'])} lookups."
            )
        elif "linear_scan_iterations" in settings:
            caption += f" Linear scan uses {int(settings['linear_scan_iterations']):,} iterations per trial"
            if "linear_scan_lookup_cycle" in settings:
                caption += f", repeating the first {int(settings['linear_scan_lookup_cycle'])} lookups"
            caption += "."
        headers = ("Capacity", "Linear scan", "Std. dev.", "PathORAM", "Std. dev.", "PathORAM/Linear scan")
        rows = []
        for n in (256, 1024, 4096, 16384):
            suffix = f"/blocks={n}/blockSize=4096/read"
            scan = ("BenchmarkLinearScan" + suffix, "sgx")
            oram = ("BenchmarkAccess" + suffix, "sgx")
            rows.append((str(n), *latency_columns(scan, oram), ratio(medians[oram], medians.get(scan))))
        if any(row[1] == "---" for row in rows):
            caption += " Dashes indicate runs with no recorded linear-scan timing."

    if deviations:
        caption += f" Latencies are medians and standard deviations are sample estimates across {int(settings['trials'])} trials."
        if settings.get("warmup_trials") == "1":
            caption += " One warm-up trial per benchmark case and mode was discarded."
    columns = "l" + "r" * (len(headers) - 1)
    with (directory / f"table{table}.tex").open("w") as file:
        print(r"\begin{table}", r"\centering", r"\small", r"\setlength{\tabcolsep}{4pt}",
              rf"\begin{{tabular}}{{{columns}}}", r"\toprule", sep="\n", file=file)
        print(" & ".join(headers), r"\\", file=file)
        print(r"\midrule", file=file)
        for row in rows:
            print(" & ".join(row), r"\\", file=file)
        label = f"tab:reproduction-table{table}"
        if table in {"4", "6"} and settings.get("iterations") == "1000000":
            label += "-1m"
        print(r"\bottomrule", r"\end{tabular}", rf"\caption{{{caption}}}",
              rf"\label{{{label}}}", r"\end{table}", sep="\n", file=file)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_dir", type=Path, help="Directory containing medians.csv")
    args = parser.parse_args()
    directory = args.result_dir

    try:
        settings = dict(line.split("=", 1) for line in (directory / "parameters.txt").read_text().splitlines())
        table = settings["table"]
        if table not in {"4", "4-aes", "5", "6"}:
            raise ValueError(f"Unsupported table {table}")
        medians, deviations = read_medians(directory, table)
        write_table(directory, table, medians, deviations, settings)
        fig, ax = plt.subplots(figsize=(8, 4.5), layout="constrained")
        if table in {"4", "4-aes"}:
            plot_crypto(ax, medians, table)
            ax.grid(axis="x", alpha=0.25)
        else:
            plot_reads(ax, medians, deviations, table)
            ax.grid(axis="y", alpha=0.25)
        ax.legend()
        fig.savefig(directory / "latency.pdf")
        fig.savefig(directory / "latency.png", dpi=200)
        plt.close(fig)
    except (OSError, KeyError, ValueError) as error:
        parser.exit(1, f"Could not plot microbenchmark results: {error}\n")


if __name__ == "__main__":
    main()
