#!/usr/bin/env python3
"""Analyze IPFS upload-download benchmark results and create graphs."""

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import sys
import os

# Set Japanese font if available
try:
    plt.rcParams['font.family'] = ['sans-serif']
    plt.rcParams['font.sans-serif'] = ['Hiragino Sans', 'Yu Gothic', 'Meirio', 'Takao',
                                        'IPAexGothic', 'IPAPGothic', 'VL PGothic',
                                        'Noto Sans CJK JP', 'DejaVu Sans']
except:
    pass

# Load CSV file
csv_file = sys.argv[1] if len(sys.argv) > 1 else '../bench_upload_download_20251014_124214.csv'
output_dir = sys.argv[2] if len(sys.argv) > 2 else 'upload_download_analysis'

# Create output directory
os.makedirs(output_dir, exist_ok=True)

# Read CSV
df = pd.read_csv(csv_file)

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

# File order by size
file_order = ["test10m.dat", "test50m.dat", "test100m.dat", "test250m.dat",
              "test500m.dat", "test1g.dat", "test2g.dat", "test4g.dat"]

# Calculate statistics per file
stats = df.groupby('file').agg({
    'upload_throughput_mib_per_s': ['mean', 'std', 'min', 'max'],
    'download_throughput_mib_per_s': ['mean', 'std', 'min', 'max'],
    'size_bytes': 'first'
}).round(2)

# Calculate percentiles separately
upload_p50 = df.groupby('file')['upload_throughput_mib_per_s'].quantile(0.5).round(2)
upload_p95 = df.groupby('file')['upload_throughput_mib_per_s'].quantile(0.95).round(2)
download_p50 = df.groupby('file')['download_throughput_mib_per_s'].quantile(0.5).round(2)
download_p95 = df.groupby('file')['download_throughput_mib_per_s'].quantile(0.95).round(2)

# Flatten column names
stats.columns = ['_'.join(col).strip() if col[1] else col[0] for col in stats.columns.values]

# Add percentiles
stats['upload_p50'] = upload_p50
stats['upload_p95'] = upload_p95
stats['download_p50'] = download_p50
stats['download_p95'] = download_p95

# Sort by file order
stats = stats.reindex(file_order)

# 1. Combined Upload/Download Bar Chart with error bars
fig, ax = plt.subplots(figsize=(14, 7))

x = np.arange(len(file_order))
width = 0.35

# Get data in correct order
upload_means = [stats.loc[f, 'upload_throughput_mib_per_s_mean'] for f in file_order]
upload_stds = [stats.loc[f, 'upload_throughput_mib_per_s_std'] for f in file_order]
download_means = [stats.loc[f, 'download_throughput_mib_per_s_mean'] for f in file_order]
download_stds = [stats.loc[f, 'download_throughput_mib_per_s_std'] for f in file_order]

# Create bars
bars1 = ax.bar(x - width/2, upload_means, width, yerr=upload_stds,
               label='アップロード', color='#4c72b0', alpha=0.85, capsize=4)
bars2 = ax.bar(x + width/2, download_means, width, yerr=download_stds,
               label='ダウンロード', color='#55a868', alpha=0.85, capsize=4)

# Add value labels on bars
for i, (bar1, bar2) in enumerate(zip(bars1, bars2)):
    ax.text(bar1.get_x() + bar1.get_width()/2, bar1.get_height() + 20,
            f'{upload_means[i]:.0f}',
            ha='center', va='bottom', fontsize=9)
    ax.text(bar2.get_x() + bar2.get_width()/2, bar2.get_height() + 20,
            f'{download_means[i]:.0f}',
            ha='center', va='bottom', fontsize=9)

ax.set_xlabel('ファイルサイズ', fontsize=12)
ax.set_ylabel('スループット (MiB/s)', fontsize=12)
ax.set_title('10ノードIPFS アップロード・ダウンロードスループット', fontsize=14, fontweight='bold')
ax.set_xticks(x)
ax.set_xticklabels([size_labels[f] for f in file_order], rotation=45, ha='right')
ax.legend(loc='upper right', fontsize=11)
ax.grid(True, axis='y', linestyle='--', alpha=0.3)

plt.tight_layout()
plt.savefig(os.path.join(output_dir, 'throughput_upload_download_bar.png'), dpi=150, bbox_inches='tight')
plt.show()

# 2. Speed Ratio Chart (Download/Upload)
fig, ax = plt.subplots(figsize=(12, 6))

ratios = [download_means[i]/upload_means[i] for i in range(len(file_order))]
colors = ['#55a868' if r > 1 else '#dd8452' for r in ratios]

bars = ax.bar(x, ratios, color=colors, alpha=0.85)

# Add value labels
for i, bar in enumerate(bars):
    ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.05,
            f'{ratios[i]:.2f}x',
            ha='center', va='bottom', fontsize=10)

