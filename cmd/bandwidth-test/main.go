package main

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"mime/multipart"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// TestConfiguration represents the test configuration
type TestConfiguration struct {
	Name            string `json:"name"`
	Description     string `json:"description"`
	TestDirectory   string `json:"testDirectory"`
	Iterations      int    `json:"iterations"`
	OutputDirectory string `json:"outputDirectory"`
	Timeout         int    `json:"timeout"`
}

// TestFile represents a test file
type TestFile struct {
	Filename  string `json:"filename"`
	Size      string `json:"size"`
	SizeBytes int64  `json:"sizeBytes"`
}

// NetworkScenario represents a network scenario
type NetworkScenario struct {
	ID               string  `json:"id"`
	Name             string  `json:"name"`
	Description      string  `json:"description"`
	Bandwidth        *string `json:"bandwidth"`
	BandwidthCommand string  `json:"bandwidthCommand"`
	Enabled          bool    `json:"enabled"`
}

// TestTarget represents a test target node
type TestTarget struct {
	Container   string `json:"container"`
	Role        string `json:"role"`
	APIPort     int    `json:"apiPort"`
	GatewayPort int    `json:"gatewayPort"`
}

// Config represents the entire test configuration
type Config struct {
	TestConfiguration TestConfiguration `json:"testConfiguration"`
	TestFiles         []TestFile        `json:"testFiles"`
	NetworkScenarios  []NetworkScenario `json:"networkScenarios"`
	TestTargets       []TestTarget      `json:"testTargets"`
}

// TestResult represents a single test result
type TestResult struct {
	Iteration          int     `json:"iteration"`
	File               string  `json:"file"`
	FileSize           int64   `json:"fileSize"`
	Scenario           string  `json:"scenario"`
	ScenarioName       string  `json:"scenario_name"`
	Bandwidth          *string `json:"bandwidth"`
	Success            bool    `json:"success"`
	IPFSHash           string  `json:"ipfs_hash"`
	UploadTime         float64 `json:"upload_time"`
	DownloadTime       float64 `json:"download_time"`
	UploadThroughput   float64 `json:"upload_throughput"`
	DownloadThroughput float64 `json:"download_throughput"`
	TotalTime          float64 `json:"total_time"`
	Error              string  `json:"error,omitempty"`
	RandomDataGenTime  float64 `json:"random_data_gen_time"`
}

// Statistics represents statistical calculations
type Statistics struct {
	Mean   float64 `json:"mean"`
	Median float64 `json:"median"`
	Min    float64 `json:"min"`
	Max    float64 `json:"max"`
	StdDev float64 `json:"stddev"`
	P95    float64 `json:"p95"`
	P99    float64 `json:"p99"`
	Count  int     `json:"count"`
}

// IPFSAddResponse represents the response from IPFS add API
type IPFSAddResponse struct {
	Hash string `json:"Hash"`
	Size string `json:"Size"`
}

// BandwidthTester handles the bandwidth testing
type BandwidthTester struct {
	config     Config
	results    []TestResult
	resultFile string
	mutex      sync.Mutex
}

// NewBandwidthTester creates a new bandwidth tester
func NewBandwidthTester(configFile string) (*BandwidthTester, error) {
	data, err := os.ReadFile(configFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %v", err)
	}

	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %v", err)
	}

	// Create output directory
	if err := os.MkdirAll(config.TestConfiguration.OutputDirectory, 0755); err != nil {
		return nil, fmt.Errorf("failed to create output directory: %v", err)
	}

	// Create result file name with timestamp
	timestamp := time.Now().Format("20060102_150405")
	resultFile := filepath.Join(
		config.TestConfiguration.OutputDirectory,
		fmt.Sprintf("test_results_%s.json", timestamp),
	)

	return &BandwidthTester{
		config:     config,
		results:    []TestResult{},
		resultFile: resultFile,
	}, nil
}

