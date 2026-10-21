# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
"""Compare what MT5 drew (DumpIndicator CSVs) with the Python reference, bar by bar.

    python3 tests/check_parity.py <dump dir>                 (needs numpy and pandas)
    python3 tests/check_parity.py <MT4 dump dir> --mt4       (the MT4 edition, dumps from the MT4 tester)

Each CONFIG is one DumpIndicator run (tag -> parameters). Dumps hold buffers b0..b6 (see reference.py).
The dump's time column is server time (epoch seconds); the reference assumes a New York-close server clock
(server = New York + 7h), so run the dump on a server with that clock. Pass: every closed bar's seven buffers match
(levels within 1e-9 relative, signals exactly, NaN where MT5 is blank)."""
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from reference import session_levels  # noqa: E402

# Inputs in declaration order (groups don't count); SignalAlerts' 5 inputs last.
# days, [asia on,start,end,colour], [london on,start,end,colour], [ny on,start,end,colour], labels, fill,
# PD, PW, open, 3 colours, level labels, width, clock(enum), fixed UTC, 4 alert kinds, alert popup/sound/file/push/mail
CONFIGS = {   # tag: (reference kwargs, DumpIndicator InpParams)
    "sl_default": (dict(),
                   "i:5|b:true|s:19:00|s:04:00|c:16748574|b:true|s:03:00|s:12:00|c:42495|b:true|s:08:00|s:17:00|c:7451452"
                   "|b:true|b:true|b:true|b:true|b:true|c:55295|c:14053594|c:12632256|b:true|i:1|i:1|i:0"
                   "|b:true|b:true|b:true|b:true|b:false|b:false|s:alert.wav|b:false|b:false"),
    "sl_killzones": (dict(),
                     "i:5|b:true|s:19:00|s:04:00|c:16748574|b:true|s:02:00|s:05:00|c:42495|b:true|s:07:00|s:10:00|c:7451452"
                     "|b:true|b:true|b:true|b:true|b:true|c:55295|c:14053594|c:12632256|b:true|i:1|i:1|i:0"
                     "|b:true|b:true|b:true|b:true|b:false|b:false|s:alert.wav|b:false|b:false"),
}
# note: InpClock is pinned to 1 (New York close) so the parity does not depend on auto-detection.


def check(csv: Path, kw: dict, mt4=False) -> tuple[bool, str]:
    d = pd.read_csv(csv)
    if mt4:                            # Dump4 writes the bar time as text (server time, as MT5's epoch seconds)
        d["time"] = (pd.to_datetime(d["time"], format="%Y.%m.%d %H:%M") - pd.Timestamp(0)) // pd.Timedelta(seconds=1)
    ref = session_levels(d["time"].to_numpy("int64"), d["open"], d["high"], d["low"], d["close"], **kw)
    closed = slice(0, len(d) - 1)
    parts, ok = [], True
    for k in range(7):
        mt = d[f"b{k}"].to_numpy(float)[closed]
        rf = ref[closed, k]
        same_nan = np.array_equal(np.isnan(mt), np.isnan(rf))
        close = np.allclose(mt, rf, rtol=1e-9, atol=0, equal_nan=True)
        bad = int((~np.isclose(mt, rf, rtol=1e-9, atol=0, equal_nan=True)).sum())
        ok &= same_nan and close
        parts.append(f"b{k} {'OK' if same_nan and close else f'{bad} differ'}")
    nsig = int((~np.isnan(ref[closed, 6])).sum())
    return ok, f"{csv.stem:40} bars {len(d):>6}  signals {nsig:>4}  " + "  ".join(parts)


if __name__ == "__main__":
    mt4 = "--mt4" in sys.argv          # dumps written by tests/mt4/SessionLevelsDump.mq4 in the MT4 Strategy Tester
    root = Path([a for a in sys.argv[1:] if a != "--mt4"][0])
    allok, n = True, 0
    for tag, (kw, _) in CONFIGS.items():
        for f in sorted(root.glob(f"{tag}_*.csv")):
            ok, msg = check(f, kw, mt4)
            allok &= ok
            n += 1
            print(("PASS " if ok else "FAIL ") + msg)
    print(f"\n{'ALL PASS' if allok and n else 'FAILURES'} ({n} files)")
    sys.exit(0 if allok and n else 1)
