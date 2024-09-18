// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

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
        uint64 creationFeeValue = uint64(vm.envUint("CREATION_FEE_VALUE"));
        uint64 poolFeePercentage = uint64(vm.envUint("POOL_FEE_PERCENTAGE"));

        // Instantiate the Factory
        factory = new RafflFactory(
            address(implementation),
            feeCollectorAddress,
            creationFeeValue,
            poolFeePercentage,
            chainlinkConfig.vrfCoordinator,
            chainlinkConfig.keyHash,
            chainlinkConfig.subscriptionId
        );
    }
}
