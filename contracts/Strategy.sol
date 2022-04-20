// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./interfaces/IAcelab.sol";
import "./interfaces/IMirrorWorld.sol";
import "./interfaces/ISpookyRouter.sol";

contract Strategy is BaseStrategy {
    address public constant acelab =
    address(0x2352b745561e7e6FCD03c093cE7220e3e126ace0);
    address public constant mirrorworld =
    address(0xa48d959AE2E88f1dAA7D5F611E01908106dE7598); // aka xboo
    address public constant spookyrouter =
    address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);
    address public constant wftm =
    address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);

    uint256 public chefId;
    address[] public swapPath;
    IERC20 public rewardToken;

    constructor(address _vault) public BaseStrategy(_vault) {
        want.approve(mirrorworld, type(uint256).max);
        IERC20(mirrorworld).approve(acelab, type(uint256).max);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        return "Spooky BOO optimizer";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfReward() public view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    function balanceOfWantInMirrorWorld() public view returns (uint256) {
        // how much boo we sent to xboo contract
        return IMirrorWorld(mirrorworld).BOOBalance(address(this));
    }

    function balanceOfWantInAcelab() public view returns (uint256 booAmount) {
        uint256 xbooAmount = _balanceOfXBOOInAceLab();
        return IMirrorWorld(mirrorworld).xBOOForBOO(xbooAmount);
    }

    function _balanceOfXBOOInAceLab() internal view returns (uint256) {
        IAcelab.UserInfo memory user = IAcelab(acelab).userInfo(
            chefId,
            address(this)
        );
        return user.amount;
    }

    function _balanceOfXBOO() internal view returns (uint256) {
        return IERC20(mirrorworld).balanceOf(address(this));
    }

    function getRewardToken() public view returns (IERC20 _rewardToken) {
        IAcelab.PoolInfo memory pool = IAcelab(acelab).poolInfo(chefId);
        return pool.RewardToken;
    }

    /// in seconds
    function rewardTimeRemaining() public view returns (uint256) {
        uint256 end = IAcelab(acelab).poolInfo(chefId).endTime;
        return end > now ? end - now : 0;
    }

    function setReward(uint256 _chefId, address[] memory _swapPath) external onlyVaultManagers {
        if (address(rewardToken) != address(0x0)) {
            // make sure old rewards are sold before switching
            require(balanceOfReward() == 0, "unsold rewards!");
            // revoke old
            rewardToken.approve(spookyrouter, 0);
        }

        swapPath = _swapPath;
        chefId = _chefId;
        rewardToken = getRewardToken();

        require(address(rewardToken) == _swapPath[0], "illegal path!");
        require(address(want) == _swapPath[_swapPath.length - 1], "illegal path!");
        require(rewardTimeRemaining() > 0, "rewards ended!");

        rewardToken.approve(spookyrouter, type(uint256).max);
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWantInAcelab().add(balanceOfWant());
    }

    function prepareReturn(uint256 _debtOutstanding) internal override returns (uint256 _profit, uint256 _loss, uint256 _debtPayment){
        uint256 debt = vault.strategies(address(this)).totalDebt;
        uint256 _lossFromPrevious;

        if (debt > estimatedTotalAssets()) {
            _lossFromPrevious = debt.sub(estimatedTotalAssets());
        }
        _claimRewardsAndBOO();
        if (_debtOutstanding > 0) {
            uint256 _amountFreed = 0;
            (_amountFreed, _loss) = liquidatePosition(_debtOutstanding);
            _debtPayment = Math.min(_amountFreed, _debtOutstanding);
        }
        uint256 _wantBefore = balanceOfWant();
        // 0
        _swapRewardToWant();
        uint256 _wantAfter = balanceOfWant();
        // 100

        _profit = _wantAfter.sub(_wantBefore);

        //net off profit and loss

        if (_profit >= _loss.add(_lossFromPrevious)) {
            _profit = _profit.sub((_loss.add(_lossFromPrevious)));
            _loss = 0;
        } else {
            _profit = 0;
            _loss = (_loss.add(_lossFromPrevious)).sub(_profit);
        }
    }

    function claimRewardsAndBOO() external onlyVaultManagers {
        _claimRewardsAndBOO();
    }

    function _claimRewardsAndBOO() internal {
        IAcelab(acelab).withdraw(chefId, _balanceOfXBOOInAceLab());
        IMirrorWorld(mirrorworld).leave(_balanceOfXBOO());
    }

    function swapRewardToWant() external onlyVaultManagers {
        _swapRewardToWant();
    }

    function _swapRewardToWant() internal {
        uint256 rewards = balanceOfReward();
        if (rewards > 0) {
            ISpookyRouter(spookyrouter).swapExactTokensForTokens(
                rewards,
                0,
                swapPath,
                address(this),
                block.timestamp + 120
            );
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 wantBal = want.balanceOf(address(this));
        if (wantBal > 0 || _balanceOfXBOO() > 0) {
            IMirrorWorld(mirrorworld).enter(wantBal);
            IAcelab(acelab).deposit(chefId, _balanceOfXBOO());
        }
    }

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _liquidatedAmount, uint256 _loss){
        uint256 wantBalance = balanceOfWant();
        if (wantBalance > _amountNeeded) {
            // if there is enough free want, let's use it
            return (_amountNeeded, 0);
        }

        // we need to free funds

        uint256 amountRequired = _amountNeeded - wantBalance;
        _withdrawSome(amountRequired);
        uint256 freeAssets = balanceOfWant();
        if (_amountNeeded > freeAssets) {
            _liquidatedAmount = freeAssets;
            _loss = _amountNeeded.sub(_liquidatedAmount);
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function _withdrawSome(uint256 _amountRequired) internal {
        uint256 _actualWithdrawn = IMirrorWorld(mirrorworld).BOOForxBOO(
            _amountRequired
        );
        IAcelab(acelab).withdraw(chefId, _actualWithdrawn);
        IMirrorWorld(mirrorworld).leave(_actualWithdrawn);
    }

    function liquidateAllPositions() internal override returns (uint256) {
        require(emergencyExit);
        IAcelab(acelab).withdraw(chefId, _balanceOfXBOOInAceLab());
        IMirrorWorld(mirrorworld).leave(_balanceOfXBOO());
        return want.balanceOf(address(this));
    }

    function prepareMigration(address _newStrategy) internal override {
        if (_balanceOfXBOOInAceLab() > 0) {
            IAcelab(acelab).withdraw(chefId, _balanceOfXBOOInAceLab());
        }
        IERC20(mirrorworld).safeTransfer(_newStrategy, _balanceOfXBOO());

        uint256 rewards = balanceOfReward();
        if (rewards > 0) {
            rewardToken.safeTransfer(
                _newStrategy,
                rewards
            );
        }
    }

    function protectedTokens() internal view override returns (address[] memory){
        address[] memory protected = new address[](2);
        protected[0] = address(rewardToken);
        protected[1] = mirrorworld;
    }

    function ethToWant(uint256 _amtInWei) public view virtual override returns (uint256){
        return _amtInWei;
    }
}
