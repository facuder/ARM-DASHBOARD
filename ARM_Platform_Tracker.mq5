//+------------------------------------------------------------------+
//|  ARM Account Tracker — Platform Edition                         |
//|  Envia datos a la plataforma ARM centralizada                   |
//|  Cada usuario usa su propia API Key                             |
//+------------------------------------------------------------------+
#property copyright "ARM Strategy"
#property version   "2.00"
#property strict

input string ApiKey      = "PEGA_AQUI_TU_API_KEY";  // API Key (obtenela en tu perfil)
input string ServerURL   = "https://TU-APP.railway.app"; // URL del servidor
input int    UpdateMin   = 1;      // Frecuencia en minutos
input bool   SendOnTrade = true;   // Enviar al cerrar/abrir trade
input bool   EnableLogs  = true;

datetime lastSent    = 0;
int      lastHistory = 0;
string   endpoint    = "";

int OnInit()
{
   if(ApiKey == "PEGA_AQUI_TU_API_KEY" || StringLen(ApiKey) < 10)
   {
      Alert("ARM Tracker: ⚠️ Configurá tu API Key en los parámetros del EA");
      return INIT_PARAMETERS_INCORRECT;
   }
   endpoint = ServerURL + "/api/ea/update";
   Log("ARM Platform Tracker v2 iniciado ✓");
   Log("Conectando a: " + endpoint);
   SendAccountData();
   return INIT_SUCCEEDED;
}

void OnTick()
{
   datetime now = TimeCurrent();
   if(now - lastSent >= UpdateMin * 60)
   {
      SendAccountData();
      lastSent = now;
   }
   if(SendOnTrade)
   {
      int cur = HistoryDealsTotal();
      if(cur != lastHistory)
      {
         Sleep(500);
         SendAccountData();
         lastHistory = cur;
      }
   }
}

void SendAccountData()
{
   string json = BuildJSON();
   if(json == "") return;

   string headers  = "Content-Type: application/json\r\nX-Api-Key: " + ApiKey + "\r\n";
   char   post[];
   char   result[];
   string resultHeaders;

   StringToCharArray(json, post, 0, StringLen(json));

   int res = WebRequest("POST", endpoint, headers, 15000, post, result, resultHeaders);

   if(res == -1)
   {
      int err = GetLastError();
      Log("❌ Error " + IntegerToString(err) + " — Verificá la URL en Herramientas > Opciones > Asesores Expertos");
   }
   else if(res == 200 || res == 201)
   {
      Log("✓ Datos enviados correctamente");
   }
   else
   {
      Log("⚠️ Respuesta HTTP: " + IntegerToString(res) + " — " + CharArrayToString(result));
   }
}

