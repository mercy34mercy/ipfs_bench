# IPFS Bandwidth Test Graphs

このディレクトリには、IPFS帯域幅テストの結果を視覚化したグラフが含まれています。

## グラフの説明

### 1. throughput_comparison.png

**スループット比較グラフ**

- 100Mbpsと1Gbpsネットワークにおける実測スループット
- Upload（青）とDownload（紫）の速度を比較
- 各ファイルサイズ（10MB〜1GB）での結果
- 赤い破線は理論値（100Mbps/1Gbps）

**主な発見**:
- 100MB以上のファイルで理論値に近い速度を達成
- 1Gbpsでは85%以上の効率
- Downloadは2ホップ通信にもかかわらず高速

### 2. ratio_comparison.png

**Download/Upload時間比率グラフ**

- Download時間 / Upload時間の比率
- パイプライン処理の効果を示す重要な指標
- 赤い破線（2.0x）: 理論値（逐次処理）
- 緑の破線（1.0x）: 理想値（完全並行処理）

**主な発見**:
- 実測値は1.05x〜1.19x（逐次処理の約半分！）
- IPFSのストリーミング＋パイプライン処理の証拠
- 大きなファイルほど効率的（1.18x〜1.19x）

### 3. efficiency_comparison.png

**効率比較グラフ**

- 理論最大帯域幅に対する実効速度の割合
- Upload（青）とDownload（紫）の効率を％で表示
- 100%に近いほど帯域幅を有効活用

**主な発見**:
- 1Gbps Uploadは最大107%の効率（一時的なバースト）
- 100Mbpsでも95%程度の効率を達成
- Downloadは若干低いが73%程度の高効率

### 4. time_comparison.png

**転送時間比較グラフ**

- 各ファイルサイズでのUpload/Download所要時間
- 秒単位で表示
- ファイルサイズとの線形関係を確認可能

**主な発見**:
- 1GBファイルでも1Gbpsなら約9秒で転送完了
- Downloadは約1.2倍の時間（理論値2.0xよりはるかに高速）

## グラフの生成方法

```bash
# テスト結果から自動生成
python3 scripts/generate_graphs.py
```

**必要なファイル**:
- `test-results/test_results_100mbps_complete.json`
- `test-results/test_results_1GBps.json`

**必要なパッケージ**:
```bash
pip install matplotlib numpy
```

## データの出典

- **100Mbpsテスト**: 2025-10-27実施
- **1Gbpsテスト**: 2025-10-27実施
- **ファイルサイズ**: 10MB, 50MB, 100MB, 250MB, 500MB, 1GB
- **反復回数**: 各ファイル2回（平均値を使用）

---

**生成日**: 2025-10-27
**スクリプト**: `scripts/generate_graphs.py`
