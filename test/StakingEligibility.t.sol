// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { StakingEligibility, IERC20 } from "src/StakingEligibility.sol";
import { DeployImplementation } from "script/StakingEligibility.s.sol";
import { HatsModuleFactory, IHats } from "hats-module/HatsModuleFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingEligibilityTest is Test, DeployImplementation { }
