# IPFS Multi-Region Transfer Test Results
## Osaka → Multiple Regions (10 Tests Average)

### Test Configuration
- **Date**: 2025-11-08
- **Source**: Osaka (asia-northeast2-a) - 34.97.58.78
- **File Size**: 10 MB (10,485,760 bytes) per test
- **Number of Tests**: 10 per region
- **IPFS Node**: ipfs/kubo:latest (single public node on each region)
- **Cache Clearing**: Yes - cache cleared before each test ✓
- **Source Peer ID**: 12D3KooWHK176yKqwWjdn9BkwqvKHRsuF2n5KU7Kfo3qfFyVexW7

### Test Results Summary

| Destination Region | Avg Speed (Mbps) | Best Speed (Mbps) | Worst Speed (Mbps) | Variance | Distance from Osaka |
|-------------------|------------------|-------------------|--------------------|---------|--------------------|
| **Tokyo** (asia-northeast1-a) | 101.93 | 115.58 | 86.53 | 33% | ~400 km |
| **Taiwan** (asia-east1-a) | 64.08 | 77.52 | 31.42 | 72% | ~2,100 km |
| **Singapore** (asia-southeast1-a) | 33.55 | 41.29 | 11.09 | 272% | ~5,300 km |
| **US West** (us-west1-a) | 33.83 | 37.94 | 21.36 | 78% | ~8,300 km |
| **Europe** (europe-west1-b) | 17.42 | 18.20 | 12.43 | 46% | ~9,400 km |

### Key Findings

1. **Geographic Distance Impact**:
   - Tokyo (closest): 101.93 Mbps average
   - Europe (farthest): 17.42 Mbps average
   - **Speed decreases by ~83% from closest to farthest region**

2. **Regional Performance**:
   - **Best**: Tokyo (101.93 Mbps) - Same region in Japan
   - **Good**: Taiwan (64.08 Mbps) - East Asia
   - **Medium**: Singapore & US West (~34 Mbps) - Southeast Asia & North America
   - **Slowest**: Europe (17.42 Mbps) - Longest distance

3. **Performance Consistency**:
   - Tokyo: Most consistent (33% variance)
   - Taiwan: Moderate variance (72%)
   - Singapore: High variance (272%) - unstable first test
   - US West: Moderate variance (78%)
   - Europe: Moderate variance (46%)

### Detailed Test Results

#### Tokyo → Osaka (101.93 Mbps avg)
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

#### Taiwan → Osaka (64.08 Mbps avg)
| Test # | CID | Duration (s) | Speed (Mbps) |
|--------|-----|--------------|--------------|
| 1 | QmQ6mdXcTBeaEayVfaHZkmZnUpbYpG5KPC8bSvyYyj2hXa | 2.669 | 31.42 |
| 2 | QmWJg5rwJBZeU52T54YW1v4WC5tMS38TwCSa2usiLidF2U | 1.265 | 66.32 |
| 3 | QmcaYETjC3rUzgrVMCYSo7LqtTHHzAVG7oXrt1vMWdXmK1 | 1.113 | 75.35 |
| 4 | QmYFMcQKayQTs6BcyMEuPjq4kHvYwH4mw2g3umQaHBKDNX | 1.082 | 77.52 |
| 5 | QmVMQeW9GWcwaqsXXPzwp42EYiAbin97gRWsm62Ri8Zm2L | 1.130 | 74.21 |
| 6 | QmPJS5GwNrGGQAHLe2vPyRXveLQfFY6GK8k9kjb73p6saQ | 1.499 | 55.97 |
| 7 | QmRwx376tbngACVJuzKySYd8oyft2cynaT5kfSJwKFmhaJ | 1.240 | 67.65 |
| 8 | QmehVcS9wEFTsesiPeMtdhuAJy2p4tmhXDgAfVBUgg2DMt | 1.317 | 63.67 |
| 9 | QmP8mtQ7FNA6VEDCtJniheFbdzwMZG1Trkcaix3Rvpp525 | 1.324 | 63.35 |
| 10 | QmaqgV8QogkcG1ZYbXx3NXJH4yEYP6DgNMxxtqE4MsTBT6 | 1.284 | 65.35 |

