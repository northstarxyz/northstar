// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {Test} from "forge-std/Test.sol";
import {Engine} from "../src/Engine.sol";


import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

// Snippet from m1guelpf's Lil Web3.
contract TestNFT is ERC721("Test NFT", "TEST") {
    uint256 public tokenId = 1;

    function tokenURI(uint256) public pure override returns (string memory) {
        return "test";
    }

    function mint() public payable returns (uint256) {
        _mint(msg.sender, tokenId);

        return tokenId++;
    }
}

contract EngineTest is Test {
    uint256 public id;
    uint256 public listingId;

    Engine public northstar;
    TestNFT internal listing;
    Vm internal hevm = Vm(HEVM_ADDRESS);

    function setUp() public {
        northstar = new Engine(msg.sender);
        listing = new TestNFT();

        listing.setApprovalForAll(address(northstar), true);

        id = listing.mint();
    }

    function testListingCreation(uint128 _price, uint128 _fee) public {
        assertEq(listing.ownerOf(id), address(this));

        listingId = northstar.list(listing, id, _price, _fee);

        (
            ERC721 tokenContract,
            uint256 tokenId,
            address owner,
            uint128 price,
            uint128 fee,
            uint256 allocationId,
            uint256 allocationSum
        ) = northstar.listings(listingId);

        assertEq(address(tokenContract), address(listing));
        assertEq(tokenId, id);
        assertEq(owner, address(this));
        assertEq(price, _price);
        assertEq(fee, _fee);
        assertEq(allocationId, 0);
        assertEq(allocationSum, 0);
    }

    function testNonOwnerCannotList(uint128 _price, uint128 _fee) public {
        hevm.prank(address(0x00000000));
        hevm.expectRevert("WRONG_FROM");

        listingId = northstar.list(listing, id, _price, _fee);
    }

    function testCannotListWithoutApproval(uint128 _price, uint128 _fee) public {
        listing.setApprovalForAll(address(northstar), false);

        hevm.expectRevert("NOT_AUTHORIZED");

        listingId = northstar.list(listing, id, _price, _fee);
    }

    function testAllocate(uint256 _amount, uint128 _price, uint128 _fee) public {
        vm.assume(_amount <= northstar.balanceOf(address(this)));

        (,,,,, uint256 allocationId, uint256 allocationSum) = northstar.listings(listingId);

        listingId = northstar.list(listing, id, _price, _fee);
        northstar.allocate(listingId, _amount);

        (,,,,, uint256 newAllocationId, uint256 newAllocationSum) = northstar.listings(listingId);
        (address curator, uint256 amount) = northstar.allocations(listingId, newAllocationId);

        assertEq(newAllocationId, allocationId += 1);
        assertEq(curator, address(this));
        assertEq(allocationSum += (newAllocationId + (_amount / 1000)), newAllocationSum);
        assertEq(amount, _amount);
    }

    function testCannotAllocateOverBalance(uint256 _amount, uint128 _price, uint128 _fee) public {
        vm.assume(_amount > northstar.balanceOf(address(this)));

        listingId = northstar.list(listing, id, _price, _fee);

        hevm.expectRevert("TRANSFER_FROM_FAILED");

        northstar.allocate(listingId, _amount);
    }
}
