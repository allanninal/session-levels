//+------------------------------------------------------------------+
//|                                            SessionLevelsDump.mq4 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Test EA (not shipped): dumps the 7 MT4 Session Levels buffers and|
//| checks the signal buffer for repainting in the Strategy Tester,  |
//| via Dump4.mqh. The indicator runs over the whole history, so the |
//| final values are those of the running instance.                  |
//| Run it in the MT4 Strategy Tester (open prices) once per symbol,|
//| timeframe and input set in tests/mt4/configs.tsv, then run       |
//| tests/check_parity.py <folder with the CSVs> --mt4               |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict

#define DUMP4_BUFFERS "0,1,2,3,4,5,6"
#define DUMP4_PROBE   "6"

input string InpLondonStart = "03:00";
input string InpLondonEnd   = "12:00";
input string InpNYStart     = "08:00";
input string InpNYEnd       = "17:00";

double IndValue(const int buf,const int shift)
  {
   return(iCustom(NULL,0,"SessionLevels\\SessionLevels",5,true,"19:00","04:00",16748574,
                  true,InpLondonStart,InpLondonEnd,42495,true,InpNYStart,InpNYEnd,7451452,
                  true,true,true,true,true,55295,14053594,12632256,true,1,1,0,
                  true,true,true,true,false,false,"alert.wav",false,false,buf,shift));
  }

#include <IndTest4/Dump4.mqh>
//+------------------------------------------------------------------+
