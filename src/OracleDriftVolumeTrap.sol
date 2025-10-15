// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Trap} from "drosera-contracts/Trap.sol";

interface IAggregatorV3 {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

contract OracleDriftVolumeTrap is Trap {
    // Configurable addresses (set at deployment)
    IAggregatorV3 public primaryAggregator;   // e.g., Chainlink primary
    IAggregatorV3 public fallbackAggregator;  // e.g., another Chainlink / aggregator
    address public trackedPair;               // optional: dex pair or token to inspect for volume
    uint256 public divergenceThresholdBP;     // basis points (e.g., 500 = 5%)
    uint256 public volumeThreshold;           // raw units (depends on what trackedPair collects)
    uint256 public requireCounts;             // how many recent samples must meet condition to fire

    struct CollectOutput {
        uint256 primaryPrice;    // scaled to 1e18
        uint256 fallbackPrice;   // scaled to 1e18
        uint256 volumeMetric;    // e.g., token amount swapped in this block or transfers (raw)
        uint256 blockTimestamp;
    }

    constructor(
        address _primaryAggregator,
        address _fallbackAggregator,
        address _trackedPair,
        uint256 _divergenceThresholdBP,
        uint256 _volumeThreshold,
        uint256 _requireCounts
    ) {
        primaryAggregator = IAggregatorV3(_primaryAggregator);
        fallbackAggregator = IAggregatorV3(_fallbackAggregator);
        trackedPair = _trackedPair;
        divergenceThresholdBP = _divergenceThresholdBP;
        volumeThreshold = _volumeThreshold;
        requireCounts = _requireCounts;
    }

    /// @notice collect() is called per-block by node operators; keep it view-only and cheap.
    function collect() external view override returns (bytes memory) {
        // Read primary aggregator
        (, int256 primaryAnswer, , uint256 pUpdatedAt, ) = primaryAggregator.latestRoundData();
        (, int256 fallbackAnswer, , uint256 fUpdatedAt, ) = fallbackAggregator.latestRoundData();

        // normalize to uint256 and 1e18 scale (assumes aggregator gives price in some decimals; caller must deploy with matching oracles)
        uint256 p = primaryAnswer < 0 ? 0 : uint256(primaryAnswer);
        uint256 f = fallbackAnswer < 0 ? 0 : uint256(fallbackAnswer);

        // Placeholder volume metric:
        // For maximal compatibility, we read a simple on-chain metric.
        // If trackedPair is an ERC20 pair with event-based volume, the Drosera operator's collect could supply off-chain aggregated volume,
        // but here we attempt an on-chain heuristic: sum of last-block transfers is impractical on-chain in a cheap view.
        // So contract exposes trackedPair as an address and expects indexer or tooling to write a volume into the trap via off-chain transforms.
        // For this example, we'll set volumeMetric = 0 (operator-side can augment)  collecting some on-chain proxy is possible if the pair stores accumulators.
        uint256 volumeMetric = 0;

        return abi.encode(CollectOutput({
            primaryPrice: p,
            fallbackPrice: f,
            volumeMetric: volumeMetric,
            blockTimestamp: block.timestamp
        }));
    }

    /// @notice shouldRespond is given an array of `collect` outputs (most recent first at index 0)
    function shouldRespond(bytes[] calldata data)
    external
    pure
    override
    returns (bool, bytes memory)
{{
        uint256 len = data.length;
        if (len == 0) {
            return (false, abi.encodePacked(uint8(0)));
        }

        uint256 triggerCount = 0;

        for (uint256 i = 0; i < len; i++) {
            CollectOutput memory c = abi.decode(data[i], (CollectOutput));

            // Avoid division by zero; skip noisy or stale points
            if (c.primaryPrice == 0 || c.fallbackPrice == 0) {
                continue;
            }

            // compute absolute difference and basis points divergence scaled using 1e18 base
            uint256 diff = c.primaryPrice > c.fallbackPrice ? c.primaryPrice - c.fallbackPrice : c.fallbackPrice - c.primaryPrice;
            // divergenceBP = (diff * 10000) / min(price)
            uint256 minP = c.primaryPrice < c.fallbackPrice ? c.primaryPrice : c.fallbackPrice;
            uint256 divergenceBP = (diff * 10000) / minP;

            // Check divergence AND volume metric
            bool divergenceOK = divergenceBP >= divergenceThresholdBP;
            bool volumeOK = c.volumeMetric >= volumeThreshold;

            if (divergenceOK && volumeOK) {
                triggerCount += 1;
            }
        }

        if (triggerCount >= requireCounts) {
            // Build context for response: include latest primary/fallback and triggerCount
            CollectOutput memory latest = abi.decode(data[0], (CollectOutput));
            return (true, abi.encode(latest.primaryPrice, latest.fallbackPrice, latest.volumeMetric, triggerCount));
        }

        return (false, abi.encode(uint8(0)));
    }
}

