"""Latency chart (without vs with breaker, custom and Resilience4j) from the demo JSON files."""
import json, os, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1]
fig, axes = plt.subplots(1, 2, figsize=(9, 3.4), dpi=150, sharey=True)
fig.patch.set_facecolor("#fcfcfb")
for ax, impl in zip(axes, ["custom", "resilience4j"]):
    s = json.load(open(os.path.join(d, f"01-circuit-breaker-{impl}.json")))["summary"]
    x = range(1, 31)
    ax.set_facecolor("#fcfcfb")
    ax.axvspan(5.5, 21.5, color="#e7e6e2", lw=0)
    ax.plot(x, s["latencyMsWithout"], color="#2a78d6", lw=2, marker="o", ms=3, label="Without breaker")
    ax.plot(x, s["latencyMsWith"], color="#eb6834", lw=2, marker="o", ms=3, label="With breaker")
    ax.set_title(f"impl = {impl}", loc="left", fontsize=9)
    ax.set_xlabel("Call number", fontsize=8, color="#52514e")
    for sp in ("top", "right"):
        ax.spines[sp].set_visible(False)
    ax.grid(axis="y", color="#e7e6e2")
    ax.tick_params(labelsize=7, colors="#52514e")
axes[0].set_ylabel("Caller latency (ms)", fontsize=8, color="#52514e")
axes[1].legend(frameon=False, fontsize=7)
fig.suptitle("ms-requests -> ms-inventory latency during an outage (grey = inventory hanging)", x=0.01, ha="left", fontsize=10)
fig.tight_layout()
fig.savefig(os.path.join(d, "circuit-breaker-latency.png"))
