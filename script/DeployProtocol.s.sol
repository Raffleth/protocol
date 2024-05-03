// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Raffl } from "../src/Raffl.sol";
import { RafflFactory } from "../src/RafflFactory.sol";

import { BaseScript } from "./Base.s.sol";
import { ChainlinkConfig } from "./ChainlinkConfig.sol";

contract DeployProtocol is BaseScript, ChainlinkConfig {
    function run() public broadcast returns (Raffl implementation, RafflFactory factory) {
        // Get Chainlink Config
        ChainlinkConfig.NetworkConfig memory chainlinkConfig = getActiveNetworkChainlinkConfig();

        // Instantiate the implementation
        implementation = new Raffl();

        // Fee Collector Address
        address feeCollectorAddress = vm.envAddress("FEE_COLLECTOR_ADDRESS");

        // Fee values
        uint64 feePercentage = uint64(vm.envUint("FEE_PERCENTAGE"));
        uint64 feePenality = uint64(vm.envUint("FEE_PENALITY"));

        // Instantiate the Factory
        factory = new RafflFactory(
            address(implementation),
            feeCollectorAddress,
            feePercentage,
            feePenality,
            chainlinkConfig.vrfCoordinator,
            chainlinkConfig.keyHash,
            chainlinkConfig.subscriptionId
        );
    }
}
