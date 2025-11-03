#!/usr/bin/env python3
"""
Visualize test results with tables and graphs
"""

import json
import sys
import statistics
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np
from pathlib import Path
from datetime import datetime
import seaborn as sns

# Set style
plt.style.use('seaborn-v0_8-darkgrid')
sns.set_palette("husl")

def load_results(json_file):
    """Load results from JSON file"""
    with open(json_file, 'r') as f:
        return json.load(f)

def create_summary_table(data):
    """Create a summary table of results"""
    results = data['results']

    # Group results by scenario and file
    summary_data = []

    scenarios = {}
    for result in results:
        key = (result['scenario'], result['scenario_name'], result.get('bandwidth', 'unlimited'))
        if key not in scenarios:
            scenarios[key] = {}

        file_key = result['file']
        if file_key not in scenarios[key]:
            scenarios[key][file_key] = {
                'upload_times': [],
                'download_times': [],
                'upload_throughputs': [],
                'download_throughputs': [],
                'success_count': 0,
                'total_count': 0
            }

        scenarios[key][file_key]['total_count'] += 1
        if result['success']:
            scenarios[key][file_key]['upload_times'].append(result['upload_time'])
            scenarios[key][file_key]['download_times'].append(result['download_time'])
            scenarios[key][file_key]['upload_throughputs'].append(result['upload_throughput'])
            scenarios[key][file_key]['download_throughputs'].append(result['download_throughput'])
            scenarios[key][file_key]['success_count'] += 1

    # Create summary rows
    for (scenario_id, scenario_name, bandwidth), files in scenarios.items():
        for filename, stats in files.items():
            if stats['success_count'] > 0:
                row = {
                    'Scenario': scenario_name,
                    'Bandwidth': bandwidth if bandwidth != 'unlimited' else 'No Limit',
                    'File': filename,
                    'Success Rate': f"{stats['success_count']}/{stats['total_count']}",
                    'Avg Upload (ms)': f"{statistics.mean(stats['upload_times'])*1000:.2f}",
                    'Avg Download (ms)': f"{statistics.mean(stats['download_times'])*1000:.2f}",
                    'Upload Speed (Mbps)': f"{statistics.mean(stats['upload_throughputs'])*8/1_000_000:.1f}",
                    'Download Speed (Mbps)': f"{statistics.mean(stats['download_throughputs'])*8/1_000_000:.1f}",
                }
                summary_data.append(row)

    df = pd.DataFrame(summary_data)
    return df

