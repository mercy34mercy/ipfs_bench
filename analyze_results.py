#!/usr/bin/env python3
"""
Analyze and display detailed test results from JSON output
"""

import json
import sys
import statistics
from pathlib import Path
from datetime import datetime

def format_size(bytes):
    """Format bytes to human readable size"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes < 1024.0:
            return f"{bytes:.2f} {unit}"
        bytes /= 1024.0
    return f"{bytes:.2f} PB"

def format_throughput(bytes_per_sec):
    """Format throughput to Mbps"""
    mbps = (bytes_per_sec * 8) / 1_000_000
    return f"{mbps:.2f} Mbps"

def analyze_results(json_file):
    """Analyze test results from JSON file"""

    with open(json_file, 'r') as f:
        data = json.load(f)

    config = data['config']
    results = data['results']
    timestamp = data.get('timestamp', 'Unknown')

    print("=" * 80)
    print(f"IPFS Bandwidth Test - Detailed Analysis")
    print(f"Test: {config['testConfiguration']['name']}")
    print(f"Timestamp: {timestamp}")
    print(f"Total iterations per file: {config['testConfiguration']['iterations']}")
    print("=" * 80)

    # Group results by scenario and file
    scenarios = {}
    for result in results:
        scenario_key = (result['scenario'], result['scenario_name'], result['bandwidth'])
        file_key = (result['file'], result['fileSize'])

        if scenario_key not in scenarios:
            scenarios[scenario_key] = {}
        if file_key not in scenarios[scenario_key]:
            scenarios[scenario_key][file_key] = []

        scenarios[scenario_key][file_key].append(result)

    # Analyze each scenario
    for (scenario_id, scenario_name, bandwidth), files in scenarios.items():
        print(f"\n{'='*60}")
        print(f"Scenario: {scenario_name}")
        print(f"Bandwidth Limit: {bandwidth or 'Unlimited'}")
        print(f"{'='*60}")

        for (filename, filesize), iterations in files.items():
            print(f"\n  File: {filename} ({format_size(filesize)})")
            print(f"  {'─'*40}")

            # Individual iteration details
            print(f"  Individual Iterations:")
            for i, result in enumerate(iterations, 1):
                status = "✅" if result['success'] else "❌"
                print(f"    Iteration {i}: {status}")
                if result['success']:
                    print(f"      IPFS Hash: {result['ipfs_hash']}")
                    print(f"      Random Data Gen: {result['random_data_gen_time']*1000:.2f} ms")
                    print(f"      Upload Time: {result['upload_time']*1000:.2f} ms ({format_throughput(result['upload_throughput'])})")
                    print(f"      Download Time: {result['download_time']*1000:.2f} ms ({format_throughput(result['download_throughput'])})")
                    print(f"      Total Time: {result['total_time']*1000:.2f} ms")
                else:
                    print(f"      Error: {result.get('error', 'Unknown error')}")

            # Statistical summary
            successful = [r for r in iterations if r['success']]
            if successful:
                upload_times = [r['upload_time'] for r in successful]
                download_times = [r['download_time'] for r in successful]
                upload_throughputs = [r['upload_throughput'] for r in successful]
                download_throughputs = [r['download_throughput'] for r in successful]
                total_times = [r['total_time'] for r in successful]
                gen_times = [r['random_data_gen_time'] for r in successful]

                print(f"\n  Statistical Summary ({len(successful)}/{len(iterations)} successful):")
                print(f"  {'─'*40}")

                # Upload statistics
                print(f"    Upload Time (ms):")
                print(f"      Mean: {statistics.mean(upload_times)*1000:.2f}")
                print(f"      Median: {statistics.median(upload_times)*1000:.2f}")
                print(f"      Min: {min(upload_times)*1000:.2f}")
                print(f"      Max: {max(upload_times)*1000:.2f}")
                if len(upload_times) > 1:
                    print(f"      StdDev: {statistics.stdev(upload_times)*1000:.2f}")

                # Download statistics
                print(f"    Download Time (ms):")
                print(f"      Mean: {statistics.mean(download_times)*1000:.2f}")
                print(f"      Median: {statistics.median(download_times)*1000:.2f}")
                print(f"      Min: {min(download_times)*1000:.2f}")
                print(f"      Max: {max(download_times)*1000:.2f}")
                if len(download_times) > 1:
                    print(f"      StdDev: {statistics.stdev(download_times)*1000:.2f}")

                # Throughput statistics
                print(f"    Upload Throughput:")
                print(f"      Mean: {format_throughput(statistics.mean(upload_throughputs))}")
                print(f"      Median: {format_throughput(statistics.median(upload_throughputs))}")
                print(f"      Min: {format_throughput(min(upload_throughputs))}")
                print(f"      Max: {format_throughput(max(upload_throughputs))}")

                print(f"    Download Throughput:")
                print(f"      Mean: {format_throughput(statistics.mean(download_throughputs))}")
                print(f"      Median: {format_throughput(statistics.median(download_throughputs))}")
                print(f"      Min: {format_throughput(min(download_throughputs))}")
                print(f"      Max: {format_throughput(max(download_throughputs))}")

                # Total time and generation time
                print(f"    Total Transfer Time (ms):")
                print(f"      Mean: {statistics.mean(total_times)*1000:.2f}")
                print(f"      Median: {statistics.median(total_times)*1000:.2f}")

                print(f"    Random Data Generation Time (ms):")
                print(f"      Mean: {statistics.mean(gen_times)*1000:.2f}")
                print(f"      Median: {statistics.median(gen_times)*1000:.2f}")

    # Overall summary
    print(f"\n{'='*80}")
    print("Overall Summary")
    print(f"{'='*80}")

    total_tests = len(results)
    successful_tests = len([r for r in results if r['success']])
    failed_tests = total_tests - successful_tests

    print(f"Total Tests: {total_tests}")
    print(f"Successful: {successful_tests} ({successful_tests/total_tests*100:.1f}%)")
    print(f"Failed: {failed_tests} ({failed_tests/total_tests*100:.1f}%)")

    if successful_tests > 0:
        all_upload_times = [r['upload_time'] for r in results if r['success']]
        all_download_times = [r['download_time'] for r in results if r['success']]
        all_total_times = [r['total_time'] for r in results if r['success']]

        print(f"\nAggregated Performance:")
        print(f"  Average Upload Time: {statistics.mean(all_upload_times)*1000:.2f} ms")
        print(f"  Average Download Time: {statistics.mean(all_download_times)*1000:.2f} ms")
        print(f"  Average Total Time: {statistics.mean(all_total_times)*1000:.2f} ms")

    # Comparison between scenarios
    if len(scenarios) > 1:
        print(f"\n{'='*80}")
        print("Scenario Comparison")
        print(f"{'='*80}")

        for (filename, filesize) in set(file_key for _, files in scenarios.items() for file_key in files.keys()):
            print(f"\n{filename} ({format_size(filesize)}):")
            print(f"{'─'*40}")
            print(f"{'Scenario':<30} {'Upload':<15} {'Download':<15} {'Total':<15}")
            print(f"{'─'*75}")

            for (scenario_id, scenario_name, bandwidth), files in scenarios.items():
                if (filename, filesize) in files:
                    iterations = files[(filename, filesize)]
                    successful = [r for r in iterations if r['success']]
                    if successful:
                        avg_upload = statistics.mean([r['upload_time'] for r in successful]) * 1000
                        avg_download = statistics.mean([r['download_time'] for r in successful]) * 1000
                        avg_total = statistics.mean([r['total_time'] for r in successful]) * 1000

                        scenario_label = f"{scenario_name[:20]:20} ({bandwidth or 'No limit'})"
                        print(f"{scenario_label:<30} {avg_upload:>10.2f} ms   {avg_download:>10.2f} ms   {avg_total:>10.2f} ms")

def main():
    if len(sys.argv) < 2:
        # Find the latest result file
        results_dir = Path("test-results")
        if results_dir.exists():
            json_files = sorted(results_dir.glob("test_results_*.json"))
            if json_files:
                json_file = json_files[-1]
                print(f"Using latest result file: {json_file}")
            else:
                print("No result files found in test-results directory")
                sys.exit(1)
        else:
            print("test-results directory not found")
            sys.exit(1)
    else:
        json_file = Path(sys.argv[1])
        if not json_file.exists():
            print(f"File not found: {json_file}")
            sys.exit(1)

    analyze_results(json_file)

if __name__ == "__main__":
    main()