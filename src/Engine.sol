// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {wadLn} from "solmate/utils/SignedWadMath.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract Engine is ERC20 {
    using SafeTransferLib for ERC20;

    uint256 public currentId;

    struct Allocation {
        address curator;
        uint256 amount;
    }

    struct Listing {
        ERC721 tokenContract;
        uint256 tokenId;
        address owner;
        uint128 price;
        uint128 fee;
        uint256 allocationId;
        uint256 allocationSum;
    }

    mapping(uint256 => Listing) public listings;
    mapping(address => uint256) public balances;
    mapping(uint256 => mapping(uint256 => Allocation)) public allocations;
    
    constructor(address controller) ERC20("Northstar", "NRTH", 18) {
        _mint(controller, 100000);
    }

    function list(ERC721 tokenContract, uint256 tokenId, uint128 price, uint128 fee) external payable returns (uint256) {
        listings[currentId] =
            Listing({tokenContract: tokenContract, tokenId: tokenId, price: price, owner: msg.sender, fee: fee, allocationId: 0, allocationSum: 0});

        tokenContract.transferFrom(msg.sender, address(this), tokenId);

        return currentId++;
    }

    function buy(uint256 listingId) external payable {
        Listing memory listing = listings[listingId];

        if (listing.owner == address(0)) revert();
        if (listing.price != msg.value) revert();

        delete listings[listingId];

        uint256 curationFee = (listing.fee / 10000) * listing.price;
 
        SafeTransferLib.safeTransferETH(listing.owner, listing.price - curationFee);

        _updateBalances(listingId);

        listing.tokenContract.transferFrom(address(this), msg.sender, listing.tokenId);
    }    

    function allocate(uint256 listingId, uint256 amount) external {
        Listing memory listing = listings[listingId];

        SafeTransferLib.safeTransferFrom(ERC20(address(this)), msg.sender, address(this), amount);

        uint256 nextPosition = listing.allocationId += 1;

        listings[listingId].allocationSum += (nextPosition + (amount / 1000));
        allocations[listingId][nextPosition] = Allocation({curator: msg.sender, amount: amount});
    }

    function claim(uint256 amount) external {
        _withdraw(amount, msg.sender);
    }

    function claimAll() external {
        // this is inefficient as we are accessing the same mapping twice when we can do it once.
        _withdraw(balances[msg.sender], msg.sender);
    }

    function _updateBalances(uint256 listingId) internal {
        Listing memory listing = listings[listingId];

        uint256 currentPosition = listing.allocationId;

        for (uint256 position = 0; position <= currentPosition; ++position) {
            Allocation memory allocation = allocations[listingId][position];

            uint256 listingFee = (listing.fee / 10000) * listing.price;

            uint256 curationFee = listingFee * _getPayoff(position, allocation.amount, listing.allocationSum);

            balances[allocation.curator] += curationFee;
        }
    }

    function _getPayoff(uint256 position, uint256 amount, uint256 sum) internal pure returns (uint256) {
        int256 numerator = wadLn(int256((position * 1e18) + (amount / 1000)));
        int256 denominator = wadLn(int256(sum) * 1e18);

        uint256 payoff = uint256(numerator / denominator);

        return payoff;
    }

    function _withdraw(uint256 amount, address to) internal {
        uint256 currentBalance = balances[to];

        if (amount > currentBalance) revert();

        balances[msg.sender] -= amount;
        SafeTransferLib.safeTransferFrom(ERC20(address(this)), address(this), to, amount);        
    }
}