// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";

contract Elyas is VRFConsumerBaseV2, Ownable {

    using SafeMath for uint256;

    mapping(address => bool) s_drawingStatus;
    mapping(address => uint256) public s_consecutiveLosses;
    mapping(address => uint256) public s_rupeesBalance;
    mapping(address => bool) public s_isWinner;
    mapping(address => uint256) public s_initialDeposit;
    mapping(address => uint256) public s_claimedWinnings;
    mapping(uint256 => address) public s_requester;
    mapping(address => uint256) public s_lastDraw;

    // - Constants (THESE STAY)
    uint32 numWords = 1;
    uint16 requestConfirmations = 3;
    uint32 callbackGasLimit = 200000;
    // Set in constructor
    uint64 subscriptionId;
    AggregatorV3Interface ethUsdPriceFeed;
    VRFCoordinatorV2Interface COORDINATOR;
    bytes32 keyhash;

    event RequestedRandomness(uint256 requestId);
    event FulfillRandomness(uint256 requestId);

    uint256 public s_rupeePrice;
    uint256 public s_rupeeReserve;
    uint256 public s_contractReserve;
    uint256 public immutable i_devFee;
    uint256[] public randomness;

    constructor(
        uint64 _subscriptionId,
        address _priceFeedAddress,
        address _vrfCoordinator,
        bytes32 _keyhash,
        // add:
        uint256 rupeeSupply,
        uint256 devFee
    ) VRFConsumerBaseV2(_vrfCoordinator) payable {
        subscriptionId = _subscriptionId;
        ethUsdPriceFeed = AggregatorV3Interface(_priceFeedAddress);
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        keyhash = _keyhash;
        // add:
        s_rupeeReserve = rupeeSupply;
        s_contractReserve = address(this).balance;
        i_devFee = devFee;
    }

    function quote(uint256 inputAmount, bool buy) public view returns (uint256) {
        if (buy == true) {
            uint256 inputReserve = s_contractReserve;
            uint256 outputReserve = s_rupeeReserve;
            uint256 _inputAmountWithFee = (inputAmount).mul(997);
            uint256 _numerator = _inputAmountWithFee.mul(outputReserve);
            uint256 _denominator = inputReserve.mul(1000).add(_inputAmountWithFee);
            return _numerator / _denominator;
        } else if (buy == false) {
            uint256 inputReserve = s_rupeeReserve;
            uint256 outputReserve = s_contractReserve;
            uint256 _inputAmountWithFee = (inputAmount).mul(997);
            uint256 _numerator = _inputAmountWithFee.mul(outputReserve);
            uint256 _denominator = inputReserve.mul(1000).add(_inputAmountWithFee);
            return _numerator / _denominator;
        } else revert("Expected true or false value");
    }

    function deposit() external payable {
        // do we need rupees balance to be 0? How about a warning that if they add to their position, their counter is set to zero
        // set loser counter to zero here if so
        require(s_rupeesBalance[msg.sender] == 0, "rupees balance must be 0");
        s_rupeesBalance[msg.sender] = quote(msg.value, true);
        s_initialDeposit[msg.sender] = msg.value;
        s_rupeeReserve = s_rupeeReserve - s_rupeesBalance[msg.sender];
        s_contractReserve = s_contractReserve + msg.value;
    }

    function winnerWithdrawal() external payable {
        require(s_isWinner[msg.sender] == true, "isWinner not true");

        s_isWinner[msg.sender] = false;
        s_claimedWinnings[msg.sender] = s_claimedWinnings[msg.sender] + quote(s_rupeesBalance[msg.sender], false);
        uint256 _winnings = quote(s_rupeesBalance[msg.sender], false);
        uint256 _rupeesSold = s_rupeesBalance[msg.sender];
        s_rupeesBalance[msg.sender] = 0;

        require(_winnings < address(this).balance, "winnings exceed contract balance");
        // implement 3x max here:
        uint256 _maxPayout = calculateWinnings();

        if (_winnings > _maxPayout) {
            // I suppose here is the best time to send out the divvied up excess winnings
            console.log("WINNINGS MORE THAN 3X LIMIT. CURRENTLY %s", _winnings);
            uint256 _excessWinnings = _winnings - _maxPayout;
            console.log("EXCESS WINNINGS: %s", _excessWinnings);
            _winnings = _maxPayout;
            console.log("NEW WINNINGS: %s", _winnings);
            // pay out the calculated excess deductions
        }

        address payable _winner = payable(msg.sender);
        (bool success, ) = _winner.call{ value: _winnings }("");
        if (!success) {
            revert("transfer failed");
        }
        s_rupeeReserve = s_rupeeReserve + _rupeesSold;
        s_contractReserve = s_contractReserve - _winnings;
    }

    function calculateWinnings() internal view returns (uint256) {
        // Here we calculate the payout as well as implement the 300% ceiling
        // We will get the initial deposit and limit to 3x of that
        uint256 _initial = s_initialDeposit[msg.sender];
        uint256 _maxPayout = _initial.mul(3);

        console.log("INITIAL INVESTMENT IN AVAX: %s", _initial);
        console.log("MAX PAYOUT (3X): %s", _maxPayout);

        return _maxPayout;
    }

    function claimLoserPrize() external payable {
        // requires s_consecutiveLosses to equal 4
        require(s_consecutiveLosses[msg.sender] == 5);
        // gets intial deposit and calculates prize
        uint256 prize = s_initialDeposit[msg.sender] / 5;
        // sets consecutive losses to 0
        s_consecutiveLosses[msg.sender] = 0;
        // transfers prize to sender
        payable (msg.sender).transfer(prize);
    }

    // VRF IMPLEMENTATION ============================================================

    // drawing will be the "requestRandomWords" function. "fulfillRandomWords" (pretty much the existing one) will be used to get the result and share with user and update counters / isWinner status

    function draw() public payable{
        // requires balance to be greater than 0 / drawing state to be false / payment of 0.01 native token / requires consecutive losses to be less than 5

        // in addition, current blocktimestamp minus s_lastDraw needs to be over the drawCooldown

        // sets drawing status to true 
        require(msg.value == 10000000000000000 && s_rupeesBalance[msg.sender] > 0 && s_drawingStatus[msg.sender] == false && s_consecutiveLosses[msg.sender] < 5, "message value incorrect / zero balance / drawing currently in progress / consecutive losses past threshold");

        s_drawingStatus[msg.sender] == true;
        // generates random number
        uint256 requestId = COORDINATOR.requestRandomWords(
            keyhash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        // map requestId to requester
        s_requester[requestId] = msg.sender;

        emit RequestedRandomness(requestId);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomness
    ) internal override {

        address account = s_requester[_requestId];

        uint256 rand = _randomness[0];
        require(rand > 0, "RNG failed!");

        uint256 _result = rand % 7;

        if (_result == 7) {
            // set isWinner to true for the requestor
            console.log("WE HAVE A WINNER!!");
            s_isWinner[account] = true;
        } else {
            //increment loser counter by one
            console.log("WE HAVE A LOSER!!");
            s_consecutiveLosses[account] += 1;
        }

        // - set lastDraw (mapping to user) to block timestamp

        randomness = _randomness;
        s_isWinner[account] = true;
        s_drawingStatus[account] == false;

        emit FulfillRandomness(_requestId);
    }

    // getLosersPool

    function getRupeeBalance(address account) public view returns (uint256) {
        return s_rupeesBalance[account];
    }

    function getRupeePrice() public view returns (uint256) {
        return s_rupeePrice;
    }

    function isWinner(address account) public view returns (bool) {
        return s_isWinner[account];
    }

    function getRupeeReserve() public view returns (uint256) {
        return s_rupeeReserve;
    }

    function getContractReserve() public view returns (uint256) {
        return s_contractReserve;
    }

    function getConsecutiveLosses(address account) public view returns (uint256) {
        return s_consecutiveLosses[account];
    }
}
