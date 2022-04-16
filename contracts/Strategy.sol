// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./interfaces/IAcalab.sol";
import "./interfaces/IMirrorWorld.sol";
import "./interfaces/ISpookyRouter.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;

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

    // solhint-disable-next-line no-empty-blocks

    constructor(address _vault) public BaseStrategy(_vault) {
        chefId = 12; // spell
        rewardToken = getRewardToken();

        want.approve(mirrorworld, type(uint256).max);
        IERC20(mirrorworld).approve(acalab, type(uint256).max);
        rewardToken.approve(spookyrouter, type(uint256).max);
        // You can set these parameters on deployment to whatever you want
        // maxReportDelay = 6300;
        // profitFactor = 100;
        // debtThreshold = 0;
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
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
        // TODO: Build a more accurate estimate using the value of all positions in terms of `want`

        return balanceOfWantInAcalab().add(balanceOfWant());
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    // solhint-disable-next-line no-empty-blocks
    {
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
        uint256 _wantBefore = want.balanceOf(address(this)); // 0
        _swapRewardToWant();
        uint256 _wantAfter = want.balanceOf(address(this)); // 100

        _profit = _wantAfter.sub(_wantBefore);

        //net off profit and loss

        if (_profit >= _loss.add(_lossFromPrevious)) {
            _profit = _profit.sub((_loss.add(_lossFromPrevious)));
            _loss = 0;
        } else {
            _profit = 0;
            _loss = (_loss.add(_lossFromPrevious)).sub(_profit);
        }

        // TODO: Do stuff here to free up any returns back into `want`
        // NOTE: Return `_profit` which is value generated by all positions, priced in `want`
        // NOTE: Should try to free up at least `_debtOutstanding` of underlying position
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

    // solhint-disable-next-line no-empty-blocks
    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 wantBal = want.balanceOf(address(this));
        if (wantBal > 0 || balanceOfXBOO() > 0) {
            IMirrorWorld(mirrorworld).enter(wantBal);
            IAcalab(acalab).deposit(chefId, balanceOfXBOO());
        }
        // TODO: Do something to invest excess `want` tokens (from the Vault) into your positions
        // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // TODO: Do stuff here to free up to `_amountNeeded` from all positions back into `want`
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`

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
        // TODO: Liquidate all positions and return the amount freed.
        require(emergencyExit);
        IAcalab(acalab).withdraw(chefId, balanceOfXBOOInAcaLab());
        IMirrorWorld(mirrorworld).leave(balanceOfXBOO());
        return want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary
    // solhint-disable-next-line no-empty-blocks
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
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    // solhint-disable-next-line no-empty-blocks
    {
        address[] memory protected = new address[](2);
        protected[0] = address(rewardToken);
        protected[1] = mirrorworld;
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // TODO create an accurate price oracle
        return _amtInWei;
    }
}
