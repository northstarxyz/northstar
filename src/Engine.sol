// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {wadLn} from "solmate/utils/SignedWadMath.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

///@title          Northstar
///@notice         Perpetual, binary non-fungible token derivatives.
///@author         ts0yu
///@custom:version 0.0
contract Engine is ERC20 {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                  STATE
    //////////////////////////////////////////////////////////////*/

    ///@notice ID of the current listing.
    uint256 public currentId;

    ///@notice Represents an allocation of signal tokens to a listing.
    struct Allocation {
        ///@custom:member Address of the curator / allocator.
        address curator;
        ///@custom:member Amount allocated.
        uint256 amount;
    }

    ///@notice A listing that can be allocated to and also bought.
    struct Listing {
        ///@custom:member Contract of the underlying ERC721 token.
        ERC721 tokenContract;
        ///@custom:member Token ID of the underlying ERC721 token.
        uint256 tokenId;
        ///@custom:member Owner of the listing.
        address owner;
        ///@custom:member Price (in ETH) of the listing.
        uint128 price;
        ///@custom:member Basis point representation of the curation fee.
        uint128 fee;
        ///@custom:member Current position of the allocations.
        uint256 allocationId;
        ///@custom:member Sum of the weighted allocations.
        ///TODO: how tf do we actually explain this
        uint256 allocationSum;
    }

    ///@notice Maps a listing ID to a listing.
    mapping(uint256 => Listing) public listings;

    ///@notice Maximum claimable amount for an address.
    mapping(address => uint256) public balances;

    ///@notice Maps a listing ID to a mapping of allocation positions and their corresponding allocations.
    mapping(uint256 => mapping(uint256 => Allocation)) public allocations;

    /*//////////////////////////////////////////////////////////////
                               DIAGNOSTIC
    //////////////////////////////////////////////////////////////*/

    error Northstar__InvalidListing();
    error Northstar__InvalidListingPrice();
    error Northstar__InvalidWithdrawalAmount();

    event Northstar__List(uint256 indexed listingId);
    event Northstar__Buy(uint256 indexed listingId);
    event Northstar__Allocate(uint256 indexed listingId, uint256 indexed amount);
    event Northstar__Claim(uint256 indexed amount, address indexed from);

    /*//////////////////////////////////////////////////////////////
                                INTERFACE
    //////////////////////////////////////////////////////////////*/

    ///@notice Initialize the contract, and the signal token.
    ///@param controller Address to mint signal tokens to.
    constructor(address controller) ERC20("Northstar", "NRTH", 18) {
        // Figure out some distribution mechanism.
        _mint(controller, 100000);
    }

    ///@notice List an ERC721 token.
    ///@param tokenContract Contract of the ERC721 token.
    ///@param tokenId Token ID of the ERC721 token.
    ///@param price Price of the listing in ETH.
    ///@param fee Curation fee in basis points to initialize the listing with.
    function list(ERC721 tokenContract, uint256 tokenId, uint128 price, uint128 fee)
        external
        payable
        returns (uint256)
    {
        listings[currentId] = Listing({
            tokenContract: tokenContract,
            tokenId: tokenId,
            price: price,
            owner: msg.sender,
            fee: fee,
            allocationId: 0,
            allocationSum: 0
        });

        tokenContract.transferFrom(msg.sender, address(this), tokenId);

        emit Northstar__List(currentId);

        return currentId++;
    }

    ///@notice Buy a listing.
    ///@param listingId Listing to purchase.
    function buy(uint256 listingId) external payable {
        Listing memory listing = listings[listingId];

        if (listing.owner == address(0)) revert Northstar__InvalidListing();
        if (listing.price != msg.value) revert Northstar__InvalidListingPrice();

        delete listings[listingId];

        uint256 curationFee = (listing.fee / 10000) * listing.price;

        SafeTransferLib.safeTransferETH(listing.owner, listing.price - curationFee);

        _updateBalances(listingId);

        emit Northstar__Buy(currentId);

        listing.tokenContract.transferFrom(address(this), msg.sender, listing.tokenId);
    }

    ///@notice Allocate to a listing.
    ///@param listingId Listing to allocate to.
    ///@param amount Amount of signal token to allocate to the listing.
    function allocate(uint256 listingId, uint256 amount) external {
        Listing memory listing = listings[listingId];

        SafeTransferLib.safeTransferFrom(ERC20(address(this)), msg.sender, address(this), amount);

        uint256 nextPosition = listing.allocationId += 1;

        listings[listingId].allocationSum += (nextPosition + (amount / 1000));
        allocations[listingId][nextPosition] = Allocation({curator: msg.sender, amount: amount});

        emit Northstar__Allocate(listingId, amount);
    }

    ///@notice Claim payoffs from allocation.
    ///@param amount Amount to claim.
    function claim(uint256 amount) external {
        _withdraw(amount, msg.sender);

        emit Northstar__Claim(amount, msg.sender);
    }

    ///@notice Claim all payoffs.
    function claimAll() external {
        uint256 totalBalance = balances[msg.sender];

        // This is inefficient as we are accessing the same mapping twice when we can do it once.
        _withdraw(totalBalance, msg.sender);

        emit Northstar__Claim(totalBalance, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    ///@notice Iterate through the allocations and update the balances of each curator accordingly.
    ///@param listingId Listing to update.
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

    ///@notice Get the payoff of an allocation.
    ///@param position Position of the allocation.
    ///@param amount Amount of signal token allocated.
    ///@param sum Sum of all weighted allocations.
    ///@dev Position 1 is the first allocator, position n is the nth.
    ///@dev The sum should be equivalent to: sum(position + (amount / 1000))
    function _getPayoff(uint256 position, uint256 amount, uint256 sum) internal pure returns (uint256) {
        int256 numerator = wadLn(int256((position * 1e18) + (amount / 1000)));
        int256 denominator = wadLn(int256(sum) * 1e18);

        uint256 payoff = uint256(numerator / denominator);

        return payoff;
    }

    ///@notice Withdraw a specified amount from a specific balance and transfer it to the withdrawee(?).
    ///@param amount Amount to withdraw.
    ///@param to Address to transfer withdrawal to.
    function _withdraw(uint256 amount, address to) internal {
        uint256 currentBalance = balances[to];

        if (amount > currentBalance) revert Northstar__InvalidWithdrawalAmount();

        balances[msg.sender] -= amount;
        SafeTransferLib.safeTransferFrom(ERC20(address(this)), address(this), to, amount);
    }
}
