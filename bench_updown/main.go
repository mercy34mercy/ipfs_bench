package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/csv"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type addResponse struct {
	Name string `json:"Name"`
	Hash string `json:"Hash"`
	Size string `json:"Size"`
}

type benchResult struct {
	Run            int
	FileName       string
	SizeBytes      int64
	UploadNode     int
	DownloadNode   int
	UploadDuration time.Duration
	DownloadDuration time.Duration
	CID            string
	Started        time.Time
}

func main() {
	defaultDir := filepath.Clean(filepath.Join("..", "test-files"))

	// Configure flags
	apiBaseTemplate := flag.String("api-template", "http://127.0.0.1:500%d", "IPFS API base URL template (use %d for node number)")
	filesDir := flag.String("dir", defaultDir, "Directory containing files to upload")
	include := flag.String("include", "", "Comma-separated glob patterns to filter file names")
	timeout := flag.Duration("timeout", 5*time.Minute, "Per-operation timeout")
	runs := flag.Int("runs", 10, "Number of upload/download iterations per file")
	csvOut := flag.String("csv", "bench_upload_download_results.csv", "Path to write CSV results")
	nodeCount := flag.Int("nodes", 10, "Number of IPFS nodes (default: 10)")
	flag.Parse()

	// Read test files
	entries, err := os.ReadDir(*filesDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to open test-files directory: %v\n", err)
		os.Exit(1)
	}

	var files []string
	patterns := splitPatterns(*include)

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if !shouldInclude(name, patterns) {
			continue
		}
		files = append(files, filepath.Join(*filesDir, name))
	}

	if len(files) == 0 {
		fmt.Fprintf(os.Stderr, "no files found in %s\n", *filesDir)
		os.Exit(1)
	}

	sort.Strings(files)

	client := &http.Client{
		Timeout: *timeout,
	}

	// Build node API endpoints
	nodeAPIs := make([]string, *nodeCount)
	for i := 0; i < *nodeCount; i++ {
		nodeAPIs[i] = fmt.Sprintf(*apiBaseTemplate, i+1)
	}

	totalOps := len(files) * *runs
	fmt.Printf("Testing %d files (%d runs each, %d total operations) with %d nodes\n",
		len(files), *runs, totalOps, *nodeCount)

	results := make([]benchResult, 0, totalOps)

	for run := 1; run <= *runs; run++ {
		for _, file := range files {
			// Select different nodes for upload and download
			uploadNode := (run - 1) % *nodeCount
			downloadNode := (uploadNode + 1) % *nodeCount

			uploadAPI := nodeAPIs[uploadNode]
			downloadAPI := nodeAPIs[downloadNode]

			fmt.Printf("\n[Run %d] File: %s\n", run, filepath.Base(file))
			fmt.Printf("  Upload node: %d, Download node: %d\n", uploadNode+1, downloadNode+1)

			// Read file and add random bytes to ensure unique CID
			fileData, size, err := readFileWithRandomSuffix(file)
			if err != nil {
				fmt.Fprintf(os.Stderr, "failed to read file %s: %v\n", file, err)
				continue
			}

			// Upload file (with pinning enabled)
			started := time.Now()
			cid, err := uploadData(context.Background(), client, uploadAPI, filepath.Base(file), fileData)
			uploadDuration := time.Since(started)

			if err != nil {
				fmt.Fprintf(os.Stderr, "upload failed for %s: %v\n", file, err)
				continue
			}

			uploadMBps := float64(size) / uploadDuration.Seconds() / (1024 * 1024)
			fmt.Printf("  Upload completed: %s in %v (%.2f MiB/s), CID: %s\n",
				formatBytes(size), uploadDuration.Round(time.Millisecond), uploadMBps, cid)

			// Wait a bit for propagation
			time.Sleep(500 * time.Millisecond)

			// Download file from different node
			started = time.Now()
			downloadedSize, err := downloadFile(context.Background(), client, downloadAPI, cid)
			downloadDuration := time.Since(started)

			if err != nil {
				fmt.Fprintf(os.Stderr, "download failed for CID %s: %v\n", cid, err)
				// Still try to unpin
				unpinFile(context.Background(), client, uploadAPI, cid)
				continue
			}

			downloadMBps := float64(downloadedSize) / downloadDuration.Seconds() / (1024 * 1024)
			fmt.Printf("  Download completed: %s in %v (%.2f MiB/s)\n",
				formatBytes(downloadedSize), downloadDuration.Round(time.Millisecond), downloadMBps)

			// Unpin the file from upload node
			err = unpinFile(context.Background(), client, uploadAPI, cid)
			if err != nil {
				fmt.Fprintf(os.Stderr, "failed to unpin CID %s: %v\n", cid, err)
			}

			// Record result
			result := benchResult{
				Run:              run,
				FileName:         filepath.Base(file),
				SizeBytes:        size,
				UploadNode:       uploadNode + 1,
				DownloadNode:     downloadNode + 1,
				UploadDuration:   uploadDuration,
				DownloadDuration: downloadDuration,
				CID:              cid,
				Started:          started,
			}
			results = append(results, result)
		}
	}

	// Write results to CSV
	if *csvOut != "" {
		if err := writeCSV(*csvOut, results); err != nil {
			fmt.Fprintf(os.Stderr, "failed to write CSV: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("\nResults written to %s\n", *csvOut)
	}

	// Print summary
	printSummary(results)
}

func readFileWithRandomSuffix(path string) ([]byte, int64, error) {
	// Read original file
	originalData, err := os.ReadFile(path)
	if err != nil {
		return nil, 0, err
	}

	// Add random 32 bytes to make content unique
	randomBytes := make([]byte, 32)
	if _, err := rand.Read(randomBytes); err != nil {
		return nil, 0, err
	}

	// Combine original data with random suffix
	data := append(originalData, randomBytes...)
	return data, int64(len(data)), nil
}

func uploadData(ctx context.Context, client *http.Client, apiBase, filename string, data []byte) (string, error) {
	// Note: pin=true (pinning enabled)
	endpoint := strings.TrimRight(apiBase, "/") + "/api/v0/add?progress=false&cid-version=1&wrap-with-directory=false"

	var buf bytes.Buffer
	writer := multipart.NewWriter(&buf)

	part, err := writer.CreateFormFile("file", filename)
	if err != nil {
		return "", err
	}

	if _, err = part.Write(data); err != nil {
		return "", err
	}

	if err = writer.Close(); err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, &buf)
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("unexpected status %s: %s", resp.Status, strings.TrimSpace(string(body)))
	}

	scanner := bufio.NewScanner(resp.Body)
	var cid string
	for scanner.Scan() {
		var parsed addResponse
		if err := json.Unmarshal(scanner.Bytes(), &parsed); err != nil {
			return "", fmt.Errorf("decode response: %w", err)
		}
		if parsed.Hash != "" {
			cid = parsed.Hash
		}
	}

	if cid == "" {
		return "", fmt.Errorf("no CID returned")
	}

	return cid, nil
}

