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

    enum LOTTERY_STATE {
        OPEN,
        CLOSED,
        CALCULATING_WINNER
    }
    LOTTERY_STATE public state;

    //Repurposing above============================================

    mapping(address => bool) s_drawingStatus;
    mapping(address => uint256) public s_consecutiveLosses;
    mapping(address => uint256) public s_rupeesBalance;
    mapping(address => bool) public s_isWinner;
    mapping(address => uint256) public s_initialDeposit;
    mapping(address => uint256) public s_claimedWinnings;

    //=============================================================

    // - Constants (THESE STAY)
    uint32 numWords = 1;
    uint16 requestConfirmations = 3;
    uint32 callbackGasLimit = 200000;
    // Set in constructor
    uint64 subscriptionId;
    AggregatorV3Interface ethUsdPriceFeed;
    VRFCoordinatorV2Interface COORDINATOR;
    bytes32 keyhash;

    address payable[] public players;
    address payable public recentWinner;
    // uint256[] public randomness;
    uint256 public usdEntryFee;

    event RequestedRandomness(uint256 requestId);
    event FulfillRandomness(uint256 requestId);

    //Repurposing above============================================

    uint256 public s_rupeePrice;
    uint256 public s_rupeeReserve;
    uint256 public s_contractReserve;
    
    // ?
    uint256[] public randomness;

    //=============================================================

    // will have to insert myself in here:
    constructor(
        uint64 _subscriptionId,
        address _priceFeedAddress,
        address _vrfCoordinator,
        bytes32 _keyhash,
        // add:
        uint256 rupeeSupply
    ) VRFConsumerBaseV2(_vrfCoordinator) payable {
        usdEntryFee = 50 * (10**18);
        subscriptionId = _subscriptionId;
        ethUsdPriceFeed = AggregatorV3Interface(_priceFeedAddress);
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        state = LOTTERY_STATE.CLOSED;
        keyhash = _keyhash;
        // add:
        s_rupeeReserve = rupeeSupply;
        s_contractReserve = address(this).balance;
    }

    // ELYAS FUNCTIONS ==================================================

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

        address payable _winner = payable(msg.sender);
        (bool success, ) = _winner.call{ value: _winnings }("");
        if (!success) {
            revert("transfer failed");
        }
        s_rupeeReserve = s_rupeeReserve + _rupeesSold;
        s_contractReserve = s_contractReserve - _winnings;
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

    function drawing() external payable{
        // requires balance to be greater than 0
        //require(s_rupeesBalance[msg.sender] > 0);
        // requires a payment of 0.01 AVAX to draw
        console.log("Rupees balance: %s", s_rupeesBalance[msg.sender]);
        require(msg.value == 10000000000000000 && s_rupeesBalance[msg.sender] > 0, "message value incorrect or zero balance");
        // generates random number
        // for now assume that they win
        s_isWinner[msg.sender] = true;
    }

    // ELYAS FUNCTIONS ==================================================

    function enter() public payable {
        require(state == LOTTERY_STATE.OPEN);
        require(msg.value >= getEntranceFee(), "Not enough ETH!");
        players.push(payable(msg.sender));
    }

    function getPriceFeed() public view returns (uint256) {
        return _getPriceFeed();
    }

    function _getPriceFeed() internal view returns (uint256) {
        (, int256 price, , , ) = ethUsdPriceFeed.latestRoundData();
        return uint256(price) * 10**10; // 18 decimals
    }

    function getEntranceFee() public view returns (uint256) {
        uint256 price = _getPriceFeed();
        uint256 costToEnter = (usdEntryFee * 10**18) / price;
        return costToEnter;
    }

    function startLottery() public onlyOwner {
        require(state == LOTTERY_STATE.CLOSED, "Closed!");
        state = LOTTERY_STATE.OPEN;
    }

    function endLottery() public onlyOwner {
        state = LOTTERY_STATE.CALCULATING_WINNER;
        uint256 requestId = COORDINATOR.requestRandomWords(
            keyhash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        emit RequestedRandomness(requestId);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomness
    ) internal override {
        // - state can be adjusted for a particular user entering the drawing
        require(state == LOTTERY_STATE.CALCULATING_WINNER);
        uint256 rand = _randomness[0];
        require(rand > 0, "RNG failed!");
        // - players.length can just be 7-10 depending on how hard it should be to win and be able to withdraw
        uint256 indexOfWinner = rand % players.length;
        // - if the person wins, set isWinner to true
        // - else, increment the counter by 1
        recentWinner = players[indexOfWinner];
        recentWinner.transfer(address(this).balance);

        // Reset
        players = new address payable[](0);
        // - change state to be ready to draw again
        // - set lastDraw (mapping to user) to block timestamp
        state = LOTTERY_STATE.CLOSED;
        randomness = _randomness;
        emit FulfillRandomness(_requestId);
    }

    function getPlayersCount() public view returns (uint256 count) {
        return players.length;
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
