#!/usr/bin/env python3
"""Compare benchmark results between single node and previous experiment."""

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import sys

# Set Japanese font if available
try:
    plt.rcParams['font.family'] = ['sans-serif']
    plt.rcParams['font.sans-serif'] = ['Hiragino Sans', 'Yu Gothic', 'Meirio', 'Takao',
                                        'IPAexGothic', 'IPAPGothic', 'VL PGothic',
                                        'Noto Sans CJK JP', 'DejaVu Sans']
except:
    pass

# Load both CSV files
previous = pd.read_csv('analysis/summary.csv')
single = pd.read_csv('single_node_analysis/summary.csv')

# File size labels
size_labels = {
    "test10m.dat": "10MB",
    "test50m.dat": "50MB",
    "test100m.dat": "100MB",
    "test250m.dat": "250MB",
    "test500m.dat": "500MB",
    "test1g.dat": "1GB",
    "test2g.dat": "2GB",
    "test4g.dat": "4GB"
}

# Sort files by size
file_order = ["test10m.dat", "test50m.dat", "test100m.dat", "test250m.dat",
              "test500m.dat", "test1g.dat", "test2g.dat", "test4g.dat"]

previous_sorted = previous.set_index('file').reindex(file_order).reset_index()
single_sorted = single.set_index('file').reindex(file_order).reset_index()

# Create comparison bar chart
fig, ax = plt.subplots(figsize=(14, 7))

x = np.arange(len(file_order))
width = 0.35

# Previous experiment bars (100 runs)
bars1 = ax.bar(x - width/2, previous_sorted['throughput_mean'], width,
               yerr=previous_sorted['throughput_std'], capsize=4,
               label='前回の実験 (100ラン)', color='#4c72b0', alpha=0.85)

# Single node bars (10 runs)
bars2 = ax.bar(x + width/2, single_sorted['throughput_mean'], width,
               yerr=single_sorted['throughput_std'], capsize=4,
               label='単一ノード (10ラン)', color='#dd8452', alpha=0.85)

# Add value labels on bars
for i, (bar1, bar2) in enumerate(zip(bars1, bars2)):
    ax.text(bar1.get_x() + bar1.get_width()/2, bar1.get_height() + 10,
            f'{previous_sorted.iloc[i]["throughput_mean"]:.0f}',
            ha='center', va='bottom', fontsize=9)
    ax.text(bar2.get_x() + bar2.get_width()/2, bar2.get_height() + 10,
            f'{single_sorted.iloc[i]["throughput_mean"]:.0f}',
            ha='center', va='bottom', fontsize=9)

ax.set_xlabel('ファイルサイズ', fontsize=12)
ax.set_ylabel('スループット (MiB/s)', fontsize=12)
ax.set_title('IPFSアップロードスループット比較', fontsize=14, fontweight='bold')
ax.set_xticks(x)
ax.set_xticklabels([size_labels[f] for f in file_order], rotation=45, ha='right')
ax.legend(loc='upper right', fontsize=11)
ax.grid(True, axis='y', linestyle='--', alpha=0.3)
ax.set_ylim(0, max(previous_sorted['throughput_mean'].max(),
                    single_sorted['throughput_mean'].max()) * 1.15)

plt.tight_layout()
plt.savefig('comparison_throughput.png', dpi=150, bbox_inches='tight')
plt.show()

# Print comparison statistics
print("\n=== スループット比較 (MiB/s) ===")
print(f"{'ファイル':<15} {'前回実験':>12} {'単一ノード':>12} {'差':>12} {'比率':>10}")
print("-" * 61)

for file in file_order:
    prev_val = previous_sorted[previous_sorted['file'] == file]['throughput_mean'].values[0]
    single_val = single_sorted[single_sorted['file'] == file]['throughput_mean'].values[0]
    diff = single_val - prev_val
    ratio = single_val / prev_val

    print(f"{size_labels[file]:<15} {prev_val:>12.2f} {single_val:>12.2f} "
          f"{diff:>+12.2f} {ratio:>10.2%}")

print("\n全体平均:")
prev_avg = previous_sorted['throughput_mean'].mean()
single_avg = single_sorted['throughput_mean'].mean()
print(f"前回実験: {prev_avg:.2f} MiB/s")
print(f"単一ノード: {single_avg:.2f} MiB/s")
print(f"差: {single_avg - prev_avg:+.2f} MiB/s ({single_avg/prev_avg:.2%})")