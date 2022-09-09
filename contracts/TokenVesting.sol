// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
pragma abicoder v2;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TokenVesting is Ownable,ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    struct VestingSchedule{
        bool initialized;
        address  beneficiary;
        uint256  duration;
        uint256 amountTotal;
        uint256  released;
    }
    address public rewardToken = address(0x0);
    uint256 public totalRewardtokenSupply;
    uint256 public start;
    mapping(address => uint256) private totalAmountStakedPerUser;
    uint256 private totalAmountStaked;
    uint256 private totalAmountVestedAndClaimed;
    bytes32[] private vestingSchedulesIds;
    mapping(bytes32 => VestingSchedule) private vestingSchedules;
    uint256 private vestingSchedulesTotalAmount;
    mapping(address => uint256) private holdersVestingCount;
    event Stake(address indexed wallet, uint256 amount, uint256 date, uint256 vestingAmount, uint256 stakingAmountInBusd);
    event Withdraw(address indexed wallet, uint256 amount, uint256 date, string projectId);
    event Claimed(address indexed wallet, uint256 amount, uint256 date);
    constructor(uint256 _totalRewardtokenSupply, uint256 _start) {
        totalRewardtokenSupply = _totalRewardtokenSupply;
        start = _start;
    }
    function setRewardTokenAddress(address _address) public onlyOwner {
        rewardToken = _address;
    }
    function setTotalRewardTokenSupply(uint256 _totalRewardtokenSupply) public onlyOwner {
        totalRewardtokenSupply = _totalRewardtokenSupply;
    }
    function setStartTimeForVesting(uint256 _start) public onlyOwner{
        start = _start;
    }
    function getSmartContractBalance() public view onlyOwner returns(uint256) {
        return address(this).balance;
    }
    function getTotalAmountStakedbyUser(address _address) public view onlyOwner returns(uint256){
        return totalAmountStakedPerUser[_address];
    }
    function getTotalAmountStaked() public view onlyOwner returns(uint256) {
        return totalAmountStaked;
    }
    function getTotalAmountVestedAndClaimed() public view onlyOwner returns(uint256){
        return totalAmountVestedAndClaimed;
    }
    function getVestingSchedulesTotalAmount() public view onlyOwner returns(uint256) {
        return vestingSchedulesTotalAmount;
    }
    function getAvailableTokensForVesting() public view returns(uint256){
        return totalRewardtokenSupply.sub(totalAmountVestedAndClaimed);
    }
    function stake(
        uint256 _stakingAmount,
        address _beneficiary,
        uint256 _duration,
        uint256 _vestingAmount,
        uint256 _stakingAmountInBusd)
        public payable returns(bytes32){
            require(_stakingAmount > 0, "Staking Amount is 0!");
            require(msg.value >= _stakingAmount, "Tokens sent must be greater than or equal to the staking amount");
            totalAmountStakedPerUser[_beneficiary] = totalAmountStakedPerUser[_beneficiary].add(_stakingAmount);
            totalAmountStaked = totalAmountStaked.add(_stakingAmount);
            payable(address(this)).call{value: msg.value};
            bytes32 vestingScheduleId = createVestingSchedule(_beneficiary, _duration, _vestingAmount);
            emit Stake(msg.sender, _stakingAmount, start, _vestingAmount, _stakingAmountInBusd);
            return vestingScheduleId;
        }
    function createVestingSchedule(
        address _beneficiary,
        uint256 _duration,
        uint256 _amount
    )
        internal
        returns(bytes32){
        require(
            getWithdrawableAmount() >= _amount,
            "TokenVesting: cannot create vesting schedule because not sufficient tokens"
        );
        require(_duration > 0, "TokenVesting: duration must be > 0");
        require(_amount > 0, "TokenVesting: amount must be > 0");
        bytes32 vestingScheduleId = computeNextVestingScheduleIdForHolder(_beneficiary);
        vestingSchedules[vestingScheduleId] = VestingSchedule(
            true,
            _beneficiary,
            _duration,
            _amount,
            0
        );
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.add(_amount);
        totalAmountVestedAndClaimed = totalAmountVestedAndClaimed.add(_amount);
        vestingSchedulesIds.push(vestingScheduleId);
        uint256 currentVestingCount = holdersVestingCount[_beneficiary];
        holdersVestingCount[_beneficiary] = currentVestingCount.add(1);
        return vestingScheduleId;
    }
     function getWithdrawableAmount()
        internal
        view
        returns(uint256){
        return totalRewardtokenSupply.sub(totalAmountVestedAndClaimed);
    }
    function computeNextVestingScheduleIdForHolder(address holder)
        internal
        view
        returns(bytes32){
        return computeVestingScheduleIdForAddressAndIndex(holder, holdersVestingCount[holder]);
    }
    function computeVestingScheduleIdForAddressAndIndex(address holder, uint256 index)
        public
        pure
        returns(bytes32){
        return keccak256(abi.encodePacked(holder, index));
    }
    function claim(bytes32 vestingScheduleId)
    public nonReentrant payable
    {
        require(vestingSchedules[vestingScheduleId].released == 0, "Amount already released");
        require(rewardToken != address(0x0), "Reward Token address must be set to the appropriate address");
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        if(isEligibleForRelease(vestingSchedule)){
            releaseAmount(vestingScheduleId);
            vestingSchedules[vestingScheduleId].released = vestingSchedules[vestingScheduleId].amountTotal;
            vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.sub(vestingSchedules[vestingScheduleId].amountTotal);
            emit Claimed(vestingSchedule.beneficiary, vestingSchedule.amountTotal, block.timestamp);
        }
    }
    function releaseAmount(bytes32 vestingScheduleId)
    internal{
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        bool isBeneficiary = msg.sender == vestingSchedule.beneficiary;
        bool isOwner = msg.sender == owner();
        require(
            isBeneficiary || isOwner,
            "TokenVesting: only beneficiary and owner can release vested tokens"
        );
        address payable beneficiaryPayable = payable(vestingSchedule.beneficiary);
        IERC20(rewardToken).transfer(beneficiaryPayable, vestingSchedules[vestingScheduleId].amountTotal);
    }
    function isEligibleForRelease(VestingSchedule memory vestingSchedule)
    internal
    view
    returns(bool){
        uint256 currentTime = getCurrentTime();
        if (currentTime >= start.add(vestingSchedule.duration)) {
            return true;
        }
        return false;
    }
    function getCurrentTime()
        internal
        virtual
        view
        returns(uint256){
        return block.timestamp;
    }
    function withdraw(address _address, string memory projectId) payable public onlyOwner {
        uint256 withdrawalAmount = address(this).balance;
        (bool os, ) = payable(_address).call{value: address(this).balance}("");
        require(os, "Withdraw not Successful!");
        emit Withdraw(_address, withdrawalAmount, block.timestamp, projectId);
    }
}