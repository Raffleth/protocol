// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { VRFCoordinatorV2PlusMock } from "../test/mocks/VRFCoordinatorV2PlusMock.sol";

contract ChainlinkConfig {
    struct NetworkConfig {
        uint256 subscriptionId;
        address vrfCoordinator;
        bytes32 keyHash;
    }

    mapping(uint256 => NetworkConfig) public chainIdToNetworkConfig;

    function getActiveNetworkChainlinkConfig() public returns (NetworkConfig memory activeNetworkConfig) {
        chainIdToNetworkConfig[11_155_111] = getSepoliaEthConfig();
        chainIdToNetworkConfig[31_337] = getAnvilEthConfig();

        activeNetworkConfig = chainIdToNetworkConfig[block.chainid];

        if (activeNetworkConfig.vrfCoordinator == address(0)) revert("Chainlink VRF Coordinator required");
    }

    function getSepoliaEthConfig() internal pure returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            //  solhint-disable-next-line max-line-length
            subscriptionId: 64_336_788_156_056_022_578_152_949_903_769_173_775_874_862_968_421_238_424_076_813_306_884_208_832_258,
            vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae
        });
    }

    function getAnvilEthConfig() internal returns (NetworkConfig memory anvilNetworkConfig) {
        address vrfCoordinator = address(new VRFCoordinatorV2PlusMock(0.01 ether, 1_000_000_000));

        anvilNetworkConfig = NetworkConfig({
            subscriptionId: 0,
            vrfCoordinator: vrfCoordinator, // This is a mock
            keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae
        });
    }
}
