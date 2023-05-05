// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Script, console2 } from "forge-std/Script.sol";
import { StakingEligibility } from "../src/StakingEligibility.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Deploy is Script {
  StakingEligibility public se;
  bytes32 public SALT = keccak256("lets add some salt to this meal");

  // default values
  bool private verbose = true;
  IERC20 public token;
  uint248 public minStake;
  uint256 public judgeHat;
  uint256 public recipientHat;

  /// @notice Override default values, if desired
  function prepare(bool _verbose) public {
    verbose = _verbose;
  }

  function run() public {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);
    vm.startBroadcast(deployer);

    se = new StakingEligibility{ salt: SALT}(token, minStake, judgeHat, recipientHat);

    vm.stopBroadcast();

    if (verbose) {
      console2.log("Counter:", address(se));
    }
  }
}

// forge script script/Deploy.s.sol -f ethereum --broadcast --verify