// generateRandomData generates random data of specified size
func (bt *BandwidthTester) generateRandomData(size int64) ([]byte, error) {
	data := make([]byte, size)
	bufSize := 1024 * 1024 // 1MB buffer for efficient random generation
	buf := make([]byte, bufSize)

	for i := int64(0); i < size; i += int64(bufSize) {
		remaining := size - i
		if remaining < int64(bufSize) {
			buf = buf[:remaining]
		}

		if _, err := rand.Read(buf); err != nil {
			return nil, fmt.Errorf("failed to generate random data: %v", err)
		}

		copy(data[i:], buf)
	}

	return data, nil
}

// applyBandwidthLimit applies bandwidth limit to a container
func (bt *BandwidthTester) applyBandwidthLimit(scenario NetworkScenario, container string) error {
	if scenario.Bandwidth == nil {
		fmt.Printf("  No bandwidth limit for %s\n", scenario.Name)
		return nil
	}

	// Check if we're using a bulk bandwidth script (applies to all containers at once)
	isBulkScript := strings.Contains(scenario.BandwidthCommand, "limit-bandwidth-all.sh") ||
		strings.Contains(scenario.BandwidthCommand, "limit-bandwidth-routers.sh")

	// Only apply once if this is the first container and we're using a bulk script
	if container == "ipfs-org1" && isBulkScript {
		// Apply to all containers/routers at once
		cmd := exec.Command(scenario.BandwidthCommand, *scenario.Bandwidth)
		output, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("failed to apply bandwidth limit: %v\nOutput: %s", err, output)
		}
		if strings.Contains(scenario.BandwidthCommand, "limit-bandwidth-routers.sh") {
			fmt.Printf("  Applied %s limit to all routers\n", *scenario.Bandwidth)
		} else {
			fmt.Printf("  Applied %s limit to all containers\n", *scenario.Bandwidth)
		}
		time.Sleep(3 * time.Second)
		return nil
	} else if isBulkScript {
		// Skip individual containers when using bulk scripts
		return nil
	}

	// Individual container limit (legacy support)
	stopCmd := exec.Command("/app/scripts/network-chaos/stop-chaos.sh", container)
	stopCmd.Run()

	cmd := exec.Command(scenario.BandwidthCommand, container, *scenario.Bandwidth)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to apply bandwidth limit: %v\nOutput: %s", err, output)
	}

	fmt.Printf("  Applied %s limit to %s\n", *scenario.Bandwidth, container)
	time.Sleep(2 * time.Second)
	return nil
}

// removeBandwidthLimit removes bandwidth limit from a container
func (bt *BandwidthTester) removeBandwidthLimit(container string) {
	// Remove Pumba chaos
	cmd := exec.Command("/app/scripts/network-chaos/stop-chaos.sh", container)
	cmd.Run()

	fmt.Printf("  Removed bandwidth limit from %s\n", container)
	time.Sleep(2 * time.Second)
}

// restartContainers restarts all IPFS nodes (excluding ipfs-bench) to clear network rules
func (bt *BandwidthTester) restartContainers() error {
	// First, remove all existing bandwidth limits
	fmt.Printf("    Removing existing bandwidth limits...\n")
	removeCmd := exec.Command("/app/scripts/network-chaos/remove-bandwidth-limit.sh")
	if output, err := removeCmd.CombinedOutput(); err != nil {
		fmt.Printf("    Warning: Failed to remove bandwidth limits: %v\n%s\n", err, output)
	}

	// Restart the containers using docker-compose (must be run from project root)
	fmt.Printf("    Restarting containers via docker-compose...\n")
	// Restart only the IPFS nodes; restarting ipfs-bench would kill this process
	restartCmd := exec.Command("docker", "restart",
		"ipfs-org1", "ipfs-org2", "ipfs-org3", "ipfs-org4", "ipfs-org5",
		"ipfs-org6", "ipfs-org7", "ipfs-org8", "ipfs-org9", "ipfs-org10")

	output, err := restartCmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to restart containers: %v\nOutput: %s", err, output)
	}

	return nil
}

