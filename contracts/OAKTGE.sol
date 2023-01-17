pragma solidity ^0.4.25;

import "./Permission.sol";
import "./SafeMath.sol";

import "./IERC20.sol";
import "./IRoundCalendar.sol";
import "./IRandomDataSource.sol";

contract OAKEternalStorage {

    struct OAKTicket {
        uint256 block;
        uint256 roundId; // the date the ticket was created
        uint256 index; // the index of the ticket
        uint256 status;//0-default 1-selected，2-unselected 3-withdrawn 4.refunded 5.can be withdrawn
        uint256 price;
        uint256 baseFeeRate;
        uint256 devFeeRate;
    }
    
    struct OAKConfig {
        uint256 burnFeeRate;//will send this part to the dead address
        uint256 devFeeRate;//will send this part to the dev foundation wallet address
        uint256 baseFeeRate;//will send this part to the dead address
        uint256 rewardFeeRate;//will send this part to the staking smart contract
        uint256 roundTotalLimit;//The total limit for a single round
        uint256 roundTimeLimit;//The limit for a single purchase
    }

    struct RoundResult {
        uint256 roundId; 
        bool allSelected;
        bool executed;
    }
    


    mapping(bytes32 => address[]) internal roundUserStorage;

    mapping(bytes32 => uint256[]) internal userRoundTicketIndexes;
    mapping(bytes32 => OAKTicket[]) internal userTicketStorage;




}

pragma experimental ABIEncoderV2;

