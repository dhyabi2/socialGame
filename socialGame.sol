// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

// Importing the OpenZeppelin contracts for ERC-20 and DEX functionality
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// Defining the Token Master contract
contract TokenMaster is ERC20 {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Defining the state variables
    address public owner; // The owner of the contract
    address public lottery; // The address of the lottery contract
    IUniswapV2Router02 public uniswap; // The address of the Uniswap router
    uint256 public referralRate; // The percentage of tokens given to referrers
    uint256 public rewardRate; // The percentage of tokens given to leaderboard winners
    uint256 public jackpot; // The amount of tokens given to lottery winners
    uint256 public leaderboardPeriod; // The time period for updating the leaderboard
    uint256 public lotteryPeriod; // The time period for drawing the lottery
    uint256 public lastLeaderboardUpdate; // The timestamp of the last leaderboard update
    uint256 public lastLotteryDraw; // The timestamp of the last lottery draw
    mapping(address => address) public referrals; // A mapping of users to their referrers
    mapping(address => uint256) public balances; // A mapping of users to their token balances
    address[] public users; // An array of all users
    address[] public leaderboard; // An array of the top users

    // Defining the events
    event Bought(address indexed buyer, uint256 amount); // Emitted when a user buys tokens
    event Referred(address indexed referrer, address indexed referee); // Emitted when a user refers another user
    event Rewarded(address indexed user, uint256 amount); // Emitted when a user receives a reward
    event Jackpot(address indexed winner, uint256 amount); // Emitted when a user wins the jackpot

    // Defining the constructor
    constructor(address _lottery, address _uniswap) ERC20("Token Master", "TKN") {
        owner = msg.sender; // Setting the owner as the deployer
        lottery = _lottery; // Setting the lottery address
        uniswap = IUniswapV2Router02(_uniswap); // Setting the Uniswap router address
        referralRate = 10; // Setting the referral rate to 10%
        rewardRate = 5; // Setting the reward rate to 5%
        jackpot = 1000000 * 10 ** decimals(); // Setting the jackpot to 1 million tokens
        leaderboardPeriod = 1 weeks; // Setting the leaderboard period to 1 week
        lotteryPeriod = 1 weeks; // Setting the lottery period to 1 week
        lastLeaderboardUpdate = block.timestamp; // Setting the last leaderboard update to now
        lastLotteryDraw = block.timestamp; // Setting the last lottery draw to now
        _mint(owner, 100000000 * 10 ** decimals()); // Minting 100 million tokens to the owner
        _approve(owner, address(uniswap), totalSupply()); // Approving Uniswap to spend all tokens
    }

    // Defining a modifier to check if the caller is the owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    // Defining a function to buy tokens with ETH through Uniswap and optionally use a referral code
    function buyTokens(address _referrer) external payable {
        require(msg.value > 0, "You must send some ETH"); // Checking if the user sent some ETH

        if (_referrer != address(0) && referrals[msg.sender] == address(0)) { // Checking if the user has a valid and new referrer
            referrals[msg.sender] = _referrer; // Setting the referrer for the user
            emit Referred(_referrer, msg.sender); // Emitting an event for referral
        }

    }
         
        // Defining a function to buy tokens with ETH through Uniswap and optionally use a referral code
    function buyTokens(address _referrer) external payable {
        require(msg.value > 0, "You must send some ETH"); // Checking if the user sent some ETH

        if (_referrer != address(0) && referrals[msg.sender] == address(0)) { // Checking if the user has a valid and new referrer
            referrals[msg.sender] = _referrer; // Setting the referrer for the user
            emit Referred(_referrer, msg.sender); // Emitting an event for referral
        }

        address[] memory path = new address[](2); // Creating an array for the Uniswap path
        path[0] = uniswap.WETH(); // Setting the first element to WETH
        path[1] = address(this); // Setting the second element to this contract

        uint256 amountOutMin = 0; // Setting the minimum amount of tokens to receive
        uint256 deadline = block.timestamp + 15 minutes; // Setting the deadline for the swap

        uniswap.swapExactETHForTokens{value: msg.value}(amountOutMin, path, msg.sender, deadline); // Swapping ETH for tokens and sending them to the user

        uint256 amount = balanceOf(msg.sender); // Getting the amount of tokens received by the user
        balances[msg.sender] = amount; // Updating the user's balance in the mapping
        users.push(msg.sender); // Adding the user to the users array

        emit Bought(msg.sender, amount); // Emitting an event for buying tokens

        if (referrals[msg.sender] != address(0)) { // Checking if the user has a referrer
            address referrer = referrals[msg.sender]; // Getting the referrer's address
            uint256 referralBonus = amount.mul(referralRate).div(100); // Calculating the referral bonus as a percentage of the amount
            _mint(referrer, referralBonus); // Minting new tokens to the referrer
            balances[referrer] = balances[referrer].add(referralBonus); // Updating the referrer's balance in the mapping
            emit Rewarded(referrer, referralBonus); // Emitting an event for rewarding the referrer
        }

        updateLeaderboard(); // Updating the leaderboard
        drawLottery(); // Drawing the lottery
    }

    // Defining a function to update the leaderboard based on the users' balances
    function updateLeaderboard() public {
        require(block.timestamp >= lastLeaderboardUpdate + leaderboardPeriod, "Leaderboard update not due yet"); // Checking if the leaderboard update is due

        uint256 length = users.length; // Getting the length of the users array
        require(length > 0, "No users to rank"); // Checking if there are any users to rank

        leaderboard = new address[](10); // Creating a new array for the leaderboard with 10 slots

        for (uint256 i = 0; i < length; i++) { // Looping through all users
            address user = users[i]; // Getting the user's address
            uint256 balance = balances[user]; // Getting the user's balance

            for (uint256 j = 0; j < 10; j++) { // Looping through all slots in the leaderboard
                address leader = leaderboard[j]; // Getting the leader's address
                uint256 leaderBalance = balances[leader]; // Getting the leader's balance

                if (balance > leaderBalance) { // Checking if the user's balance is greater than the leader's balance
                    leaderboard[j] = user; // Replacing the leader with the user in the slot
                    balance = leaderBalance; // Updating the balance to compare with the next slot
                    user = leader; // Updating the user to compare with the next slot
                }
            }
        }

        lastLeaderboardUpdate = block.timestamp; // Updating the timestamp of the last leaderboard update

        for (uint256 k = 0; k < 10; k++) { // Looping through all slots in the leaderboard
            address winner = leaderboard[k]; // Getting the winner's address
            uint256 reward = totalSupply().mul(rewardRate).div(100).div(10); // Calculating the reward as a percentage of total supply divided by 10 slots
            _mint(winner, reward); // Minting new tokens to the winner
            balances[winner] = balances[winner].add(reward); // Updating the winner's balance in

            // Defining a function to update the leaderboard based on the users' balances
    function updateLeaderboard() public {
        require(block.timestamp >= lastLeaderboardUpdate + leaderboardPeriod, "Leaderboard update not due yet"); // Checking if the leaderboard update is due

        uint256 length = users.length; // Getting the length of the users array
        require(length > 0, "No users to rank"); // Checking if there are any users to rank

        leaderboard = new address[](10); // Creating a new array for the leaderboard with 10 slots

        for (uint256 i = 0; i < length; i++) { // Looping through all users
            address user = users[i]; // Getting the user's address
            uint256 balance = balances[user]; // Getting the user's balance

            for (uint256 j = 0; j < 10; j++) { // Looping through all slots in the leaderboard
                address leader = leaderboard[j]; // Getting the leader's address
                uint256 leaderBalance = balances[leader]; // Getting the leader's balance

                if (balance > leaderBalance) { // Checking if the user's balance is greater than the leader's balance
                    leaderboard[j] = user; // Replacing the leader with the user in the slot
                    balance = leaderBalance; // Updating the balance to compare with the next slot
                    user = leader; // Updating the user to compare with the next slot
                }
            }
        }

        lastLeaderboardUpdate = block.timestamp; // Updating the timestamp of the last leaderboard update

        for (uint256 k = 0; k < 10; k++) { // Looping through all slots in the leaderboard
            address winner = leaderboard[k]; // Getting the winner's address
            uint256 reward = totalSupply().mul(rewardRate).div(100).div(10); // Calculating the reward as a percentage of total supply divided by 10 slots
            _mint(winner, reward); // Minting new tokens to the winner
            balances[winner] = balances[winner].add(reward); // Updating the winner's balance in the mapping
            emit Rewarded(winner, reward); // Emitting an event for rewarding the winner
        }
    }

    // Defining a function to draw the lottery based on a verifiable RNG
    function drawLottery() public {
        require(block.timestamp >= lastLotteryDraw + lotteryPeriod, "Lottery draw not due yet"); // Checking if the lottery draw is due

        uint256 length = users.length; // Getting the length of the users array
        require(length > 0, "No users to participate"); // Checking if there are any users to participate

        bytes32 requestId = requestRandomness(blockhash(block.number - 1), block.timestamp); // Requesting a random number from a verifiable RNG using blockhash and timestamp as seed

        uint256 randomNumber = uint256(requestId) % length; // Modulo the random number by the length of the users array to get an index

        address winner = users[randomNumber]; // Getting the winner's address from the users array using the index

        _mint(winner, jackpot); // Minting new tokens to the winner
        balances[winner] = balances[winner].add(jackpot); // Updating the winner's balance in the mapping
        emit Jackpot(winner, jackpot); // Emitting an event for winning the jackpot

        lastLotteryDraw = block.timestamp; // Updating the timestamp of the last lottery draw
    }

    // Defining a function to get the current leaderboard
    function getLeaderboard() public view returns (address[] memory) {
        return leaderboard; // Returning the leaderboard array
    }

    // Defining a function to get a user's referrer
    function getReferrer(address _user) public view returns (address) {
        return referrals[_user]; // Returning the referrer's address from the referrals mapping
    }

    // Defining a function to change the owner of the contract (onlyOwner)
    function changeOwner(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "Invalid address"); // Checking if the new owner's address is valid
        owner = _newOwner; // Changing the owner to the new owner
    }

    // Defining a function to change t

    // Defining a function to change the owner of the contract (onlyOwner)
    function changeOwner(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "Invalid address"); // Checking if the new owner's address is valid
        owner = _newOwner; // Changing the owner to the new owner
    }

    // Defining a function to change the lottery address (onlyOwner)
    function changeLottery(address _newLottery) public onlyOwner {
        require(_newLottery != address(0), "Invalid address"); // Checking if the new lottery's address is valid
        lottery = _newLottery; // Changing the lottery to the new lottery
    }

    // Defining a function to change the Uniswap router address (onlyOwner)
    function changeUniswap(address _newUniswap) public onlyOwner {
        require(_newUniswap != address(0), "Invalid address"); // Checking if the new Uniswap's address is valid
        uniswap = IUniswapV2Router02(_newUniswap); // Changing the Uniswap router to the new Uniswap router
    }

    // Defining a function to change the referral rate (onlyOwner)
    function changeReferralRate(uint256 _newReferralRate) public onlyOwner {
        require(_newReferralRate >= 0 && _newReferralRate <= 100, "Invalid rate"); // Checking if the new referral rate is valid
        referralRate = _newReferralRate; // Changing the referral rate to the new referral rate
    }

    // Defining a function to change the reward rate (onlyOwner)
    function changeRewardRate(uint256 _newRewardRate) public onlyOwner {
        require(_newRewardRate >= 0 && _newRewardRate <= 100, "Invalid rate"); // Checking if the new reward rate is valid
        rewardRate = _newRewardRate; // Changing the reward rate to the new reward rate
    }

    // Defining a function to change the jackpot amount (onlyOwner)
    function changeJackpot(uint256 _newJackpot) public onlyOwner {
        require(_newJackpot > 0, "Invalid amount"); // Checking if the new jackpot amount is valid
        jackpot = _newJackpot; // Changing the jackpot amount to the new jackpot amount
    }

    // Defining a function to change the leaderboard period (onlyOwner)
    function changeLeaderboardPeriod(uint256 _newLeaderboardPeriod) public onlyOwner {
        require(_newLeaderboardPeriod > 0, "Invalid period"); // Checking if the new leaderboard period is valid
        leaderboardPeriod = _newLeaderboardPeriod; // Changing the leaderboard period to the new leaderboard period
    }

    // Defining a function to change the lottery period (onlyOwner)
    function changeLotteryPeriod(uint256 _newLotteryPeriod) public onlyOwner {
        require(_newLotteryPeriod > 0, "Invalid period"); // Checking if the new lottery period is valid
        lotteryPeriod = _newLotteryPeriod; // Changing the lottery period to the new lottery period
    }
}