// uploadFile uploads random data to IPFS and measures performance
func (bt *BandwidthTester) uploadFile(data []byte, hostname string, apiPort int) (string, float64, error) {
	// Create multipart form
	var b bytes.Buffer
	w := multipart.NewWriter(&b)

	fw, err := w.CreateFormFile("file", "random.dat")
	if err != nil {
		return "", 0, err
	}

	if _, err := fw.Write(data); err != nil {
		return "", 0, err
	}

	if err := w.Close(); err != nil {
		return "", 0, err
	}

	// Upload to IPFS without pinning to save space
	url := fmt.Sprintf("http://%s:%d/api/v0/add?pin=false", hostname, apiPort)

	startTime := time.Now()
	req, err := http.NewRequest("POST", url, &b)
	if err != nil {
		return "", 0, err
	}
	req.Header.Set("Content-Type", w.FormDataContentType())

	client := &http.Client{
		Timeout: time.Duration(bt.config.TestConfiguration.Timeout) * time.Second,
	}

	resp, err := client.Do(req)
	if err != nil {
		return "", time.Since(startTime).Seconds(), err
	}
	defer resp.Body.Close()

	uploadTime := time.Since(startTime).Seconds()

	if resp.StatusCode != http.StatusOK {
		return "", uploadTime, fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	var result IPFSAddResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", uploadTime, err
	}

	return result.Hash, uploadTime, nil
}

