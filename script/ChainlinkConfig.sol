// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { VRFCoordinatorV2PlusMock } from "../test/mocks/VRFCoordinatorV2PlusMock.sol";

contract ChainlinkConfig {
    struct NetworkConfig {
        uint256 subscriptionId;
        address vrfCoordinator;
        bytes32 keyHash;
    }

    mapping(uint256 => NetworkConfig) public chainIdToNetworkConfig;

    function getActiveNetworkChainlinkConfig() public returns (NetworkConfig memory activeNetworkConfig) {
        chainIdToNetworkConfig[137] = getPolygonConfig();
        chainIdToNetworkConfig[8453] = getBaseConfig();
        chainIdToNetworkConfig[42_161] = getArbitrumConfig();
        chainIdToNetworkConfig[31_337] = getAnvilEthConfig();
        chainIdToNetworkConfig[11_155_111] = getSepoliaEthConfig();
        chainIdToNetworkConfig[80_002] = getPolygonAmoyConfig();

        activeNetworkConfig = chainIdToNetworkConfig[block.chainid];

        if (activeNetworkConfig.vrfCoordinator == address(0)) revert("Chainlink VRF Coordinator required");
    }

    function getSepoliaEthConfig() internal pure returns (NetworkConfig memory networkConfig) {
        networkConfig = NetworkConfig({
            //  solhint-disable-next-line max-line-length
            subscriptionId: 64_336_788_156_056_022_578_152_949_903_769_173_775_874_862_968_421_238_424_076_813_306_884_208_832_258,
            vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae
        });
    }

    function getArbitrumConfig() internal pure returns (NetworkConfig memory networkConfig) {
        networkConfig = NetworkConfig({
            //  solhint-disable-next-line max-line-length
            subscriptionId: 71_129_791_559_647_049_751_166_775_094_489_245_575_269_316_441_732_220_439_993_240_353_092_676_987_328,
            vrfCoordinator: 0x3C0Ca683b403E37668AE3DC4FB62F4B29B6f7a3e,
            // 150 gwei key hash
            keyHash: 0xe9f223d7d83ec85c4f78042a4845af3a1c8df7757b4997b815ce4b8d07aca68c
        });
    }

    function getPolygonConfig() internal pure returns (NetworkConfig memory networkConfig) {
        networkConfig = NetworkConfig({
            //  solhint-disable-next-line max-line-length
            subscriptionId: 52_174_578_717_677_442_198_027_907_440_749_619_567_260_199_112_121_017_504_473_047_006_148_103_495_917,
            vrfCoordinator: 0xec0Ed46f36576541C75739E915ADbCb3DE24bD77,
            // 500 gwei key hash
            keyHash: 0x719ed7d7664abc3001c18aac8130a2265e1e70b7e036ae20f3ca8b92b3154d86
        });
    }

    function getBaseConfig() internal pure returns (NetworkConfig memory networkConfig) {
        networkConfig = NetworkConfig({
            //  solhint-disable-next-line max-line-length
            subscriptionId: 81_329_362_586_917_986_816_753_857_554_443_823_328_068_912_955_405_746_084_377_039_695_378_029_689_412,
            vrfCoordinator: 0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634,
            // 30 gwei Key Hash
            keyHash: 0xdc2f87677b01473c763cb0aee938ed3341512f6057324a584e5944e786144d70
        });
    }

    function getPolygonAmoyConfig() internal pure returns (NetworkConfig memory networkConfig) {
        networkConfig = NetworkConfig({
            //  solhint-disable-next-line max-line-length
            subscriptionId: 66_432_537_676_828_968_029_875_447_158_564_913_588_950_144_180_196_515_935_983_839_759_248_927_220_038,
            vrfCoordinator: 0x343300b5d84D444B2ADc9116FEF1bED02BE49Cf2,
            // 500 gwei key hash
            keyHash: 0x816bedba8a50b294e5cbd47842baf240c2385f2eaf719edbd4f250a137a8c899
        });
    }

    function getAnvilEthConfig() internal returns (NetworkConfig memory networkConfig) {
        address vrfCoordinator;

        if (block.chainid == 31_337) {
            vrfCoordinator = address(new VRFCoordinatorV2PlusMock(0.01 ether, 1_000_000_000));
        }

        networkConfig = NetworkConfig({
            subscriptionId: 0,
            vrfCoordinator: vrfCoordinator, // This is a mock
            keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae
        });
    }
}
