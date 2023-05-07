// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { StakingEligibility } from "../src/StakingEligibility.sol";
import { StakingEligibilityFactory } from "../src/StakingEligibilityFactory.sol";
import { Deploy } from "../script/StakingEligibility.s.sol";

contract StakingEligibilityFactoryTest is Deploy, Test {
  // variables inhereted from Deploy script
  // StakingEligibility public implementation;
  // StakingEligibilityFactory public factory;
  // IHats public constant hats = IHats(0x9D2dfd6066d5935267291718E8AA16C8Ab729E9d); // v1.hatsprotocol.eth
  // bytes32 public SALT = bytes32(abi.encode(0x4a75)); // ~ H(4) A(a) T(7) S(5)

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 16_947_805; // when v1.hatsprotocol.eth was deployed
  string public VERSION = "test version";

  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // deploy via the script
    Deploy.prepare(VERSION, false); // set to true to log deployment addresses
    Deploy.run();
  }
}

contract FactoryDeployTest is StakingEligibilityFactoryTest {
  function test_deploy() public {
    // // check that the implementation is deployed
    // assertTrue(address(implementation) != address(0), "implementation not deployed");
    // // check that the factory is deployed
    // assertTrue(address(factory) != address(0), "factory not deployed");
  }
}
