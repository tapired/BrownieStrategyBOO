import brownie
from brownie import Contract
import pytest
from brownie import ZERO_ADDRESS

def test_rewards(
    chain, accounts, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, gov
):

   solidly = Contract("0x888EF71766ca594DED1F0FA3AE64eD2941740A20")
   acelab = Contract("0x2352b745561e7e6FCD03c093cE7220e3e126ace0")
   xboo = Contract("0xa48d959AE2E88f1dAA7D5F611E01908106dE7598")

   token.approve(vault.address, amount, {"from": user})
   vault.deposit(amount, {"from": user})
   chain.sleep(1)
   strategy.harvest()
   assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

   chain.mine(1)
   strategy.harvest()
   chain.sleep(3600 * 6)  # 6 hrs needed for profits to unlock
   chain.mine(1)
   strategy.harvest()

   print(strategy.estimatedTotalAssets())
   assert(strategy.estimatedTotalAssets() > amount) # profit

   # LUNA => WFTM => BOO
   strategy.setReward(33, ["0x593AE1d34c8BD7587C11D539E4F42BFf242c82Af",
                           "0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83",
                           token], {"from":gov})

   # make sure we don't have previous rewards idling
   assert(solidly.balanceOf(strategy) == 0) # no rewards at strategy
   assert(acelab.pendingReward(30, strategy.address) == 0) # no pending rewards at acelab
   assert(acelab.userInfo(30, strategy.address)[0] == 0) # no xboo in previous chef

   chain.sleep(86400)
   chain.mine(1)
   strategy.harvest()
   print(strategy.estimatedTotalAssets())

   chain.sleep(86400)
   chain.mine(1)
   strategy.harvest()
   print(strategy.estimatedTotalAssets())