#### Singapore → Osaka (33.55 Mbps avg)
| Test # | CID | Duration (s) | Speed (Mbps) |
|--------|-----|--------------|--------------|
| 1 | QmQ6mdXcTBeaEayVfaHZkmZnUpbYpG5KPC8bSvyYyj2hXa | 4.598 | 18.24 |
| 2 | QmWJg5rwJBZeU52T54YW1v4WC5tMS38TwCSa2usiLidF2U | 2.369 | 35.41 |
| 3 | QmcaYETjC3rUzgrVMCYSo7LqtTHHzAVG7oXrt1vMWdXmK1 | 2.053 | 40.85 |
| 4 | QmYFMcQKayQTs6BcyMEuPjq4kHvYwH4mw2g3umQaHBKDNX | 2.210 | 37.95 |
| 5 | QmVMQeW9GWcwaqsXXPzwp42EYiAbin97gRWsm62Ri8Zm2L | 2.292 | 36.60 |
| 6 | QmPJS5GwNrGGQAHLe2vPyRXveLQfFY6GK8k9kjb73p6saQ | 2.278 | 36.82 |
| 7 | QmRwx376tbngACVJuzKySYd8oyft2cynaT5kfSJwKFmhaJ | 2.124 | 39.48 |
| 8 | QmehVcS9wEFTsesiPeMtdhuAJy2p4tmhXDgAfVBUgg2DMt | 2.220 | 37.79 |
| 9 | QmP8mtQ7FNA6VEDCtJniheFbdzwMZG1Trkcaix3Rvpp525 | 7.561 | 11.09 |
| 10 | QmaqgV8QogkcG1ZYbXx3NXJH4yEYP6DgNMxxtqE4MsTBT6 | 2.031 | 41.29 |

#### US West → Osaka (33.83 Mbps avg)
| Test # | CID | Duration (s) | Speed (Mbps) |
|--------|-----|--------------|--------------|
| 1 | QmQ6mdXcTBeaEayVfaHZkmZnUpbYpG5KPC8bSvyYyj2hXa | 3.926 | 21.36 |
| 2 | QmWJg5rwJBZeU52T54YW1v4WC5tMS38TwCSa2usiLidF2U | 2.392 | 35.07 |
| 3 | QmcaYETjC3rUzgrVMCYSo7LqtTHHzAVG7oXrt1vMWdXmK1 | 2.375 | 35.31 |
| 4 | QmYFMcQKayQTs6BcyMEuPjq4kHvYwH4mw2g3umQaHBKDNX | 2.211 | 37.94 |
| 5 | QmVMQeW9GWcwaqsXXPzwp42EYiAbin97gRWsm62Ri8Zm2L | 2.416 | 34.72 |
| 6 | QmPJS5GwNrGGQAHLe2vPyRXveLQfFY6GK8k9kjb73p6saQ | 2.384 | 35.19 |
| 7 | QmRwx376tbngACVJuzKySYd8oyft2cynaT5kfSJwKFmhaJ | 2.378 | 35.27 |
| 8 | QmehVcS9wEFTsesiPeMtdhuAJy2p4tmhXDgAfVBUgg2DMt | 2.419 | 34.67 |
| 9 | QmP8mtQ7FNA6VEDCtJniheFbdzwMZG1Trkcaix3Rvpp525 | 2.310 | 36.30 |
| 10 | QmaqgV8QogkcG1ZYbXx3NXJH4yEYP6DgNMxxtqE4MsTBT6 | 2.584 | 32.46 |

