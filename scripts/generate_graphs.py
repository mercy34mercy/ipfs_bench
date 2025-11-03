#!/usr/bin/env python3
"""
IPFS Bandwidth Test Results Visualization
Generate graphs from test results JSON files
"""

import json
import matplotlib.pyplot as plt
import matplotlib
import numpy as np
from pathlib import Path
import japanize_matplotlib

# Use non-interactive backend
matplotlib.use('Agg')

def load_json(filepath):
    """Load JSON test results"""
    with open(filepath, 'r') as f:
        return json.load(f)

def aggregate_results(results):
    """Aggregate results by file size (average of iterations)"""
    aggregated = {}

    for result in results:
        filename = result['file']
        if filename not in aggregated:
            aggregated[filename] = {
                'fileSize': result['fileSize'],
                'upload_times': [],
                'download_times': [],
                'upload_throughputs': [],
                'download_throughputs': []
            }

        aggregated[filename]['upload_times'].append(result['upload_time'])
        aggregated[filename]['download_times'].append(result['download_time'])
        aggregated[filename]['upload_throughputs'].append(result['upload_throughput'])
        aggregated[filename]['download_throughputs'].append(result['download_throughput'])

    # Calculate averages
    for filename in aggregated:
        data = aggregated[filename]
        data['avg_upload_time'] = np.mean(data['upload_times'])
        data['avg_download_time'] = np.mean(data['download_times'])
        data['avg_upload_mbps'] = np.mean(data['upload_throughputs']) * 8 / 1_000_000
        data['avg_download_mbps'] = np.mean(data['download_throughputs']) * 8 / 1_000_000
        data['ratio'] = data['avg_download_time'] / data['avg_upload_time']

    return aggregated

def create_throughput_comparison_graph(data_100mbps, data_1gbps, output_dir):
    """Create throughput comparison graph for both network scenarios"""

    # Prepare data
    file_labels = ['10MB', '50MB', '100MB', '250MB', '500MB', '1GB']
    files = ['test10m.dat', 'test50m.dat', 'test100m.dat', 'test250m.dat', 'test500m.dat', 'test1g.dat']

    # Extract data for 100Mbps
    upload_100 = [data_100mbps[f]['avg_upload_mbps'] for f in files]
    download_100 = [data_100mbps[f]['avg_download_mbps'] for f in files]

    # Extract data for 1Gbps
    upload_1g = [data_1gbps[f]['avg_upload_mbps'] for f in files]
    download_1g = [data_1gbps[f]['avg_download_mbps'] for f in files]

    # Create figure with 2 subplots
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))

    x = np.arange(len(file_labels))
    width = 0.35

    # 100Mbps graph
    bars1 = ax1.bar(x - width/2, upload_100, width, label='Upload', color='#2E86AB', alpha=0.8)
    bars2 = ax1.bar(x + width/2, download_100, width, label='Download', color='#A23B72', alpha=0.8)

    ax1.axhline(y=100, color='red', linestyle='--', linewidth=1, label='理論値 100Mbps', alpha=0.5)
    ax1.set_xlabel('ファイルサイズ', fontsize=12)
    ax1.set_ylabel('スループット (Mbps)', fontsize=12)
    ax1.set_title('100Mbps ネットワーク - Upload vs Download', fontsize=14, fontweight='bold')
    ax1.set_xticks(x)
    ax1.set_xticklabels(file_labels)
    ax1.legend(fontsize=10)
    ax1.grid(axis='y', alpha=0.3)
    ax1.set_ylim(0, 120)

    # Add value labels on bars
    for bars in [bars1, bars2]:
        for bar in bars:
            height = bar.get_height()
            ax1.text(bar.get_x() + bar.get_width()/2., height,
                    f'{height:.0f}',
                    ha='center', va='bottom', fontsize=9)

    # 1Gbps graph
    bars3 = ax2.bar(x - width/2, upload_1g, width, label='Upload', color='#2E86AB', alpha=0.8)
    bars4 = ax2.bar(x + width/2, download_1g, width, label='Download', color='#A23B72', alpha=0.8)

    ax2.axhline(y=1000, color='red', linestyle='--', linewidth=1, label='理論値 1Gbps', alpha=0.5)
    ax2.set_xlabel('ファイルサイズ', fontsize=12)
    ax2.set_ylabel('スループット (Mbps)', fontsize=12)
    ax2.set_title('1Gbps ネットワーク - Upload vs Download', fontsize=14, fontweight='bold')
    ax2.set_xticks(x)
    ax2.set_xticklabels(file_labels)
    ax2.legend(fontsize=10)
    ax2.grid(axis='y', alpha=0.3)
    ax2.set_ylim(0, 1200)

    # Add value labels on bars
    for bars in [bars3, bars4]:
        for bar in bars:
            height = bar.get_height()
            ax2.text(bar.get_x() + bar.get_width()/2., height,
                    f'{height:.0f}',
                    ha='center', va='bottom', fontsize=9)

    plt.tight_layout()
    output_path = output_dir / 'throughput_comparison.png'
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"✓ Created: {output_path}")
    plt.close()

