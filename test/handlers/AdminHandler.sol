// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2, DSTest, TestBase, StdCheats, StdUtils } from "forge-std/Test.sol";
import { StakingEligibility, IERC20 } from "src/StakingEligibility.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { AddressSet, LibAddressSet } from "test/handlers/LibHandler.sol";

interface IAdminHandler {
  function changeMinStake(uint248 _newMinStake) external;
  function changeCooldownPeriod(uint256 _newCooldownPeriod) external;
  function changeJudgeHat(uint256 _newJudgeHat) external;
  function changeRecipientHat(uint256 _newRecipientHat) external;
  function numCalls(bytes32 _func) external returns (uint256);
}

contract AdminHandler is IAdminHandler, TestBase, DSTest, StdCheats, StdUtils {
  using LibAddressSet for AddressSet;

  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  StakingEligibility public immutable se;
  IHats public immutable HATS;

  /*//////////////////////////////////////////////////////////////
                            GHOST VARS
  //////////////////////////////////////////////////////////////*/

  // call tracker
  mapping(bytes32 => uint256) public numCalls;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(StakingEligibility _se) {
    se = _se;
    HATS = se.HATS();
  }

  /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function changeMinStake(uint248 _newMinStake) public virtual countCall {
    vm.prank(msg.sender);
    se.changeMinStake(_newMinStake);

    console2.log("changeMinStake to", _newMinStake);
  }

  function changeCooldownPeriod(uint256 _newCooldownPeriod) public virtual countCall {
    vm.prank(msg.sender);
    se.changeCooldownPeriod(_newCooldownPeriod);

    console2.log("changeCooldownPeriod to", _newCooldownPeriod);
  }

  function changeJudgeHat(uint256 _newJudgeHat) public virtual countCall {
    vm.prank(msg.sender);
    se.changeJudgeHat(_newJudgeHat);

    console2.log("changeJudgeHat to", _newJudgeHat);
  }

  function changeRecipientHat(uint256 _newRecipientHat) public virtual countCall {
    vm.prank(msg.sender);
    se.changeRecipientHat(_newRecipientHat);

    console2.log("changeRecipientHat to", _newRecipientHat);
  }

  /*//////////////////////////////////////////////////////////////
                            CALL ACCOUNTING
  //////////////////////////////////////////////////////////////*/

  modifier countCall() {
    numCalls[msg.sig]++;
    _;
  }
}

contract BoundedAdminHandler is AdminHandler {
  constructor(StakingEligibility _se) AdminHandler(_se) { }

  function changeMinStake(uint248 _newMinStake) public override countCall {
    // mock msg.sender as the admin
    vm.mockCall(
      address(HATS), abi.encodeWithSelector(IHats.isAdminOfHat.selector, msg.sender, se.hatId()), abi.encode(true)
    );
    super.changeMinStake(_newMinStake);
  }

  function changeCooldownPeriod(uint256 _newCooldownPeriod) public override countCall {
    _newCooldownPeriod = bound(_newCooldownPeriod, 1, 730 days);

    // mock msg.sender as the admin
    vm.mockCall(
      address(HATS), abi.encodeWithSelector(IHats.isAdminOfHat.selector, msg.sender, se.hatId()), abi.encode(true)
    );

    super.changeCooldownPeriod(_newCooldownPeriod);
  }

  function changeJudgeHat(uint256 _newJudgeHat) public override countCall {
    // mock msg.sender as the admin
    vm.mockCall(
      address(HATS), abi.encodeWithSelector(IHats.isAdminOfHat.selector, msg.sender, se.hatId()), abi.encode(true)
    );

    super.changeJudgeHat(_newJudgeHat);
  }

  function changeRecipientHat(uint256 _newRecipientHat) public override countCall {
    // mock msg.sender as the admin
    vm.mockCall(
      address(HATS), abi.encodeWithSelector(IHats.isAdminOfHat.selector, msg.sender, se.hatId()), abi.encode(true)
    );

    super.changeRecipientHat(_newRecipientHat);
  }
}
