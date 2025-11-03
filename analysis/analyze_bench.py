#!/usr/bin/env python3
"""Analyze IPFS upload benchmark CSV and produce summaries/plots."""

import argparse
import csv
import math
import pathlib
from collections import defaultdict
from statistics import mean, pstdev
from typing import Dict, List, Optional

try:
    import matplotlib.pyplot as plt  # type: ignore
except ImportError:  # pragma: no cover - handled at runtime
    plt = None

FILE_SORT_ORDER = {
    "test10m.dat": 10,
    "test50m.dat": 50,
    "test100m.dat": 100,
    "test250m.dat": 250,
    "test500m.dat": 500,
    "test1g.dat": 1024,
    "test2g.dat": 2048,
    "test4g.dat": 4096,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=pathlib.Path, help="Path to bench_results.csv")
    parser.add_argument(
        "--outdir",
        type=pathlib.Path,
        default=pathlib.Path("analysis"),
        help="Directory to write summary artifacts",
    )
    parser.add_argument(
        "--show", action="store_true", help="Display plots interactively after generation"
    )
    parser.add_argument(
        "--no-plots",
        action="store_true",
        help="Skip plot generation (useful if matplotlib is unavailable)",
    )
    return parser.parse_args()


class BenchRow:
    __slots__ = ("run", "file", "size_bytes", "duration_ms", "throughput_mib_per_s")

    def __init__(self, run: int, file: str, size_bytes: int, duration_ms: float, throughput: float):
        self.run = run
        self.file = file
        self.size_bytes = size_bytes
        self.duration_ms = duration_ms
        self.throughput_mib_per_s = throughput


def sort_key(file: str) -> float:
    if file in FILE_SORT_ORDER:
        return FILE_SORT_ORDER[file]
    if file.endswith("g.dat"):
        return float(file.split("test", 1)[1].split("g", 1)[0]) * 1024
    if file.endswith("m.dat"):
        return float(file.split("test", 1)[1].split("m", 1)[0])
    return float("inf")


def size_label(file: str, summary: Dict[str, Dict[str, float]]) -> str:
    size_mib = summary[file]["size_mib"]
    if size_mib >= 1024:
        return f"{size_mib/1024:.1f} GiB"
    return f"{size_mib:.0f} MiB"


def size_label_simple(file: str) -> str:
    """Return simple size labels like '10MB' or '4GB'."""
    if file == "test10m.dat":
        return "10MB"
    elif file == "test50m.dat":
        return "50MB"
    elif file == "test100m.dat":
        return "100MB"
    elif file == "test250m.dat":
        return "250MB"
    elif file == "test500m.dat":
        return "500MB"
    elif file == "test1g.dat":
        return "1GB"
    elif file == "test2g.dat":
        return "2GB"
    elif file == "test4g.dat":
        return "4GB"
    else:
        return file


def load_data(csv_path: pathlib.Path) -> List[BenchRow]:
    rows: List[BenchRow] = []
    with csv_path.open("r", newline="") as handle:
        reader = csv.DictReader(handle)
        required = {
            "run",
            "file",
            "size_bytes",
            "duration_ms",
            "throughput_mib_per_s",
        }
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"CSV is missing required columns: {sorted(missing)}")
        for raw in reader:
            rows.append(
                BenchRow(
                    run=int(raw["run"]),
                    file=raw["file"],
                    size_bytes=int(raw["size_bytes"]),
                    duration_ms=float(raw["duration_ms"]),
                    throughput=float(raw["throughput_mib_per_s"]),
                )
            )
    rows.sort(key=lambda r: (sort_key(r.file), r.run))
    return rows


def percentile(values: List[float], pct: float) -> float:
    if not values:
        return math.nan
    sorted_vals = sorted(values)
    k = (len(sorted_vals) - 1) * pct
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return sorted_vals[int(k)]
    d0 = sorted_vals[f] * (c - k)
    d1 = sorted_vals[c] * (k - f)
    return d0 + d1


def summarise(rows: List[BenchRow]) -> Dict[str, Dict[str, float]]:
    grouped: Dict[str, List[BenchRow]] = defaultdict(list)
    for row in rows:
        grouped[row.file].append(row)

    summary: Dict[str, Dict[str, float]] = {}
    for file, items in grouped.items():
        durations = [item.duration_ms for item in items]
        throughputs = [item.throughput_mib_per_s for item in items]
        size_bytes = items[0].size_bytes
        summary[file] = {
            "run_count": len(items),
            "size_bytes": size_bytes,
            "size_mib": size_bytes / (1024 * 1024),
            "duration_ms_mean": mean(durations),
            "duration_ms_std": pstdev(durations) if len(durations) > 1 else 0.0,
            "duration_ms_min": min(durations),
            "duration_ms_max": max(durations),
            "throughput_mean": mean(throughputs),
            "throughput_std": pstdev(throughputs) if len(throughputs) > 1 else 0.0,
            "throughput_min": min(throughputs),
            "throughput_p50": percentile(throughputs, 0.5),
            "throughput_p95": percentile(throughputs, 0.95),
            "throughput_max": max(throughputs),
        }
    return summary


def write_summary_csv(summary: Dict[str, Dict[str, float]], outdir: pathlib.Path) -> pathlib.Path:
    outdir.mkdir(parents=True, exist_ok=True)
    csv_path = outdir / "summary.csv"
    fieldnames = [
        "file",
        "run_count",
        "size_bytes",
        "size_mib",
        "duration_ms_mean",
        "duration_ms_std",
        "duration_ms_min",
        "duration_ms_max",
        "throughput_mean",
        "throughput_std",
        "throughput_min",
        "throughput_p50",
        "throughput_p95",
        "throughput_max",
    ]
    with csv_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for file in sorted(summary, key=sort_key):
            row = {"file": file}
            row.update(summary[file])
            writer.writerow(row)
    return csv_path