func downloadFile(ctx context.Context, client *http.Client, apiBase, cid string) (int64, error) {
	endpoint := fmt.Sprintf("%s/api/v0/cat?arg=%s", strings.TrimRight(apiBase, "/"), cid)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, nil)
	if err != nil {
		return 0, err
	}

	resp, err := client.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return 0, fmt.Errorf("unexpected status %s: %s", resp.Status, strings.TrimSpace(string(body)))
	}

	// Read and discard the data (simulating actual download)
	written, err := io.Copy(io.Discard, resp.Body)
	if err != nil {
		return 0, err
	}

	return written, nil
}

func unpinFile(ctx context.Context, client *http.Client, apiBase, cid string) error {
	endpoint := fmt.Sprintf("%s/api/v0/pin/rm?arg=%s", strings.TrimRight(apiBase, "/"), cid)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, nil)
	if err != nil {
		return err
	}

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("unexpected status %s: %s", resp.Status, strings.TrimSpace(string(body)))
	}

	return nil
}

func writeCSV(path string, results []benchResult) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()

	writer := csv.NewWriter(file)
	defer writer.Flush()

	header := []string{
		"run", "file", "size_bytes", "size_readable",
		"upload_node", "download_node",
		"upload_duration_ms", "download_duration_ms",
		"upload_throughput_mib_per_s", "download_throughput_mib_per_s",
		"cid", "started",
	}

	if err := writer.Write(header); err != nil {
		return err
	}

	for _, r := range results {
		uploadMs := float64(r.UploadDuration) / float64(time.Millisecond)
		downloadMs := float64(r.DownloadDuration) / float64(time.Millisecond)
		uploadThroughput := throughputMiB(r.SizeBytes, r.UploadDuration)
		downloadThroughput := throughputMiB(r.SizeBytes, r.DownloadDuration)

		record := []string{
			strconv.Itoa(r.Run),
			r.FileName,
			strconv.FormatInt(r.SizeBytes, 10),
			formatBytes(r.SizeBytes),
			strconv.Itoa(r.UploadNode),
			strconv.Itoa(r.DownloadNode),
			fmt.Sprintf("%.3f", uploadMs),
			fmt.Sprintf("%.3f", downloadMs),
			fmt.Sprintf("%.3f", uploadThroughput),
			fmt.Sprintf("%.3f", downloadThroughput),
			r.CID,
			r.Started.Format(time.RFC3339Nano),
		}

		if err := writer.Write(record); err != nil {
			return err
		}
	}

	return writer.Error()
}

