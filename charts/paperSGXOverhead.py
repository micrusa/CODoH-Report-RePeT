import numpy as np
import matplotlib.pyplot as plt

capacities = [256, 512, 1024, 2048]
lru = [0.11, 0.11, 0.12, 0.13]
oram = [108, 103, 99, 107]
oram_sgx = [223, 222, 228, 377]

x = np.arange(len(capacities))
width = 0.27

fig, ax = plt.subplots(figsize=(9, 5))

bars1 = ax.bar(x - width, lru, width, label="LRU", color="#94a3b8")
bars2 = ax.bar(x, oram, width, label="ORAM without SGX", color="#64748b")
bars3 = ax.bar(x + width, oram_sgx, width, label="ORAM with SGX", color="#2563eb")

ax.bar_label(bars2, fmt="%.0f", padding=3)
ax.bar_label(bars3, fmt="%.0f", padding=3)

ax.set_ylabel("Cache read latency (µs)")
ax.set_xlabel("Cache capacity (entries)")
ax.set_title("Cache Read Latency: LRU vs. ORAM vs. SGX")
ax.set_xticks(x, capacities)
ax.set_ylim(0, 430)
ax.legend()
ax.grid(axis="y", alpha=0.2)
ax.set_axisbelow(True)

plt.tight_layout()
plt.savefig("codoh_cache_overhead.pdf", bbox_inches="tight")
plt.savefig("codoh_cache_overhead.png", dpi=300, bbox_inches="tight")
plt.show()
