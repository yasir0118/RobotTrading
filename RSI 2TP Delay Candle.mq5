//+------------------------------------------------------------------+
//|                                                  RSI_Grid_EA.mq5 |
//|                                         Expert Advisor Grid RSI |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "RSI Grid EA"
#property link      ""
#property version   "1.01"
#property description "EA Grid berbasis RSI dengan TP Global per Basket dan TP2"

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+

// --- Parameter RSI ---
input int    InpRSIPeriod   = 14;                    // Periode RSI
input ENUM_APPLIED_PRICE InpRSIPrice = PRICE_CLOSE;  // Harga yang digunakan RSI
input double InpRSI_OB     = 70.0;                   // Level Overbought
input double InpRSI_OS     = 30.0;                   // Level Oversold

// --- Grid & TP ---
input double InpGridDistancePoints = 20;   // Jarak antar entry (dalam POINT)
input double InpTPPoints           = 20;   // TP untuk entry pertama (dalam POINT)

// --- TP2 Parameters ---
input int    InpTP2MinPositions    = 50;   // Jumlah minimum posisi untuk aktifkan TP2
input double InpTP2ProfitPercent   = 60.0; // Persentase posisi profit untuk close all (%)
input int    InpTP2CandleDelay     = 3;    // Jeda candle setelah close all TP2

// --- Money Management ---
input double InpLotSize  = 0.10;           // Lot fixed per entry
input int    InpMaxOrdersPerBasket = 100;  // Batas maksimal jumlah order per basket

// --- Lain-lain ---
input int    InpMagicNumber = 123456;      // Magic number EA
input double InpMaxSpreadPoints = 50;      // Batas maksimal spread (dalam POINT)
input bool   InpOnlyOneBasket = true;      // Hanya boleh satu arah basket aktif
input bool   InpUseSL        = false;      // Gunakan SL
input double InpSLPoints     = 0;          // Nilai SL (POINT)

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
int      g_rsi_handle;           // Handle indikator RSI
double   g_rsi_buffer[];         // Buffer untuk nilai RSI
double   g_prev_rsi;             // RSI candle sebelumnya untuk deteksi cross
bool     g_initialized = false;  // Flag inisialisasi