string BuildJSON()
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin     = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double profit     = AccountInfoDouble(ACCOUNT_PROFIT);
   double drawdown   = balance > 0 ? (balance - equity) / balance * 100 : 0;
   long   accountNum = AccountInfoInteger(ACCOUNT_LOGIN);
   string broker     = AccountInfoString(ACCOUNT_COMPANY);
   string currency   = AccountInfoString(ACCOUNT_CURRENCY);
   double leverage   = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);

   // Trades abiertos
   string openTrades = "";
   int totalOpen = PositionsTotal();
   for(int i = 0; i < totalOpen; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string symbol    = PositionGetString(POSITION_SYMBOL);
      double lots      = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curPrice  = PositionGetDouble(POSITION_PRICE_CURRENT);
      double posProfit = PositionGetDouble(POSITION_PROFIT);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      long   posType   = PositionGetInteger(POSITION_TYPE);
      datetime openTime= (datetime)PositionGetInteger(POSITION_TIME);
      string direction = posType == POSITION_TYPE_BUY ? "BUY" : "SELL";
      double swap      = PositionGetDouble(POSITION_SWAP);

      if(openTrades != "") openTrades += ",";
      openTrades += "{";
      openTrades += "\"ticket\":"     + IntegerToString(ticket)      + ",";
      openTrades += "\"symbol\":\""   + symbol                       + "\",";
      openTrades += "\"type\":\""     + direction                    + "\",";
      openTrades += "\"lots\":"       + DoubleToString(lots, 2)      + ",";
      openTrades += "\"openPrice\":"  + DoubleToString(openPrice, 5) + ",";
      openTrades += "\"curPrice\":"   + DoubleToString(curPrice, 5)  + ",";
      openTrades += "\"profit\":"     + DoubleToString(posProfit, 2) + ",";
      openTrades += "\"sl\":"         + DoubleToString(sl, 5)        + ",";
      openTrades += "\"tp\":"         + DoubleToString(tp, 5)        + ",";
      openTrades += "\"swap\":"       + DoubleToString(swap, 2)      + ",";
      openTrades += "\"openTime\":\"" + TimeToString(openTime)       + "\"";
      openTrades += "}";
   }

   // Historial completo
   HistorySelect(0, TimeCurrent());
   string closedTrades = "";
   int dealsTotal = HistoryDealsTotal();
   int count = 0;
   for(int i = dealsTotal - 1; i >= 0 && count < 5000; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      long dealType  = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
      long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT) continue;

      string symbol     = HistoryDealGetString(ticket, DEAL_SYMBOL);
      double dealProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double dealSwap   = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double dealComm   = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double netProfit  = dealProfit + dealSwap + dealComm;
      double lots       = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double price      = HistoryDealGetDouble(ticket, DEAL_PRICE);
      datetime closeTime= (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      string direction  = dealType == DEAL_TYPE_BUY ? "BUY" : "SELL";

      if(closedTrades != "") closedTrades += ",";
      closedTrades += "{";
      closedTrades += "\"ticket\":"       + IntegerToString(ticket)         + ",";
      closedTrades += "\"symbol\":\""     + symbol                          + "\",";
      closedTrades += "\"type\":\""       + direction                       + "\",";
      closedTrades += "\"lots\":"         + DoubleToString(lots, 2)         + ",";
      closedTrades += "\"closePrice\":"   + DoubleToString(price, 5)        + ",";
      closedTrades += "\"profit\":"       + DoubleToString(dealProfit, 2)   + ",";
      closedTrades += "\"swap\":"         + DoubleToString(dealSwap, 2)     + ",";
      closedTrades += "\"commission\":"   + DoubleToString(dealComm, 2)     + ",";
      closedTrades += "\"netProfit\":"    + DoubleToString(netProfit, 2)    + ",";
      closedTrades += "\"closeTime\":\"" + TimeToString(closeTime)          + "\"";
      closedTrades += "}";
      count++;
   }

   string json = "{";
   json += "\"account\":{";
   json += "\"number\":"     + IntegerToString(accountNum)   + ",";
   json += "\"broker\":\""   + broker                        + "\",";
   json += "\"currency\":\"" + currency                      + "\",";
   json += "\"leverage\":"   + DoubleToString(leverage, 0)   + ",";
   json += "\"balance\":"    + DoubleToString(balance, 2)    + ",";
   json += "\"equity\":"     + DoubleToString(equity, 2)     + ",";
   json += "\"margin\":"     + DoubleToString(margin, 2)     + ",";
   json += "\"freeMargin\":" + DoubleToString(freeMargin, 2) + ",";
   json += "\"floatingPL\":" + DoubleToString(profit, 2)     + ",";
   json += "\"drawdown\":"   + DoubleToString(drawdown, 4);
   json += "},";
   json += "\"openTrades\":["   + openTrades   + "],";
   json += "\"closedTrades\":["  + closedTrades + "]";
   json += "}";

   return json;
}

void Log(string msg) { if(EnableLogs) Print("[ARM Platform] " + msg); }
void OnDeinit(const int reason) { Log("EA detenido. Razón: " + IntegerToString(reason)); }
