//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;
pragma abicoder v2;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./LotteryOwner.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "hardhat/console.sol";

contract Lottery is LotteryOwnable, Initializable {
    address constant burnAddress =
        address(0x000000000000000000000000000000000000dEaD);
    uint8 constant keyLengthForEachBuy = 11;
    uint8[3] public allocation;
    uint8 public rolloverAllocation;
    IERC20 public winery;

    address public treasuryAddress;
    address public adminAddress;
    uint8 public maxNumber;
    uint256 public minPrice;
    uint256 public lotteryId;
    address[] public vipList;
    uint256 public adminNonce = 0;

    struct LotteryStructInfo {
        address user;
        uint256 total;
        uint8[4] numbers;
        bool isClaimed;
        uint256 time;
        uint256 issueIndex;
    }

    struct LotteryFreeClaim {
        address user;
        bool isSigned;
    }

    mapping(uint256 => LotteryStructInfo) public lotteryBuyInfo;
    // LotteryStructInfo[] public lotteryBuyInfo;
    // issueId => winningNumbers[numbers]
    mapping(uint256 => uint8[4]) public historyNumbers;
    // issueId => [tokenId]
    mapping(uint256 => uint256[]) public lotteryInfo;
    // issueId => [totalAmount, firstMatchAmount, secondMatchingAmount, thirdMatchingAmount]
    mapping(uint256 => uint256[]) public historyAmount;
    // issueId => trickyNumber => buyAmountSum
    mapping(uint256 => mapping(uint64 => uint256)) public userBuyAmountSum;
    // address => [tokenId]
    mapping(address => uint256[]) public userInfo;
    // address => issueIndex => [tokenId]
    mapping(address => mapping(uint256 => uint256[])) public userHistory;
    // mapping
    mapping(address => uint256) public freeClaimCounts;

    uint256 public issueIndex = 0;
    uint256 public totalAddresses = 0;
    uint256 public totalAmount = 0;
    uint256 public lastTimestamp;
    uint256 public nextTimeDraw = 0;

    uint8[4] public winningNumbers;
    uint8[4] private nullTicket = [0, 0, 0, 0];

    bool public drawingPhase;

    event Buy(address indexed user, uint256 tokenId);
    event Drawing(uint256 indexed issueIndex, uint8[4] winningNumbers);
    event Claim(address indexed user, uint256 tokenid, uint256 amount);
    event DevWithdraw(address indexed user, uint256 amount);
    event Reset(
        uint256 indexed issueIndex,
        uint256 unclaimableRewards,
        uint256 burnAmount
    );
    event MultiClaim(address indexed user, uint256 amount);
    event MultiBuy(address indexed user, uint256 amount);

    constructor() {}

    function initialize(
        IERC20 _winery,
        uint256 _minPrice,
        uint8 _maxNumber,
        address _owner,
        address _adminAddress,
        address _treasuryAddress,
        uint256 _nextTime
    ) public initializer {
        winery = _winery;
        minPrice = _minPrice;
        maxNumber = _maxNumber;
        adminAddress = _adminAddress;
        treasuryAddress = _treasuryAddress;
        lastTimestamp = block.timestamp;
        rolloverAllocation = 5;
        _setAllocation(65, 20, 10);
        initOwner(_owner);
        lotteryId = 0;
        nextTimeDraw = _nextTime;
    }

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "admin: wut?");
        _;
    }

    function drawed() public view returns (bool) {
        return winningNumbers[0] != 0;
    }

    function burnAllocation() public view returns (uint8) {
        uint8 rewardAllocation = rolloverAllocation;
        for (uint8 i = 0; i < allocation.length; i++) {
            rewardAllocation = rewardAllocation + allocation[i];
        }
        return 100 - rewardAllocation;
    }

    function reset() internal onlyAdmin {
        //require(drawed(), "drawed?");
        lastTimestamp = block.timestamp;
        totalAddresses = 0;
        totalAmount = 0;
        winningNumbers[0] = 0;
        winningNumbers[1] = 0;
        winningNumbers[2] = 0;
        winningNumbers[3] = 0;
        drawingPhase = false;
        issueIndex++;
        uint256 rolloverAmount = 0;
        uint256 previousRewards = getTotalRewards(issueIndex - 1);
        // Calculate unclaimable rewards from previous issueIndex and add to rollover
        for (uint i = 0; i < allocation.length; i++) {
            if (getMatchingRewardAmount(issueIndex - 1, 4 - i) == 0) {
                rolloverAmount =
                    rolloverAmount +
                    ((previousRewards * allocation[i]) / (100));
            }
        }
        // Calculate roll over balance
        rolloverAmount =
            rolloverAmount +
            ((previousRewards * (rolloverAllocation)) / (100));

        if (rolloverAmount > 0) {
            internalBuy(rolloverAmount, nullTicket);
        }
    }

    function enterDrawingPhase() external onlyAdmin {
        require(!drawed(), "drawed");
        drawingPhase = true;
    }

    function setMainToken(IERC20 _newToken) public onlyAdmin {
        winery = _newToken;
    }

    function getNumbersTicket(uint256 _lotteryId)
        public
        view
        returns (uint8[4] memory)
    {
        return lotteryBuyInfo[_lotteryId].numbers;
    }

    function drawing(uint256 _nextTime) external onlyAdmin {
        require(!drawed(), "reset?");
        require(drawingPhase, "enter drawing phase first");

        winningNumbers[0] = random(1 + block.timestamp);

        winningNumbers[1] = random(2 + block.timestamp);

        winningNumbers[2] = random(3 + block.timestamp);

        winningNumbers[3] = random(4 + block.timestamp);

        historyNumbers[issueIndex] = winningNumbers;
        historyAmount[issueIndex] = calculateMatchingRewardAmount();
        drawingPhase = false;

        nextTimeDraw = _nextTime;
        reset();
        emit Drawing(issueIndex, winningNumbers);
    }

    function internalBuy(uint256 _price, uint8[4] memory _numbers) internal {
        require(!drawed(), "drawed, can not buy now");
        for (uint i = 0; i < 4; i++) {
            require(_numbers[i] <= maxNumber, "exceed the maximum");
        }
        lotteryBuyInfo[lotteryId].user = msg.sender;
        lotteryBuyInfo[lotteryId].total = _price;
        lotteryBuyInfo[lotteryId].isClaimed = false;
        lotteryBuyInfo[lotteryId].time = block.timestamp;
        lotteryBuyInfo[lotteryId].issueIndex = issueIndex;
        lotteryBuyInfo[lotteryId].numbers = _numbers;

        lotteryInfo[issueIndex].push(lotteryId);
        totalAmount = totalAmount + _price;
        lastTimestamp = block.timestamp;

        lotteryId++;
        emit Buy(address(this), lotteryId - 1);
    }

    function approveTransfer(uint256 _price) public returns (bool) {
        return winery.approve(address(this), _price);
    }

    function encodeFreeClaimTicketHasedMessage(
        address _sender,
        uint256 _freeClaimCounts,
        uint256 _timeout,
        uint8[4] memory _numbers
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _sender,
                    _freeClaimCounts,
                    _numbers,
                    _timeout,
                    adminNonce
                )
            );
    }

    function verifyFreeClaimTicketSignedByAdmin(
        address _sender,
        uint256 _freeClaimCounts,
        uint256 _timeout,
        uint8[4] memory _numbers,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal returns (bool) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 hashedMessage = encodeFreeClaimTicketHasedMessage(
            _sender,
            _freeClaimCounts,
            _timeout,
            _numbers
        );

        adminNonce++;

        bytes32 prefixedHashMessage = keccak256(
            abi.encodePacked(prefix, hashedMessage)
        );
        address signer = ecrecover(prefixedHashMessage, _v, _r, _s);
        return signer == adminAddress;
    }

    function freeClaimTicketPermit(
        uint256 _timeout,
        uint8[4] memory _numbers,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public {
        require(block.timestamp < _timeout, "Timeout");
        require(
            verifyFreeClaimTicketSignedByAdmin(
                msg.sender,
                freeClaimCounts[msg.sender],
                _timeout,
                _numbers,
                _v,
                _r,
                _s
            ),
            "Not Accepted"
        );
        require(!drawed(), "drawed, can not buy now");
        require(!drawingPhase, "drawing, can not buy now");
        for (uint i = 0; i < 4; i++) {
            require(_numbers[i] <= maxNumber, "exceed number scope");
        }

        lotteryBuyInfo[lotteryId].user = msg.sender;
        lotteryBuyInfo[lotteryId].total = minPrice;
        lotteryBuyInfo[lotteryId].isClaimed = false;
        lotteryBuyInfo[lotteryId].time = block.timestamp;
        lotteryBuyInfo[lotteryId].issueIndex = issueIndex;
        lotteryBuyInfo[lotteryId].numbers = _numbers;
        lotteryInfo[issueIndex].push(lotteryId);

        if (userInfo[msg.sender].length == 0) {
            totalAddresses = totalAddresses + 1;
        }
        userInfo[msg.sender].push(lotteryId);
        totalAmount = totalAmount + (minPrice);
        lastTimestamp = block.timestamp;
        uint64[keyLengthForEachBuy]
            memory userNumberIndex = generateNumberIndexKey(_numbers);
        for (uint i = 0; i < keyLengthForEachBuy; i++) {
            userBuyAmountSum[issueIndex][userNumberIndex[i]] =
                userBuyAmountSum[issueIndex][userNumberIndex[i]] +
                (minPrice);
        }

        userHistory[msg.sender][issueIndex].push(lotteryId);

        lotteryId++;

        emit Buy(msg.sender, lotteryId - 1);
    }

    // function

    function buy(uint256 _price, uint8[4] memory _numbers)
        external
        returns (uint256)
    {
        require(!drawed(), "drawed, can not buy now");
        require(!drawingPhase, "drawing, can not buy now");
        require(_price >= minPrice, "price must above minPrice");
        for (uint i = 0; i < 4; i++) {
            require(_numbers[i] <= maxNumber, "exceed number scope");
        }

        lotteryBuyInfo[lotteryId].user = msg.sender;
        lotteryBuyInfo[lotteryId].total = _price;
        lotteryBuyInfo[lotteryId].isClaimed = false;
        lotteryBuyInfo[lotteryId].time = block.timestamp;
        lotteryBuyInfo[lotteryId].issueIndex = issueIndex;
        lotteryBuyInfo[lotteryId].numbers = _numbers;

        lotteryInfo[issueIndex].push(lotteryId);
        if (userInfo[msg.sender].length == 0) {
            totalAddresses = totalAddresses + 1;
        }
        userInfo[msg.sender].push(lotteryId);
        totalAmount = totalAmount + (_price);
        lastTimestamp = block.timestamp;
        uint64[keyLengthForEachBuy]
            memory userNumberIndex = generateNumberIndexKey(_numbers);
        for (uint i = 0; i < keyLengthForEachBuy; i++) {
            userBuyAmountSum[issueIndex][userNumberIndex[i]] =
                userBuyAmountSum[issueIndex][userNumberIndex[i]] +
                (_price);
        }

        userHistory[msg.sender][issueIndex].push(lotteryId);

        lotteryId++;

        winery.transferFrom(
            address(msg.sender),
            address(treasuryAddress),
            _price
        );
        emit Buy(msg.sender, lotteryId - 1);
    }

    function multiBuy(uint256 _price, uint8[4][] memory _numbers) external {
        require(!drawed(), "drawed, can not buy now");
        require(_price >= minPrice, "price must above minPrice");
        uint256 totalPrice = 0;
        for (uint i = 0; i < _numbers.length; i++) {
            for (uint j = 0; j < 4; j++) {
                require(
                    _numbers[i][j] <= maxNumber && _numbers[i][j] > 0,
                    "exceed number scope"
                );
            }

            lotteryBuyInfo[lotteryId].user = msg.sender;
            lotteryBuyInfo[lotteryId].total = _price;
            lotteryBuyInfo[lotteryId].isClaimed = false;
            lotteryBuyInfo[lotteryId].time = block.timestamp;
            lotteryBuyInfo[lotteryId].issueIndex = issueIndex;
            lotteryBuyInfo[lotteryId].numbers = _numbers[i];

            lotteryInfo[issueIndex].push(lotteryId);
            if (userInfo[msg.sender].length == 0) {
                totalAddresses = totalAddresses + 1;
            }
            userInfo[msg.sender].push(lotteryId);
            totalAmount = totalAmount + (_price);
            lastTimestamp = block.timestamp;
            totalPrice = totalPrice + (_price);

            userHistory[msg.sender][issueIndex].push(lotteryId);

            uint64[keyLengthForEachBuy]
                memory numberIndexKey = generateNumberIndexKey(_numbers[i]);
            for (uint k = 0; k < keyLengthForEachBuy; k++) {
                userBuyAmountSum[issueIndex][numberIndexKey[k]] =
                    userBuyAmountSum[issueIndex][numberIndexKey[k]] +
                    (_price);
            }

            lotteryId++;
        }

        winery.transferFrom(
            address(msg.sender),
            address(treasuryAddress),
            totalPrice
        );

        emit MultiBuy(msg.sender, totalPrice);
    }

    function claimReward(uint256 _lotteryId) external {
        require(
            msg.sender == lotteryBuyInfo[_lotteryId].user,
            "not from owner"
        );
        require(!lotteryBuyInfo[_lotteryId].isClaimed, "claimed");
        uint256 reward = getRewardView(_lotteryId);

        lotteryBuyInfo[_lotteryId].isClaimed = true;
        if (reward > 0) {
            winery.transferFrom(
                address(treasuryAddress),
                address(msg.sender),
                reward
            );
        }
        emit Claim(msg.sender, _lotteryId, reward);
    }

    function multiClaim(uint256[] memory _tickets) external {
        uint256 totalReward = 0;
        for (uint i = 0; i < _tickets.length; i++) {
            require(
                msg.sender == lotteryBuyInfo[_tickets[i]].user,
                "not from owner"
            );
            require(!lotteryBuyInfo[_tickets[i]].isClaimed, "claimed");
            uint256 reward = getRewardView(_tickets[i]);
            if (reward > 0) {
                totalReward = reward + (totalReward);
            }
        }

        for (uint i = 0; i < _tickets.length; i++) {
            lotteryBuyInfo[_tickets[i]].isClaimed = true;
        }

        if (totalReward > 0) {
            winery.transferFrom(
                address(treasuryAddress),
                address(msg.sender),
                totalReward
            );
        }
        emit MultiClaim(msg.sender, totalReward);
    }

    function generateNumberIndexKey(uint8[4] memory number)
        public
        pure
        returns (uint64[keyLengthForEachBuy] memory)
    {
        uint64[4] memory tempNumber;
        tempNumber[0] = uint64(number[0]);
        tempNumber[1] = uint64(number[1]);
        tempNumber[2] = uint64(number[2]);
        tempNumber[3] = uint64(number[3]);

        uint64[keyLengthForEachBuy] memory result;
        result[0] =
            tempNumber[0] *
            256 *
            256 *
            256 *
            256 *
            256 *
            256 +
            1 *
            256 *
            256 *
            256 *
            256 *
            256 +
            tempNumber[1] *
            256 *
            256 *
            256 *
            256 +
            2 *
            256 *
            256 *
            256 +
            tempNumber[2] *
            256 *
            256 +
            3 *
            256 +
            tempNumber[3];

        result[1] =
            tempNumber[0] *
            256 *
            256 *
            256 *
            256 +
            1 *
            256 *
            256 *
            256 +
            tempNumber[1] *
            256 *
            256 +
            2 *
            256 +
            tempNumber[2];
        result[2] =
            tempNumber[0] *
            256 *
            256 *
            256 *
            256 +
            1 *
            256 *
            256 *
            256 +
            tempNumber[1] *
            256 *
            256 +
            3 *
            256 +
            tempNumber[3];
        result[3] =
            tempNumber[0] *
            256 *
            256 *
            256 *
            256 +
            2 *
            256 *
            256 *
            256 +
            tempNumber[2] *
            256 *
            256 +
            3 *
            256 +
            tempNumber[3];
        result[4] =
            1 *
            256 *
            256 *
            256 *
            256 *
            256 +
            tempNumber[1] *
            256 *
            256 *
            256 *
            256 +
            2 *
            256 *
            256 *
            256 +
            tempNumber[2] *
            256 *
            256 +
            3 *
            256 +
            tempNumber[3];

        result[5] = tempNumber[0] * 256 * 256 + 1 * 256 + tempNumber[1];
        result[6] = tempNumber[0] * 256 * 256 + 2 * 256 + tempNumber[2];
        result[7] = tempNumber[0] * 256 * 256 + 3 * 256 + tempNumber[3];
        result[8] =
            1 *
            256 *
            256 *
            256 +
            tempNumber[1] *
            256 *
            256 +
            2 *
            256 +
            tempNumber[2];
        result[9] =
            1 *
            256 *
            256 *
            256 +
            tempNumber[1] *
            256 *
            256 +
            3 *
            256 +
            tempNumber[3];
        result[10] =
            2 *
            256 *
            256 *
            256 +
            tempNumber[2] *
            256 *
            256 +
            3 *
            256 +
            tempNumber[3];

        return result;
    }

    function calculateMatchingRewardAmount()
        internal
        view
        returns (uint256[4] memory)
    {
        uint64[keyLengthForEachBuy]
            memory numberIndexKey = generateNumberIndexKey(winningNumbers);

        uint256 totalAmout1 = userBuyAmountSum[issueIndex][numberIndexKey[0]];

        uint256 sumForTotalAmout2 = userBuyAmountSum[issueIndex][
            numberIndexKey[1]
        ];
        sumForTotalAmout2 =
            sumForTotalAmout2 +
            (userBuyAmountSum[issueIndex][numberIndexKey[2]]);
        sumForTotalAmout2 =
            sumForTotalAmout2 +
            (userBuyAmountSum[issueIndex][numberIndexKey[3]]);
        sumForTotalAmout2 =
            sumForTotalAmout2 +
            (userBuyAmountSum[issueIndex][numberIndexKey[4]]);

        uint256 totalAmout2 = sumForTotalAmout2 - (totalAmout1 * (4));

        uint256 sumForTotalAmout3 = userBuyAmountSum[issueIndex][
            numberIndexKey[5]
        ];
        sumForTotalAmout3 =
            sumForTotalAmout3 +
            (userBuyAmountSum[issueIndex][numberIndexKey[6]]);
        sumForTotalAmout3 =
            sumForTotalAmout3 +
            (userBuyAmountSum[issueIndex][numberIndexKey[7]]);
        sumForTotalAmout3 =
            sumForTotalAmout3 +
            (userBuyAmountSum[issueIndex][numberIndexKey[8]]);
        sumForTotalAmout3 =
            sumForTotalAmout3 +
            (userBuyAmountSum[issueIndex][numberIndexKey[9]]);
        sumForTotalAmout3 =
            sumForTotalAmout3 +
            (userBuyAmountSum[issueIndex][numberIndexKey[10]]);

        uint256 totalAmout3 = sumForTotalAmout3 +
            (totalAmout1 * (6)) -
            (sumForTotalAmout2 * (3));

        return [totalAmount, totalAmout1, totalAmout2, totalAmout3];
    }

    function getMatchingRewardAmount(
        uint256 _issueIndex,
        uint256 _matchingNumber
    ) public view returns (uint256) {
        return historyAmount[_issueIndex][5 - _matchingNumber];
    }

    function getUserHistory(address member, uint256 _issueIndex)
        public
        view
        returns (uint256[] memory)
    {
        return userHistory[member][_issueIndex];
    }

    function getTotalRewards(uint256 _issueIndex)
        public
        view
        returns (uint256)
    {
        require(_issueIndex <= issueIndex, "_issueIndex <= issueIndex");

        if (!drawed() && _issueIndex == issueIndex) {
            return totalAmount;
        }
        return historyAmount[_issueIndex][0];
    }

    function getRewardView(uint256 _lotteryId) public view returns (uint256) {
        uint256 _issueIndex = lotteryBuyInfo[_lotteryId].issueIndex;
        uint8[4] memory lotteryNumbers = lotteryBuyInfo[_lotteryId].numbers;
        uint8[4] memory _winningNumbers = historyNumbers[_issueIndex];
        require(_winningNumbers[0] != 0, "not drawed");

        uint256 matchingNumber = 0;
        for (uint i = 0; i < _winningNumbers.length; i++) {
            if (_winningNumbers[i] == lotteryNumbers[i]) {
                matchingNumber = matchingNumber + 1;
            }
        }
        uint256 reward = 0;
        if (matchingNumber > 1) {
            uint256 amount = lotteryBuyInfo[_lotteryId].total;
            uint256 poolAmount = (getTotalRewards(_issueIndex) *
                (allocation[4 - matchingNumber])) / (100);
            reward =
                ((amount * (1e12)) /
                    (getMatchingRewardAmount(_issueIndex, matchingNumber))) *
                (poolAmount);
        }
        return reward / (1e12);
    }

    function random(uint randNum) private view returns (uint8) {
        // Generate a random number between 1 and 100:
        uint randNonce = randNum;
        uint random = uint(
            keccak256(abi.encodePacked(block.timestamp, msg.sender, randNonce))
        ) % maxNumber;
        randNonce++;
        uint random2 = uint(
            keccak256(abi.encodePacked(block.timestamp, msg.sender, randNonce))
        ) % maxNumber;

        if (random2 == maxNumber) {
            return uint8(random2 - 1);
        }

        if (random2 == 0) {
            return 1;
        }

        return uint8(random2);
    }

    // Update admin address by the previous dev.
    function setAdmin(address _adminAddress) public onlyOwner {
        adminAddress = _adminAddress;
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function adminWithdraw(uint256 _amount) public onlyOwner {
        winery.transfer(address(msg.sender), _amount);
        emit DevWithdraw(msg.sender, _amount);
    }

    // Reset treasury address for contract
    function setTreasuryAddress(address _treasuryAddress) external onlyOwner {
        treasuryAddress = _treasuryAddress;
    }

    // Set the minimum price for one ticket
    function setMinPrice(uint256 _price) external onlyOwner {
        minPrice = _price;
    }

    // Set the max number
    function setMaxNumber(uint8 _maxNumber) external onlyOwner {
        maxNumber = _maxNumber;
    }

    // Set the time for next round
    function setNextTimeDraw(uint256 _nextTime) external onlyOwner {
        nextTimeDraw = _nextTime;
    }

    function setAllocation(
        uint8 _allocation1,
        uint8 _allocation2,
        uint8 _allocation3
    ) external onlyOwner {
        _setAllocation(_allocation1, _allocation2, _allocation3);
    }

    // Set the allocation for one reward
    function _setAllocation(
        uint8 _allocation1,
        uint8 _allocation2,
        uint8 _allocation3
    ) internal {
        uint8 totalAllocation = uint8(
            _allocation1 +
                (_allocation2 + (_allocation3) + (rolloverAllocation))
        );
        require(totalAllocation <= 100, "Total allocation is more than 100");
        allocation = [_allocation1, _allocation2, _allocation3];
    }
}