// TP2 Variables
datetime g_last_buy_close_time = 0;   // Waktu terakhir close all BUY
datetime g_last_sell_close_time = 0;  // Waktu terakhir close all SELL
int      g_buy_candle_delay = 0;      // Counter candle delay BUY
int      g_sell_candle_delay = 0;     // Counter candle delay SELL
datetime g_last_candle_time = 0;      // Waktu candle terakhir untuk deteksi candle baru

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set array sebagai series (index 0 = candle terbaru)
   ArraySetAsSeries(g_rsi_buffer, true);
   
   // Inisialisasi indikator RSI
   g_rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, InpRSIPrice);
   
   if(g_rsi_handle == INVALID_HANDLE)
   {
      Print("ERROR: Gagal membuat handle RSI");
      return(INIT_FAILED);
   }
   
   // Tunggu data RSI tersedia
   if(CopyBuffer(g_rsi_handle, 0, 0, 2, g_rsi_buffer) <= 0)
   {
      Print("WARNING: Data RSI belum tersedia, menunggu...");
   }
   else
   {
      g_prev_rsi = g_rsi_buffer[1];
      g_initialized = true;
   }
   
   // Inisialisasi waktu candle
   g_last_candle_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // Tampilkan informasi EA
   Print("========================================");
   Print("RSI Grid EA - Initialized");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: ", EnumToString(PERIOD_CURRENT));
   Print("RSI Period: ", InpRSIPeriod);
   Print("RSI OB/OS: ", InpRSI_OB, " / ", InpRSI_OS);
   Print("Grid Distance: ", InpGridDistancePoints, " points");
   Print("TP Distance: ", InpTPPoints, " points");
   Print("TP2 Min Positions: ", InpTP2MinPositions);
   Print("TP2 Profit %: ", InpTP2ProfitPercent, "%");
   Print("TP2 Candle Delay: ", InpTP2CandleDelay);
   Print("Lot Size: ", InpLotSize);
   Print("Max Orders per Basket: ", InpMaxOrdersPerBasket);
   Print("Only One Basket: ", InpOnlyOneBasket ? "YES" : "NO");
   Print("Magic Number: ", InpMagicNumber);
   Print("========================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indikator RSI
   if(g_rsi_handle != INVALID_HANDLE)
      IndicatorRelease(g_rsi_handle);
   
   Print("RSI Grid EA - Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Deteksi candle baru
   datetime current_candle_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool is_new_candle = (current_candle_time != g_last_candle_time);
   
   if(is_new_candle)
   {
      g_last_candle_time = current_candle_time;
      
      // Update counter delay
      if(g_buy_candle_delay > 0)
         g_buy_candle_delay--;
      if(g_sell_candle_delay > 0)
         g_sell_candle_delay--;
   }
   
   // Update nilai RSI
   if(CopyBuffer(g_rsi_handle, 0, 0, 2, g_rsi_buffer) <= 0)
   {
      Print("ERROR: Gagal mengambil data RSI");
      return;
   }
   
   double current_rsi = g_rsi_buffer[0];
   
   // Inisialisasi prev_rsi jika belum
   if(!g_initialized)
   {
      g_prev_rsi = g_rsi_buffer[1];
      g_initialized = true;
      return;
   }
   
   // Cek spread
   double current_spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   if(current_spread > InpMaxSpreadPoints)
   {
      // Spread terlalu besar, skip
      return;
   }
   
   // Hitung jumlah order aktif
   int buy_count = CountBuyOrders();
   int sell_count = CountSellOrders();
   
   // ========== CEK TP2 untuk BUY ==========
   if(buy_count > InpTP2MinPositions)
   {
      CheckTP2Buy(buy_count);
   }
   
   // ========== CEK TP2 untuk SELL ==========
   if(sell_count > InpTP2MinPositions)
   {
      CheckTP2Sell(sell_count);
   }
   
   // ========== CEK SINYAL SELL ==========
   CheckAndOpenSell(current_rsi, buy_count, sell_count);
   
   // ========== CEK SINYAL BUY ==========
   CheckAndOpenBuy(current_rsi, buy_count, sell_count);
   
   // Update prev_rsi untuk tick berikutnya
   g_prev_rsi = current_rsi;
}

//+------------------------------------------------------------------+
//| Cek TP2 untuk posisi BUY                                         |
//+------------------------------------------------------------------+
void CheckTP2Buy(int total_buy)
{
   int profit_count = 0;
   
   // Hitung berapa posisi BUY yang profit
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit > 0)
               profit_count++;
         }
      }
   }
   
   // Hitung persentase profit
   double profit_percentage = (profit_count * 100.0) / total_buy;
   
   // Jika mencapai target, close all BUY
   if(profit_percentage >= InpTP2ProfitPercent)
   {
      Print("TP2 TRIGGERED! BUY - Total: ", total_buy, " | Profit: ", profit_count, " (", DoubleToString(profit_percentage, 2), "%)");
      CloseAllBuyOrders();
      
      // Set delay
      g_buy_candle_delay = InpTP2CandleDelay;
      g_last_buy_close_time = TimeCurrent();
      
      Print("BUY delay aktif untuk ", InpTP2CandleDelay, " candle");
   }
}

//+------------------------------------------------------------------+
//| Cek TP2 untuk posisi SELL                                        |
//+------------------------------------------------------------------+
void CheckTP2Sell(int total_sell)
{
   int profit_count = 0;
   
   // Hitung berapa posisi SELL yang profit
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit > 0)
               profit_count++;
         }
      }
   }
   
   // Hitung persentase profit
   double profit_percentage = (profit_count * 100.0) / total_sell;
   
   // Jika mencapai target, close all SELL
   if(profit_percentage >= InpTP2ProfitPercent)
   {
      Print("TP2 TRIGGERED! SELL - Total: ", total_sell, " | Profit: ", profit_count, " (", DoubleToString(profit_percentage, 2), "%)");
      CloseAllSellOrders();
      
      // Set delay
      g_sell_candle_delay = InpTP2CandleDelay;
      g_last_sell_close_time = TimeCurrent();
      
      Print("SELL delay aktif untuk ", InpTP2CandleDelay, " candle");
   }
}

//+------------------------------------------------------------------+
//| Close semua posisi BUY                                           |
//+------------------------------------------------------------------+
void CloseAllBuyOrders()
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            request.action = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = ORDER_TYPE_SELL;
            request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            request.deviation = 10;
            request.magic = InpMagicNumber;
            
            if(!OrderSend(request, result))
            {
               Print("ERROR: Gagal close BUY #", ticket, " | Error: ", GetLastError());
            }
         }
      }
   }
   
   Print("Semua posisi BUY telah di-close (TP2)");
}

