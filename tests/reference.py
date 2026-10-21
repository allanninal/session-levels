# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
"""Independent pandas/numpy reference for Session Levels MT5 (buffers 0-6), written from the spec, not from the MQL code.

Assumes the server clock is New York close (server time = New York time + 7h), so the
trading day is simply the server calendar day (17:00 New York = 00:00 server) and a New York wall-clock
minute is (server seconds - 7h) mod a day. Bars are identified by their open time (epoch seconds, server time).

    b0 previous-day high      b1 previous-day low      b2 previous-week high     b3 previous-week low
    b4 Asia high so far       b5 Asia low so far       b6 +1 first close > PDH of the day, -1 first close < PDL,
                                                          +2 first close > Asia high after Asia ended, -2 first close < Asia low
Days/weeks: week = Monday-based week of the trading day. The first day/week in the data has no "previous" (NaN).
The last bar is the live bar: callers compare closed bars only (b6 of the last bar is NaN here as well)."""
import numpy as np
import pandas as pd

NY_SHIFT = 7 * 3600


def hm(s: str) -> int:
    h, m = s.split(":")
    return int(h) * 60 + int(m)


def in_session(minute, s, e):
    if s == e:
        return np.zeros(len(minute), bool)
    return (minute >= s) & (minute < e) if s < e else (minute >= s) | (minute < e)


def session_levels(t, o, h, l, c, asia_start="19:00", asia_end="04:00") -> np.ndarray:
    """Return an (n, 7) float array, NaN for empty."""
    t = np.asarray(t, dtype="int64")
    h, l, c = (np.asarray(x, float) for x in (h, l, c))
    n = len(t)
    out = np.full((n, 7), np.nan)
    day = t // 86400
    week = (day + 3) // 7                      # 1970-01-01 was a Thursday; Monday-based week number
    df = pd.DataFrame({"day": day, "week": week, "h": h, "l": l, "c": c})
    # previous day / week extremes: aggregate each group, then look one group back
    for key, hi_col, lo_col in (("day", 0, 1), ("week", 2, 3)):
        agg = df.groupby(key).agg(hi=("h", "max"), lo=("l", "min"))
        prev = agg.shift(1)
        out[:, hi_col] = df[key].map(prev["hi"]).to_numpy()
        out[:, lo_col] = df[key].map(prev["lo"]).to_numpy()
    # Asia range so far, for the trading day the Asia session belongs to
    nyw = t - NY_SHIFT
    minute = (nyw % 86400) // 60
    s, e = hm(asia_start), hm(asia_end)
    ina = in_session(minute, s, e)
    owner = nyw // 86400 + ((minute >= s) & (s > e)).astype(int)
    a = pd.DataFrame({"owner": np.where(ina, owner, -1), "day": day, "h": h, "l": l})
    a_in = a[ina]
    run_hi = a_in.groupby("owner").h.cummax()
    run_lo = a_in.groupby("owner").l.cummin()
    first_day = a_in.groupby("owner").day.transform("first")
    ah = pd.Series(np.nan, index=a.index); al = ah.copy(); ad = ah.copy()
    ah[ina], al[ina], ad[ina] = run_hi, run_lo, first_day
    ah, al, ad = ah.ffill(), al.ffill(), ad.ffill()      # the latest Asia instance carries forward
    valid = (ad.to_numpy() == day)
    out[:, 4] = np.where(valid, ah.to_numpy(), np.nan)
    out[:, 5] = np.where(valid, al.to_numpy(), np.nan)
    # signals on closed bars, each kind once per trading day
    pdh, pdl = out[:, 0], out[:, 1]
    after_asia = valid & ~ina
    for d in np.unique(day):
        idx = np.flatnonzero(day == d)
        idx = idx[idx < n - 1]                            # closed bars only
        done = set()
        for i in idx:
            kinds = []
            if not np.isnan(pdh[i]):
                if 1 not in done and c[i] > pdh[i]:
                    kinds.append(1)
                if 2 not in done and c[i] < pdl[i]:
                    kinds.append(2)
            if after_asia[i]:
                if 4 not in done and c[i] > out[i, 4]:
                    kinds.append(4)
                if 8 not in done and c[i] < out[i, 5]:
                    kinds.append(8)
            if kinds:
                done.update(kinds)
                k = kinds[0]            # priority: PDH, PDL, Asia high, Asia low
                out[i, 6] = {1: 1, 2: -1, 4: 2, 8: -2}[k]
    return out
