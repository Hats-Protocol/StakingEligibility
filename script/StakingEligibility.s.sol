// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Script, console2 } from "forge-std/Script.sol";
import { StakingEligibility } from "src/StakingEligibility.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { HatsModuleFactory, deployModuleInstance } from "hats-module/utils/DeployFunctions.sol";

contract DeployImplementation is Script {
  StakingEligibility public implementation;
  bytes32 public SALT = bytes32(abi.encode(0x4a75)); // ~ H(4) A(a) T(7) S(5)

  // default values
  string public version = "0.1.0"; // increment with each deploy
  bool private verbose = true;

  /// @notice Override default values, if desired
  function prepare(string memory _version, bool _verbose) public {
    version = _version;
    verbose = _verbose;
  }

  function run() public {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);
    vm.startBroadcast(deployer);

    // deploy the implementation
    implementation = new StakingEligibility{ salt: SALT}(version);

    vm.stopBroadcast();

    if (verbose) {
      console2.log("Implementation:", address(implementation));
    }
  }
}

contract DeployInstance is Script {
  address public implementation = 0xfFc3eFab7EeA6fe08B3A9FdE1F95B21683DdE869; // goerli
  address public instance;
  bytes public otherImmutableArgs;
  bytes public initData;
  address public token = 0xaFF4481D10270F50f203E0763e2597776068CBc5; // goerli, WEENUS
  HatsModuleFactory public factory = HatsModuleFactory(0x696DBABd781D0e90b833968cF5C36C405772D4EA); // goerli, v0.1.0
  uint256 public minStake = 1 ether;
  uint256 public stakerHat = 0x00000060_0001_0003_0003_0001_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000; // 96.1.3.3.1
    // Arbitrator
  uint256 public judgeHat = 0x00000060_0001_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000; // 96.1
    // Demo Admin Hat
  uint256 public recipientHat = 0x00000060_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000; // 96
    // Demo DAO
  uint256 public cooldownPeriod = 5 minutes;

  bool private verbose = true;

  function run() public {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);
    vm.startBroadcast(deployer);

    // encode the other immutable args
    otherImmutableArgs = abi.encodePacked(token);
    // encode the init data
    initData = abi.encode(minStake, judgeHat, recipientHat, cooldownPeriod);
    // deploy the instance
    instance = deployModuleInstance(factory, implementation, stakerHat, otherImmutableArgs, initData);

    vm.stopBroadcast();

    if (verbose) {
      console2.log("Instance:", instance);
    }
  }
}

// forge script script/StakingEligibility.s.sol:DeployInstance -f goerli --broadcast --verify