def create_performance_graphs(data, output_dir):
    """Create performance visualization graphs"""
    results = data['results']

    # Prepare data for visualization
    plot_data = []
    for result in results:
        if result['success']:
            plot_data.append({
                'Scenario': result['scenario_name'],
                'Bandwidth': result.get('bandwidth', 'unlimited'),
                'File': result['file'],
                'File Size (MB)': result['fileSize'] / (1024*1024),
                'Upload Time (ms)': result['upload_time'] * 1000,
                'Download Time (ms)': result['download_time'] * 1000,
                'Upload Speed (Mbps)': result['upload_throughput'] * 8 / 1_000_000,
                'Download Speed (Mbps)': result['download_throughput'] * 8 / 1_000_000,
                'Total Time (ms)': result['total_time'] * 1000
            })

    df = pd.DataFrame(plot_data)

    # Create figure with subplots
    fig = plt.figure(figsize=(20, 12))

    # 1. Upload Speed by Scenario and File
    ax1 = plt.subplot(2, 3, 1)
    pivot_upload = df.pivot_table(values='Upload Speed (Mbps)',
                                   index='File',
                                   columns='Scenario',
                                   aggfunc='mean')
    pivot_upload.plot(kind='bar', ax=ax1)
    ax1.set_title('Average Upload Speed by File and Scenario', fontsize=12, fontweight='bold')
    ax1.set_ylabel('Speed (Mbps)')
    ax1.set_xlabel('File')
    ax1.legend(title='Scenario', bbox_to_anchor=(1.05, 1), loc='upper left')
    ax1.grid(True, alpha=0.3)

    # 2. Download Speed by Scenario and File
    ax2 = plt.subplot(2, 3, 2)
    pivot_download = df.pivot_table(values='Download Speed (Mbps)',
                                     index='File',
                                     columns='Scenario',
                                     aggfunc='mean')
    pivot_download.plot(kind='bar', ax=ax2)
    ax2.set_title('Average Download Speed by File and Scenario', fontsize=12, fontweight='bold')
    ax2.set_ylabel('Speed (Mbps)')
    ax2.set_xlabel('File')
    ax2.legend(title='Scenario', bbox_to_anchor=(1.05, 1), loc='upper left')
    ax2.grid(True, alpha=0.3)

    # 3. Total Time Comparison
    ax3 = plt.subplot(2, 3, 3)
    pivot_time = df.pivot_table(values='Total Time (ms)',
                                 index='File',
                                 columns='Scenario',
                                 aggfunc='mean')
    pivot_time.plot(kind='bar', ax=ax3)
    ax3.set_title('Average Total Transfer Time', fontsize=12, fontweight='bold')
    ax3.set_ylabel('Time (ms)')
    ax3.set_xlabel('File')
    ax3.legend(title='Scenario', bbox_to_anchor=(1.05, 1), loc='upper left')
    ax3.grid(True, alpha=0.3)

    # 4. Speed vs File Size (Upload)
    ax4 = plt.subplot(2, 3, 4)
    for scenario in df['Scenario'].unique():
        scenario_data = df[df['Scenario'] == scenario]
        avg_by_size = scenario_data.groupby('File Size (MB)')['Upload Speed (Mbps)'].mean()
        ax4.plot(avg_by_size.index, avg_by_size.values, marker='o', label=scenario, linewidth=2)
    ax4.set_title('Upload Speed vs File Size', fontsize=12, fontweight='bold')
    ax4.set_xlabel('File Size (MB)')
    ax4.set_ylabel('Upload Speed (Mbps)')
    ax4.legend()
    ax4.grid(True, alpha=0.3)
    ax4.set_xscale('log')

    # 5. Speed vs File Size (Download)
    ax5 = plt.subplot(2, 3, 5)
    for scenario in df['Scenario'].unique():
        scenario_data = df[df['Scenario'] == scenario]
        avg_by_size = scenario_data.groupby('File Size (MB)')['Download Speed (Mbps)'].mean()
        ax5.plot(avg_by_size.index, avg_by_size.values, marker='s', label=scenario, linewidth=2)
    ax5.set_title('Download Speed vs File Size', fontsize=12, fontweight='bold')
    ax5.set_xlabel('File Size (MB)')
    ax5.set_ylabel('Download Speed (Mbps)')
    ax5.legend()
    ax5.grid(True, alpha=0.3)
    ax5.set_xscale('log')

    # 6. Distribution of Transfer Times
    ax6 = plt.subplot(2, 3, 6)
    scenarios_list = df['Scenario'].unique()
    colors = sns.color_palette("husl", len(scenarios_list))

    for i, scenario in enumerate(scenarios_list):
        scenario_data = df[df['Scenario'] == scenario]['Total Time (ms)']
        ax6.hist(scenario_data, alpha=0.5, label=scenario, bins=20, color=colors[i], edgecolor='black')

    ax6.set_title('Distribution of Total Transfer Times', fontsize=12, fontweight='bold')
    ax6.set_xlabel('Total Time (ms)')
    ax6.set_ylabel('Frequency')
    ax6.legend()
    ax6.grid(True, alpha=0.3)

    plt.suptitle('IPFS Bandwidth Test Performance Analysis', fontsize=16, fontweight='bold', y=1.02)
    plt.tight_layout()

    # Save the figure
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = f"{output_dir}/performance_analysis_{timestamp}.png"
    plt.savefig(output_file, dpi=150, bbox_inches='tight')
    print(f"Graphs saved to: {output_file}")

    return fig, df