//+------------------------------------------------------------------+
//| Close semua posisi SELL                                          |
//+------------------------------------------------------------------+
void CloseAllSellOrders()
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            request.action = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = ORDER_TYPE_BUY;
            request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.deviation = 10;
            request.magic = InpMagicNumber;
            
            if(!OrderSend(request, result))
            {
               Print("ERROR: Gagal close SELL #", ticket, " | Error: ", GetLastError());
            }
         }
      }
   }
   
   Print("Semua posisi SELL telah di-close (TP2)");
}

//+------------------------------------------------------------------+
//| Fungsi untuk cek dan buka order SELL                            |
//+------------------------------------------------------------------+
void CheckAndOpenSell(double current_rsi, int buy_count, int sell_count)
{
   // Cek delay candle
   if(g_sell_candle_delay > 0)
   {
      // Masih dalam periode delay, skip
      return;
   }
   
   // Jika InpOnlyOneBasket = true dan ada basket BUY aktif, jangan buka SELL
   if(InpOnlyOneBasket && buy_count > 0)
      return;
   
   // ===== SELL PERTAMA =====
   if(sell_count == 0)
   {
      // Deteksi cross: RSI baru masuk zona overbought
      bool rsi_cross_ob = (g_prev_rsi < InpRSI_OB && current_rsi >= InpRSI_OB);
      
      if(rsi_cross_ob || current_rsi >= InpRSI_OB)
      {
         // Buka SELL pertama
         double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double tp_price = entry_price - (InpTPPoints * _Point);
         double sl_price = 0;
         
         if(InpUseSL && InpSLPoints > 0)
            sl_price = entry_price + (InpSLPoints * _Point);
         
         OpenSellOrder(InpLotSize, sl_price, tp_price);
         
         Print("SELL PERTAMA dibuka. RSI: ", current_rsi, " | Entry: ", entry_price, " | TP: ", tp_price);
      }
   }
   // ===== SELL GRID TAMBAHAN =====
   else if(sell_count < InpMaxOrdersPerBasket)
   {
      double last_sell_price = GetLastSellPrice();
      double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double distance = (current_price - last_sell_price) / _Point;
      
      // Jika harga naik minimal InpGridDistancePoints dari entry terakhir
      if(distance >= InpGridDistancePoints)
      {
         // Jika sudah lebih dari InpTP2MinPositions, jangan set TP (gunakan TP2)
         double tp_price = 0;
         double sl_price = 0;
         
         if(sell_count < InpTP2MinPositions)
         {
            // Masih pakai TP global
            double first_sell_price = GetFirstSellPrice();
            tp_price = first_sell_price - (InpTPPoints * _Point);
            
            if(InpUseSL && InpSLPoints > 0)
               sl_price = first_sell_price + (InpSLPoints * _Point);
         }
         
         OpenSellOrder(InpLotSize, sl_price, tp_price);
         
         if(sell_count >= InpTP2MinPositions)
            Print("SELL GRID tambahan (TP2 Mode). Entry: ", current_price, " | Total SELL: ", sell_count + 1);
         else
            Print("SELL GRID tambahan. Entry: ", current_price, " | TP Global: ", tp_price, " | Total SELL: ", sell_count + 1);
      }
   }
}

//+------------------------------------------------------------------+
//| Fungsi untuk cek dan buka order BUY                             |
//+------------------------------------------------------------------+
void CheckAndOpenBuy(double current_rsi, int buy_count, int sell_count)
{
   // Cek delay candle
   if(g_buy_candle_delay > 0)
   {
      // Masih dalam periode delay, skip
      return;
   }
   
   // Jika InpOnlyOneBasket = true dan ada basket SELL aktif, jangan buka BUY
   if(InpOnlyOneBasket && sell_count > 0)
      return;
   
   // ===== BUY PERTAMA =====
   if(buy_count == 0)
   {
      // Deteksi cross: RSI baru masuk zona oversold
      bool rsi_cross_os = (g_prev_rsi > InpRSI_OS && current_rsi <= InpRSI_OS);
      
      if(rsi_cross_os || current_rsi <= InpRSI_OS)
      {
         // Buka BUY pertama
         double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double tp_price = entry_price + (InpTPPoints * _Point);
         double sl_price = 0;
         
         if(InpUseSL && InpSLPoints > 0)
            sl_price = entry_price - (InpSLPoints * _Point);
         
         OpenBuyOrder(InpLotSize, sl_price, tp_price);
         
         Print("BUY PERTAMA dibuka. RSI: ", current_rsi, " | Entry: ", entry_price, " | TP: ", tp_price);
      }
   }
   // ===== BUY GRID TAMBAHAN =====
   else if(buy_count < InpMaxOrdersPerBasket)
   {
      double last_buy_price = GetLastBuyPrice();
      double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double distance = (last_buy_price - current_price) / _Point;
      
      // Jika harga turun minimal InpGridDistancePoints dari entry terakhir
      if(distance >= InpGridDistancePoints)
      {
         // Jika sudah lebih dari InpTP2MinPositions, jangan set TP (gunakan TP2)
         double tp_price = 0;
         double sl_price = 0;
         
         if(buy_count < InpTP2MinPositions)
         {
            // Masih pakai TP global
            double first_buy_price = GetFirstBuyPrice();
            tp_price = first_buy_price + (InpTPPoints * _Point);
            
            if(InpUseSL && InpSLPoints > 0)
               sl_price = first_buy_price - (InpSLPoints * _Point);
         }
         
         OpenBuyOrder(InpLotSize, sl_price, tp_price);
         
         if(buy_count >= InpTP2MinPositions)
            Print("BUY GRID tambahan (TP2 Mode). Entry: ", current_price, " | Total BUY: ", buy_count + 1);
         else
            Print("BUY GRID tambahan. Entry: ", current_price, " | TP Global: ", tp_price, " | Total BUY: ", buy_count + 1);
      }
   }
}

