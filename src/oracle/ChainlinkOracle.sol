// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ChainlinkOracle is IPriceOracle, Ownable {
    struct FeedCfg {
        AggregatorV3Interface feed;
    }

    mapping(address => FeedCfg) public s_cfg; // asset => config

    event FeedSet(address indexed asset, address indexed feed);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setFeed(address asset, address feed) external onlyOwner {
        require(asset != address(0) && feed != address(0), "asset=0");
        s_cfg[asset] = FeedCfg({feed: AggregatorV3Interface(feed)});
        emit FeedSet(asset, feed);
    }

    function latestAnswer(address asset) external view override returns (int256) {
        AggregatorV3Interface f = s_cfg[asset].feed;
        require(address(f) != address(0), "no feed");
        (, int256 answer,,,) = f.latestRoundData();
        return answer; // typically 1e8
    }

    function decimals(address asset) external view override returns (uint8) {
        AggregatorV3Interface f = s_cfg[asset].feed;
        require(address(f) != address(0), "no feed");
        return f.decimals();
    }
}
