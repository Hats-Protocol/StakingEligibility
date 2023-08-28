// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

struct AddressSet {
  address[] addrs;
  mapping(address => bool) saved;
}

library LibAddressSet {
  function add(AddressSet storage s, address addr) internal {
    if (!s.saved[addr]) {
      s.addrs.push(addr);
      s.saved[addr] = true;
    }
  }

  function contains(AddressSet storage s, address addr) internal view returns (bool) {
    return s.saved[addr];
  }

  function count(AddressSet storage s) internal view returns (uint256) {
    return s.addrs.length;
  }
}