//+------------------------------------------------------------------+
//| Hitung jumlah order BUY aktif                                    |
//+------------------------------------------------------------------+
int CountBuyOrders()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Hitung jumlah order SELL aktif                                   |
//+------------------------------------------------------------------+
int CountSellOrders()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Dapatkan harga entry BUY pertama (berdasarkan waktu buka)       |
//+------------------------------------------------------------------+
double GetFirstBuyPrice()
{
   datetime earliest_time = D'2099.12.31';
   double first_price = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
            if(open_time < earliest_time)
            {
               earliest_time = open_time;
               first_price = PositionGetDouble(POSITION_PRICE_OPEN);
            }
         }
      }
   }
   return first_price;
}

//+------------------------------------------------------------------+
//| Dapatkan harga entry SELL pertama (berdasarkan waktu buka)      |
//+------------------------------------------------------------------+
double GetFirstSellPrice()
{
   datetime earliest_time = D'2099.12.31';
   double first_price = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
            if(open_time < earliest_time)
            {
               earliest_time = open_time;
               first_price = PositionGetDouble(POSITION_PRICE_OPEN);
            }
         }
      }
   }
   return first_price;
}

//+------------------------------------------------------------------+
//| Dapatkan harga entry BUY terakhir (paling baru)                 |
//+------------------------------------------------------------------+
double GetLastBuyPrice()
{
   datetime latest_time = 0;
   double last_price = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
            if(open_time > latest_time)
            {
               latest_time = open_time;
               last_price = PositionGetDouble(POSITION_PRICE_OPEN);
            }
         }
      }
   }
   return last_price;
}

//+------------------------------------------------------------------+
//| Dapatkan harga entry SELL terakhir (paling baru)                |
//+------------------------------------------------------------------+
double GetLastSellPrice()
{
   datetime latest_time = 0;
   double last_price = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
            if(open_time > latest_time)
            {
               latest_time = open_time;
               last_price = PositionGetDouble(POSITION_PRICE_OPEN);
            }
         }
      }
   }
   return last_price;
}

//+------------------------------------------------------------------+
//| Buka order BUY                                                    |
//+------------------------------------------------------------------+
bool OpenBuyOrder(double lot, double sl, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lot;
   request.type = ORDER_TYPE_BUY;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = InpMagicNumber;
   request.comment = "RSI Grid BUY";
   
   // Normalisasi harga
   request.price = NormalizeDouble(request.price, _Digits);
   if(sl > 0) request.sl = NormalizeDouble(sl, _Digits);
   if(tp > 0) request.tp = NormalizeDouble(tp, _Digits);
   
   // Kirim order
   if(!OrderSend(request, result))
   {
      Print("ERROR: Gagal membuka BUY order. Error: ", GetLastError(), " | Retcode: ", result.retcode);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Buka order SELL                                                   |
//+------------------------------------------------------------------+
bool OpenSellOrder(double lot, double sl, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lot;
   request.type = ORDER_TYPE_SELL;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = InpMagicNumber;
   request.comment = "RSI Grid SELL";
   
   // Normalisasi harga
   request.price = NormalizeDouble(request.price, _Digits);
   if(sl > 0) request.sl = NormalizeDouble(sl, _Digits);
   if(tp > 0) request.tp = NormalizeDouble(tp, _Digits);
   
   // Kirim order
   if(!OrderSend(request, result))
   {
      Print("ERROR: Gagal membuka SELL order. Error: ", GetLastError(), " | Retcode: ", result.retcode);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+