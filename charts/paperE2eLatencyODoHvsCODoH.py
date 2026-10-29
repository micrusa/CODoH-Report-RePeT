import numpy as np
import matplotlib.pyplot as plt

workloads = ["Cold", "Zipf", "Warm"]
odoh = [108.49, 48.59, 47.97]
codoh = [97.20, 22.34, 17.96]

x = np.arange(len(workloads))
width = 0.35

fig, ax = plt.subplots(figsize=(9, 5))

bars1 = ax.bar(x - width / 2, odoh, width, label="ODoH baseline", color="#64748b")
bars2 = ax.bar(x + width / 2, codoh, width, label="Full CODoH (SGX)", color="#2563eb")

ax.bar_label(bars1, fmt="%.2f", padding=3)
ax.bar_label(bars2, fmt="%.2f", padding=3)

ax.set_ylabel("Median E2E latency (ms)")
ax.set_xlabel("Workload")
ax.set_title("Median End-to-End Latency: ODoH vs. CODoH")
ax.set_xticks(x, workloads)
ax.set_ylim(0, 125)
ax.legend()
ax.grid(axis="y", alpha=0.2)
ax.set_axisbelow(True)

plt.tight_layout()
plt.savefig("codoh_latency.pdf", bbox_inches="tight")
plt.savefig("codoh_latency.png", dpi=300, bbox_inches="tight")
plt.show()
