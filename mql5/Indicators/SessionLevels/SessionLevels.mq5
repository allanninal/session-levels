//+------------------------------------------------------------------+
//|                                                SessionLevels.mq5 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Trading sessions (Asia, London, New York) as translucent boxes   |
//| with their high and low, plus the previous day and previous week |
//| high/low and today's open as lines. Session times are entered in |
//| New York time and converted per bar from the broker's clock, so  |
//| daylight saving is right on any broker. A trading day ends at   |
//| the 17:00 New York close.                                        |
//| Alerts (closed bars only, each at most once per trading day):    |
//| close above the previous day high / below the previous day low,  |
//| and after the Asia session, close above its high / below its low.|
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property copyright "Copyright 2026, Allan Niñal <https://www.allanninal.dev/mql5>"
#property link      "https://www.allanninal.dev/mql5"
#property version   "1.00"
#property description "Asia / London / New York session boxes, previous day and week high/low, today's open. Times in New York time, DST-safe."
#property description "Alerts on closed bars: break of the previous day high/low and of the Asia range. Non-repainting."
#property indicator_chart_window
#property indicator_buffers 20
#property indicator_plots   7
#property indicator_label1  "Prev day high"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "Prev day low"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "Prev week high"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "Prev week low"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "Asia high (so far)"
#property indicator_type5   DRAW_NONE
#property indicator_label6  "Asia low (so far)"
#property indicator_type6   DRAW_NONE
#property indicator_label7  "Signal"
#property indicator_type7   DRAW_NONE

enum ENUM_SL_CLOCK
  {
   SL_CLOCK_AUTO=0,    // Auto: detect from the live server time
   SL_CLOCK_NY=1,      // New York close: UTC+2/+3 with US daylight saving
   SL_CLOCK_EET=2,     // UTC+2/+3 with European daylight saving
   SL_CLOCK_FIXED=3    // Fixed offset from UTC (set below), no daylight saving
  };

input int           InpDays        = 5;                // Days to draw
input group "Asia session (New York time)"
input bool          InpShowAsia    = true;             // Draw Asia
input string        InpAsiaStart   = "19:00";          // Asia start HH:MM
input string        InpAsiaEnd     = "04:00";          // Asia end HH:MM
input color         InpAsiaColor   = 16748574;         // Asia colour
input group "London session (New York time)"
input bool          InpShowLondon  = true;             // Draw London
input string        InpLondonStart = "03:00";          // London start HH:MM
input string        InpLondonEnd   = "12:00";          // London end HH:MM
input color         InpLondonColor = 42495;            // London colour
input group "New York session (New York time)"
input bool          InpShowNY      = true;             // Draw New York
input string        InpNYStart     = "08:00";          // New York start HH:MM
input string        InpNYEnd       = "17:00";          // New York end HH:MM
input color         InpNYColor     = 7451452;          // New York colour
input group "Session boxes"
input bool          InpSessionLabels = true;           // Label each box
input bool          InpFillBoxes     = true;           // Fill the boxes (translucent)
input group "Levels"
input bool          InpShowPD      = true;             // Previous day high/low
input bool          InpShowPW      = true;             // Previous week high/low
input bool          InpShowOpen    = true;             // Today's open
input color         InpPDColor     = 55295;            // Previous day colour
input color         InpPWColor     = 14053594;         // Previous week colour
input color         InpOpenColor   = 12632256;         // Today's open colour
input bool          InpLevelLabels = true;             // Price labels on the levels
input int           InpLevelWidth  = 1;                // Line width
input group "Broker clock"
input ENUM_SL_CLOCK InpClock       = SL_CLOCK_AUTO;    // Broker server clock
input int           InpFixedUTC    = 0;                // Broker offset from UTC, hours (Fixed offset only)
input group "Alert kinds"
input bool          InpAlertPDH    = true;             // Close above previous day high
input bool          InpAlertPDL    = true;             // Close below previous day low
input bool          InpAlertAsiaH  = true;             // Close above Asia high (after Asia)
input bool          InpAlertAsiaL  = true;             // Close below Asia low (after Asia)