contract OAKTGE is Permission, OAKEternalStorage{

    using SafeMath for uint;
    event OAKTicketed(address buyer, uint256 round,uint256 index);
    event OAKWithdrawn(address user, uint256 round, uint256 amount);
    event OAKRefund(address user, uint256 round, uint256 amount);
    
    event ACNBurnt(uint256 round, address _receiver, uint256 amount);
    event ACNDevFeeReceived(uint256 round, address _receiver, uint256 amount);
    event ACNBaseFeeReceived(uint256 round, address _receiver, uint256 amount);
    event ACNRewardReceived(uint256 round, address _receiver, uint256 amount);

  function initialize(  
        address _owner, 
        address _devFeeReceiver,
        address _baseFeeReceiver,
        address _rewardCollector,
        address _randomDataSource,
        address _roundCalendar,
        uint256[] _feeRates,
        uint256[] _limits,
        address _acnToken, 
        address _oakToken) public{

        require(!initialized());
        setOwner(_owner);

        require(
            _feeRates[0].add(_feeRates[1]).add(_feeRates[2]).add(_feeRates[3]) == 100, 
            "Please set a correct fee rate");
        require(
            _limits[0] > 0 && _limits[1] > 0, "Please set a correct limit");

        SET_BASE_FEE_RATE(_feeRates[0]);
        SET_BURN_RATE(_feeRates[1]);
        SET_DEV_FEE_RATE(_feeRates[2]);
        SET_REWARD_RATE(_feeRates[3]);

        SAVE_ROUND_LIMIT(_limits[0], _limits[1]);
        
        SET_DEV_FEE_ADDRESS(_devFeeReceiver);
        SET_BASE_FEE_ADDRESS(_baseFeeReceiver);
        SET_REWARD_COLLECTOR(_rewardCollector);
        SET_DEAD_ADDRESS(0x000000000000000000000000000000000000dEaD);
        SET_ACN_ADDRESS(_acnToken);
        SET_OAK_ADDRESS(_oakToken);
        SET_RANDOM_DATA_SOURCE(_randomDataSource);
        SET_ROUND_CALENDAR(_roundCalendar);


        boolStorage[keccak256("initialized")] = true;
  }

  function initialized() public view returns (bool) {
        return boolStorage[keccak256("initialized")];
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
  
  /* Return dailly oak mint info
  /* Return the price that use ACN to buy OAK
  */
  function getPublicPeriodInfo() public view returns (uint256 _dallyMint, uint256 _price){
        uint256 blockNumber = block.number;
        return _getPeriodInfo(blockNumber);
  }

  function roundCalendarInterface() internal view returns(RoundCalendar){
      return RoundCalendar(ROUND_CALENDAR());
  }

  function _getPeriodInfo(uint256 blockNumber) internal view returns (uint256 _dallyMint, uint256 _price){
        if(blockNumber == 0){
            blockNumber = block.number;
        }
        RoundCalendar _roundCalendar = roundCalendarInterface();
        uint256 _BLOCKS_PER_PERIOD = _roundCalendar.BLOCKS_PER_PERIOD();
        uint256 _GENESIS_BLOCK = _roundCalendar.GENESIS_BLOCK();
        uint256 _PRE_PERIOD = _GENESIS_BLOCK + 15 * _BLOCKS_PER_PERIOD;
        uint256 _MAIN_PERIOD_0 = _PRE_PERIOD + 30 * _BLOCKS_PER_PERIOD;
        uint256 _MAIN_PERIOD_1 = _MAIN_PERIOD_0 + 180 * _BLOCKS_PER_PERIOD;
        uint256 _MAIN_PERIOD_2 = _MAIN_PERIOD_1 + 180 * _BLOCKS_PER_PERIOD;
        uint256 _MAIN_PERIOD_3 = _MAIN_PERIOD_2 + 180 * _BLOCKS_PER_PERIOD;
        uint256 _MAIN_PERIOD_4 = _MAIN_PERIOD_3 + 180 * _BLOCKS_PER_PERIOD;
        uint256 _MAIN_PERIOD_5 = _MAIN_PERIOD_4 + 360 * _BLOCKS_PER_PERIOD;

        if(blockNumber >= _GENESIS_BLOCK && blockNumber < _PRE_PERIOD){
             _dallyMint = 1000000;
             _price = 10;
        }else if(blockNumber >= _PRE_PERIOD && blockNumber < _MAIN_PERIOD_0){
            _dallyMint = 500000;
            _price = 20;
        }else if(blockNumber >= _MAIN_PERIOD_0 && blockNumber < _MAIN_PERIOD_1){
            _dallyMint = 250000;
            _price = 40;
        }else if(blockNumber >= _MAIN_PERIOD_1 && blockNumber < _MAIN_PERIOD_2){
            _dallyMint = 12500;
             _price = 80;
        }else if(blockNumber >= _MAIN_PERIOD_2 && blockNumber < _MAIN_PERIOD_3){
            _dallyMint = 62500;
             _price = 160;
        }else if(blockNumber >= _MAIN_PERIOD_3 && blockNumber < _MAIN_PERIOD_4){
            _dallyMint = 31250;
             _price = 320;
        }else if(blockNumber >= _MAIN_PERIOD_4 && blockNumber < _MAIN_PERIOD_5){
            _dallyMint = 15625;
             _price = 640;
        }
        _price = 1;//Only for Testing
        _dallyMint = 500;//Only for Testing
        if(PRICE_PER_TICKET() > 0){
            //if there are voted price, return _votedPrice
            _price = PRICE_PER_TICKET();
        }

  }


  function userKey(address _userAddress) internal pure returns(bytes32){
      return keccak256(abi.encodePacked("user_t", _userAddress));
  }

  function roundUsersKey(uint256 _roundId) internal pure returns(bytes32){
      return keccak256(abi.encodePacked("round_users", _roundId));
  }

  function ticketRoundIndexKey(address _user, uint256 _roundId) internal pure returns(bytes32){
      return keccak256(abi.encodePacked("t_r_index", _user,_roundId));
  }


function storeUserTickets(uint256 _dayRoundId, uint256 _price, uint256 _fromTicket, uint256 _totalTickets) internal{
      uint256 _toTicket = _fromTicket.add(_totalTickets);
      OAKTicket[] storage userTickets = userTicketStorage[userKey(msg.sender)];
      bytes32  _userRoundKey = ticketRoundIndexKey(msg.sender, _dayRoundId);
      uint256[] storage userRoundTicketKeys = userRoundTicketIndexes[_userRoundKey];
      uint256 _baseFeeRate = BASE_FEE_RATE();
      uint256 _devFeeRate = DEV_FEE_RATE();
      uint256 _block = block.number;
      uint256 _total = userTickets.length;
      for(uint256 i = _fromTicket; i < _toTicket; i++){
          OAKTicket memory ticket = OAKTicket(
              _block,_dayRoundId,i,0,_price, _baseFeeRate, _devFeeRate
          );
          userTickets.push(ticket);
          userRoundTicketKeys.push(_total);
          _total++;
          emit OAKTicketed(msg.sender, _dayRoundId, i);
      }
}


  function buyOAKTicket(uint256 _tickets) public returns (bool){
      require(_tickets > 0 && _tickets <= ROUND_TIME_LIMIT(), "Not Allowed to buy more than 100 per payment"); 
      uint256 _dayRoundId = roundCalendarInterface().CURRENT_ROUND();
      uint256 _userRoundTotals = totalUserRoundOAKTickets(msg.sender, _dayRoundId);
      require(_userRoundTotals.add(_tickets) <= ROUND_TOTAL_LIMIT(), "Not Allowed to buy more than 500 per round");
      
      if(_userRoundTotals ==0){//Store current round users
          bytes32 _roundUsersKey = roundUsersKey(_dayRoundId);
          address[] storage _users = roundUserStorage[_roundUsersKey];
          _users.push(msg.sender);
      }

      (, uint256 _price) = getPublicPeriodInfo();
      uint256 _totalACN = _tickets * _price * 10**18;
      IERC20 _token = IERC20(ACN_ADDRESS());
      _token.transferFrom(msg.sender, address(this), _totalACN);  

      uint256 _totalTickets = ROUND_TICKETS(_dayRoundId);
      uint256 _newTotalTickets = _totalTickets.add(_tickets);

      SAVE_ROUND_TICKETS(_dayRoundId, _newTotalTickets);
      SAVE_ROUND_ACN_INFO(_dayRoundId, _totalACN.add(ROUND_ACN_INFO(_dayRoundId)));
      storeUserTickets(_dayRoundId, _price, _totalTickets, _tickets);
      
      return true;
  }





  function checkRewarded(uint256 _roundId, uint256 _index) internal view returns(bool) {
      if(IS_ROUND_ALL_SELECTED(_roundId)){
          return true;
      }
      RandomDataSource _random = RandomDataSource(RANDOM_DATA_SOURCE());
      return _random.isRandomSelected(_roundId, _index);
  }

  function checkRefunded(address _user, uint256 _roundId, uint256 _index) internal view returns(bool) {
      return IS_ROUND_REFUNDED(_user, _roundId, _index);
  }

  
  function checkRoundOAKSupply(uint256 _roundId) internal view returns(bool) {
    (uint256 _dallyMint,) = getRoundBaseInfo(_roundId);
    if(ROUND_OAK_MINT_INFO(_roundId) <= (_dallyMint * 10**18)){
        return true;
    }else{
        return false;
    }
  }

  function checkRoundTime(uint256 _roundId) internal view returns(bool) {
      uint256 _currentRoundId = roundCalendarInterface().CURRENT_ROUND();
      if(_currentRoundId.sub(_roundId) > 0){
          return true;
      }
      return false;
  }

  function withdrawOAK(uint256 _roundId) public{
      require(checkRoundTime(_roundId), "Round not reached");//
      require(checkRoundRewardDataDone(_roundId), "Round result has not been executed");
      require(!IS_ROUND_WITHDRAWN(msg.sender, _roundId), "Round has been withdrawn");
      require(checkRoundOAKSupply(_roundId), "Round supply exception");

      bytes32  _userRoundKey = ticketRoundIndexKey(msg.sender, _roundId);
      uint256[] storage userRoundTicketKeys = userRoundTicketIndexes[_userRoundKey];
      OAKTicket[] storage userTickets = userTicketStorage[userKey(msg.sender)];
      
      uint256 _total = userRoundTicketKeys.length;
      uint256 _oakNumber = 0;
      bool isSelectedAll = IS_ROUND_ALL_SELECTED(_roundId);
      if(isSelectedAll){
          _oakNumber = _total * 10**18;
      }else{
          for(uint256 i;i<_total;i++){
              OAKTicket memory _ticket = userTickets[userRoundTicketKeys[i]];
              if(checkRewarded(_roundId, _ticket.index )){
                  _oakNumber = _oakNumber.add(10**18);
              }
        }
      }
      require(_oakNumber !=0, "You dont have OAK to be withdrawn");
      IERC20 _token = IERC20(OAK_ADDRESS());
      require(_token.mintTo(msg.sender, _oakNumber));
      SAVE_ROUND_OAK_MINT_INFO(_roundId, _oakNumber);
      SET_IS_ROUND_WITHDRAWN(msg.sender, _roundId, true);
      emit OAKWithdrawn(msg.sender, _roundId, _oakNumber);
      
  }

 function totalUserOAKTickets(address _user) public view returns(uint256 _total){
      OAKTicket[] storage userTickets = userTicketStorage[userKey(_user)];
      return userTickets.length;
  }

  function totalUserRoundOAKTickets(address _user,uint256 _roundId) public view returns(uint256 _total){
      uint256[] storage userRoundTicketKeys = userRoundTicketIndexes[ticketRoundIndexKey(_user, _roundId)];
      return userRoundTicketKeys.length;
  }
  
  
  function getUserOAKRoundTickets(address _user, uint256 _roundId, uint256 _fromIndex, uint256 _toIndex) public view returns(uint256[] memory){
    require(_toIndex > _fromIndex, "You should set a correct range");
    uint256[] storage userRoundTicketKeys = userRoundTicketIndexes[ticketRoundIndexKey(_user, _roundId)];
    uint256 _totalTickets = userRoundTicketKeys.length;
    if(_toIndex > _totalTickets){
        _toIndex = _totalTickets;
    }
    uint256 _size =  _toIndex.sub(_fromIndex);
    uint256[] memory _result = new uint256[](_size);
    uint256 _rIndex = 0;
    for(uint256 i = _fromIndex; i < _toIndex; i++){
        _result[_rIndex] = userRoundTicketKeys[i];
        _rIndex++;
    }
    return _result;
  }

  function getUserOAKTickets(address _user, uint256 _fromIndex, uint256 _toIndex) public view returns(OAKTicket[] memory){
    require(_toIndex > _fromIndex, "You should set a correct range");
    OAKTicket[] storage userTickets = userTicketStorage[userKey(_user)];
    uint256 _totalTickets = userTickets.length;
    if(_toIndex > _totalTickets){
        _toIndex = _totalTickets;
    }
    uint256 _size =  _toIndex.sub(_fromIndex);
    OAKTicket[] memory _result = new OAKTicket[](_size);
    uint256 _rIndex = 0;
    for(uint256 i = _fromIndex; i < _toIndex; i++){
        OAKTicket memory _ticket = userTickets[i];
        _ticket.status = 0;
        uint256 _roundId = _ticket.roundId;
        bool roundDone = checkRoundRewardDataDone(_roundId);
        if(IS_ROUND_RESULTED(_roundId) && roundDone){
            if(checkRewarded(_roundId, _ticket.index )){
            _ticket.status = 1;
            if(IS_ROUND_WITHDRAWN(_user, _roundId)){
                _ticket.status = 3;
            }else{
                if(_ticket.status == 1 && checkRoundTime(_roundId)){
                    _ticket.status = 5;
                }
            }
            }else{
                if(checkRefunded(_user, _roundId, _ticket.index)){
                _ticket.status = 4;
                }else{
                _ticket.status = 2;
                }
            }
        }
        
        _result[_rIndex] = _ticket;
        _rIndex++;
    }
    return _result;
  }

  function getRoundUsers(uint256 _roundId, uint256 _fromIndex, uint256 _toIndex) public view returns(address[]){
    require(_toIndex > _fromIndex, "You should set a correct range");
    bytes32 _roundUsersKey = roundUsersKey(_roundId);
    address[] storage _users = roundUserStorage[_roundUsersKey];
    if(_toIndex > _users.length){
        _toIndex = _users.length;
    }
    uint256 _size =  _toIndex.sub(_fromIndex);
    address[] memory _result = new address[](_size);
    uint256 _rIndex = 0;
    for(uint256 i = _fromIndex; i < _toIndex; i++){
        _result[_rIndex] = _users[i];
        _rIndex++;
    }
    return _result;
  }

  function getRoundBaseInfo(uint256 _roundId) public view returns(uint256 _dallyMint, uint256 _price){
      RoundCalendar _roundCalendar = roundCalendarInterface();
      uint256 _BLOCKS_PER_PERIOD = _roundCalendar.BLOCKS_PER_PERIOD();
      uint256 _GENESIS_BLOCK = _roundCalendar.GENESIS_BLOCK();
      uint256 _roundBlock = _GENESIS_BLOCK.add(_roundId * _BLOCKS_PER_PERIOD).sub(1);
      return _getPeriodInfo(_roundBlock);
  }
  
  function checkRoundRewardDataDone(uint256 _roundId) internal view returns(bool){
      if(IS_ROUND_RESULTED(_roundId)){
          if(IS_ROUND_ALL_SELECTED(_roundId)){
              return true;
          }else{
                RandomDataSource _random = RandomDataSource(RANDOM_DATA_SOURCE());
                uint256 _indexCount = _random.randomIndexCount(_roundId);
                (uint256 _dallyMint,) = getRoundBaseInfo(_roundId);
                if(_indexCount >= _dallyMint){
                    return true;
                }else{
                    return false;
                }
          }
      }else{
          return false;
      }
  }
  
  function refundUser(address _user, uint256 _roundId, uint256 _fromIndex, uint256 _toIndex) public hasAdminRole{
        require(checkRoundRewardDataDone(_roundId), "Data has not prepared yet");
        bytes32 _userRoundIndexKey = ticketRoundIndexKey(_user, _roundId);
        uint256[] storage userRoundTicketKeys = userRoundTicketIndexes[_userRoundIndexKey];
        uint256 _totalTickets = userRoundTicketKeys.length;

        uint256 _refundACN = 0;
        uint256 _totalRate = 100;
        if(_toIndex > _totalTickets){
            _toIndex = _totalTickets;
        }

        OAKTicket[] storage userTickets = userTicketStorage[userKey(_user)];
        for(uint256 i = _fromIndex; i < _toIndex; i++){
            OAKTicket memory _ticket = userTickets[userRoundTicketKeys[i]];
              if(!checkRewarded(_roundId, _ticket.index) && !checkRefunded(_user, _roundId, _ticket.index)){
                  _refundACN = _refundACN.add(
                      _ticket.price.mul(10**18).mul(_totalRate.sub(_ticket.baseFeeRate).sub(_ticket.devFeeRate)).div(_totalRate)
                  );
                  SAVE_IS_ROUND_REFUNDED(_user, _roundId, _ticket.index, true);
              }
        }
        if(_refundACN > 0){
            IERC20 _token = IERC20(ACN_ADDRESS());
            _token.transfer(_user, _refundACN);
            emit OAKRefund(_user, _roundId, _refundACN);
        }
        
  }
  
  function generateRoundResultByUser() public{
      uint256 _roundId = roundCalendarInterface().CURRENT_ROUND();
      require(_roundId > 1, "You can only generate the result for last round");
      uint256 _lastRoundId = _roundId.sub(1);
      require(!IS_ROUND_RESULTED(_lastRoundId), "Round result has been executed");

      (uint256 _dallyMint,) = getRoundBaseInfo(_lastRoundId);
      uint256 _totalTickets = ROUND_TICKETS(_lastRoundId);
        if(_totalTickets <= _dallyMint){
            SET_IS_ROUND_ALL_SELECTED(_lastRoundId, true);
        }
      processACN(_lastRoundId);
      SET_IS_ROUND_RESULTED(_lastRoundId, true);    
  }

  function generateRoundResultByAdmin(uint256 _roundId) public hasAdminRole{
       require(_roundId < roundCalendarInterface().CURRENT_ROUND(), "You cant generate the future round result");
       require(!IS_ROUND_RESULTED(_roundId), "Round result has been executed");
        (uint256 _dallyMint,) = getRoundBaseInfo(_roundId);
        uint256 _totalTickets = ROUND_TICKETS(_roundId);
        if(_totalTickets <= _dallyMint){
            SET_IS_ROUND_ALL_SELECTED(_roundId, true);
        }
        SET_IS_ROUND_RESULTED(_roundId, true);
        processACN(_roundId);

  }

  function processACN(uint256 _roundId) internal{
        (uint256 _dallyMint,uint256 price) = getRoundBaseInfo(_roundId);
        uint256 totalOAKs = roundGeneratedOAKs(_roundId);
        uint256 _acnReward = totalOAKs.mul(price).mul(10**18).mul(REWARD_RATE()).div(100);
        uint256 _acnBurn = totalOAKs.mul(price).mul(10**18).mul(BURN_RATE().add(BASE_FEE_RATE())).div(100);
        uint256 _acnDev = totalOAKs.mul(price).mul(10**18).mul(DEV_FEE_RATE()).div(100);

        //Process for non-luckers
        uint256 _actualTotalTickets = ROUND_TICKETS(_roundId);
        uint256 _unRewardedTickets = 0;
        if(_actualTotalTickets > _dallyMint){
            _unRewardedTickets = _actualTotalTickets.sub(_dallyMint);
        }
        if(_unRewardedTickets > 0){
            _acnBurn = _acnBurn.add(_unRewardedTickets.mul(price).mul(10**18).mul(BASE_FEE_RATE()).div(100));
            _acnDev = _acnDev.add(_unRewardedTickets.mul(price).mul(10**18).mul(DEV_FEE_RATE()).div(100));
        }

        IERC20 _token = IERC20(ACN_ADDRESS());
        if(_acnReward > 0){
            _token.transfer(REWARD_COLLECTOR(), _acnReward);
            emit ACNRewardReceived(_roundId, REWARD_COLLECTOR(), _acnReward);
            SAVE_ROUND_ACN_REWARD(_roundId,_acnReward);
            SAVE_TOTAL_ACN_REWARDED(_acnReward.add(TOTAL_ACN_REWARDED()));
        }
        if(_acnBurn > 0){
            _token.transfer(DEAD_ADDRESS(), _acnBurn);
            emit ACNBurnt(_roundId, DEAD_ADDRESS(), _acnBurn);
            SAVE_TOTAL_ACN_BURNT(_acnBurn.add(TOTAL_ACN_BURNT()));
        }
        if(_acnDev > 0){
            _token.transfer(DEV_FEE_ADDRESS(), _acnDev);
            emit ACNDevFeeReceived(_roundId, DEV_FEE_ADDRESS(), _acnDev);
            SAVE_TOTAL_ACN_DEV_FEE(_acnDev.add(TOTAL_ACN_DEV_FEE()));
        }
  }

  function roundGeneratedOAKs(uint256 _roundId) internal view returns(uint256){
        
        (uint256 _dallyMint,) = getRoundBaseInfo(_roundId);
         uint256 _totalTickets = ROUND_TICKETS(_roundId);
         if(_totalTickets <= _dallyMint){
             return _totalTickets;
         }else{
             return _dallyMint;
         }
  }


    function PRICE_PER_TICKET() public view returns (uint256){
        return uintStorage[keccak256("PRICE_PER_TICKET")];
    }

    function SET_PRICE_PER_TICKET(uint _price) onlyOwner public  {
        uintStorage[keccak256("PRICE_PER_TICKET")] = _price;
    }

    function BURN_RATE() public view returns (uint256) {
        return uintStorage[keccak256("BURN_RATE")];
    }
    function SET_BURN_RATE(uint _rate) onlyOwner public  {
        uintStorage[keccak256("BURN_RATE")] = _rate;
    }

    function DEV_FEE_RATE() public view returns (uint256) {
        return uintStorage[keccak256("DEV_FEE_RATE")];
    }
    function SET_DEV_FEE_RATE(uint _rate) onlyOwner public  {
        uintStorage[keccak256("DEV_FEE_RATE")] = _rate;
    }

    function REWARD_RATE() public view returns (uint256) {
        return uintStorage[keccak256("REWARD_RATE")];
    }
    function SET_REWARD_RATE(uint _rate) onlyOwner public  {
        uintStorage[keccak256("REWARD_RATE")] = _rate;
    }

    function BASE_FEE_RATE() public view returns (uint256) {
        return uintStorage[keccak256("BASE_FEE_RATE")];
    }
    function SET_BASE_FEE_RATE(uint _rate) onlyOwner public  {
        uintStorage[keccak256("BASE_FEE_RATE")] = _rate;
    }

    function RANDOM_DATA_SOURCE() public view returns (address) {
        return addressStorage[keccak256("RANDOM_DATA_SOURCE")];
    }

    function SET_RANDOM_DATA_SOURCE(address _new) onlyOwner public  {
        addressStorage[keccak256("RANDOM_DATA_SOURCE")] = _new;
    }

    function SET_ROUND_CALENDAR(address _new) onlyOwner public  {
        addressStorage[keccak256("ROUND_CALENDAR")] = _new;
    }

    function ROUND_CALENDAR() public view returns (address) {
        return addressStorage[keccak256("ROUND_CALENDAR")];
    }

    //Burn address
    function DEAD_ADDRESS() public view returns (address) {
        return addressStorage[keccak256("DEAD_ADDRESS")];
    }

    function SET_DEAD_ADDRESS(address _new) onlyOwner public  {
        addressStorage[keccak256("DEAD_ADDRESS")] = _new;
    }

    //Service fee address
    function DEV_FEE_ADDRESS() public view returns (address) {
        return addressStorage[keccak256("DEV_FEE_ADDRESS")];
    }
    function SET_DEV_FEE_ADDRESS(address _new) onlyOwner public  {
        addressStorage[keccak256("DEV_FEE_ADDRESS")] = _new;
    }

    function BASE_FEE_ADDRESS() public view returns (address) {
        return addressStorage[keccak256("BASE_FEE_ADDRESS")];
    }
    function SET_BASE_FEE_ADDRESS(address _new) onlyOwner public  {
        addressStorage[keccak256("BASE_FEE_ADDRESS")] = _new;
    }

    //
    function REWARD_COLLECTOR() public view returns (address) {
        return addressStorage[keccak256("REWARD_COLLECTOR")];
    }

    function SET_REWARD_COLLECTOR(address _new) onlyOwner public  {
        addressStorage[keccak256("REWARD_COLLECTOR")] = _new;
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

    function SAVE_ROUND_INFO(uint256 _roundID, uint256 _totalTickets) internal  {
        uintStorage[keccak256(abi.encodePacked("ROUND_INFO", _roundID))] = _totalTickets;
    }

    function ROUND_ACN_INFO(uint256 _roundID)  public view returns (uint256)  {
        return uintStorage[keccak256(abi.encodePacked("ROUND_ACN_INFO", _roundID))];
    }

    function SAVE_ROUND_ACN_INFO(uint256 _roundID, uint256 _totalACN) internal  {
        uintStorage[keccak256(abi.encodePacked("ROUND_ACN_INFO", _roundID))] = _totalACN;
    }

    function ROUND_ACN_REWARD(uint256 _roundID)  public view returns (uint256)  {
        return uintStorage[keccak256(abi.encodePacked("ROUND_ACN_REWARD", _roundID))];
    }

    function SAVE_ROUND_ACN_REWARD(uint256 _roundID, uint256 _totalACN) internal  {
        uintStorage[keccak256(abi.encodePacked("ROUND_ACN_REWARD", _roundID))] = _totalACN;
    }

    function TOTAL_ACN_REWARDED()  public view returns (uint256)  {
        return uintStorage[keccak256("TOTAL_ACN_REWARDED")];
    }
    
    function SAVE_TOTAL_ACN_REWARDED(uint256 _totalACN) internal  {
        uintStorage[keccak256("TOTAL_ACN_REWARDED")] = _totalACN;
    }

    function SAVE_ROUND_USER_INDEX(address _user, uint256 _roundId, uint256 _index) internal{
        addressStorage[keccak256(abi.encodePacked("ROUND_USER_INDEX", _roundId, _index))] = _user;
    }

    function ROUND_USER_INDEX(uint256 _roundId, uint256 _index) internal view returns(address){
        return addressStorage[keccak256(abi.encodePacked("ROUND_USER_INDEX", _roundId, _index))];
    }

    function TOTAL_ACN_BURNT()  public view returns (uint256)  {
        return uintStorage[keccak256("TOTAL_ACN_BURNT")];
    }

    function SAVE_TOTAL_ACN_BURNT(uint256 _totalACN) internal  {
        uintStorage[keccak256("TOTAL_ACN_BURNT")] = _totalACN;
    }

    function TOTAL_ACN_DEV_FEE()  public view returns (uint256)  {
        return uintStorage[keccak256("TOTAL_ACN_DEV_FEE")];
    }

    function SAVE_TOTAL_ACN_DEV_FEE(uint256 _totalACN) internal  {
        uintStorage[keccak256("TOTAL_ACN_DEV_FEE")] = _totalACN;
    }

    function TOTAL_ACN_BASE_FEE()  public view returns (uint256)  {
        return uintStorage[keccak256("TOTAL_ACN_BASE_FEE")];
    }

    function SAVE_TOTAL_ACN_BASE_FEE(uint256 _totalACN) internal  {
        uintStorage[keccak256("TOTAL_ACN_BASE_FEE")] = _totalACN;
    }

    function ROUND_TICKETS(uint256 _roundID)  public view returns (uint256)  {
        return uintStorage[keccak256(abi.encodePacked("ROUND_TICKETS", _roundID))];
    }

    function SAVE_ROUND_TICKETS(uint256 _roundID, uint256 _totalTickets) internal{
        uintStorage[keccak256(abi.encodePacked("ROUND_TICKETS", _roundID))] = _totalTickets;
    }

    function SAVE_ROUND_LIMIT(uint256 _userRoundLimit, uint256 _userTimeLimit) onlyOwner public   {
        uintStorage[keccak256("ROUND_TOTAL_LIMIT")] = _userRoundLimit;
        uintStorage[keccak256("ROUND_TIME_LIMIT")] = _userTimeLimit;
    }

    function ROUND_TOTAL_LIMIT() public view returns (uint256)  {
        return uintStorage[keccak256("ROUND_TOTAL_LIMIT")];
    }

    function ROUND_TIME_LIMIT() public view returns (uint256)  {
        return uintStorage[keccak256("ROUND_TIME_LIMIT")];
    }


    function APP_CONFIG()  public view returns (OAKConfig)  {
        OAKConfig memory oakConfig;
        oakConfig.burnFeeRate = BURN_RATE();
        oakConfig.devFeeRate = DEV_FEE_RATE();
        oakConfig.baseFeeRate = BASE_FEE_RATE();
        oakConfig.rewardFeeRate = REWARD_RATE();
        oakConfig.roundTotalLimit = ROUND_TOTAL_LIMIT();
        oakConfig.roundTimeLimit = ROUND_TIME_LIMIT();
        return oakConfig;
    }

    function IS_ROUND_ALL_SELECTED(uint256 _roundId) public view returns (bool)  {
        return boolStorage[keccak256(abi.encodePacked("IS_ROUND_ALL_SELECTED", _roundId))];
    }
    function IS_ROUND_RESULTED(uint256 _roundId) public view returns (bool)  {
        return boolStorage[keccak256(abi.encodePacked("IS_ROUND_RESULTED", _roundId))];
    }

    function SET_IS_ROUND_ALL_SELECTED(uint256 _roundId, bool _isSelected) internal {
        boolStorage[keccak256(abi.encodePacked("IS_ROUND_ALL_SELECTED", _roundId))] = _isSelected;
    }
    function SET_IS_ROUND_RESULTED(uint256 _roundId, bool _isResulted) internal {
        boolStorage[keccak256(abi.encodePacked("IS_ROUND_RESULTED", _roundId))] = _isResulted;
    }

    function SET_IS_ROUND_WITHDRAWN(address _user, uint256 _roundId, bool _isWithdrawn) internal {
        boolStorage[keccak256(abi.encodePacked("IS_ROUND_WITHDRAWN", _user, _roundId))] = _isWithdrawn;
    }

    function IS_ROUND_WITHDRAWN(address _user, uint256 _roundId) public view returns (bool)  {
        return boolStorage[keccak256(abi.encodePacked("IS_ROUND_WITHDRAWN", _user,  _roundId))];
    }

    function SAVE_IS_ROUND_REFUNDED(address _user, uint256 _roundId, uint256 _index, bool _isRefunded) internal {
        boolStorage[keccak256(abi.encodePacked("IS_ROUND_REFUNDED", _user, _roundId, _index))] = _isRefunded;
    }

    function IS_ROUND_REFUNDED(address _user, uint256 _roundId, uint256 _index) public view returns (bool)  {
        return boolStorage[keccak256(abi.encodePacked("IS_ROUND_REFUNDED", _user,  _roundId, _index))];
    }

    function ROUND_OAK_MINT_INFO(uint256 _roundID)  public view returns (uint256)  {
        return uintStorage[keccak256(abi.encodePacked("ROUND_OAK_MINT_INFO", _roundID))];
    }

    function SAVE_ROUND_OAK_MINT_INFO(uint256 _roundID, uint256 _totalOAK) internal  {
        uintStorage[keccak256(abi.encodePacked("ROUND_OAK_MINT_INFO", _roundID))] = _totalOAK;
    }

    function ROUND_RESULT(uint256 _roundId) public view returns (RoundResult )  {
        RoundResult memory result;
        result.roundId = _roundId;
        result.allSelected = IS_ROUND_ALL_SELECTED(_roundId);
        result.executed = IS_ROUND_RESULTED(_roundId);
        return result;
    }

  function CAL_ROUND_ACN_REWARD(uint256 _roundId) public view returns(uint256){
    uint256 totalOAKs = roundGeneratedOAKs(_roundId);
    (,uint256 price) = getRoundBaseInfo(_roundId);
    return totalOAKs.mul(price).mul(10**18).mul(REWARD_RATE()).div(100);
  }
  function CAL_ROUND_ACN_BURN(uint256 _roundId) public view returns(uint256){
    uint256 totalOAKs = roundGeneratedOAKs(_roundId);
    (,uint256 price) = getRoundBaseInfo(_roundId);
    return totalOAKs.mul(price).mul(10**18).mul(BURN_RATE()).div(100);
  }

  function CAL_ROUND_ACN_DEV(uint256 _roundId) public  view returns(uint256){
    uint256 totalOAKs = roundGeneratedOAKs(_roundId);
    (,uint256 price) = getRoundBaseInfo(_roundId);
    return totalOAKs.mul(price).mul(10**18).mul(DEV_FEE_RATE()).div(100);
  }

  function CAL_ROUND_ACN_BASE(uint256 _roundId) public  view returns(uint256){
    uint256 totalOAKs = roundGeneratedOAKs(_roundId);
    (,uint256 price) = getRoundBaseInfo(_roundId);
    return totalOAKs.mul(price).mul(10**18).mul(BASE_FEE_RATE()).div(100);
  }

}
