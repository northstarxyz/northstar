// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from 'forge-std/Test.sol';
import {Northstar} from '../src/Northstar.sol';
import {ERC20} from 'solmate/tokens/ERC20.sol';
import {ERC721} from 'solmate/tokens/ERC721.sol';

// Snippet from m1guelpf's Lil Web3.
contract TestNFT is ERC721('Test NFT', 'TEST') {
	uint256 public tokenId = 1;

	function tokenURI(uint256) public pure override returns (string memory) {
		return 'test';
	}

	function mint() public payable returns (uint256) {
		_mint(msg.sender, tokenId);

		return tokenId++;
	}
}

contract NorthstarTest is Test {
    uint256 public id;
    uint256 public listingId;

    Northstar public northstar;
    TestNFT internal listing;

    function setUp() public {
        northstar = new Northstar(msg.sender);
        listing = new TestNFT();

        listing.setApprovalForAll(address(northstar), true);

        id = listing.mint();
    }

    function testListing() public {
        listingId = northstar.list(listing, id, 1 ether, 500);
    }
}