#include "SignalAlerts.mqh"

//--- buffers shown to the outside
double g_pdh[],g_pdl[],g_pwh[],g_pwl[],g_ash[],g_asl[],g_sig[];
//--- internal state, one value per bar so a recalculation can restart from any bar
double g_nyw[];     // New York wall time of the bar (seconds)
double g_dk[];      // trading-day number (New York close clock)
double g_wk[];      // trading-week number
double g_dhi[],g_dlo[],g_dop[];   // the day so far
double g_whi[],g_wlo[];           // the week so far
double g_aown[];    // owner date of the running Asia instance
double g_adk[];     // trading day the running Asia instance belongs to
double g_ahi[],g_alo[];
double g_flag[];    // signals already given today: 1 PDH, 2 PDL, 4 Asia high, 8 Asia low

const string PRODUCT="Session Levels";
const int    NY_CLOSE_SHIFT=7*3600;   // New York-close clock minus New York wall clock

ENUM_SL_CLOCK g_clock=SL_CLOCK_NY;
int      g_fixed_off=0;
bool     g_native=true;
long     g_sh_hour=-1;
int      g_sh_val=0;
int      g_s_start[3],g_s_end[3];
bool     g_s_on[3];
color    g_s_clr[3];
string   g_s_name[3]={"Asia","London","New York"};
string   g_pfx="";
datetime g_draw_bar=0;
uint     g_draw_tick=0;
double   g_draw_hi=0,g_draw_lo=0;
int      g_secs=60;
bool     g_no_draw=false;   // set in OnInit: tester without visual mode (no chart to draw on)

//+------------------------------------------------------------------+
//| Broker clock -> New York time                                    |
//+------------------------------------------------------------------+
//--- Sunday on or after `day` of `month` in year `y`, at `hour` UTC
datetime SundayFrom(const int y,const int month,const int day,const int hour)
  {
   MqlDateTime t;
   ZeroMemory(t);
   t.year=y;
   t.mon=month;
   t.day=day;
   datetime d=StructToTime(t);
   TimeToStruct(d,t);
   return(d+(datetime)(((7-t.day_of_week)%7)*86400+hour*3600));
  }

//--- US daylight saving (second Sunday of March 07:00 UTC to first Sunday of November 06:00 UTC)
bool UsDst(const datetime utc)
  {
   MqlDateTime t;
   TimeToStruct(utc,t);
   return(utc>=SundayFrom(t.year,3,8,7) && utc<SundayFrom(t.year,11,1,6));
  }

//--- EU summer time (last Sunday of March to last Sunday of October, 01:00 UTC)
bool EuDst(const datetime utc)
  {
   MqlDateTime t;
   TimeToStruct(utc,t);
   return(utc>=SundayFrom(t.year,3,25,1) && utc<SundayFrom(t.year,10,25,1));
  }

int NyOffset(const datetime utc) { return(UsDst(utc) ? 3*3600 : 2*3600); }

//--- the broker's offset from UTC at server time `srv`
int BrokerOffset(const datetime srv)
  {
   if(g_clock==SL_CLOCK_FIXED)
      return(g_fixed_off);
   if(g_clock==SL_CLOCK_EET)
      return(EuDst(srv-2*3600) ? 3*3600 : 2*3600);
   return(NyOffset(srv-2*3600));
  }

//--- seconds to add to server time to get New York-close time (cached per hour: offsets change on the hour)
int Shift(const datetime srv)
  {
   if(g_native)
      return(0);
   long h=(long)srv/3600;
   if(h!=g_sh_hour)
     {
      int b=BrokerOffset(srv);
      g_sh_val=NyOffset(srv-b)-b;
      g_sh_hour=h;
     }
   return(g_sh_val);
  }

