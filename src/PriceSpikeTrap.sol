// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title SimplePriceSpikeTrap
/// @notice Drosera-compatible trap that detects a sudden price spike.
/// @dev Input format: [p0, p1, ..., pn], where each entry is a price sample.
contract SimplePriceSpikeTrap {
    /// @notice threshold in basis points (1 bps = 0.01%); e.g. 1000 = 10%
    uint256 public immutable thresholdBps;

    constructor(uint256 _thresholdBps) {
        require(_thresholdBps > 0, "threshold > 0");
        thresholdBps = _thresholdBps;
    }

    /// @notice Called by Drosera operator with price history array.
    /// @param collect an array of recent price samples (oldest -> newest)
    /// @return true if latest sample deviates too much from average of prior samples
    function shouldRespond(uint256[] calldata collect) external view returns (bool) {
        uint256 len = collect.length;
        if (len < 3) return false; // need at least 3 samples

        // compute average of all but last sample
        uint256 sum = 0;
        for (uint256 i = 0; i < len - 1; ++i) {
            sum += collect[i];
        }
        uint256 avg = sum / (len - 1);

        uint256 latest = collect[len - 1];
        if (avg == 0 || latest == 0) return false; // invalid data

        // compute absolute difference in basis points
        uint256 diff = avg > latest ? avg - latest : latest - avg;
        uint256 diffBps = (diff * 10000) / avg;

        return diffBps >= thresholdBps;
    }
}