def plot_mean_bar(summary: Dict[str, Dict[str, float]], outdir: pathlib.Path) -> Optional[pathlib.Path]:
    if plt is None:
        return None
    outdir.mkdir(parents=True, exist_ok=True)
    files = sorted(summary, key=sort_key)
    labels = [size_label_simple(file) for file in files]
    means = [summary[file]["throughput_mean"] for file in files]
    stds = [summary[file]["throughput_std"] for file in files]

    # Set Japanese font if available
    try:
        plt.rcParams['font.family'] = ['sans-serif']
        plt.rcParams['font.sans-serif'] = ['Hiragino Sans', 'Yu Gothic', 'Meirio', 'Takao', 'IPAexGothic', 'IPAPGothic', 'VL PGothic', 'Noto Sans CJK JP', 'DejaVu Sans']
    except:
        pass

    fig, ax = plt.subplots(figsize=(12, 6))
    positions = list(range(len(files)))
    ax.bar(positions, means, yerr=stds, capsize=4, color="#4c72b0", alpha=0.85)
    ax.set_xticks(positions)
    ax.set_xticklabels(labels, rotation=45, ha="right")
    ax.set_ylabel("スループット (MiB/s)")
    ax.set_xlabel("ファイルサイズ")
    ax.set_title("平均スループットと標準偏差")
    ax.grid(True, axis="y", linestyle="--", alpha=0.3)
    fig.tight_layout()
    out_path = outdir / "throughput_mean_bar.png"
    fig.savefig(out_path, dpi=150)
    plt.close(fig)
    return out_path


def plot_time_series(rows: List[BenchRow], outdir: pathlib.Path) -> Optional[pathlib.Path]:
    if plt is None:
        return None
    outdir.mkdir(parents=True, exist_ok=True)
    series: Dict[str, List[BenchRow]] = defaultdict(list)
    for row in rows:
        series[row.file].append(row)
    fig, ax = plt.subplots(figsize=(12, 6))
    for file in sorted(series, key=sort_key):
        runs = [item.run for item in series[file]]
        values = [item.throughput_mib_per_s for item in series[file]]
        ax.plot(runs, values, marker="o", markersize=3, linestyle="-", label=file)
    ax.set_xlabel("Run")
    ax.set_ylabel("Throughput (MiB/s)")
    ax.set_title("Throughput across runs")
    ax.grid(True, linestyle="--", alpha=0.3)
    ax.legend(ncol=2)
    fig.tight_layout()
    out_path = outdir / "throughput_timeseries.png"
    fig.savefig(out_path, dpi=150)
    plt.close(fig)
    return out_path


def plot_throughput_vs_size(summary: Dict[str, Dict[str, float]], outdir: pathlib.Path) -> Optional[pathlib.Path]:
    if plt is None:
        return None
    outdir.mkdir(parents=True, exist_ok=True)
    files = sorted(summary, key=sort_key)
    sizes = [summary[file]["size_mib"] for file in files]
    labels = [size_label(file, summary) for file in files]
    means = [summary[file]["throughput_mean"] for file in files]
    p95s = [summary[file]["throughput_p95"] for file in files]
    fig, ax = plt.subplots(figsize=(10, 6))
    ax.plot(sizes, means, marker="o", label="Mean")
    ax.plot(sizes, p95s, marker="o", linestyle="--", label="P95")
    for x, y, label in zip(sizes, means, labels):
        ax.annotate(label, (x, y), textcoords="offset points", xytext=(0, 6), ha="center", fontsize=8)
    ax.set_xlabel("File size (MiB)")
    ax.set_ylabel("Throughput (MiB/s)")
    ax.set_title("Throughput vs file size")
    ax.grid(True, linestyle="--", alpha=0.3)
    ax.legend()
    fig.tight_layout()
    out_path = outdir / "throughput_vs_size.png"
    fig.savefig(out_path, dpi=150)
    plt.close(fig)
    return out_path


def main() -> None:
    args = parse_args()
    rows = load_data(args.csv)
    summary = summarise(rows)
    summary_path = write_summary_csv(summary, args.outdir)

    mean_bar_path = None
    timeseries_path = None
    vs_size_path = None
    if not args.no_plots:
        if plt is None:
            print(
                "matplotlib not available. Install with `python3 -m pip install matplotlib` to generate plots.",
                flush=True,
            )
        else:
            mean_bar_path = plot_mean_bar(summary, args.outdir)
            timeseries_path = plot_time_series(rows, args.outdir)
            vs_size_path = plot_throughput_vs_size(summary, args.outdir)

    print("Summary (per file):")
    for file in sorted(summary, key=sort_key):
        stats = summary[file]
        print(
            f"  {file}: runs={stats['run_count']}, size={stats['size_mib']:.2f} MiB, "
            f"avg throughput={stats['throughput_mean']:.2f} MiB/s (p50={stats['throughput_p50']:.2f}, p95={stats['throughput_p95']:.2f})"
        )
    print()
    print(f"Summary CSV written to: {summary_path}")
    if mean_bar_path:
        print(f"Throughput bar chart saved to: {mean_bar_path}")
    if timeseries_path:
        print(f"Throughput time-series saved to: {timeseries_path}")
    if vs_size_path:
        print(f"Throughput vs size plot saved to: {vs_size_path}")

    if args.show and plt is not None:
        plt.show()


if __name__ == "__main__":
    main()
