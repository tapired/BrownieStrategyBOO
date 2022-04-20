// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface IAcelab is IERC20 {
    struct UserInfo {
        uint256 amount;     // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    struct PoolInfo {
        IERC20 RewardToken;       // Address of reward token contract.
        uint256 RewardPerSecond;   // reward token per second for this pool
        uint256 TokenPrecision; // The precision factor used for calculations, dependent on a tokens decimals
        uint256 xBooStakedAmount; // # of xboo allocated to this pool
        uint256 lastRewardTime;  // Last block time that reward distribution occurs.
        uint256 accRewardPerShare; // Accumulated reward per share, times the pools token precision. See below.
        uint256 endTime; // end time of pool
        uint256 startTime; // start time of pool
        uint256 userLimitEndTime;
        address protocolOwnerAddress; // this address is the owner of the protocol corresponding to the reward token, used for emergency withdraw to them only
    }

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function userInfo(uint256 _pid, address _userAddress) external view returns (UserInfo memory _userInfo);

    function poolInfo(uint _index) external view returns (PoolInfo memory _poolInfo);
}
