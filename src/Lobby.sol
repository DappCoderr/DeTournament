// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract Lobby is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Create tournament -> Admin
    // Join tournament
    // Cancel tournament -> Admin
    // Claim Refund

    // NFT as a badge

    // Leaderboard Calculation
    // Reward Distribution

    event NewTournamentIsCreated(uint256 indexed id, string indexed name, uint256 capacity, uint256 indexed entryFee);
    event TorunamentJoined(uint256 indexed tournamentId, address indexed player);
    event TorunamentCanceled(uint256 tournamentId);
    event ClaimRefund(uint256 indexed tournamentId, address indexed player, uint256 indexed amount);

    error Lobby__NOT_ADMIN();
    error Lobby__INVALID_TOURNAMENT();
    error Lobby__TOURNAMENT_FULL();
    error Lobby__TOURNAMENT_CLOSE(uint256 currentTime, uint256 tournamentEndTime);
    error Lobby__LOW_BALANCE();
    error Lobby__INCORRECT_TOKEN();
    error Lobby__ALREADY_JOINED();
    error Lobby__TOURNAMENT_CANCELLED();

    enum TorunamentStatus {
        Open,
        Close,
        Full,
        Completed,
        Cancelled
    }

    // torunament struct
    struct TorunamentDetail {
        uint256 poolId;
        string name;
        uint256 maxPlayer;
        uint256 entryFee;
        uint256 playersJoined;
        TorunamentStatus status;
        address wETH;
        uint256 startTime;
        uint256 duration;
    }

    TorunamentDetail[] public _tournaments;

    receive() external payable {}
    fallback() external payable {}

    mapping(uint256 => mapping(address => bool)) private tournamentParticipated;
    mapping(address => uint256[]) private userTournamentHistory;
    mapping(address => bool) private hasClaimedRefund;

    uint256 private tournamentId = 1;
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    constructor() {
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function createTournament(string calldata _name, uint256 _capacity, uint256 _entryFee, address _wETHAddress)
        external
    {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert Lobby__NOT_ADMIN();

        if (_wETHAddress == address(0)) revert Lobby__INCORRECT_TOKEN();

        _tournaments.push(
            TorunamentDetail(
                tournamentId,
                _name,
                _capacity,
                _entryFee,
                0,
                TorunamentStatus.Open,
                _wETHAddress,
                block.timestamp,
                20 minutes
            )
        );
        tournamentId++;

        emit NewTournamentIsCreated(tournamentId, _name, _capacity, _entryFee);
    }

    function joinTournament(uint256 _tournamentId, address user) external payable {
        if (_tournamentId >= _tournaments.length) revert Lobby__INVALID_TOURNAMENT();

        TorunamentDetail storage tour = _tournaments[_tournamentId];

        if (tour.status == TorunamentStatus.Cancelled) revert Lobby__TOURNAMENT_CANCELLED();
        if (tournamentParticipated[_tournamentId][user]) revert Lobby__ALREADY_JOINED();

        if (block.timestamp >= tour.startTime + tour.duration) {
            tour.status = TorunamentStatus.Close;
            revert Lobby__TOURNAMENT_CLOSE(block.timestamp, tour.startTime + tour.duration);
        }

        if (tour.status == TorunamentStatus.Full) revert Lobby__TOURNAMENT_FULL();
        if (IERC20(tour.wETH).balanceOf(msg.sender) < tour.entryFee) revert Lobby__LOW_BALANCE();

        IERC20(tour.wETH).safeTransferFrom(msg.sender, address(this), tour.entryFee);

        tournamentParticipated[_tournamentId][user] = true;
        userTournamentHistory[user].push(_tournamentId);
        tour.playersJoined++;

        if (tour.playersJoined == tour.maxPlayer) {
            tour.status = TorunamentStatus.Full;
        }
        emit TorunamentJoined(_tournamentId, msg.sender);
    }

    function cancelTournament(uint256 _tourId) private {
        TorunamentDetail storage tour = _tournaments[_tourId];
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert Lobby__NOT_ADMIN();
        require(
            tour.maxPlayer > tour.playersJoined && block.timestamp > tour.startTime + tour.duration, "CAN_NOT_CANCEL"
        );
        tour.status = TorunamentStatus.Cancelled;
        emit TorunamentCanceled(_tourId);
    }

    function claimRefund(uint256 _tourId) external nonReentrant {
        TorunamentDetail storage tour = _tournaments[_tourId];
        require(tour.status == TorunamentStatus.Cancelled, "NOT_CANCELED");
        require(tournamentParticipated[_tourId][msg.sender], "DID_NOT_PARTICIPATED");
        require(!hasClaimedRefund[msg.sender], "ALREADY_CLAIMED");
        hasClaimedRefund[msg.sender] = true;
        uint256 amountRefund = tour.entryFee;
        (bool success,) = msg.sender.call{value: amountRefund}("");
        require(success, "Transfer failed");
        emit ClaimRefund(_tourId, msg.sender, amountRefund);
    }
}