//--- decide the clock once: the inputs, or the live server time against UTC (the tester can't tell)
void ResolveClock(void)
  {
   g_clock=InpClock;
   g_fixed_off=InpFixedUTC*3600;
   if(InpClock==SL_CLOCK_AUTO)
     {
      g_clock=SL_CLOCK_NY;
      if(!MQLInfoInteger(MQL_TESTER))
        {
         datetime gmt=TimeGMT();
         int off=(int)MathRound((double)(TimeTradeServer()-gmt)/1800.0)*1800;
         if(off==NyOffset(gmt))
            g_clock=SL_CLOCK_NY;
         else
            if(off==(EuDst(gmt) ? 3*3600 : 2*3600))
               g_clock=SL_CLOCK_EET;
            else
              {
               g_clock=SL_CLOCK_FIXED;
               g_fixed_off=off;
              }
        }
     }
   g_native=(g_clock==SL_CLOCK_NY);
   g_sh_hour=-1;
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
//--- "HH:MM" -> minutes since midnight, -1 when invalid
int ParseHM(const string s)
  {
   string p[];
   if(StringSplit(s,':',p)!=2)
      return(-1);
   int h=(int)StringToInteger(p[0]),m=(int)StringToInteger(p[1]);
   if(h<0 || h>23 || m<0 || m>59)
      return(-1);
   return(h*60+m);
  }

//--- is minute-of-day `m` inside [s,e) ? A session with s>e crosses midnight
bool InSession(const int m,const int s,const int e)
  {
   if(s==e)
      return(false);
   if(s<e)
      return(m>=s && m<e);
   return(m>=s || m<e);
  }

//--- owner date of a session bar: a session that crosses midnight belongs to the day it ends on
long OwnerDate(const long nyw,const int m,const int s,const int e)
  {
   long d=nyw/86400;
   return((s>e && m>=s) ? d+1 : d);
  }

int OnInit()
  {
   g_s_start[0]=ParseHM(InpAsiaStart);   g_s_end[0]=ParseHM(InpAsiaEnd);
   g_s_start[1]=ParseHM(InpLondonStart); g_s_end[1]=ParseHM(InpLondonEnd);
   g_s_start[2]=ParseHM(InpNYStart);     g_s_end[2]=ParseHM(InpNYEnd);
   for(int s=0; s<3; s++)
      if(g_s_start[s]<0 || g_s_end[s]<0)
        {
         Print("Session Levels: session times must be HH:MM (00:00 to 23:59)");
         return(INIT_PARAMETERS_INCORRECT);
        }
   g_s_on[0]=InpShowAsia;   g_s_clr[0]=InpAsiaColor;
   g_s_on[1]=InpShowLondon; g_s_clr[1]=InpLondonColor;
   g_s_on[2]=InpShowNY;     g_s_clr[2]=InpNYColor;
   if(InpDays<1 || InpLevelWidth<1)
     {
      Print("Session Levels: days to draw and line width must be at least 1");
      return(INIT_PARAMETERS_INCORRECT);
     }
   SetIndexBuffer(0,g_pdh,INDICATOR_DATA);
   SetIndexBuffer(1,g_pdl,INDICATOR_DATA);
   SetIndexBuffer(2,g_pwh,INDICATOR_DATA);
   SetIndexBuffer(3,g_pwl,INDICATOR_DATA);
   SetIndexBuffer(4,g_ash,INDICATOR_DATA);
   SetIndexBuffer(5,g_asl,INDICATOR_DATA);
   SetIndexBuffer(6,g_sig,INDICATOR_DATA);
   SetIndexBuffer(7,g_nyw,INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,g_dk,INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,g_wk,INDICATOR_CALCULATIONS);
   SetIndexBuffer(10,g_dhi,INDICATOR_CALCULATIONS);
   SetIndexBuffer(11,g_dlo,INDICATOR_CALCULATIONS);
   SetIndexBuffer(12,g_dop,INDICATOR_CALCULATIONS);
   SetIndexBuffer(13,g_whi,INDICATOR_CALCULATIONS);
   SetIndexBuffer(14,g_wlo,INDICATOR_CALCULATIONS);
   SetIndexBuffer(15,g_aown,INDICATOR_CALCULATIONS);
   SetIndexBuffer(16,g_adk,INDICATOR_CALCULATIONS);
   SetIndexBuffer(17,g_ahi,INDICATOR_CALCULATIONS);
   SetIndexBuffer(18,g_alo,INDICATOR_CALCULATIONS);
   SetIndexBuffer(19,g_flag,INDICATOR_CALCULATIONS);
   for(int p=0; p<7; p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME,"Session Levels");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   ResolveClock();
   if(MQLInfoInteger(MQL_TESTER) && InpClock==SL_CLOCK_AUTO)
      Print("Session Levels: the Strategy Tester can't detect the broker's clock; New York close is assumed. ",
            "Set 'Broker server clock' for a broker on another clock.");
   g_secs=PeriodSeconds();
   g_pfx="SLV"+IntegerToString((int)(GetMicrosecondCount()%1000000))+"_";
   g_draw_bar=0;
   g_no_draw=(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(g_pfx!="")
     {
      ObjectsDeleteAll(0,g_pfx);
      ChartRedraw();
     }
  }

//+------------------------------------------------------------------+
//| Drawing                                                          |
//+------------------------------------------------------------------+
void PutObj(const string name,const ENUM_OBJECT type,const datetime t1,const double p1,const datetime t2,const double p2)
  {
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,type,0,t1,p1,t2,p2);
   else
     {
      ObjectSetInteger(0,name,OBJPROP_TIME,0,t1);
      ObjectSetDouble(0,name,OBJPROP_PRICE,0,p1);
      ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
      ObjectSetDouble(0,name,OBJPROP_PRICE,1,p2);
     }
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
  }

void PutText(const string name,const datetime t,const double price,const string text,const color clr,const ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   else
     {
      ObjectSetInteger(0,name,OBJPROP_TIME,0,t);
      ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
     }
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void DrawBox(const int s,const long owner,const datetime t1,const datetime t2,const double hi,const double lo)
  {
   string nm=g_pfx+"B"+IntegerToString(s)+"_"+IntegerToString(owner);
   PutObj(nm,OBJ_RECTANGLE,t1,hi,t2,lo);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,InpFillBoxes ? ColorToARGB(g_s_clr[s],60) : g_s_clr[s]);
   ObjectSetInteger(0,nm,OBJPROP_FILL,InpFillBoxes);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,1);
   if(InpSessionLabels)
      PutText(g_pfx+"T"+IntegerToString(s)+"_"+IntegerToString(owner),t1,hi,g_s_name[s],g_s_clr[s],ANCHOR_LEFT_LOWER);
  }

