// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import {
  StakingEligibility,
  StakingEligibilityFactory,
  StakingEligibilityFactoryTest
} from "../test/StakingEligibilityFactory.t.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingEligibilityTest is StakingEligibilityFactoryTest { }