def create_ratio_graph(data_100mbps, data_1gbps, output_dir):
    """Create Download/Upload ratio comparison graph"""

    file_labels = ['10MB', '50MB', '100MB', '250MB', '500MB', '1GB']
    files = ['test10m.dat', 'test50m.dat', 'test100m.dat', 'test250m.dat', 'test500m.dat', 'test1g.dat']

    ratios_100 = [data_100mbps[f]['ratio'] for f in files]
    ratios_1g = [data_1gbps[f]['ratio'] for f in files]

    fig, ax = plt.subplots(figsize=(12, 7))

    x = np.arange(len(file_labels))
    width = 0.35

    bars1 = ax.bar(x - width/2, ratios_100, width, label='100Mbps', color='#F18F01', alpha=0.8)
    bars2 = ax.bar(x + width/2, ratios_1g, width, label='1Gbps', color='#C73E1D', alpha=0.8)

    ax.axhline(y=2.0, color='red', linestyle='--', linewidth=2, label='理論値（逐次処理: 2.0x）', alpha=0.7)
    ax.axhline(y=1.0, color='green', linestyle='--', linewidth=2, label='理想値（完全並行: 1.0x）', alpha=0.7)

    ax.set_xlabel('ファイルサイズ', fontsize=12)
    ax.set_ylabel('Download / Upload 時間比率', fontsize=12)
    ax.set_title('Download/Upload 時間比率 - パイプライン処理の効果', fontsize=14, fontweight='bold')
    ax.set_xticks(x)
    ax.set_xticklabels(file_labels)
    ax.legend(fontsize=11)
    ax.grid(axis='y', alpha=0.3)
    ax.set_ylim(0.8, 3.0)

    # Add value labels
    for bars in [bars1, bars2]:
        for bar in bars:
            height = bar.get_height()
            ax.text(bar.get_x() + bar.get_width()/2., height,
                    f'{height:.2f}x',
                    ha='center', va='bottom', fontsize=9)

    # Add annotation
    ax.text(0.5, 0.95,
            '※ 2.0xに近いほど逐次処理、1.0xに近いほど並行処理\n実測値が1.05x〜1.19xなのはIPFSのパイプライン処理の証拠',
            transform=ax.transAxes,
            fontsize=10,
            verticalalignment='top',
            bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.3))

    plt.tight_layout()
    output_path = output_dir / 'ratio_comparison.png'
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"✓ Created: {output_path}")
    plt.close()