void DrawLevel(const string tag,const string label,const double price,const color clr,const int a,const int b,
               const bool current,const datetime &time[],const int last,const ENUM_LINE_STYLE style)
  {
   if(price==EMPTY_VALUE || price<=0)
      return;
   datetime t1=time[a],t2=(current ? time[last]+g_secs : time[b]+g_secs);
   string nm=g_pfx+"L"+tag+"_"+IntegerToString((long)time[a]);
   PutObj(nm,OBJ_TREND,t1,price,t2,price);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,InpLevelWidth);
   ObjectSetInteger(0,nm,OBJPROP_STYLE,style);
   ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,current);
   if(current && InpLevelLabels)
      PutText(g_pfx+"P"+tag,time[last]+3*g_secs,price,label+" "+DoubleToString(price,_Digits),clr,ANCHOR_LEFT);
  }

//--- redraw everything for the last InpDays days (objects are deleted first, so old days disappear)
void Draw(const int rates_total,const datetime &time[],const double &high[],const double &low[])
  {
   int last=rates_total-1;
   bool intraday=(g_secs<=PeriodSeconds(PERIOD_H4));
   int days=(intraday ? MathMin(InpDays,60) : 1);
   ObjectsDeleteAll(0,g_pfx);
   //--- first bar of the oldest day to draw
   int first=last,cnt=1;
   for(int k=last; k>0; k--)
     {
      if(g_dk[k-1]!=g_dk[k])
        {
         if(cnt>=days)
            break;
         cnt++;
        }
      first=k-1;
     }
   //--- session boxes
   if(intraday)
      for(int s=0; s<3; s++)
        {
         if(!g_s_on[s])
            continue;
         bool open=false;
         long owner=0;
         int st=0,en=0;
         double hi=0,lo=0;
         for(int j=first; j<=last; j++)
           {
            int m=(int)(((long)g_nyw[j]%86400)/60);
            if(InSession(m,g_s_start[s],g_s_end[s]))
              {
               long ow=OwnerDate((long)g_nyw[j],m,g_s_start[s],g_s_end[s]);
               if(open && ow==owner)
                 {
                  en=j;
                  hi=MathMax(hi,high[j]);
                  lo=MathMin(lo,low[j]);
                 }
               else
                 {
                  if(open)
                     DrawBox(s,owner,time[st],time[en]+g_secs,hi,lo);
                  open=true;
                  owner=ow;
                  st=j;
                  en=j;
                  hi=high[j];
                  lo=low[j];
                 }
              }
            else
               if(open)
                 {
                  DrawBox(s,owner,time[st],time[en]+g_secs,hi,lo);
                  open=false;
                 }
           }
         if(open)
            DrawBox(s,owner,time[st],time[en]+g_secs,hi,lo);
        }
   //--- level lines, one segment per day; the current day is a ray to the right
   int a=first;
   while(a<=last)
     {
      int b=a;
      while(b<last && g_dk[b+1]==g_dk[a])
         b++;
      bool cur=(b==last);
      if(InpShowPD)
        {
         DrawLevel("PDH","PDH",g_pdh[a],InpPDColor,a,b,cur,time,last,STYLE_SOLID);
         DrawLevel("PDL","PDL",g_pdl[a],InpPDColor,a,b,cur,time,last,STYLE_SOLID);
        }
      if(InpShowPW)
        {
         DrawLevel("PWH","PWH",g_pwh[a],InpPWColor,a,b,cur,time,last,STYLE_DASH);
         DrawLevel("PWL","PWL",g_pwl[a],InpPWColor,a,b,cur,time,last,STYLE_DASH);
        }
      if(InpShowOpen && intraday)
         DrawLevel("OP","Open",g_dop[a],InpOpenColor,a,b,cur,time,last,STYLE_DOT);
      a=b+1;
     }
   g_draw_bar=time[last];
   g_draw_tick=GetTickCount();
   g_draw_hi=high[last];
   g_draw_lo=low[last];
   ChartRedraw();
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<2)
      return(0);
   int start=(prev_calculated>0 ? prev_calculated-1 : 0);
   for(int i=start; i<rates_total; i++)
     {
      long nyc=(long)time[i]+Shift(time[i]);
      long nyw=nyc-NY_CLOSE_SHIFT;
      long dk=nyc/86400,wk=(dk+3)/7;
      int  m=(int)((nyw%86400)/60);
      g_nyw[i]=(double)nyw;
      g_dk[i]=(double)dk;
      g_wk[i]=(double)wk;
      bool new_day=(i==0 || (long)g_dk[i-1]!=dk);
      bool new_week=(i==0 || (long)g_wk[i-1]!=wk);
      int  fl=0;
      //--- day: previous day levels and today's range
      if(new_day)
        {
         g_pdh[i]=(i>0 ? g_dhi[i-1] : EMPTY_VALUE);
         g_pdl[i]=(i>0 ? g_dlo[i-1] : EMPTY_VALUE);
         g_dhi[i]=high[i];
         g_dlo[i]=low[i];
         g_dop[i]=open[i];
        }
      else
        {
         g_pdh[i]=g_pdh[i-1];
         g_pdl[i]=g_pdl[i-1];
         g_dhi[i]=MathMax(g_dhi[i-1],high[i]);
         g_dlo[i]=MathMin(g_dlo[i-1],low[i]);
         g_dop[i]=g_dop[i-1];
         fl=(int)g_flag[i-1];
        }
      //--- week
      if(new_week)
        {
         g_pwh[i]=(i>0 ? g_whi[i-1] : EMPTY_VALUE);
         g_pwl[i]=(i>0 ? g_wlo[i-1] : EMPTY_VALUE);
         g_whi[i]=high[i];
         g_wlo[i]=low[i];
        }
      else
        {
         g_pwh[i]=g_pwh[i-1];
         g_pwl[i]=g_pwl[i-1];
         g_whi[i]=MathMax(g_whi[i-1],high[i]);
         g_wlo[i]=MathMin(g_wlo[i-1],low[i]);
        }
      //--- Asia range of the current trading day
      if(i>0)
        {
         g_aown[i]=g_aown[i-1];
         g_adk[i]=g_adk[i-1];
         g_ahi[i]=g_ahi[i-1];
         g_alo[i]=g_alo[i-1];
        }
      else
        {
         g_aown[i]=-1;
         g_adk[i]=-1;
         g_ahi[i]=0;
         g_alo[i]=0;
        }
      bool in_asia=InSession(m,g_s_start[0],g_s_end[0]);
      if(in_asia)
        {
         long ow=OwnerDate(nyw,m,g_s_start[0],g_s_end[0]);
         if((long)g_aown[i]!=ow)
           {
            g_aown[i]=(double)ow;
            g_adk[i]=(double)dk;
            g_ahi[i]=high[i];
            g_alo[i]=low[i];
           }
         else
           {
            g_ahi[i]=MathMax(g_ahi[i],high[i]);
            g_alo[i]=MathMin(g_alo[i],low[i]);
           }
        }
      bool asia_ok=((long)g_adk[i]==dk && g_aown[i]!=-1);
      g_ash[i]=(asia_ok ? g_ahi[i] : EMPTY_VALUE);
      g_asl[i]=(asia_ok ? g_alo[i] : EMPTY_VALUE);
      //--- signals: closed bars only, each kind once per trading day
      g_sig[i]=EMPTY_VALUE;
      if(i<=rates_total-2)
        {
         int kinds=0;
         if(g_pdh[i]!=EMPTY_VALUE)
           {
            if((fl&1)==0 && close[i]>g_pdh[i])
               kinds|=1;
            if((fl&2)==0 && close[i]<g_pdl[i])
               kinds|=2;
           }
         if(asia_ok && !in_asia)
           {
            if((fl&4)==0 && close[i]>g_ahi[i])
               kinds|=4;
            if((fl&8)==0 && close[i]<g_alo[i])
               kinds|=8;
           }
         fl|=kinds;
         if((kinds&1)!=0)
            g_sig[i]=1;
         else
            if((kinds&2)!=0)
               g_sig[i]=-1;
            else
               if((kinds&4)!=0)
                  g_sig[i]=2;
               else
                  if((kinds&8)!=0)
                     g_sig[i]=-2;
         if(kinds!=0 && i==rates_total-2)
           {
            string txt="";
            if((kinds&1)!=0 && InpAlertPDH)
               txt+="closed above previous day high "+DoubleToString(g_pdh[i],_Digits)+"; ";
            if((kinds&2)!=0 && InpAlertPDL)
               txt+="closed below previous day low "+DoubleToString(g_pdl[i],_Digits)+"; ";
            if((kinds&4)!=0 && InpAlertAsiaH)
               txt+="closed above Asia high "+DoubleToString(g_ahi[i],_Digits)+"; ";
            if((kinds&8)!=0 && InpAlertAsiaL)
               txt+="closed below Asia low "+DoubleToString(g_alo[i],_Digits)+"; ";
            if(txt!="")
               SignalAlert(PRODUCT,StringSubstr(txt,0,StringLen(txt)-2),time[i],prev_calculated>0);
           }
        }
      g_flag[i]=fl;
     }
   if(g_no_draw)
      return(rates_total);
   //--- objects: on a new bar, or (throttled) when the live bar widens the live session
   int last=rates_total-1;
   bool newbar=(time[last]!=g_draw_bar);
   bool widen=(g_secs<=PeriodSeconds(PERIOD_H4) && (high[last]>g_draw_hi || low[last]<g_draw_lo) && GetTickCount()-g_draw_tick>=1000);
   if(newbar || widen)
      Draw(rates_total,time,high,low);
   return(rates_total);
  }
//+------------------------------------------------------------------+
