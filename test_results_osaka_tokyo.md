# IPFS Inter-Region Transfer Test Results
## Osaka → Tokyo (10 Tests Average) - CORRECTED

### Test Configuration
- **Date**: 2025-11-08 (Updated)
- **Source**: Osaka (asia-northeast2-a) - 34.97.58.78
- **Destination**: Tokyo (asia-northeast1-a) - 34.146.223.124
- **File Size**: 10 MB (10,485,760 bytes) per test
- **Number of Tests**: 10
- **Network Restrictions**: None (baseline measurement)
- **IPFS Node**: ipfs/kubo:latest (single public node on each region)
- **Cache Clearing**: **Yes - cache cleared before each test** ✓

### Test Results Summary
- **Average Download Duration**: 0.829 seconds
- **Average Download Speed**: **101.93 Mbps**
- **Total Transfer Time**: 8.29 seconds (for all 10 files)
- **Connection**: Direct peer-to-peer connection

### Individual Test Results

| Test # | CID | Duration (s) | Speed (Mbps) |
|--------|-----|--------------|--------------|
| 1 | QmQ6mdXcTBeaEayVfaHZkmZnUpbYpG5KPC8bSvyYyj2hXa | 0.941 | 89.15 |
| 2 | QmWJg5rwJBZeU52T54YW1v4WC5tMS38TwCSa2usiLidF2U | 0.781 | 107.45 |
| 3 | QmcaYETjC3rUzgrVMCYSo7LqtTHHzAVG7oXrt1vMWdXmK1 | 0.807 | 103.96 |
| 4 | QmYFMcQKayQTs6BcyMEuPjq4kHvYwH4mw2g3umQaHBKDNX | 0.768 | 109.22 |
| 5 | QmVMQeW9GWcwaqsXXPzwp42EYiAbin97gRWsm62Ri8Zm2L | 0.782 | 107.30 |
| 6 | QmPJS5GwNrGGQAHLe2vPyRXveLQfFY6GK8k9kjb73p6saQ | 0.969 | 86.53 |
| 7 | QmRwx376tbngACVJuzKySYd8oyft2cynaT5kfSJwKFmhaJ | 0.843 | 99.53 |
| 8 | QmehVcS9wEFTsesiPeMtdhuAJy2p4tmhXDgAfVBUgg2DMt | 0.888 | 94.42 |
| 9 | QmP8mtQ7FNA6VEDCtJniheFbdzwMZG1Trkcaix3Rvpp525 | 0.726 | 115.58 |
| 10 | QmaqgV8QogkcG1ZYbXx3NXJH4yEYP6DgNMxxtqE4MsTBT6 | 0.790 | 106.25 |

### Performance Statistics
- **Best Speed**: 115.58 Mbps (Test #9)
- **Worst Speed**: 86.53 Mbps (Test #6)
- **Speed Variation**: 29.05 Mbps (33% variance)
- **Consistency**: Good - all tests completed in under 1 second

### Infrastructure Details
**Osaka Node:**
- Instance: ipfs-bench-osaka
- Zone: asia-northeast2-a
- Machine Type: n1-standard-2
- Peer ID: 12D3KooWHK176yKqwWjdn9BkwqvKHRsuF2n5KU7Kfo3qfFyVexW7
- External IP: 34.97.58.78
- Container: ipfs-test

**Tokyo Node:**
- Instance: ipfs-bench-tokyo
- Zone: asia-northeast1-a
- Machine Type: n1-standard-2
- Container: ipfs-tokyo
- External IP: 34.146.223.124

### Notes
- **IMPORTANT**: Each test used a unique 10MB file with different CID
- **IMPORTANT**: Cache was cleared (`ipfs repo gc`) before each download test
- This ensures accurate network transfer measurement without cache effects
- All 10 files were unique random data generated separately
- Direct P2P connection was established before testing
- Tests demonstrate baseline IPFS performance between GCP regions without network throttling

### Comparison with Previous Test
- **Previous (with cache)**: 123.53 Mbps average
- **Current (cache cleared)**: 101.93 Mbps average
- **Difference**: ~21.6 Mbps slower when cache is cleared
- **Conclusion**: The ~20 Mbps difference shows the significant impact of IPFS caching on transfer speeds