def create_efficiency_graph(data_100mbps, data_1gbps, output_dir):
    """Create efficiency comparison graph (actual vs theoretical)"""

    file_labels = ['10MB', '50MB', '100MB', '250MB', '500MB', '1GB']
    files = ['test10m.dat', 'test50m.dat', 'test100m.dat', 'test250m.dat', 'test500m.dat', 'test1g.dat']

    # Calculate efficiency (% of theoretical max)
    efficiency_100_upload = [(data_100mbps[f]['avg_upload_mbps'] / 100) * 100 for f in files]
    efficiency_100_download = [(data_100mbps[f]['avg_download_mbps'] / 100) * 100 for f in files]
    efficiency_1g_upload = [(data_1gbps[f]['avg_upload_mbps'] / 1000) * 100 for f in files]
    efficiency_1g_download = [(data_1gbps[f]['avg_download_mbps'] / 1000) * 100 for f in files]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))

    x = np.arange(len(file_labels))
    width = 0.35

    # 100Mbps efficiency
    bars1 = ax1.bar(x - width/2, efficiency_100_upload, width, label='Upload', color='#2E86AB', alpha=0.8)
    bars2 = ax1.bar(x + width/2, efficiency_100_download, width, label='Download', color='#A23B72', alpha=0.8)

    ax1.axhline(y=100, color='red', linestyle='--', linewidth=1, label='理論値 100%', alpha=0.5)
    ax1.set_xlabel('ファイルサイズ', fontsize=12)
    ax1.set_ylabel('効率 (%)', fontsize=12)
    ax1.set_title('100Mbps ネットワーク効率', fontsize=14, fontweight='bold')
    ax1.set_xticks(x)
    ax1.set_xticklabels(file_labels)
    ax1.legend(fontsize=10)
    ax1.grid(axis='y', alpha=0.3)
    ax1.set_ylim(0, 120)

    for bars in [bars1, bars2]:
        for bar in bars:
            height = bar.get_height()
            ax1.text(bar.get_x() + bar.get_width()/2., height,
                    f'{height:.0f}%',
                    ha='center', va='bottom', fontsize=9)

    # 1Gbps efficiency
    bars3 = ax2.bar(x - width/2, efficiency_1g_upload, width, label='Upload', color='#2E86AB', alpha=0.8)
    bars4 = ax2.bar(x + width/2, efficiency_1g_download, width, label='Download', color='#A23B72', alpha=0.8)

    ax2.axhline(y=100, color='red', linestyle='--', linewidth=1, label='理論値 100%', alpha=0.5)
    ax2.set_xlabel('ファイルサイズ', fontsize=12)
    ax2.set_ylabel('効率 (%)', fontsize=12)
    ax2.set_title('1Gbps ネットワーク効率', fontsize=14, fontweight='bold')
    ax2.set_xticks(x)
    ax2.set_xticklabels(file_labels)
    ax2.legend(fontsize=10)
    ax2.grid(axis='y', alpha=0.3)
    ax2.set_ylim(0, 120)

    for bars in [bars3, bars4]:
        for bar in bars:
            height = bar.get_height()
            ax2.text(bar.get_x() + bar.get_width()/2., height,
                    f'{height:.0f}%',
                    ha='center', va='bottom', fontsize=9)

    plt.tight_layout()
    output_path = output_dir / 'efficiency_comparison.png'
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"✓ Created: {output_path}")
    plt.close()