ax.axhline(y=1, color='black', linestyle='--', alpha=0.5, linewidth=1)
ax.set_xlabel('ファイルサイズ', fontsize=12)
ax.set_ylabel('速度比 (ダウンロード/アップロード)', fontsize=12)
ax.set_title('ダウンロード速度 vs アップロード速度比', fontsize=14, fontweight='bold')
ax.set_xticks(x)
ax.set_xticklabels([size_labels[f] for f in file_order], rotation=45, ha='right')
ax.grid(True, axis='y', linestyle='--', alpha=0.3)

plt.tight_layout()
plt.savefig(os.path.join(output_dir, 'speed_ratio.png'), dpi=150, bbox_inches='tight')
plt.show()

# 3. Time Series Plot for both upload and download
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 10))

for file in file_order:
    file_data = df[df['file'] == file].sort_values('run')
    ax1.plot(file_data['run'], file_data['upload_throughput_mib_per_s'],
             marker='o', markersize=4, label=size_labels[file], alpha=0.7)
    ax2.plot(file_data['run'], file_data['download_throughput_mib_per_s'],
             marker='o', markersize=4, label=size_labels[file], alpha=0.7)

ax1.set_xlabel('実行回数', fontsize=11)
ax1.set_ylabel('アップロード スループット (MiB/s)', fontsize=11)
ax1.set_title('アップロードスループット時系列', fontsize=12)
ax1.grid(True, linestyle='--', alpha=0.3)
ax1.legend(ncol=4, loc='upper right', fontsize=9)

ax2.set_xlabel('実行回数', fontsize=11)
ax2.set_ylabel('ダウンロード スループット (MiB/s)', fontsize=11)
ax2.set_title('ダウンロードスループット時系列', fontsize=12)
ax2.grid(True, linestyle='--', alpha=0.3)
ax2.legend(ncol=4, loc='upper right', fontsize=9)

plt.tight_layout()
plt.savefig(os.path.join(output_dir, 'throughput_timeseries.png'), dpi=150, bbox_inches='tight')
plt.show()

# 4. Summary Statistics Table
print("\n=== スループット統計サマリー (MiB/s) ===")
print("\n【アップロード】")
print(f"{'ファイル':<10} {'平均':>10} {'標準偏差':>10} {'P50':>10} {'P95':>10} {'最小':>10} {'最大':>10}")
print("-" * 75)
for file in file_order:
    print(f"{size_labels[file]:<10} "
          f"{stats.loc[file, 'upload_throughput_mib_per_s_mean']:>10.2f} "
          f"{stats.loc[file, 'upload_throughput_mib_per_s_std']:>10.2f} "
          f"{stats.loc[file, 'upload_p50']:>10.2f} "
          f"{stats.loc[file, 'upload_p95']:>10.2f} "
          f"{stats.loc[file, 'upload_throughput_mib_per_s_min']:>10.2f} "
          f"{stats.loc[file, 'upload_throughput_mib_per_s_max']:>10.2f}")

print("\n【ダウンロード】")
print(f"{'ファイル':<10} {'平均':>10} {'標準偏差':>10} {'P50':>10} {'P95':>10} {'最小':>10} {'最大':>10}")
print("-" * 75)
for file in file_order:
    print(f"{size_labels[file]:<10} "
          f"{stats.loc[file, 'download_throughput_mib_per_s_mean']:>10.2f} "
          f"{stats.loc[file, 'download_throughput_mib_per_s_std']:>10.2f} "
          f"{stats.loc[file, 'download_p50']:>10.2f} "
          f"{stats.loc[file, 'download_p95']:>10.2f} "
          f"{stats.loc[file, 'download_throughput_mib_per_s_min']:>10.2f} "
          f"{stats.loc[file, 'download_throughput_mib_per_s_max']:>10.2f}")

# Overall averages
overall_upload = df['upload_throughput_mib_per_s'].mean()
overall_download = df['download_throughput_mib_per_s'].mean()

print(f"\n全体平均:")
print(f"  アップロード: {overall_upload:.2f} MiB/s")
print(f"  ダウンロード: {overall_download:.2f} MiB/s")
print(f"  ダウンロード/アップロード比: {overall_download/overall_upload:.2f}x")

# Save summary to CSV
summary_df = pd.DataFrame({
    'file': file_order,
    'size_label': [size_labels[f] for f in file_order],
    'upload_mean': upload_means,
    'upload_std': upload_stds,
    'download_mean': download_means,
    'download_std': download_stds,
    'speed_ratio': ratios
})
summary_df.to_csv(os.path.join(output_dir, 'summary.csv'), index=False)
print(f"\nサマリーCSV保存先: {os.path.join(output_dir, 'summary.csv')}")

# Print experiment info
total_runs = df['run'].max()
total_operations = len(df)
print(f"\n実験情報:")
print(f"  総実行回数: {total_runs}")
print(f"  総操作数: {total_operations}")
print(f"  使用ノード数: {df['upload_node'].nunique()} (アップロード), {df['download_node'].nunique()} (ダウンロード)")