// downloadFile downloads a file from IPFS and measures performance
func (bt *BandwidthTester) downloadFile(hash string, hostname string, apiPort int, expectedSize int64) (float64, error) {
	url := fmt.Sprintf("http://%s:%d/api/v0/cat?arg=%s", hostname, apiPort, hash)

	startTime := time.Now()

	client := &http.Client{
		Timeout: time.Duration(bt.config.TestConfiguration.Timeout) * time.Second,
	}

	resp, err := client.Post(url, "", nil)
	if err != nil {
		return time.Since(startTime).Seconds(), err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return time.Since(startTime).Seconds(), fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	// Read all content to measure actual download time
	data, err := io.ReadAll(resp.Body)
	downloadTime := time.Since(startTime).Seconds()

	if err != nil {
		return downloadTime, err
	}

	if int64(len(data)) != expectedSize {
		return downloadTime, fmt.Errorf("size mismatch: expected %d, got %d", expectedSize, len(data))
	}

	return downloadTime, nil
}

// deleteFromIPFS removes a file from IPFS (no unpin needed since we upload with pin=false)
func (bt *BandwidthTester) deleteFromIPFS(hash string, hostname string, apiPort int) {
	// Since we upload with pin=false, we only need to run garbage collection
	// The content will be removed as it's not pinned
	client := &http.Client{Timeout: 10 * time.Second}

	// Run garbage collection to immediately free space
	gcURL := fmt.Sprintf("http://%s:%d/api/v0/repo/gc", hostname, apiPort)
	gcReq, err := http.NewRequest("POST", gcURL, nil)
	if err != nil {
		return
	}

	gcResp, err := client.Do(gcReq)
	if err != nil {
		return
	}
	defer gcResp.Body.Close()

	// Read the response to ensure GC completes
	io.Copy(io.Discard, gcResp.Body)
}

// runFullGarbageCollection runs garbage collection on all nodes
func (bt *BandwidthTester) runFullGarbageCollection() {
	for _, target := range bt.config.TestTargets {
		client := &http.Client{Timeout: 30 * time.Second}
		gcURL := fmt.Sprintf("http://%s:%d/api/v0/repo/gc", target.Container, target.APIPort)

		gcReq, err := http.NewRequest("POST", gcURL, nil)
		if err != nil {
			continue
		}

		gcResp, err := client.Do(gcReq)
		if err != nil {
			continue
		}

		// Read the response to ensure GC completes
		io.Copy(io.Discard, gcResp.Body)
		gcResp.Body.Close()
	}
}

// runSingleTest runs a single test iteration
func (bt *BandwidthTester) runSingleTest(file TestFile, scenario NetworkScenario, iteration int) TestResult {
	fmt.Printf("    Iteration %d/%d: %s\n", iteration+1, bt.config.TestConfiguration.Iterations, file.Filename)

	result := TestResult{
		Iteration:    iteration + 1,
		File:         file.Filename,
		FileSize:     file.SizeBytes,
		Scenario:     scenario.ID,
		ScenarioName: scenario.Name,
		Bandwidth:    scenario.Bandwidth,
		Success:      false,
	}

	// Find upload and download targets
	var uploadTarget, downloadTarget *TestTarget
	for _, target := range bt.config.TestTargets {
		if target.Role == "upload" {
			uploadTarget = &target
		} else if target.Role == "download" {
			downloadTarget = &target
		}
	}

	if uploadTarget == nil || downloadTarget == nil {
		result.Error = "Could not find upload/download targets"
		return result
	}

	// Generate random data to prevent caching
	fmt.Printf("      Generating random data (%s)...\n", file.Size)
	startGen := time.Now()
	randomData, err := bt.generateRandomData(file.SizeBytes)
	if err != nil {
		result.Error = fmt.Sprintf("Failed to generate random data: %v", err)
		return result
	}
	result.RandomDataGenTime = time.Since(startGen).Seconds()
	fmt.Printf("      Generated in %.2fs\n", result.RandomDataGenTime)

	// Upload file
	fmt.Printf("      Uploading to %s...\n", uploadTarget.Container)
	hash, uploadTime, err := bt.uploadFile(randomData, uploadTarget.Container, uploadTarget.APIPort)
	result.UploadTime = uploadTime
	if err != nil {
		fmt.Printf("      Upload failed: %v\n", err)
		result.Error = fmt.Sprintf("Upload failed: %v", err)
		return result
	}
	result.IPFSHash = hash

	// Calculate upload throughput (bytes/second)
	if uploadTime > 0 {
		result.UploadThroughput = float64(file.SizeBytes) / uploadTime
		uploadMbps := (result.UploadThroughput * 8) / 1_000_000
		fmt.Printf("      Uploaded in %.2fs (%.2f Mbps)\n", uploadTime, uploadMbps)
	}

	// Wait for propagation
	fmt.Printf("      Waiting for propagation...\n")
	time.Sleep(500 * time.Millisecond)

	// Download file from different node
	fmt.Printf("      Downloading from %s...\n", downloadTarget.Container)
	downloadTime, err := bt.downloadFile(hash, downloadTarget.Container, downloadTarget.APIPort, file.SizeBytes)
	result.DownloadTime = downloadTime
	if err != nil {
		fmt.Printf("      Download failed: %v\n", err)
		result.Error = fmt.Sprintf("Download failed: %v", err)
		// Even if download failed, try to clean up
		bt.deleteFromIPFS(hash, uploadTarget.Container, uploadTarget.APIPort)
		bt.deleteFromIPFS(hash, downloadTarget.Container, downloadTarget.APIPort)
		return result
	}

	// Calculate download throughput (bytes/second)
	if downloadTime > 0 {
		result.DownloadThroughput = float64(file.SizeBytes) / downloadTime
		downloadMbps := (result.DownloadThroughput * 8) / 1_000_000
		fmt.Printf("      Downloaded in %.2fs (%.2f Mbps)\n", downloadTime, downloadMbps)
	}

	result.Success = true
	result.TotalTime = uploadTime + downloadTime

	// Clean up: remove the file from both nodes immediately
	bt.deleteFromIPFS(hash, uploadTarget.Container, uploadTarget.APIPort)
	bt.deleteFromIPFS(hash, downloadTarget.Container, downloadTarget.APIPort)

	return result
}

// calculateStatistics calculates statistics for a slice of values
func calculateStatistics(values []float64) Statistics {
	if len(values) == 0 {
		return Statistics{}
	}

	sort.Float64s(values)

	// Calculate mean
	sum := 0.0
	for _, v := range values {
		sum += v
	}
	mean := sum / float64(len(values))

	// Calculate median
	median := values[len(values)/2]
	if len(values)%2 == 0 {
		median = (values[len(values)/2-1] + values[len(values)/2]) / 2
	}

	// Calculate standard deviation
	sumSquares := 0.0
	for _, v := range values {
		diff := v - mean
		sumSquares += diff * diff
	}
	stdDev := 0.0
	if len(values) > 1 {
		stdDev = math.Sqrt(sumSquares / float64(len(values)-1))
	}

	// Calculate percentiles
	p95Index := int(float64(len(values)) * 0.95)
	p99Index := int(float64(len(values)) * 0.99)
	if p95Index >= len(values) {
		p95Index = len(values) - 1
	}
	if p99Index >= len(values) {
		p99Index = len(values) - 1
	}

	return Statistics{
		Mean:   mean,
		Median: median,
		Min:    values[0],
		Max:    values[len(values)-1],
		StdDev: stdDev,
		P95:    values[p95Index],
		P99:    values[p99Index],
		Count:  len(values),
	}
}

// runScenarioTests runs all tests for a specific scenario
func (bt *BandwidthTester) runScenarioTests(scenario NetworkScenario) []TestResult {
	fmt.Printf("\n%s\n", strings.Repeat("=", 60))
	fmt.Printf("Running scenario: %s\n", scenario.Name)
	fmt.Printf("Description: %s\n", scenario.Description)
	fmt.Printf("%s\n", strings.Repeat("=", 60))

	var scenarioResults []TestResult

	// Restart containers if RESTART_CONTAINERS environment variable is set
	if os.Getenv("RESTART_CONTAINERS") == "1" {
		fmt.Printf("  Restarting Docker containers for clean network state...\n")
		if err := bt.restartContainers(); err != nil {
			fmt.Printf("  Warning: Failed to restart containers: %v\n", err)
		} else {
			fmt.Printf("  Containers restarted successfully\n")
			// Wait for containers to be fully ready
			time.Sleep(15 * time.Second)

			// Reconnect IPFS peers (required for internal networks)
			fmt.Printf("  Reconnecting IPFS peers...\n")
			connectCmd := exec.Command("/bin/bash", "/app/scripts/connect-ipfs-peers.sh")
			if output, err := connectCmd.CombinedOutput(); err != nil {
				fmt.Printf("  Warning: Failed to connect IPFS peers: %v\n%s\n", err, output)
			} else {
				fmt.Printf("  IPFS peers connected successfully\n")
			}
		}
	}

	// Apply bandwidth limits
	// Check if using a bulk bandwidth script (applies to all containers/routers at once)
	isBulkScript := strings.Contains(scenario.BandwidthCommand, "limit-bandwidth-all.sh") ||
		strings.Contains(scenario.BandwidthCommand, "limit-bandwidth-routers.sh")

	if isBulkScript {
		// Apply to all containers/routers at once using the bulk script
		if err := bt.applyBandwidthLimit(scenario, "ipfs-org1"); err != nil {
			fmt.Printf("  Warning: Failed to apply bandwidth limit: %v\n", err)
		}
	} else {
		// Apply individually to each container (legacy support)
		allContainers := []string{
			"ipfs-org1", "ipfs-org2", "ipfs-org3", "ipfs-org4", "ipfs-org5",
			"ipfs-org6", "ipfs-org7", "ipfs-org8", "ipfs-org9", "ipfs-org10",
			"ipfs-bench",
		}

		fmt.Printf("  Applying limits to all IPFS containers...\n")
		for _, container := range allContainers {
			if err := bt.applyBandwidthLimit(scenario, container); err != nil {
				// Log the error but continue with other containers
				fmt.Printf("  Warning: Failed to apply limit to %s: %v\n", container, err)
			}
		}
	}

	// Run tests for each file
	for _, file := range bt.config.TestFiles {
		fmt.Printf("\n  Testing file: %s (%s)\n", file.Filename, file.Size)

		var fileResults []TestResult
		for i := 0; i < bt.config.TestConfiguration.Iterations; i++ {
			result := bt.runSingleTest(file, scenario, i)
			fileResults = append(fileResults, result)
			scenarioResults = append(scenarioResults, result)

			// Progress indicator every 10 iterations
			if (i+1)%10 == 0 {
				successful := 0
				for _, r := range fileResults {
					if r.Success {
						successful++
					}
				}
				fmt.Printf("      Progress: %d/%d (Success rate: %d/%d)\n",
					i+1, bt.config.TestConfiguration.Iterations, successful, i+1)

				// Run aggressive garbage collection every 10 iterations
				bt.runFullGarbageCollection()
			}
		}

		// Calculate and display file statistics
		bt.displayFileStatistics(fileResults)

		// Run garbage collection after each file
		fmt.Printf("    Cleaning up storage...\n")
		bt.runFullGarbageCollection()
	}

	// Remove bandwidth limits
	if isBulkScript {
		// For bulk scripts (Router Pod), no need to remove individual limits
		// The next scenario will apply new limits to all routers
		fmt.Printf("  Bandwidth limits will be updated in next scenario\n")
	} else {
		// Remove limits from individual containers (legacy support)
		allContainers := []string{
			"ipfs-org1", "ipfs-org2", "ipfs-org3", "ipfs-org4", "ipfs-org5",
			"ipfs-org6", "ipfs-org7", "ipfs-org8", "ipfs-org9", "ipfs-org10",
			"ipfs-bench",
		}

		fmt.Printf("  Removing limits from all IPFS containers...\n")
		for _, container := range allContainers {
			bt.removeBandwidthLimit(container)
		}
	}

	return scenarioResults
}

// displayFileStatistics displays statistics for file test results
func (bt *BandwidthTester) displayFileStatistics(results []TestResult) {
	var uploadTimes, downloadTimes []float64
	successful := 0

	for _, r := range results {
		if r.Success {
			successful++
			uploadTimes = append(uploadTimes, r.UploadTime)
			downloadTimes = append(downloadTimes, r.DownloadTime)
		}
	}

	if len(uploadTimes) > 0 {
		uploadStats := calculateStatistics(uploadTimes)
		downloadStats := calculateStatistics(downloadTimes)

		fmt.Printf("    File Statistics:\n")
		fmt.Printf("      Success rate: %d/%d\n", successful, len(results))
		fmt.Printf("      Avg upload time: %.2fs (±%.2fs)\n", uploadStats.Mean, uploadStats.StdDev)
		fmt.Printf("      Avg download time: %.2fs (±%.2fs)\n", downloadStats.Mean, downloadStats.StdDev)
	}
}

// saveResults saves test results to file
func (bt *BandwidthTester) saveResults() error {
	bt.mutex.Lock()
	defer bt.mutex.Unlock()

	output := map[string]interface{}{
		"config":    bt.config,
		"results":   bt.results,
		"timestamp": time.Now().Format(time.RFC3339),
	}

	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(bt.resultFile, data, 0644)
}

// runAllTests runs all test scenarios
func (bt *BandwidthTester) runAllTests() error {
	fmt.Printf("\n%s\n", strings.Repeat("=", 60))
	fmt.Printf("Starting %s\n", bt.config.TestConfiguration.Name)

	enabledScenarios := 0
	for _, s := range bt.config.NetworkScenarios {
		if s.Enabled {
			enabledScenarios++
		}
	}

	fmt.Printf("Test files: %d\n", len(bt.config.TestFiles))
	fmt.Printf("Scenarios: %d\n", enabledScenarios)
	fmt.Printf("Iterations per file: %d\n", bt.config.TestConfiguration.Iterations)
	fmt.Printf("%s\n", strings.Repeat("=", 60))

	startTime := time.Now()

	// Run each enabled scenario
	for _, scenario := range bt.config.NetworkScenarios {
		if scenario.Enabled {
			scenarioResults := bt.runScenarioTests(scenario)
			bt.results = append(bt.results, scenarioResults...)

			// Save intermediate results
			if err := bt.saveResults(); err != nil {
				log.Printf("Failed to save intermediate results: %v", err)
			}
		}
	}

	totalTime := time.Since(startTime).Seconds()

	// Save final results
	if err := bt.saveResults(); err != nil {
		return fmt.Errorf("failed to save final results: %v", err)
	}

	fmt.Printf("\n%s\n", strings.Repeat("=", 60))
	fmt.Printf("Test completed in %.2f seconds\n", totalTime)
	fmt.Printf("Results saved to: %s\n", bt.resultFile)
	fmt.Printf("%s\n", strings.Repeat("=", 60))

	bt.displaySummary()

	return nil
}

// displaySummary displays a summary of test results
func (bt *BandwidthTester) displaySummary() {
	fmt.Println("\nTest Summary:")
	fmt.Println(strings.Repeat("=", 60))

	for _, scenario := range bt.config.NetworkScenarios {
		if !scenario.Enabled {
			continue
		}

		fmt.Printf("\nScenario: %s\n", scenario.Name)
		bandwidth := "Unlimited"
		if scenario.Bandwidth != nil {
			bandwidth = *scenario.Bandwidth
		}
		fmt.Printf("Bandwidth: %s\n", bandwidth)
		fmt.Println(strings.Repeat("-", 40))

		// Group results by file
		for _, file := range bt.config.TestFiles {
			var fileResults []TestResult
			for _, r := range bt.results {
				if r.Scenario == scenario.ID && r.File == file.Filename {
					fileResults = append(fileResults, r)
				}
			}

			if len(fileResults) == 0 {
				continue
			}

			var uploadTimes, downloadTimes []float64
			successful := 0

			for _, r := range fileResults {
				if r.Success {
					successful++
					uploadTimes = append(uploadTimes, r.UploadTime)
					downloadTimes = append(downloadTimes, r.DownloadTime)
				}
			}

			if len(uploadTimes) > 0 {
				uploadStats := calculateStatistics(uploadTimes)
				downloadStats := calculateStatistics(downloadTimes)

				fmt.Printf("  File: %s\n", file.Filename)
				fmt.Printf("    Success rate: %.1f%%\n", float64(successful)*100/float64(len(fileResults)))
				fmt.Printf("    Avg upload: %.2fs (±%.2fs)\n", uploadStats.Mean, uploadStats.StdDev)
				fmt.Printf("    Avg download: %.2fs (±%.2fs)\n", downloadStats.Mean, downloadStats.StdDev)

				// Calculate and display effective throughput in Mbps
				avgUploadMbps := (float64(file.SizeBytes) * 8 / uploadStats.Mean) / 1_000_000
				avgDownloadMbps := (float64(file.SizeBytes) * 8 / downloadStats.Mean) / 1_000_000
				fmt.Printf("    Throughput: ↑%.1f Mbps, ↓%.1f Mbps\n", avgUploadMbps, avgDownloadMbps)
			}
		}
	}
}

// checkDocker checks if Docker is running
func checkDocker() error {
	cmd := exec.Command("docker", "ps")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("Docker is not running or not accessible")
	}
	return nil
}

