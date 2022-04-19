// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./interfaces/IAcalab.sol";
import "./interfaces/IMirrorWorld.sol";
import "./interfaces/ISpookyRouter.sol";

contract Strategy is BaseStrategy {
    address public constant acalab =
    address(0x2352b745561e7e6FCD03c093cE7220e3e126ace0);
    address public constant mirrorworld =
    address(0xa48d959AE2E88f1dAA7D5F611E01908106dE7598); // aka xboo
    address public constant spookyrouter =
    address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);
    address public constant wftm =
    address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);

    uint256 public chefId;
    IERC20 public rewardToken;

    constructor(address _vault) public BaseStrategy(_vault) {
        chefId = 12;
        // spell
        rewardToken = getRewardToken();

        want.approve(mirrorworld, type(uint256).max);
        IERC20(mirrorworld).approve(acalab, type(uint256).max);
        rewardToken.approve(spookyrouter, type(uint256).max);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        return "StrategySpookyBOO";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfWantInMirrorWorld() public view returns (uint256) {
        // how much boo we sent to xboo contract
        return IMirrorWorld(mirrorworld).BOOBalance(address(this));
    }

    function balanceOfWantInAcalab() public view returns (uint256 booAmount) {
        uint256 xbooAmount = balanceOfXBOOInAcaLab();
        return IMirrorWorld(mirrorworld).xBOOForBOO(xbooAmount);
    }

    function balanceOfXBOOInAcaLab() internal view returns (uint256) {
        IAcalab.UserInfo memory user = IAcalab(acalab).userInfo(
            chefId,
            address(this)
        );
        return user.amount;
    }

    function balanceOfXBOO() internal view returns (uint256) {
        return IERC20(mirrorworld).balanceOf(address(this));
    }

    function getRewardToken() public view returns (IERC20 _rewardToken) {
        IAcalab.PoolInfo memory pool = IAcalab(acalab).poolInfo(chefId);
        return pool.RewardToken;
    }

    function setChefId(uint256 _chefId) external onlyAuthorized {
        chefId = _chefId;
        rewardToken = getRewardToken();
        rewardToken.approve(spookyrouter, type(uint256).max);
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWantInAcalab().add(balanceOfWant());
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
        uint256 _wantBefore = want.balanceOf(address(this));
        // 0
        _swapRewardToWant();
        uint256 _wantAfter = want.balanceOf(address(this));
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

    function _claimRewardsAndBOO() internal {
        IAcalab(acalab).withdraw(chefId, balanceOfXBOOInAcaLab());
        IMirrorWorld(mirrorworld).leave(balanceOfXBOO());
    }

    function _swapRewardToWant() internal {
        uint256 bonusToken = rewardToken.balanceOf(address(this));
        if (bonusToken > 0) {
            address[] memory path = new address[](3);
            path[0] = address(rewardToken);
            path[1] = wftm;
            path[2] = address(want);
            ISpookyRouter(spookyrouter).swapExactTokensForTokens(
                bonusToken,
                0,
                path,
                address(this),
                block.timestamp + 120
            );
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 wantBal = want.balanceOf(address(this));
        if (wantBal > 0 || balanceOfXBOO() > 0) {
            IMirrorWorld(mirrorworld).enter(wantBal);
            IAcalab(acalab).deposit(chefId, balanceOfXBOO());
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
        IAcalab(acalab).withdraw(chefId, _actualWithdrawn);
        IMirrorWorld(mirrorworld).leave(_actualWithdrawn);
    }

    function liquidateAllPositions() internal override returns (uint256) {
        require(emergencyExit);
        IAcalab(acalab).withdraw(chefId, balanceOfXBOOInAcaLab());
        IMirrorWorld(mirrorworld).leave(balanceOfXBOO());
        return want.balanceOf(address(this));
    }

    function prepareMigration(address _newStrategy) internal override {
        if (balanceOfXBOOInAcaLab() > 0) {
            IAcalab(acalab).withdraw(chefId, balanceOfXBOOInAcaLab());
        }
        IERC20(mirrorworld).safeTransfer(_newStrategy, balanceOfXBOO());

        if (rewardToken.balanceOf(address(this)) > 0) {
            rewardToken.safeTransfer(
                _newStrategy,
                rewardToken.balanceOf(address(this))
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
