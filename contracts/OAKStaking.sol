pragma solidity ^0.4.25;

import "./Permission.sol";
import "./SafeMath.sol";

import "./IERC20.sol";
import "./IRoundCalendar.sol";
import "./IRandomDataSource.sol";
import "./IOAKTGE.sol";


contract OAKEternalStorage {

    struct RewardInfo {
        uint256 roundId;
        uint256 status;//0-default, 1-can be withdrawn 2-withdrawn
        uint256 amount;
    }

    struct UnstakeApplicant {
        uint256 roundId; 
        address user;
        uint256 amount;
        uint256 status;//0-default 1-can be withdrawn 2.Canot be withdrawn 3.withdrawn
    }

    mapping(bytes32 => RewardInfo[]) internal userStakingStorage;
    mapping(bytes32 => address[]) internal stakerStorage;
    mapping(bytes32 => address[]) internal unstakerStorage;
    mapping(bytes32 => UnstakeApplicant) internal unstakeApplicantStorage;

}


pragma experimental ABIEncoderV2;

contract OAKStaking is Permission,OAKEternalStorage{

    using SafeMath for uint;
    event OAKStaked(address staker, uint256 round,uint256 amount, uint256 block);
    event OAKWithdrawn(address user, uint256 round, uint256 amount, uint256 block);
    event ACNRewardWithdrawn(address user, uint256 round, uint256 amount,uint256 block);


  function initialize(  
        address _owner, 
        address _acnToken, 
        address _oakToken,
        address _oakTGEAddress,
        address _roundCalendar,
        uint256 _minStakingAmount) public{
        require(!initialized());
        setOwner(_owner);

        SET_ACN_ADDRESS(_acnToken);
        SET_OAK_ADDRESS(_oakToken);
        SET_OAKTGE_ADDRESS(_oakTGEAddress);
        SET_ROUND_CALENDAR(_roundCalendar);
        SET_MIN_STAKING_AMOUNT(_minStakingAmount);

        boolStorage[keccak256("initialized")] = true;
  }

  function claimToken(address tokenAddress) onlyOwner public {
      address _receiverAddress = address(uint160(getReceiverAddress()));
      if(tokenAddress == address(0)){
          require(_receiverAddress.send(address(this).balance));
          return;
      }
      IERC20 token = IERC20(tokenAddress);
      uint256 balance = token.balanceOf(address(this));
      token.transfer(_receiverAddress, balance);
  }

  function getReceiverAddress() public view returns  (address){
        address _receiverAddress = addressStorage[keccak256("receiverAddress")];
        if(_receiverAddress == address(0)){
            return owner();
        }
        return _receiverAddress;
    }
    
    function stake(uint256 _amount) public{
        require(_amount >= MIN_STAKING_AMOUNT(), "Staking amount shoud be greater than 10");
        IERC20 _token = IERC20(OAK_ADDRESS());
        _token.transferFrom(msg.sender, address(this), _amount);

        uint256 _currentRoundId = currentRoundId();
        bytes32  _userKey = userKey(msg.sender);
        bytes32  _userRoundKey = userRoundKey(msg.sender, _currentRoundId);
        uint256 _currentStakingAmount = uintStorage[_userKey];
        uint256 _currentRoundStakingAmount = uintStorage[_userRoundKey];

        uintStorage[_userRoundKey] = _currentRoundStakingAmount.add(_amount);
        uintStorage[_userKey] = _currentStakingAmount.add(_amount);
        (uint256 _roundTotalStaking, uint256 _roundTotalUsers) = ROUND_STAKING_INFO(_currentRoundId);
        _roundTotalStaking = _roundTotalStaking.add(_amount);
        if(_currentRoundStakingAmount == 0){
            _roundTotalUsers = _roundTotalUsers.add(1);
        }
        SAVE_ROUND_STAKING_INFO(_currentRoundId, _roundTotalStaking, _roundTotalUsers);

        (uint256 _totalStaking, uint256 _totalUsers) = STAKING_INFO();
        if(_currentStakingAmount == 0){
            _totalUsers = _totalUsers.add(1);
            address[] storage _users = stakerStorage[stakerKey()];
            _users.push(msg.sender);
            stakerStorage[stakerKey()] = _users;
            SAVE_STAKER_INDEX(msg.sender, _users.length-1);            
        }
        
        _totalStaking = _totalStaking.add(_amount);
        SAVE_STAKING_INFO(_totalStaking, _totalUsers);

        updateSnapshotByUser();
        emit OAKStaked(msg.sender, _currentRoundId, _amount, block.number);
    }
    function currentRoundId() public view returns(uint256){
        return roundCalendarInterface().CURRENT_ROUND();
    }
    function sendOAKForApplicants(uint256 _roundId, uint256 _fromIndex, uint256 _toIndex) public hasAdminRole{
        require(currentRoundId().sub(_roundId) > 0);
        address[] storage _users = unstakerStorage[unStakerKey(_roundId)];
        if (_toIndex > _users.length){
            _toIndex = _users.length;
        }
        for (uint i=_fromIndex; i < _toIndex ; i++) {
            address user = _users[i];
            UnstakeApplicant memory _unstakeApplicant = ROUND_UNSTAKE_APPLICANT_INFO(user, _roundId);
            if(_unstakeApplicant.amount > 0){
                IERC20 _token = IERC20(OAK_ADDRESS());
                _token.transfer(user, _unstakeApplicant.amount);

                _unstakeApplicant.amount = 0;
                SAVE_UNSTAKE_APPLICANT_INFO(_unstakeApplicant);
            }
        }
    }



    function userConfirmOAKWithdraw(uint256 _roundId) public{
        uint256 _currentRoundId = currentRoundId();
        require(_currentRoundId.sub(_roundId) > 0);
        UnstakeApplicant memory _unstakeApplicant = ROUND_UNSTAKE_APPLICANT_INFO(msg.sender, _roundId);
        require(_unstakeApplicant.amount > 0, "you dont have oak to withdraw");
        IERC20 _token = IERC20(OAK_ADDRESS());
        _token.transfer(msg.sender, _unstakeApplicant.amount);

        _unstakeApplicant.amount = 0;
        SAVE_UNSTAKE_APPLICANT_INFO(_unstakeApplicant);

        updateSnapshotByUser();

    }

    function updateSnapshotByUser() internal{
        //Update snapshot info when user have action on staking smart contract
        (uint256 _totalStaking, ) = STAKING_INFO();
        uint256 _currentRoundId = currentRoundId();
        SAVE_SNAPSHOT_STAKING_AMOUNT(_currentRoundId, _totalStaking);
        SAVE_USER_SNAPSHOT_STAKING_AMOUNT(msg.sender, _currentRoundId, getStakingAmount(msg.sender));
        if(!USER_SNAPSHOTED(msg.sender,_currentRoundId)){
            SAVE_USER_SNAPSHOTED(msg.sender,_currentRoundId, true);
        }

    }

    function withdrawOAK(uint256 _amount) public{
        uint256 _currentStakingAmount = getStakingAmount(msg.sender);
        require(_amount > 0 && _amount <= _currentStakingAmount, "You dont have enough OAK to withdraw");

        bytes32  _userKey = userKey(msg.sender);
        uintStorage[_userKey] = _currentStakingAmount.sub(_amount);

        if(uintStorage[_userKey] == 0){//Clear current user from the stakers if the staking amount is zero
            address[] memory _stakers = stakerStorage[stakerKey()];
            delete _stakers[STAKER_INDEX(msg.sender)];
        }
         
        (uint256 _totalStaking, uint256 _totalUsers) = STAKING_INFO();
        if(_totalUsers > 0 && _totalStaking > _amount){
            _totalStaking = _totalStaking.sub(_amount);
            _totalUsers = _totalUsers.sub(1);
            SAVE_STAKING_INFO(_totalStaking, _totalUsers);
        }

        uint256 _currentRoundId = currentRoundId();
        UnstakeApplicant memory _unstakeApplicant = ROUND_UNSTAKE_APPLICANT_INFO(msg.sender, _currentRoundId);
        if(_unstakeApplicant.amount == 0){
            bytes32 _unStakerKey = unStakerKey(_currentRoundId);
            address[] storage _users = unstakerStorage[_unStakerKey];
            _users.push(msg.sender);
            unstakerStorage[_unStakerKey] = _users;
            _unstakeApplicant.roundId = _currentRoundId;
            _unstakeApplicant.user = msg.sender;
            _unstakeApplicant.amount = _amount;
        }else{
            _unstakeApplicant.amount = _unstakeApplicant.amount.add(_amount);
        }
        SAVE_UNSTAKE_APPLICANT_INFO(_unstakeApplicant);

        updateSnapshotByUser();

        emit OAKWithdrawn(msg.sender, _currentRoundId, _currentStakingAmount, block.number);
        
    }

    function withdrawACNReward(uint256 _roundId) public{
        // require(SNAPSHOT_DONE(_roundId), "Snapshot has not been done");
        require(currentRoundId().sub(_roundId) > 0, "Round ACN Reward should been withdrawn after 1 round");
        require(!IS_ROUND_REWARD_WITHDRAWN(msg.sender, _roundId), "Round ACN Reward has been withdrawn");
        uint256 _snapshotStakingAmount = SNAPSHOT_USER_STAKING_AMOUNT(msg.sender, _roundId);
        uint256 _snapshotTotalStakingAmount = SNAPSHOT_STAKING_AMOUNT(_roundId);
        require(_snapshotStakingAmount <= _snapshotTotalStakingAmount, "Round reward exception");

        uint256 _roundTotalACN = roundACNReward(_roundId);
        uint256 _rewardACNForUser = _snapshotStakingAmount.mul(_roundTotalACN).div(_snapshotTotalStakingAmount);

        require(_rewardACNForUser > 0, "You have nothing to withdraw");
        IERC20 _token = IERC20(ACN_ADDRESS());
        _token.transfer(msg.sender, _rewardACNForUser);
        SAVE_IS_ROUND_REWARD_WITHDRAWN(msg.sender, _roundId, true);

        updateSnapshotByUser();

        emit ACNRewardWithdrawn(msg.sender, _roundId, _rewardACNForUser, block.number);
    }

    function multiWithdrawACNReward(uint256[] _roundIds) public{
        require(_roundIds.length > 0, "No rounds to withdraw");
        for(uint256 i = 0;i < _roundIds.length; i++){
            withdrawACNReward(_roundIds[i]);
        }
    }

    function getStakers(uint256 _fromIndex, uint256 _toIndex) public view returns(address[]){
        address[] memory _users = stakerStorage[stakerKey()];
        if(_toIndex > _users.length){
            _toIndex = _users.length;
        }
        uint256 _size = _toIndex.sub(_fromIndex);
        address[] memory _result = new address[](_size);
        uint256 _rIndex = 0;
        for(uint256 i = _fromIndex;i<_toIndex;i++){
            _result[_rIndex] = _users[i];
            _rIndex++;
        }
        return _result;
    }

    //Only For Testing
    function getStakers() public view returns(address[]){
        address[] memory _users = stakerStorage[stakerKey()];
        return _users;
    }

    //Only For Testing
    function clearStakers() public hasAdminRole{
        address[] memory _users;
        stakerStorage[stakerKey()] = _users;
    }
    //Only For Testing
    function addStakers(address[] _stakers) public hasAdminRole{
        address[] memory _users = new address[](_stakers.length);
        for(uint256 i = 0; i< _stakers.length;i++){
            _users[i] = _stakers[i];
        }
        stakerStorage[stakerKey()] = _users;
    }
    //Only For Testing
    function clearUserData(address _user, uint256[] _roundIds) public hasAdminRole{
        for(uint256 i=0;i<_roundIds.length;i++){
            uint256 _roundId = _roundIds[i];
            SAVE_USER_SNAPSHOT_STAKING_AMOUNT(_user, _roundId, 0);
        }
        bytes32  _userKey = userKey(_user);
        uintStorage[_userKey] = 0;
    }

    function snapshotRoundInfo(uint256 _roundId, uint256 _fromIndex, uint256 _toIndex) public hasAdminRole{
        require(currentRoundId().sub(_roundId) > 0, "You can only snapshot the history round");
        address[] memory _users = stakerStorage[stakerKey()];
        if(_toIndex > _users.length){
            _toIndex = _users.length;
        }
        for(uint256 i = _fromIndex; i < _toIndex;i++){
            address _user = _users[i];
            SAVE_USER_SNAPSHOT_STAKING_AMOUNT(_user, _roundId, getStakingAmount(_user));
        }
    }
    function snapshotRoundInfo(uint256 _roundId, uint256 _size) public hasAdminRole{
        uint256 _currentRoundId = currentRoundId();
        require(_currentRoundId.sub(_roundId) > 0, "You can only snapshot the history round");
        address[] memory _users = stakerStorage[stakerKey()];
        uint256 _fromIndex = SNAPSHOTED_INDEX(_roundId);
        uint256 _toIndex = _fromIndex.add(_size);
        if(_toIndex > _users.length){
            _toIndex = _users.length;
        }
        for(uint256 i = _fromIndex; i < _toIndex;i++){
            address _user = _users[i];
            if(!USER_SNAPSHOTED(_user,_roundId)){
                uint256 _currentRoundStakingAmount = getRoundStakingAmount(_user, _currentRoundId);
                uint256 _currentStakingAmount = getStakingAmount(_user);
                if(_currentStakingAmount > _currentRoundStakingAmount){
                    _currentStakingAmount = _currentStakingAmount.sub(_currentRoundStakingAmount);
                }
                SAVE_USER_SNAPSHOT_STAKING_AMOUNT(_user, _roundId, _currentStakingAmount);
            }
        }
        SAVE_SNAPSHOTED_INDEX(_roundId, _toIndex);
    }

    function snapshotLastRoundInfo(uint256 _fromIndex, uint256 _toIndex) public hasAdminRole{
        snapshotRoundInfo(currentRoundId() - 1,_fromIndex, _toIndex);
    }

    function snapshotRoundTotalInfo(uint256 _roundId) public hasAdminRole{
        require(OAKTGE(OAKTGE_ADDRESS()).IS_ROUND_RESULTED(_roundId));
        (uint256 _totalStaking,) = STAKING_INFO();
        (uint256 _roundStakingAmount,) = ROUND_STAKING_INFO(currentRoundId());
        if(_totalStaking > _roundStakingAmount){
            _totalStaking = _totalStaking.sub(_roundStakingAmount);
        }
        SAVE_SNAPSHOT_STAKING_AMOUNT(_roundId, _totalStaking);
        SAVE_SNAPSHOT_DONE(_roundId, true);

    }

    function snapshotLastRoundTotalInfo() public hasAdminRole{
        snapshotRoundTotalInfo(currentRoundId() - 1);
    }

    function roundACNReward(uint256 _roundId) public view returns(uint256){
        OAKTGE _oakTge = OAKTGE(OAKTGE_ADDRESS());
        return _oakTge.ROUND_ACN_REWARD(_roundId);
    }

    function getStakingAmount(address _user) public view returns(uint256){
        bytes32  _userKey = userKey(_user);
        uint256 _currentStakingAmount = uintStorage[_userKey];
        return _currentStakingAmount;
    }

    function getRoundStakingAmount(address _user, uint256 _roundId) public view returns(uint256){
        bytes32  _userRoundKey = userRoundKey(_user, _roundId);
        uint256  _currentRoundStakingAmount = uintStorage[_userRoundKey];
        return   _currentRoundStakingAmount;
    }

    function getRoundReward(address _user, uint256 _roundId) public view returns(RewardInfo){
        uint256 _snapshotStakingAmount = SNAPSHOT_USER_STAKING_AMOUNT(_user, _roundId);
        uint256 _snapshotTotalStakingAmount = SNAPSHOT_STAKING_AMOUNT(_roundId);
        uint256 _roundTotalACN = roundACNReward(_roundId);

        RewardInfo memory rewardInfo;
        uint256 _rewardACNForUser = 0;
        if(_snapshotTotalStakingAmount > 0 && _snapshotStakingAmount <= _snapshotTotalStakingAmount){
            _rewardACNForUser = _snapshotStakingAmount.mul(_roundTotalACN).div(_snapshotTotalStakingAmount);
        }
        uint256 status = 0;
        if(IS_ROUND_REWARD_WITHDRAWN(_user, _roundId)){
            status = 2;
        }else{
            if(_rewardACNForUser > 0){
                status = 1;
            }
        }
        rewardInfo.status = status;
        rewardInfo.amount = _rewardACNForUser;
        rewardInfo.roundId = _roundId;
        return rewardInfo;
    }

    function getRoundRewardList(address _user, uint256 _fromRound, uint256 _toRound) public view returns(RewardInfo[]){
        uint256 _size =  _toRound.sub(_fromRound);
        RewardInfo[] memory _rewardList = new RewardInfo[](_size);
        uint256 _rIndex = 0;
        for(uint256 _roundId = _fromRound;_roundId<_toRound;_roundId++){
            _rewardList[_rIndex] = getRoundReward(_user, _roundId);
            _rIndex++;
        }
        return _rewardList;
    }

    function getRoundApplicantList(address _user, uint256 _fromRound, uint256 _toRound) public view returns(UnstakeApplicant[]){
        uint256 _size =  _toRound.sub(_fromRound);
        UnstakeApplicant[] memory _unstakeApplicants = new UnstakeApplicant[](_size);
        uint256 _rIndex = 0;
        uint256 _currentRoundId = currentRoundId();
        for(uint256 _roundId = _fromRound;_roundId<_toRound;_roundId++){
             UnstakeApplicant memory _unstakeApplicant = ROUND_UNSTAKE_APPLICANT_INFO(_user, _roundId);
            if(_unstakeApplicant.amount > 0){
                if(_currentRoundId > _roundId){
                    _unstakeApplicant.status = 1;
                }else{
                    _unstakeApplicant.status = 2;
                }
            }else{
                _unstakeApplicant.status = 3;
            }
            _unstakeApplicants[_rIndex] = _unstakeApplicant;
            _rIndex++;
        }
        return _unstakeApplicants;
    }


  function roundCalendarInterface() internal view returns(RoundCalendar){
      return RoundCalendar(ROUND_CALENDAR());
  }


    function ROUND_STAKING_INFO(uint256 _roundID)  public view returns (uint256, uint256)  {
        return (
            uintStorage[keccak256(abi.encodePacked("ROUND_STAKING_INFO_AMOUNT", _roundID))],
            uintStorage[keccak256(abi.encodePacked("ROUND_STAKING_INFO_USERS", _roundID))]
        );
    }

    function SAVE_ROUND_STAKING_INFO(uint256 _roundID, uint256 _totalStakingAmount, uint256 _totalStakingUsers) internal  {
        uintStorage[keccak256(abi.encodePacked("ROUND_STAKING_INFO_AMOUNT", _roundID))] = _totalStakingAmount;
        uintStorage[keccak256(abi.encodePacked("ROUND_STAKING_INFO_USERS", _roundID))] = _totalStakingUsers;
    }

    function SAVE_ROUND_STAKING_USER(uint256 _roundID, uint256 _totalStakingUsers) internal  {
        uintStorage[keccak256(abi.encodePacked("ROUND_STAKING_INFO_USERS", _roundID))] = _totalStakingUsers;
    }

    function SAVE_ROUND_STAKING_AMOUNT(uint256 _roundID, uint256 _totalStakingAmount) internal  {
        uintStorage[keccak256(abi.encodePacked("ROUND_STAKING_INFO_AMOUNT", _roundID))] = _totalStakingAmount;
    }

    function SAVE_SNAPSHOT_STAKING_AMOUNT(uint256 _roundId, uint256 _totalStakingAmount) internal  {
        uintStorage[keccak256(abi.encodePacked("SNAPSHOT_STAKING_AMOUNT", _roundId))] = _totalStakingAmount;
    }

    function SAVE_SNAPSHOT_DONE(uint256 _roundId, bool _done) internal  {
        boolStorage[keccak256(abi.encodePacked("SNAPSHOT_DONE", _roundId))] = _done;
    }

    function SNAPSHOT_DONE(uint256 _roundId) public view returns(bool){
        return boolStorage[keccak256(abi.encodePacked("SNAPSHOT_DONE", _roundId))];
    }

    function SNAPSHOT_STAKING_AMOUNT(uint256 _roundId) public view returns(uint256) {
        return uintStorage[keccak256(abi.encodePacked("SNAPSHOT_STAKING_AMOUNT", _roundId))];
    }

    function SAVE_USER_SNAPSHOT_STAKING_AMOUNT(address _user, uint256 _roundId, uint256 _totalStakingAmount) internal  {
        uintStorage[keccak256(abi.encodePacked("USER_SNAPSHOT_STAKING_AMOUNT", _user, _roundId))] = _totalStakingAmount;
    }

    function SNAPSHOT_USER_STAKING_AMOUNT(address _user, uint256 _roundId) public view returns(uint256) {
        return uintStorage[keccak256(abi.encodePacked("USER_SNAPSHOT_STAKING_AMOUNT", _user,  _roundId))];
    }

     function SAVE_USER_SNAPSHOTED(address _user, uint256 _roundId, bool _snapshoted) internal  {
        boolStorage[keccak256(abi.encodePacked("USER_SNAPSHOTED", _user, _roundId))] = _snapshoted;
    }

    function USER_SNAPSHOTED(address _user, uint256 _roundId) public view returns(bool) {
        return boolStorage[keccak256(abi.encodePacked("USER_SNAPSHOTED", _user, _roundId))];
    }

    function STAKING_INFO()  public view returns (uint256, uint256)  {
        return (
            uintStorage[keccak256("STAKING_INFO_AMOUNT")],
            uintStorage[keccak256("STAKING_INFO_USERS")]
        );
    }

    function SAVE_STAKING_INFO(uint256 _totalStakingAmount, uint256 _totalStakingUsers) internal  {
        uintStorage[keccak256("STAKING_INFO_AMOUNT")] = _totalStakingAmount;
        uintStorage[keccak256("STAKING_INFO_USERS")] = _totalStakingUsers;
    }

    function SAVE_STAKING_USER(uint256 _totalStakingUsers) internal  {
        uintStorage[keccak256("STAKING_INFO_USERS")] = _totalStakingUsers;
    }

    function SAVE_STAKING_AMOUNT(uint256 _totalStakingAmount) internal  {
        uintStorage[keccak256("STAKING_INFO_AMOUNT")] = _totalStakingAmount;
    }

    function ACN_ADDRESS() public view returns (address) {
        return addressStorage[keccak256("ACN_ADDRESS")];
    }

    function SET_ACN_ADDRESS(address _new) onlyOwner public  {
        addressStorage[keccak256("ACN_ADDRESS")] = _new;
    }

    function OAK_ADDRESS() public view returns (address) {
        return addressStorage[keccak256("OAK_ADDRESS")];
    }

    function SET_OAK_ADDRESS(address _new) onlyOwner public  {
        addressStorage[keccak256("OAK_ADDRESS")] = _new;
    }

    function OAKTGE_ADDRESS() public view returns (address) {
        return addressStorage[keccak256("OAK_TGE_ADDRESS")];
    }

    function SET_OAKTGE_ADDRESS(address _new) onlyOwner public  {
        addressStorage[keccak256("OAK_TGE_ADDRESS")] = _new;
    }


    function SET_ROUND_CALENDAR(address _new) onlyOwner public  {
        addressStorage[keccak256("ROUND_CALENDAR")] = _new;
    }

    function ROUND_CALENDAR() public view returns (address) {
        return addressStorage[keccak256("ROUND_CALENDAR")];
    }

    function SAVE_ROUND_INFO(uint256 _roundID, uint256 _totalTickets) internal  {
        uintStorage[keccak256(abi.encodePacked("ROUND_INFO", _roundID))] = _totalTickets;
    }

    function MIN_STAKING_AMOUNT() public view returns (uint256)  {
        return uintStorage[keccak256("MIN_STAKING_AMOUNT")];
    }

    function SET_MIN_STAKING_AMOUNT(uint256 _minStakingAmount)  onlyOwner public  {
        uintStorage[keccak256("MIN_STAKING_AMOUNT")] = _minStakingAmount;
    }

    function SNAPSHOTED_INDEX(uint256 _roundId) public view returns (uint256)  {
        return uintStorage[keccak256(abi.encodePacked("SNAPSHOTED_INDEX", _roundId))];
    }

    function SAVE_SNAPSHOTED_INDEX(uint256 _roundId, uint256 _index) internal {
        uintStorage[keccak256(abi.encodePacked("SNAPSHOTED_INDEX", _roundId))] = _index;
    }

    function SAVE_IS_ROUND_REWARD_WITHDRAWN(address _user, uint256 _roundId, bool _isWithdrawn) internal {
        boolStorage[keccak256(abi.encodePacked("IS_ROUND_REWARD_WITHDRAWN", _user, _roundId))] = _isWithdrawn;
    }

    function IS_ROUND_REWARD_WITHDRAWN(address _user, uint256 _roundId) public view returns (bool)  {
        return boolStorage[keccak256(abi.encodePacked("IS_ROUND_REWARD_WITHDRAWN", _user,  _roundId))];
    }

    function ROUND_UNSTAKE_APPLICANT_INFO(address _user, uint256 _roundId) public view returns (UnstakeApplicant)  {
        return unstakeApplicantStorage[keccak256(abi.encodePacked("ROUND_UNSTAKE_APPLICANT_INFO", _user,  _roundId))];
    }

    function SAVE_UNSTAKE_APPLICANT_INFO(UnstakeApplicant _applicant) internal{
        unstakeApplicantStorage[keccak256(abi.encodePacked("ROUND_UNSTAKE_APPLICANT_INFO", _applicant.user,  _applicant.roundId))] = _applicant;
    }

    function STAKER_INDEX(address _user) public view returns (uint256)  {
        return uintStorage[keccak256(abi.encodePacked("STAKER_INDEX", _user))];
    }

    function SAVE_STAKER_INDEX(address _user, uint256 _index) internal  {
        uintStorage[keccak256(abi.encodePacked("STAKER_INDEX", _user))] = _index;
    }

  function userRoundKey(address _userAddress, uint256 _roundId) internal pure returns(bytes32){
      return keccak256(abi.encodePacked("user_round", _userAddress, _roundId));
  }

  function userKey(address _userAddress) internal pure returns(bytes32){
      return keccak256(abi.encodePacked("user", _userAddress));
  }

  function stakerKey() internal pure returns(bytes32){
      return keccak256("stakers");
  }

  function unStakerKey(uint256 _roundId) internal pure returns(bytes32){
      return keccak256(abi.encodePacked("unStakers", _roundId));
  }

  function initialized() public view returns (bool) {
        return boolStorage[keccak256("initialized")];
  }

  

  


}
