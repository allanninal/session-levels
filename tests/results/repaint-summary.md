# Repaint check results (copied from the run output files of the development repo)

MT5, Strategy Tester every-tick run, EURUSD H1, default inputs (RepaintProbe EA, signal buffer 6):

| field | value |
|---|---|
| ticks processed | 10,411,052 |
| closed bars checked | 4,644 |
| signals seen when the bar closed | 345 |
| values changed after the close | 0 |
| signals shown on the live (forming) bar | 0 |

MT4, one run per dump (25 runs: 4 symbols x M15/H1/H4 x 2 input sets, plus one every-tick EURUSD H1 run of 8,417,316 tick events):

| field | total over 25 runs |
|---|---|
| closed bars checked | 506,172 |
| signals seen when the bar closed | 19,020 |
| mismatches after the close | 0 |
| signals shown on the live bar | 0 |
