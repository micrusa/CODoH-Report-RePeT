import matplotlib.pyplot as plt

batch_sizes = [5, 20, 50, 100, 256]
top1 = [8.5, 0.4, 0, 0, 0]
top5 = [43.9, 21.7, 0.9, 0, 0]

fig, ax = plt.subplots(figsize=(8, 4.5))

ax.plot(batch_sizes, top1, marker="o", linewidth=2, label="Top-1 accuracy")
ax.plot(batch_sizes, top5, marker="s", linewidth=2, label="Top-5 accuracy")

ax.set_xlabel("Batch size (B)")
ax.set_ylabel("Identification accuracy (%)")
ax.set_xticks(batch_sizes)
ax.set_ylim(0, 50)
ax.grid(axis="y", alpha=0.3)
ax.legend()
fig.tight_layout()

plt.savefig("batch_privacy.pdf", bbox_inches="tight")
plt.savefig("batch_privacy.png", dpi=300, bbox_inches="tight")
plt.show()
