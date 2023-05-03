// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { IHatsEligibility } from "hats-protocol/Interfaces/IHatsEligibility.sol";
import { HatsAccessControl } from "hats-auth/HatsOwnedInitializable.sol";

contract StakingEligibility is IHatsEligibility, HatsAccessControl {
}
