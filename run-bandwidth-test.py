#!/usr/bin/env python3
"""
IPFS Bandwidth Performance Test Runner
Executes test scenarios defined in test-scenarios.json
"""

import json
import sys
import time
import subprocess
import statistics
from datetime import datetime
from typing import Dict, List, Any
import requests
from pathlib import Path

class IPFSBandwidthTester:
    def __init__(self, config_file: str = "test-scenarios.json"):
        """Initialize the tester with configuration"""
        with open(config_file, 'r') as f:
            self.config = json.load(f)

        self.test_config = self.config['testConfiguration']
        self.test_files = self.config['testFiles']
        self.scenarios = self.config['networkScenarios']
        self.targets = self.config['testTargets']
        self.results = []

        # Create output directory if it doesn't exist
        Path(self.test_config['outputDirectory']).mkdir(parents=True, exist_ok=True)

        # Set up result file with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.result_file = f"{self.test_config['outputDirectory']}/test_results_{timestamp}.json"

    def apply_bandwidth_limit(self, scenario: Dict[str, Any], container: str) -> bool:
        """Apply bandwidth limitation to a container"""
        if scenario['bandwidth'] is None:
            print(f"  No bandwidth limit for {scenario['name']}")
            return True

        try:
            # Stop any existing chaos
            subprocess.run(
                ["./scripts/network-chaos/stop-chaos.sh", container],
                capture_output=True,
                text=True,
                check=False
            )

            # Apply new bandwidth limit
            cmd = [scenario['bandwidthCommand'], container, scenario['bandwidth']]
            subprocess.run(cmd, capture_output=True, text=True, check=True)
            print(f"  Applied {scenario['bandwidth']} limit to {container}")
            time.sleep(2)  # Wait for network changes to take effect
            return True
        except subprocess.CalledProcessError as e:
            print(f"  Failed to apply bandwidth limit: {e}")
            return False

    def remove_bandwidth_limit(self, container: str):
        """Remove bandwidth limitation from a container"""
        try:
            subprocess.run(
                ["./scripts/network-chaos/stop-chaos.sh", container],
                capture_output=True,
                text=True,
                check=False
            )
            print(f"  Removed bandwidth limit from {container}")
            time.sleep(2)
        except Exception as e:
            print(f"  Warning: Could not remove bandwidth limit: {e}")

    def upload_file(self, filepath: str, api_port: int) -> Dict[str, Any]:
        """Upload a file to IPFS and measure performance"""
        start_time = time.time()

        try:
            # Read file
            with open(filepath, 'rb') as f:
                files = {'file': f}

                # Upload to IPFS
                response = requests.post(
                    f'http://localhost:{api_port}/api/v0/add',
                    files=files,
                    timeout=self.test_config['timeout']
                )

            upload_time = time.time() - start_time

            if response.status_code == 200:
                result = response.json()
                return {
                    'success': True,
                    'hash': result['Hash'],
                    'size': result['Size'],
                    'upload_time': upload_time,
                    'throughput': int(result['Size']) / upload_time if upload_time > 0 else 0
                }
            else:
                return {
                    'success': False,
                    'error': f"HTTP {response.status_code}",
                    'upload_time': upload_time
                }

        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'upload_time': time.time() - start_time
            }

    def download_file(self, ipfs_hash: str, api_port: int, expected_size: int) -> Dict[str, Any]:
        """Download a file from IPFS and measure performance"""
        start_time = time.time()

        try:
            # Download from IPFS
            response = requests.post(
                f'http://localhost:{api_port}/api/v0/cat',
                params={'arg': ipfs_hash},
                timeout=self.test_config['timeout'],
                stream=True
            )

            if response.status_code == 200:
                # Read content to measure actual download time
                content = b''
                for chunk in response.iter_content(chunk_size=8192):
                    content += chunk

                download_time = time.time() - start_time

                return {
                    'success': True,
                    'size': len(content),
                    'size_match': len(content) == expected_size,
                    'download_time': download_time,
                    'throughput': len(content) / download_time if download_time > 0 else 0
                }
            else:
                return {
                    'success': False,
                    'error': f"HTTP {response.status_code}",
                    'download_time': time.time() - start_time
                }

        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'download_time': time.time() - start_time
            }

    def run_single_test(self, file_info: Dict, scenario: Dict, iteration: int) -> Dict:
        """Run a single test iteration"""
        filepath = f"{self.test_config['testDirectory']}/{file_info['filename']}"
        upload_target = next(t for t in self.targets if t['role'] == 'upload')
        download_target = next(t for t in self.targets if t['role'] == 'download')

        print(f"    Iteration {iteration + 1}/{self.test_config['iterations']}: {file_info['filename']}")

        # Upload file
        upload_result = self.upload_file(filepath, upload_target['apiPort'])

        if not upload_result['success']:
            return {
                'iteration': iteration + 1,
                'file': file_info['filename'],
                'fileSize': file_info['sizeBytes'],
                'scenario': scenario['id'],
                'success': False,
                'error': upload_result.get('error', 'Upload failed'),
                'upload_time': upload_result.get('upload_time', 0),
                'download_time': 0
            }

        # Wait a moment for propagation
        time.sleep(0.5)

        # Download file from different node
        download_result = self.download_file(
            upload_result['hash'],
            download_target['apiPort'],
            file_info['sizeBytes']
        )

        return {
            'iteration': iteration + 1,
            'file': file_info['filename'],
            'fileSize': file_info['sizeBytes'],
            'scenario': scenario['id'],
            'scenario_name': scenario['name'],
            'bandwidth': scenario['bandwidth'],
            'success': download_result['success'],
            'ipfs_hash': upload_result.get('hash', ''),
            'upload_time': upload_result['upload_time'],
            'download_time': download_result['download_time'],
            'upload_throughput': upload_result.get('throughput', 0),
            'download_throughput': download_result.get('throughput', 0),
            'total_time': upload_result['upload_time'] + download_result['download_time'],
            'size_match': download_result.get('size_match', False),
            'error': download_result.get('error', None)
        }

    def calculate_statistics(self, values: List[float]) -> Dict[str, float]:
        """Calculate statistics for a list of values"""
        if not values:
            return {}

        sorted_values = sorted(values)

        return {
            'mean': statistics.mean(values),
            'median': statistics.median(values),
            'min': min(values),
            'max': max(values),
            'stddev': statistics.stdev(values) if len(values) > 1 else 0,
            'p95': sorted_values[int(len(sorted_values) * 0.95)] if len(values) > 1 else values[0],
            'p99': sorted_values[int(len(sorted_values) * 0.99)] if len(values) > 1 else values[0],
            'count': len(values)
        }

    def run_scenario_tests(self, scenario: Dict) -> List[Dict]:
        """Run all tests for a specific scenario"""
        print(f"\n{'='*60}")
        print(f"Running scenario: {scenario['name']}")
        print(f"Description: {scenario['description']}")
        print(f"{'='*60}")

        scenario_results = []

        # Apply bandwidth limits to all target containers
        for target in self.targets:
            if not self.apply_bandwidth_limit(scenario, target['container']):
                print(f"Failed to apply bandwidth limit to {target['container']}")
                return scenario_results

        # Run tests for each file
        for file_info in self.test_files:
            print(f"\n  Testing file: {file_info['filename']} ({file_info['size']})")

            file_results = []
            for i in range(self.test_config['iterations']):
                result = self.run_single_test(file_info, scenario, i)
                file_results.append(result)

                # Progress indicator every 10 iterations
                if (i + 1) % 10 == 0:
                    successful = sum(1 for r in file_results if r['success'])
                    print(f"      Progress: {i + 1}/{self.test_config['iterations']} "
                          f"(Success rate: {successful}/{i + 1})")

            scenario_results.extend(file_results)

            # Calculate and display file statistics
            successful_results = [r for r in file_results if r['success']]
            if successful_results:
                upload_times = [r['upload_time'] for r in successful_results]
                download_times = [r['download_time'] for r in successful_results]

                print(f"    File Statistics:")
                print(f"      Success rate: {len(successful_results)}/{len(file_results)}")
                print(f"      Avg upload time: {statistics.mean(upload_times):.2f}s")
                print(f"      Avg download time: {statistics.mean(download_times):.2f}s")

        # Remove bandwidth limits
        for target in self.targets:
            self.remove_bandwidth_limit(target['container'])

        return scenario_results

    def generate_summary(self) -> Dict:
        """Generate test summary with statistics"""
        summary = {
            'test_info': {
                'name': self.test_config['name'],
                'description': self.test_config['description'],
                'timestamp': datetime.now().isoformat(),
                'total_iterations': self.test_config['iterations'],
                'files_tested': len(self.test_files),
                'scenarios_tested': len([s for s in self.scenarios if s['enabled']])
            },
            'scenario_summaries': []
        }

        for scenario in self.scenarios:
            if not scenario['enabled']:
                continue

            scenario_results = [r for r in self.results if r['scenario'] == scenario['id']]
            if not scenario_results:
                continue

            # Group by file
            file_summaries = []
            for file_info in self.test_files:
                file_results = [r for r in scenario_results if r['file'] == file_info['filename']]
                successful = [r for r in file_results if r['success']]

                if successful:
                    file_summary = {
                        'file': file_info['filename'],
                        'size': file_info['size'],
                        'sizeBytes': file_info['sizeBytes'],
                        'success_rate': len(successful) / len(file_results),
                        'upload_stats': self.calculate_statistics([r['upload_time'] for r in successful]),
                        'download_stats': self.calculate_statistics([r['download_time'] for r in successful]),
                        'upload_throughput_stats': self.calculate_statistics([r['upload_throughput'] for r in successful]),
                        'download_throughput_stats': self.calculate_statistics([r['download_throughput'] for r in successful])
                    }
                    file_summaries.append(file_summary)

            summary['scenario_summaries'].append({
                'scenario': scenario['name'],
                'bandwidth': scenario['bandwidth'],
                'file_summaries': file_summaries
            })

        return summary

    def run_all_tests(self):
        """Run all test scenarios"""
        print(f"\n{'='*60}")
        print(f"Starting {self.test_config['name']}")
        print(f"Test files: {len(self.test_files)}")
        print(f"Scenarios: {len([s for s in self.scenarios if s['enabled']])}")
        print(f"Iterations per file: {self.test_config['iterations']}")
        print(f"{'='*60}")

        start_time = time.time()

        # Run each enabled scenario
        for scenario in self.scenarios:
            if scenario['enabled']:
                scenario_results = self.run_scenario_tests(scenario)
                self.results.extend(scenario_results)

                # Save intermediate results
                self.save_results()

        total_time = time.time() - start_time

        # Generate and save summary
        summary = self.generate_summary()
        summary['test_info']['total_runtime'] = total_time

        # Save final results and summary
        self.save_results(include_summary=True)

        print(f"\n{'='*60}")
        print(f"Test completed in {total_time:.2f} seconds")
        print(f"Results saved to: {self.result_file}")
        print(f"{'='*60}")

        # Display summary
        self.display_summary(summary)

    def save_results(self, include_summary: bool = False):
        """Save test results to file"""
        output = {
            'config': self.config,
            'results': self.results,
            'timestamp': datetime.now().isoformat()
        }

        if include_summary:
            output['summary'] = self.generate_summary()

        with open(self.result_file, 'w') as f:
            json.dump(output, f, indent=2)

    def display_summary(self, summary: Dict):
        """Display test summary in console"""
        print("\nTest Summary:")
        print("="*60)

        for scenario_summary in summary['scenario_summaries']:
            print(f"\nScenario: {scenario_summary['scenario']}")
            print(f"Bandwidth: {scenario_summary['bandwidth'] or 'Unlimited'}")
            print("-"*40)

            for file_summary in scenario_summary['file_summaries']:
                print(f"  File: {file_summary['file']}")
                print(f"    Success rate: {file_summary['success_rate']*100:.1f}%")
                print(f"    Avg upload: {file_summary['upload_stats']['mean']:.2f}s "
                      f"(±{file_summary['upload_stats']['stddev']:.2f}s)")
                print(f"    Avg download: {file_summary['download_stats']['mean']:.2f}s "
                      f"(±{file_summary['download_stats']['stddev']:.2f}s)")

                # Calculate and display effective throughput in Mbps
                avg_upload_mbps = (file_summary['sizeBytes'] * 8 / file_summary['upload_stats']['mean']) / 1_000_000
                avg_download_mbps = (file_summary['sizeBytes'] * 8 / file_summary['download_stats']['mean']) / 1_000_000
                print(f"    Throughput: ↑{avg_upload_mbps:.1f} Mbps, ↓{avg_download_mbps:.1f} Mbps")

def main():
    """Main entry point"""
    # Check if Docker is running
    try:
        subprocess.run(['docker', 'ps'], capture_output=True, check=True)
    except subprocess.CalledProcessError:
        print("Error: Docker is not running or not accessible")
        sys.exit(1)

    # Check if IPFS containers are running
    try:
        result = subprocess.run(
            ['docker', 'ps', '--format', '{{.Names}}'],
            capture_output=True,
            text=True,
            check=True
        )
        containers = result.stdout.strip().split('\n')
        required = ['ipfs-org1', 'ipfs-org2']

        for container in required:
            if container not in containers:
                print(f"Error: Required container '{container}' is not running")
                print("Please start the IPFS network with: docker-compose up -d")
                sys.exit(1)
    except subprocess.CalledProcessError:
        print("Error: Could not check container status")
        sys.exit(1)

    # Run tests
    tester = IPFSBandwidthTester()
    tester.run_all_tests()

if __name__ == "__main__":
    main()