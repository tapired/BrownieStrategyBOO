from brownie import Contract, ZERO_ADDRESS
import datetime as dt
import time


# 1. BOO ended
# 2. SCREAM ended
# 3. WFTM ended
# 4. FOO ends on 2022-04-20 16:59:06
# 5. STEAK ended
# 6. SHADE ended
# 7. USDC ended
# 8. DAI ended
# 9. WOO ended
# 10. TREEB ends on 2022-04-21 09:26:17
# 11. FONT ended
# 12. LQDR ended
# 13. SPELL ended
# 14. xBOO ended
# 15. CFi ended
# 16. INV ended
# 17. YEL ended
# 18. TUSD ends on 2022-04-26 09:54:23
# 19. YOSHI ended
# 20. SPA ended
# 21. wsHEC ended
# 22. HEC ended
# 23. OOE ends on 2022-05-02 13:54:09
# 24. HND ended
# 25. BRUSH ended
# 26. FS ended
# 27. MST ended
# 28. ALPACA ended
# 29. KAE ends on 2022-04-23 10:00:00
# 30. TOMB ends on 2022-05-09 11:00:00
# 31. SOLID ends on 2022-05-17 15:57:30
# 32. RING ends on 2022-05-18 18:00:00
# 33. beFTM ends on 2022-05-30 13:30:00

def main():
    acelab = Contract("0x2352b745561e7e6FCD03c093cE7220e3e126ace0")
    i = 0
    while True:
        pool = acelab.poolInfo(i)
        if pool["RewardToken"] == ZERO_ADDRESS:
            break
        i += 1
        endtime = pool["endTime"]
        datetime = dt.datetime.fromtimestamp(endtime)
        try:
            Contract(pool["RewardToken"]).symbol()
        except:
            print("error")

        now = int(time.time())
        if now > endtime:
            print(f'{i}. {Contract(pool["RewardToken"]).symbol()} ended')
        else:
            print(f'{i}. {Contract(pool["RewardToken"]).symbol()} ends on {datetime}')