#### Europe → Osaka (17.42 Mbps avg)
| Test # | CID | Duration (s) | Speed (Mbps) |
|--------|-----|--------------|--------------|
| 1 | QmQ6mdXcTBeaEayVfaHZkmZnUpbYpG5KPC8bSvyYyj2hXa | 6.746 | 12.43 |
| 2 | QmWJg5rwJBZeU52T54YW1v4WC5tMS38TwCSa2usiLidF2U | 4.625 | 18.13 |
| 3 | QmcaYETjC3rUzgrVMCYSo7LqtTHHzAVG7oXrt1vMWdXmK1 | 4.614 | 18.18 |
| 4 | QmYFMcQKayQTs6BcyMEuPjq4kHvYwH4mw2g3umQaHBKDNX | 4.685 | 17.90 |
| 5 | QmVMQeW9GWcwaqsXXPzwp42EYiAbin97gRWsm62Ri8Zm2L | 4.702 | 17.84 |
| 6 | QmPJS5GwNrGGQAHLe2vPyRXveLQfFY6GK8k9kjb73p6saQ | 4.615 | 18.17 |
| 7 | QmRwx376tbngACVJuzKySYd8oyft2cynaT5kfSJwKFmhaJ | 4.698 | 17.85 |
| 8 | QmehVcS9wEFTsesiPeMtdhuAJy2p4tmhXDgAfVBUgg2DMt | 4.832 | 17.36 |
| 9 | QmP8mtQ7FNA6VEDCtJniheFbdzwMZG1Trkcaix3Rvpp525 | 4.608 | 18.20 |
| 10 | QmaqgV8QogkcG1ZYbXx3NXJH4yEYP6DgNMxxtqE4MsTBT6 | 4.623 | 18.14 |

### Infrastructure Details

**Osaka Node (Source)**:
- Instance: ipfs-bench-osaka
- Zone: asia-northeast2-a
- Machine Type: n1-standard-2
- Peer ID: 12D3KooWHK176yKqwWjdn9BkwqvKHRsuF2n5KU7Kfo3qfFyVexW7
- External IP: 34.97.58.78

**Tokyo Node**:
- Instance: ipfs-bench-tokyo
- Zone: asia-northeast1-a
- External IP: 34.146.223.124
- Peer ID: 12D3KooWLQjyhJy6YSmkGn8xoAZMjSLwYQUNfQdBRSrq3Nb8RBjX

**Taiwan Node**:
- Instance: ipfs-bench-taiwan
- Zone: asia-east1-a
- External IP: 35.229.158.178
- Peer ID: 12D3KooWFgSFrx1HjkGHqjRANtuxXNnXzJAcpG2yZTJKF1UvjQi2

**Singapore Node**:
- Instance: ipfs-bench-singapore
- Zone: asia-southeast1-a
- External IP: 34.158.50.119
- Peer ID: 12D3KooWQWvAxPXYnWkwrQUvKsSYP1PAE8UsoGXanxnwizkJbb6M

**US West Node**:
- Instance: ipfs-bench-uswest
- Zone: us-west1-a
- External IP: 34.53.6.80
- Peer ID: 12D3KooWCXhmcMv5KSvH4TewKCDuLX5iwQgsD2u9SVGptCvThpnE

**Europe Node**:
- Instance: ipfs-bench-europe
- Zone: europe-west1-b
- External IP: 35.241.220.165
- Peer ID: 12D3KooWB4NFmevZLHPX5SGdnD9NXztZtaHmHw9i14iCDUwkUFMj

### Academic Implications

This multi-region test demonstrates:

1. **Geographic Distance Effect**: Clear correlation between physical distance and IPFS transfer performance
   - Regional transfers (Tokyo): ~102 Mbps
   - Inter-continental transfers (Europe): ~17 Mbps
   - **~6x performance difference**

2. **Network Latency Impact**: Latency increases with distance significantly affect IPFS performance
   - Asia-Pacific region: Better performance (64-102 Mbps)
   - Trans-Pacific/Trans-continental: Degraded performance (17-34 Mbps)

3. **Real-World Deployment Considerations**:
   - For high-performance requirements, regional IPFS nodes are essential
   - Global content distribution via IPFS requires careful consideration of geographic replication
   - Cache warming strategies become critical for distant regions

### Notes
- All tests used unique 10MB files with different CIDs
- Cache was cleared (`ipfs repo gc`) before each download test
- Direct P2P connections were established before testing
- All nodes used identical hardware (n1-standard-2)
- Tests represent baseline IPFS performance without network throttling