func printSummary(results []benchResult) {
	if len(results) == 0 {
		return
	}

	fmt.Println("\n=== Summary ===")

	// Group by file
	fileStats := make(map[string]struct {
		uploadTimes   []time.Duration
		downloadTimes []time.Duration
		size          int64
	})

	for _, r := range results {
		stats := fileStats[r.FileName]
		stats.uploadTimes = append(stats.uploadTimes, r.UploadDuration)
		stats.downloadTimes = append(stats.downloadTimes, r.DownloadDuration)
		stats.size = r.SizeBytes
		fileStats[r.FileName] = stats
	}

	fmt.Printf("\n%-20s %15s %15s %15s %15s\n", "File", "Size", "Avg Upload", "Avg Download", "Total")
	fmt.Println(strings.Repeat("-", 85))

	for file, stats := range fileStats {
		avgUpload := avgDuration(stats.uploadTimes)
		avgDownload := avgDuration(stats.downloadTimes)
		avgTotal := avgUpload + avgDownload

		uploadMBps := float64(stats.size) / avgUpload.Seconds() / (1024 * 1024)
		downloadMBps := float64(stats.size) / avgDownload.Seconds() / (1024 * 1024)

		fmt.Printf("%-20s %15s %15s %15s %15s\n",
			file,
			formatBytes(stats.size),
			fmt.Sprintf("%v (%.1f MB/s)", avgUpload.Round(time.Millisecond), uploadMBps),
			fmt.Sprintf("%v (%.1f MB/s)", avgDownload.Round(time.Millisecond), downloadMBps),
			avgTotal.Round(time.Millisecond),
		)
	}
}

// Helper functions
func splitPatterns(raw string) []string {
	if strings.TrimSpace(raw) == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	var patterns []string
	for _, part := range parts {
		trimmed := strings.TrimSpace(part)
		if trimmed != "" {
			patterns = append(patterns, trimmed)
		}
	}
	return patterns
}

func shouldInclude(name string, patterns []string) bool {
	if len(patterns) == 0 {
		return true
	}
	for _, pattern := range patterns {
		match, err := filepath.Match(pattern, name)
		if err != nil {
			continue
		}
		if match {
			return true
		}
	}
	return false
}

func formatBytes(size int64) string {
	const unit = 1024
	if size < unit {
		return fmt.Sprintf("%d B", size)
	}
	div, exp := int64(unit), 0
	for n := size / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	value := float64(size) / float64(div)
	return fmt.Sprintf("%.2f %ciB", value, "KMGTPE"[exp])
}

func throughputMiB(size int64, duration time.Duration) float64 {
	if duration <= 0 {
		return 0
	}
	const unit = 1024 * 1024
	return float64(size) / duration.Seconds() / float64(unit)
}

func avgDuration(durations []time.Duration) time.Duration {
	if len(durations) == 0 {
		return 0
	}
	var sum time.Duration
	for _, d := range durations {
		sum += d
	}
	return sum / time.Duration(len(durations))
}