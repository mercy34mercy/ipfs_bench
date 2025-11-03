package main

import (
	"bufio"
	"context"
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
	Run       int
	FileName  string
	SizeBytes int64
	Duration  time.Duration
	CID       string
	Started   time.Time
}

func main() {
	defaultDir := filepath.Clean(filepath.Join("..", "test-files"))

	apiBase := flag.String("api", "http://127.0.0.1:5001", "IPFS API base URL (without trailing /api/v0)")
	filesDir := flag.String("dir", defaultDir, "Directory containing files to upload")
	include := flag.String("include", "", "Comma-separated glob patterns to filter file names (e.g. 'test10m.dat,*.bin')")
	timeout := flag.Duration("timeout", 0, "Per-upload timeout (e.g. 2m, 30s); 0 means no limit")
	runs := flag.Int("runs", 100, "Number of upload iterations per file")
	csvOut := flag.String("csv", "bench_results.csv", "Path to write CSV results (set empty to skip)")
	flag.Parse()

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

	if runs == nil || *runs <= 0 {
		fmt.Fprintf(os.Stderr, "runs must be >= 1 (got %d)\n", *runs)
		os.Exit(1)
	}

	client := &http.Client{}
	endpoint := strings.TrimRight(*apiBase, "/") + "/api/v0/add?pin=false&progress=false&cid-version=1&wrap-with-directory=false"

	totalUploads := len(files) * *runs
	fmt.Printf("Uploading %d files (%d runs each, %d total uploads) to %s\n", len(files), *runs, totalUploads, endpoint)

	results := make([]benchResult, 0, totalUploads)
	for run := 1; run <= *runs; run++ {
		for _, file := range files {
			size, err := fileSize(file)
			if err != nil {
				fmt.Fprintf(os.Stderr, "stat failed for %s: %v\n", file, err)
				os.Exit(1)
			}

			var (
				ctx    context.Context
				cancel context.CancelFunc
			)
			if timeout != nil && *timeout > 0 {
				ctx, cancel = context.WithTimeout(context.Background(), *timeout)
			} else {
				ctx = context.Background()
			}

			started := time.Now()
			cid, err := uploadFile(ctx, client, endpoint, file)
			duration := time.Since(started)
			if cancel != nil {
				cancel()
			}
			if err != nil {
				fmt.Fprintf(os.Stderr, "upload failed for %s (run %d): %v\n", file, run, err)
				os.Exit(1)
			}

			result := benchResult{Run: run, FileName: file, SizeBytes: size, Duration: duration, CID: cid, Started: started}
			results = append(results, result)
			fmt.Printf("[run %3d] %-20s | size=%10s | time=%9s | throughput=%8s/s | cid=%s\n",
				run, filepath.Base(file), formatBytes(size), duration.Round(time.Millisecond), formatThroughput(size, duration), cid)
		}
	}

	var totalBytes int64
	var totalDuration time.Duration
	for _, r := range results {
		totalBytes += r.SizeBytes
		totalDuration += r.Duration
	}
	fmt.Printf("Total uploaded: %s across %d uploads in %s (avg throughput %s/s)\n",
		formatBytes(totalBytes), len(results), totalDuration.Round(time.Millisecond), formatThroughput(totalBytes, totalDuration))

	csvPath := strings.TrimSpace(*csvOut)
	if csvPath != "" {
		if err := writeCSV(csvPath, results); err != nil {
			fmt.Fprintf(os.Stderr, "failed to write CSV: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("Results written to %s\n", csvPath)
	}
}

func uploadFile(ctx context.Context, client *http.Client, endpoint, path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}

	pr, pw := io.Pipe()
	writer := multipart.NewWriter(pw)

	go func() {
		defer file.Close()
		part, err := writer.CreateFormFile("file", filepath.Base(path))
		if err != nil {
			_ = pw.CloseWithError(err)
			return
		}

		if _, err = io.Copy(part, file); err != nil {
			_ = pw.CloseWithError(err)
			return
		}

		if err = writer.Close(); err != nil {
			_ = pw.CloseWithError(err)
			return
		}

		_ = pw.Close()
	}()

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, pr)
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
	if err := scanner.Err(); err != nil {
		return "", err
	}
	if cid == "" {
		return "", fmt.Errorf("no CID returned")
	}

	return cid, nil
}

func fileSize(path string) (int64, error) {
	info, err := os.Stat(path)
	if err != nil {
		return 0, err
	}
	return info.Size(), nil
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

func formatThroughput(size int64, duration time.Duration) string {
	if duration <= 0 {
		return "n/a"
	}
	bytesPerSec := float64(size) / duration.Seconds()
	const unit = 1024
	if bytesPerSec < unit {
		return fmt.Sprintf("%.0f B", bytesPerSec)
	}
	div, exp := float64(unit), 0
	for n := bytesPerSec / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	value := bytesPerSec / div
	return fmt.Sprintf("%.2f %ciB", value, "KMGTPE"[exp])
}

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

func writeCSV(path string, results []benchResult) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()

	writer := csv.NewWriter(file)
	defer writer.Flush()

	header := []string{"run", "file", "size_bytes", "size_readable", "duration_ms", "throughput_mib_per_s", "cid", "started"}
	if err := writer.Write(header); err != nil {
		return err
	}

	for _, r := range results {
		durationMs := float64(r.Duration) / float64(time.Millisecond)
		throughput := throughputMiB(r.SizeBytes, r.Duration)
		record := []string{
			strconv.Itoa(r.Run),
			filepath.Base(r.FileName),
			strconv.FormatInt(r.SizeBytes, 10),
			formatBytes(r.SizeBytes),
			fmt.Sprintf("%.3f", durationMs),
			fmt.Sprintf("%.3f", throughput),
			r.CID,
			r.Started.Format(time.RFC3339Nano),
		}
		if err := writer.Write(record); err != nil {
			return err
		}
	}

	writer.Flush()
	return writer.Error()
}

func throughputMiB(size int64, duration time.Duration) float64 {
	if duration <= 0 {
		return 0
	}
	const unit = 1024 * 1024
	return float64(size) / duration.Seconds() / float64(unit)
}