// checkContainers checks if required containers are running
func checkContainers() error {
	cmd := exec.Command("docker", "ps", "--format", "{{.Names}}")
	output, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("could not check container status: %v", err)
	}

	containers := strings.Split(string(output), "\n")
	containerMap := make(map[string]bool)
	for _, c := range containers {
		containerMap[strings.TrimSpace(c)] = true
	}

	required := []string{"ipfs-org1", "ipfs-org2"}
	for _, r := range required {
		if !containerMap[r] {
			return fmt.Errorf("required container '%s' is not running", r)
		}
	}

	return nil
}

func main() {
	configFile := "test-scenarios.json"
	if len(os.Args) >= 2 {
		configFile = os.Args[1]
	}

	fmt.Printf("Using config file: %s\n", configFile)

	// Check Docker
	if err := checkDocker(); err != nil {
		log.Fatalf("Error: %v", err)
	}

	// Check containers
	if err := checkContainers(); err != nil {
		log.Fatalf("Error: %v\nPlease start the IPFS network with: docker-compose up -d", err)
	}

	// Create and run tester
	tester, err := NewBandwidthTester(configFile)
	if err != nil {
		log.Fatalf("Failed to initialize tester: %v", err)
	}

	if err := tester.runAllTests(); err != nil {
		log.Fatalf("Test failed: %v", err)
	}
}
