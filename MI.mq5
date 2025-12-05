//+------------------------------------------------------------------+
//|                                    Momentum Candle XAUUSD by Yasir |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Converted by Assistant"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Plot Bullish Signal
#property indicator_label1  "Bullish Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrBlue
#property indicator_width1  2

//--- Plot Bearish Signal
#property indicator_label2  "Bearish Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

//--- Input parameters
input int xauM5  = 35;  // XAUUSD M5 Min Body (pip)
input int xauM15 = 45;  // XAUUSD M15 Min Body (pip)
input int xauH1  = 60;  // XAUUSD H1 Min Body (pip)

//--- Indicator buffers
double BullishBuffer[];
double BearishBuffer[];

//--- Global variables
string currentSymbol;
ENUM_TIMEFRAMES currentTimeframe;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BullishBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, BearishBuffer, INDICATOR_DATA);
   
   //--- Set arrow codes
   PlotIndexSetInteger(0, PLOT_ARROW, 233);  // Up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 234);  // Down arrow
   
   //--- Set arrow shift
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, 30); // Mengatur Jarak Panah Bearish
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -30); // Mengatur Jarak Panah Bullish
   
   //--- Set empty value
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   
   //--- Get current symbol and timeframe
   currentSymbol = Symbol();
   currentTimeframe = Period();
   
   //--- Set indicator name
   IndicatorSetString(INDICATOR_SHORTNAME, "Momentum Candle XAUUSD");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Get minimum range based on symbol and timeframe                  |
//+------------------------------------------------------------------+
double GetMinRange(string symbol, ENUM_TIMEFRAMES tf)
{
   double pip = 0.0;
   
   // Check if symbol contains "XAUUSD" or "GOLD"
   if(StringFind(symbol, "XAUUSD") >= 0 || StringFind(symbol, "GOLD") >= 0)
   {
      switch(tf)
      {
         case PERIOD_M5:
            pip = xauM5 * 0.1;
            break;
         case PERIOD_M15:
            pip = xauM15 * 0.1;
            break;
         case PERIOD_H1:
            pip = xauH1 * 0.1;
            break;
         default:
            pip = 0.0;
            break;
      }
   }
   
   return pip;
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //--- Get minimum range
   double minRange = GetMinRange(currentSymbol, currentTimeframe);
   
   //--- If no valid range, exit
   if(minRange <= 0.0)
      return rates_total;
   
   //--- Start calculation from the first uncalculated bar
   int start = prev_calculated > 0 ? prev_calculated - 1 : 0;
   
   //--- Main loop
   for(int i = start; i < rates_total - 1; i++) // -1 to skip current forming bar
   {
      //--- Initialize buffers
      BullishBuffer[i] = 0.0;
      BearishBuffer[i] = 0.0;
      
      //--- Candle structure
      double totalRange = MathAbs(close[i] - open[i]);
      double upperWick = high[i] - MathMax(open[i], close[i]);
      double lowerWick = MathMin(open[i], close[i]) - low[i];
      double totalWick = upperWick + lowerWick;
      
      //--- Candle validation
      bool isBigCandle = totalRange >= minRange;
      bool isWickShort = (totalWick / (totalRange + totalWick)) <= 0.3;
      bool isBullish = close[i] > open[i];
      bool isBearish = close[i] < open[i];
      bool isBullishValid = isBullish && lowerWick < upperWick;
      bool isBearishValid = isBearish && upperWick < lowerWick;
      bool rawSignal = isBigCandle && isWickShort && (isBullishValid || isBearishValid);
      
      //--- Plot signals
      if(rawSignal && isBullishValid)
      {
         BullishBuffer[i] = low[i];
      }
      
      if(rawSignal && isBearishValid)
      {
         BearishBuffer[i] = high[i];
      }
   }
   
   //--- Check for alert on the last completed bar
   CheckForAlert(rates_total, time, open, high, low, close, minRange);
   
   //--- Return value of prev_calculated for next call
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Check for alert condition                                         |
//+------------------------------------------------------------------+
void CheckForAlert(const int rates_total,
                   const datetime &time[],
                   const double &open[],
                   const double &high[],
                   const double &low[],
                   const double &close[],
                   double minRange)
{
   static datetime lastAlertTime = 0;
   
   if(rates_total < 2) return;
   
   int lastBar = rates_total - 2; // Last completed bar
   
   //--- Avoid duplicate alerts
   if(time[lastBar] == lastAlertTime) return;
   
   //--- Calculate time remaining (in seconds)
   datetime currentTime = TimeCurrent();
   datetime barCloseTime = time[lastBar] + PeriodSeconds(currentTimeframe);
   int barTimeLeft = (int)(barCloseTime - currentTime);
   
   //--- Alert window: between 90 and 20 seconds before close
   bool alertWindow = (barTimeLeft <= 90 && barTimeLeft >= 20);
   
   if(!alertWindow) return;
   
   //--- Candle structure for last bar
   double totalRange = MathAbs(close[lastBar] - open[lastBar]);
   double upperWick = high[lastBar] - MathMax(open[lastBar], close[lastBar]);
   double lowerWick = MathMin(open[lastBar], close[lastBar]) - low[lastBar];
   double totalWick = upperWick + lowerWick;
   
   //--- Candle validation
   bool isBigCandle = totalRange >= minRange;
   bool isWickShort = (totalWick / (totalRange + totalWick)) <= 0.3;
   bool isBullish = close[lastBar] > open[lastBar];
   bool isBearish = close[lastBar] < open[lastBar];
   bool isBullishValid = isBullish && lowerWick < upperWick;
   bool isBearishValid = isBearish && upperWick < lowerWick;
   bool rawSignal = isBigCandle && isWickShort && (isBullishValid || isBearishValid);
   
   //--- Send alert
   if(rawSignal && isBullishValid)
   {
      Alert("Momentum candle bullish valid on ", currentSymbol, " ", EnumToString(currentTimeframe));
      lastAlertTime = time[lastBar];
   }
   
   if(rawSignal && isBearishValid)
   {
      Alert("Momentum candle bearish valid on ", currentSymbol, " ", EnumToString(currentTimeframe));
      lastAlertTime = time[lastBar];
   }
}

//+------------------------------------------------------------------+