def create_time_comparison_graph(data_100mbps, data_1gbps, output_dir):
    """Create transfer time comparison graph"""

    file_labels = ['10MB', '50MB', '100MB', '250MB', '500MB', '1GB']
    files = ['test10m.dat', 'test50m.dat', 'test100m.dat', 'test250m.dat', 'test500m.dat', 'test1g.dat']

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))

    x = np.arange(len(file_labels))
    width = 0.35

    # 100Mbps time
    upload_time_100 = [data_100mbps[f]['avg_upload_time'] for f in files]
    download_time_100 = [data_100mbps[f]['avg_download_time'] for f in files]

    bars1 = ax1.bar(x - width/2, upload_time_100, width, label='Upload', color='#2E86AB', alpha=0.8)
    bars2 = ax1.bar(x + width/2, download_time_100, width, label='Download', color='#A23B72', alpha=0.8)

    ax1.set_xlabel('ファイルサイズ', fontsize=12)
    ax1.set_ylabel('転送時間 (秒)', fontsize=12)
    ax1.set_title('100Mbps ネットワーク - 転送時間', fontsize=14, fontweight='bold')
    ax1.set_xticks(x)
    ax1.set_xticklabels(file_labels)
    ax1.legend(fontsize=10)
    ax1.grid(axis='y', alpha=0.3)

    for bars in [bars1, bars2]:
        for bar in bars:
            height = bar.get_height()
            ax1.text(bar.get_x() + bar.get_width()/2., height,
                    f'{height:.1f}s',
                    ha='center', va='bottom', fontsize=8)

    # 1Gbps time
    upload_time_1g = [data_1gbps[f]['avg_upload_time'] for f in files]
    download_time_1g = [data_1gbps[f]['avg_download_time'] for f in files]

    bars3 = ax2.bar(x - width/2, upload_time_1g, width, label='Upload', color='#2E86AB', alpha=0.8)
    bars4 = ax2.bar(x + width/2, download_time_1g, width, label='Download', color='#A23B72', alpha=0.8)

    ax2.set_xlabel('ファイルサイズ', fontsize=12)
    ax2.set_ylabel('転送時間 (秒)', fontsize=12)
    ax2.set_title('1Gbps ネットワーク - 転送時間', fontsize=14, fontweight='bold')
    ax2.set_xticks(x)
    ax2.set_xticklabels(file_labels)
    ax2.legend(fontsize=10)
    ax2.grid(axis='y', alpha=0.3)

    for bars in [bars3, bars4]:
        for bar in bars:
            height = bar.get_height()
            ax2.text(bar.get_x() + bar.get_width()/2., height,
                    f'{height:.2f}s',
                    ha='center', va='bottom', fontsize=8)

    plt.tight_layout()
    output_path = output_dir / 'time_comparison.png'
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"✓ Created: {output_path}")
    plt.close()

def main():
    # Setup paths
    base_dir = Path(__file__).parent.parent
    results_dir = base_dir / 'test-results'
    output_dir = base_dir / 'docs' / 'graphs'
    output_dir.mkdir(parents=True, exist_ok=True)

    print("=== IPFS Bandwidth Test Results Visualization ===\n")

    # Load test results
    print("Loading test results...")
    data_100mbps_file = results_dir / 'test_results_100mbps.json'
    data_1gbps_file = results_dir / 'test_results_1GBps.json'

    if not data_100mbps_file.exists():
        print(f"Error: {data_100mbps_file} not found")
        return 1
    if not data_1gbps_file.exists():
        print(f"Error: {data_1gbps_file} not found")
        return 1

    results_100mbps = load_json(data_100mbps_file)
    results_1gbps = load_json(data_1gbps_file)

    print(f"  ✓ Loaded: {data_100mbps_file.name}")
    print(f"  ✓ Loaded: {data_1gbps_file.name}\n")

    # Aggregate data
    print("Aggregating results...")
    data_100mbps = aggregate_results(results_100mbps['results'])
    data_1gbps = aggregate_results(results_1gbps['results'])
    print("  ✓ Data aggregated\n")

    # Generate graphs
    print("Generating graphs...")
    create_throughput_comparison_graph(data_100mbps, data_1gbps, output_dir)
    create_ratio_graph(data_100mbps, data_1gbps, output_dir)
    create_efficiency_graph(data_100mbps, data_1gbps, output_dir)
    create_time_comparison_graph(data_100mbps, data_1gbps, output_dir)

    print(f"\n=== All graphs saved to: {output_dir} ===")
    print("\nGenerated files:")
    print("  1. throughput_comparison.png  - Upload/Download速度比較")
    print("  2. ratio_comparison.png       - Download/Upload時間比率")
    print("  3. efficiency_comparison.png  - 理論値に対する効率")
    print("  4. time_comparison.png        - 転送時間比較")

    return 0

if __name__ == '__main__':
    exit(main())
