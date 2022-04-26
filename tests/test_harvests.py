import brownie
from brownie import Contract
import pytest

def test_compoundwithoutharvest(
    chain, accounts, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, gov
):

  token.approve(vault.address, amount, {"from": user})
  vault.deposit(amount, {"from": user})
  chain.sleep(1)
  strategy.harvest()
  assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount
  etaBefore = strategy.estimatedTotalAssets()

  chain.sleep(86400)
  chain.mine(1)
  # LUNA => WFTM => BOO
  strategy.setReward(33, ["0x593AE1d34c8BD7587C11D539E4F42BFf242c82Af",
                          "0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83",
                          token], {"from":gov})
  print(strategy.estimatedTotalAssets())
  #we should have profit since we basically compound here
  assert(strategy.estimatedTotalAssets() > etaBefore)
