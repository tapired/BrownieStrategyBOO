# TODO: Add tests that show proper migration of the strategy to a newer one
#       Use another copy of the strategy to simulate the migration
#       Show that nothing is lost!

import pytest


def test_migration(
    chain,
    token,
    vault,
    strategy,
    amount,
    Strategy,
    strategist,
    gov,
    user,
    RELATIVE_APPROX,
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    # migrate to a new strategy
    new_strategy = strategist.deploy(Strategy, vault, ["0x888EF71766ca594DED1F0FA3AE64eD2941740A20",
                            "0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83",
                            token],
                            30
                                )
    # vault.addStrategy(new_strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    vault.migrateStrategy(strategy, new_strategy, {"from": gov})
    chain.sleep(1)
    new_strategy.harvest()
    assert (
        pytest.approx(new_strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX)
        == amount
    )