def create_detailed_table(data):
    """Create a detailed table with statistics"""
    results = data['results']

    # Group and calculate statistics
    grouped_stats = {}
    for result in results:
        key = (result['scenario_name'], result.get('bandwidth', 'No Limit'), result['file'])
        if key not in grouped_stats:
            grouped_stats[key] = {
                'upload_times': [],
                'download_times': [],
                'upload_speeds': [],
                'download_speeds': [],
                'total_times': [],
                'success_count': 0,
                'total_count': 0
            }

        grouped_stats[key]['total_count'] += 1
        if result['success']:
            grouped_stats[key]['success_count'] += 1
            grouped_stats[key]['upload_times'].append(result['upload_time'] * 1000)
            grouped_stats[key]['download_times'].append(result['download_time'] * 1000)
            grouped_stats[key]['upload_speeds'].append(result['upload_throughput'] * 8 / 1_000_000)
            grouped_stats[key]['download_speeds'].append(result['download_throughput'] * 8 / 1_000_000)
            grouped_stats[key]['total_times'].append(result['total_time'] * 1000)

    # Create detailed statistics table
    detailed_data = []
    for (scenario, bandwidth, file), stats in grouped_stats.items():
        if stats['success_count'] > 0:
            row = {
                'Scenario': scenario,
                'Bandwidth': bandwidth,
                'File': file,
                'Tests': f"{stats['success_count']}/{stats['total_count']}",
                'Success %': f"{stats['success_count']/stats['total_count']*100:.1f}%",
                'Upload Mean (ms)': f"{statistics.mean(stats['upload_times']):.2f}",
                'Upload Median (ms)': f"{statistics.median(stats['upload_times']):.2f}",
                'Upload StdDev (ms)': f"{statistics.stdev(stats['upload_times']):.2f}" if len(stats['upload_times']) > 1 else "0.00",
                'Download Mean (ms)': f"{statistics.mean(stats['download_times']):.2f}",
                'Download Median (ms)': f"{statistics.median(stats['download_times']):.2f}",
                'Download StdDev (ms)': f"{statistics.stdev(stats['download_times']):.2f}" if len(stats['download_times']) > 1 else "0.00",
                'Upload Speed (Mbps)': f"{statistics.mean(stats['upload_speeds']):.1f}",
                'Download Speed (Mbps)': f"{statistics.mean(stats['download_speeds']):.1f}",
                'Total Time Mean (ms)': f"{statistics.mean(stats['total_times']):.2f}"
            }
            detailed_data.append(row)

    df = pd.DataFrame(detailed_data)
    return df

def main():
    if len(sys.argv) < 2:
        json_file = Path("/Users/masashi.kobayashi/Programing/lab/encrypt_ipfs/ipfs_bench/test-results/test_results_20251026_210603.json")
    else:
        json_file = Path(sys.argv[1])

    if not json_file.exists():
        print(f"File not found: {json_file}")
        sys.exit(1)

    print(f"Analyzing: {json_file}")
    print("="*80)

    # Load data
    data = load_results(json_file)

    # Create output directory
    output_dir = Path("test-results/visualizations")
    output_dir.mkdir(exist_ok=True, parents=True)

    # Create summary table
    print("\n📊 SUMMARY TABLE")
    print("="*80)
    summary_df = create_summary_table(data)
    print(summary_df.to_string(index=False))

    # Save summary to CSV
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    summary_csv = f"{output_dir}/summary_{timestamp}.csv"
    summary_df.to_csv(summary_csv, index=False)
    print(f"\nSummary saved to: {summary_csv}")

    # Create detailed statistics table
    print("\n📈 DETAILED STATISTICS TABLE")
    print("="*80)
    detailed_df = create_detailed_table(data)
    print(detailed_df.to_string(index=False))

    # Save detailed to CSV
    detailed_csv = f"{output_dir}/detailed_stats_{timestamp}.csv"
    detailed_df.to_csv(detailed_csv, index=False)
    print(f"\nDetailed stats saved to: {detailed_csv}")

    # Create graphs
    print("\n📉 GENERATING PERFORMANCE GRAPHS...")
    print("="*80)
    fig, plot_df = create_performance_graphs(data, output_dir)
    plt.show()

    # Create comparison matrix
    print("\n🔄 PERFORMANCE COMPARISON MATRIX (Average Transfer Time in ms)")
    print("="*80)

    # Pivot table for easy comparison
    results_df = pd.DataFrame(data['results'])
    successful = results_df[results_df['success'] == True].copy()
    successful['total_ms'] = successful['total_time'] * 1000

    comparison = successful.pivot_table(
        values='total_ms',
        index='file',
        columns='scenario_name',
        aggfunc='mean'
    )

    print(comparison.round(2).to_string())

    # Save comparison to CSV
    comparison_csv = f"{output_dir}/comparison_matrix_{timestamp}.csv"
    comparison.to_csv(comparison_csv)
    print(f"\nComparison matrix saved to: {comparison_csv}")

    print("\n✅ Analysis complete!")
    print(f"All outputs saved in: {output_dir}")

if __name__ == "__main__":
    main()