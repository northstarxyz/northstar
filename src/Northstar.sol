// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

///@title Northstar
///@custom:version 0.0
///@author ts0yu
///@notice Northstar is a permissionless curation and derivatives protocol.
contract Northstar is ERC20 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    ///@notice Emitted when the wrong price is sent.
    error Northstar__WrongValueSent();

    ///@notice Emitted when the listing is not found.
    error Northstar__ListingNotFound();

    ///@notice Counter for the next sales index.
    uint256 public currentId = 1;

    ///@notice Represents a token listing.
    struct Listing {
        ///@custom:member Contract of the listed token.
        ERC721 tokenContract;
        ///@custom:member ID of the listed token.
        uint256 tokenId;
        ///@custom:member Owner of the token.
        address owner;
        ///@custom:member Price of the token.
        uint128 price;
        ///@custom:member Curation fee in basis points.
        uint8 fee;
    }

    ///@notice Represents an alloction - a claim to a percentage of a tokens payoff.
    struct Allocation {
        ///@custom:member The position of the allocation.
        ///@dev Note that allocations are position dependent, not time dependent.
        ///@dev We can probably pack this pending a decision on token supply.
        uint256 position;
        ///@custom:member The amount allocated.
        ///@dev Equally, we can pack this as well pending a decision on token supply.
        uint256 amount;
        ///@custom:member Address responsible for the allocation, and the address to recieve the payoff.
        address curator;
    }

    ///@notice Maps an ID to a listing.
    mapping(uint256 => Listing) public listings;

    ///@notice Maps a hashed `tokenContract` and `tokenId` to an allocation.
    ///@dev keccak256(abi.encodePacked(tokenContract, tokenId))
    mapping(bytes32 => Allocation[]) public allocations;

    ///@notice Initialize the contract, and create the underlying token.
    constructor() ERC20("Northstar", "NRTH", 18) {}

    ///@notice List an ERC721 token for curation, and sale.
    ///@param tokenContract Contract of the token to list.
    ///@param tokenId Token ID of the token to list.
    ///@param price Listing price.
    ///@param fee Curation fee.
    function list(ERC721 tokenContract, uint256 tokenId, uint128 price, uint8 fee) external payable returns (uint256) {
        listings[currentId] =
            Listing({tokenContract: tokenContract, tokenId: tokenId, price: price, owner: msg.sender, fee: fee});

        tokenContract.transferFrom(msg.sender, address(this), tokenId);

        return currentId++;
    }

    ///@notice Purchase a listed ERC721 token and distribute curation fee.
    ///@param listingId ID of the listing to buy.
    function buy(uint256 listingId) external payable {
        Listing memory listing = listings[listingId];

        if (listing.owner == address(0)) revert Northstar__ListingNotFound();
        if (listing.price != msg.value) revert Northstar__WrongValueSent();

        delete listings[listingId];

        SafeTransferLib.safeTransferETH(listing.owner, listing.price);
        listing.tokenContract.transferFrom(address(this), msg.sender, listing.tokenId);
    }

    ///@notice Allocate some NRTH tokens, and recieve a payoff dependent on the curation fee.
    function allocate(bytes32 listing, uint256 amount) external {
        SafeTransferLib.safeTransferFrom(ERC20(address(this)), msg.sender, address(this), amount);

        allocations[listing].push(
            Allocation({position: allocations[listing].length, amount: amount, curator: msg.sender})
        );
    }

    ///@notice Remove an allocation of NRTH tokens, and remove your payoff claim.
    function deallocate(bytes32 listing, uint256 amount) external {
        SafeTransferLib.safeTransferFrom(ERC20(address(this)), address(this), msg.sender, amount);
        Allocation[] memory currentAllocations = allocations[listing];

        for (uint256 i = 0; i < currentAllocations.length; ++i) {
            if (currentAllocations[i].curator == msg.sender) {
                if (allocations[listing][i].amount == amount) {
                    delete allocations[listing][i];
                }
                allocations[listing][i].amount -= amount;
                break;
            }
        }
    }
}
