"""
title: Stock Market Data
author: bp31
author_url: https://github.com/pattersonbl2
version: 1.0.0
license: MIT
description: Get real-time stock prices, fundamentals, and market data using Yahoo Finance. No API key required.
requirements: yfinance
"""

import yfinance as yf
from datetime import datetime, timedelta
from typing import Optional


class Tools:
    def __init__(self):
        pass

    async def get_stock_quote(self, symbol: str) -> str:
        """
        Get current stock price and key metrics for a ticker symbol.
        
        :param symbol: Stock ticker symbol (e.g., AAPL, MSFT, GOOGL)
        :return: Current price, change, volume, and key fundamentals
        """
        try:
            ticker = yf.Ticker(symbol.upper())
            info = ticker.info
            
            if not info or "regularMarketPrice" not in info:
                return f"Could not find data for symbol: {symbol}"
            
            current_price = info.get("regularMarketPrice", "N/A")
            prev_close = info.get("previousClose", 0)
            open_price = info.get("open", "N/A")
            day_high = info.get("dayHigh", "N/A")
            day_low = info.get("dayLow", "N/A")
            volume = info.get("volume", "N/A")
            market_cap = info.get("marketCap", "N/A")
            pe_ratio = info.get("trailingPE", "N/A")
            week_52_high = info.get("fiftyTwoWeekHigh", "N/A")
            week_52_low = info.get("fiftyTwoWeekLow", "N/A")
            name = info.get("shortName", symbol.upper())
            
            if isinstance(volume, (int, float)):
                volume = f"{volume:,.0f}"
            
            if isinstance(market_cap, (int, float)):
                if market_cap > 1e12:
                    market_cap = f"${market_cap/1e12:.2f}T"
                elif market_cap > 1e9:
                    market_cap = f"${market_cap/1e9:.2f}B"
                else:
                    market_cap = f"${market_cap/1e6:.2f}M"
            
            change = ""
            if isinstance(current_price, (int, float)) and prev_close:
                diff = current_price - prev_close
                pct = (diff / prev_close) * 100
                direction = "+" if diff >= 0 else ""
                change = f"{direction}${diff:.2f} ({direction}{pct:.2f}%)"
            
            return f"""**{name} ({symbol.upper()})**
- Current Price: ${current_price}
- Change: {change}
- Open: ${open_price} | High: ${day_high} | Low: ${day_low}
- Previous Close: ${prev_close}
- Volume: {volume}
- Market Cap: {market_cap}
- P/E Ratio: {pe_ratio}
- 52-Week Range: ${week_52_low} - ${week_52_high}"""
        
        except Exception as e:
            return f"Error fetching data for {symbol}: {str(e)}"

    async def get_stock_history(self, symbol: str, period: str = "1mo") -> str:
        """
        Get historical price data and trend analysis for a stock.
        
        :param symbol: Stock ticker symbol (e.g., AAPL, MSFT)
        :param period: Time period - 1d, 5d, 1mo, 3mo, 6mo, 1y, 2y, 5y, ytd, max (default: 1mo)
        :return: Price trend summary with high, low, and performance
        """
        try:
            ticker = yf.Ticker(symbol.upper())
            hist = ticker.history(period=period)
            
            if hist.empty:
                return f"No historical data found for {symbol}"
            
            start_price = hist["Close"].iloc[0]
            end_price = hist["Close"].iloc[-1]
            high = hist["High"].max()
            low = hist["Low"].min()
            avg_volume = hist["Volume"].mean()
            
            change = end_price - start_price
            change_pct = (change / start_price) * 100
            direction = "+" if change >= 0 else ""
            trend = "UP" if change >= 0 else "DOWN"
            
            return f"""**{symbol.upper()} - {period} History**
- Period Start: ${start_price:.2f}
- Period End: ${end_price:.2f}
- Change: {direction}${change:.2f} ({direction}{change_pct:.2f}%)
- Period High: ${high:.2f}
- Period Low: ${low:.2f}
- Avg Daily Volume: {avg_volume:,.0f}
- Trend: {trend}"""
        
        except Exception as e:
            return f"Error fetching history for {symbol}: {str(e)}"

    async def compare_stocks(self, symbols: str) -> str:
        """
        Compare multiple stocks side by side.
        
        :param symbols: Comma-separated list of stock symbols (e.g., "AAPL,MSFT,GOOGL")
        :return: Comparison table of key metrics
        """
        symbol_list = [s.strip().upper() for s in symbols.split(",") if s.strip()]
        
        if not symbol_list:
            return "Please provide at least one stock symbol"
        
        if len(symbol_list) > 5:
            symbol_list = symbol_list[:5]
        
        results = []
        for symbol in symbol_list:
            try:
                ticker = yf.Ticker(symbol)
                info = ticker.info
                
                if not info or "regularMarketPrice" not in info:
                    results.append(f"**{symbol}**: Data not available")
                    continue
                
                price = info.get("regularMarketPrice", "N/A")
                prev_close = info.get("previousClose", 0)
                pe = info.get("trailingPE", "N/A")
                market_cap = info.get("marketCap", 0)
                
                if isinstance(market_cap, (int, float)) and market_cap > 0:
                    if market_cap > 1e12:
                        cap_str = f"${market_cap/1e12:.1f}T"
                    elif market_cap > 1e9:
                        cap_str = f"${market_cap/1e9:.1f}B"
                    else:
                        cap_str = f"${market_cap/1e6:.1f}M"
                else:
                    cap_str = "N/A"
                
                if isinstance(price, (int, float)) and prev_close:
                    pct = ((price - prev_close) / prev_close) * 100
                    direction = "+" if pct >= 0 else ""
                    change_str = f"{direction}{pct:.2f}%"
                else:
                    change_str = "N/A"
                
                pe_str = f"{pe:.1f}" if isinstance(pe, (int, float)) else "N/A"
                
                results.append(f"**{symbol}**: ${price} ({change_str}) | P/E: {pe_str} | Cap: {cap_str}")
            
            except Exception as e:
                results.append(f"**{symbol}**: Error - {str(e)}")
        
        return "**Stock Comparison**\n" + "\n".join(results)

    async def get_market_overview(self) -> str:
        """
        Get current market overview with major indices.
        
        :return: Current values and changes for S&P 500, Dow Jones, NASDAQ, and VIX
        """
        indices = {
            "^GSPC": "S&P 500",
            "^DJI": "Dow Jones",
            "^IXIC": "NASDAQ",
            "^VIX": "VIX (Volatility)"
        }
        
        results = ["**Market Overview**"]
        
        for symbol, name in indices.items():
            try:
                ticker = yf.Ticker(symbol)
                info = ticker.info
                
                price = info.get("regularMarketPrice", "N/A")
                prev_close = info.get("previousClose", 0)
                
                if isinstance(price, (int, float)) and prev_close:
                    change = ((price - prev_close) / prev_close) * 100
                    direction = "+" if change >= 0 else ""
                    results.append(f"**{name}**: {price:,.2f} ({direction}{change:.2f}%)")
                else:
                    results.append(f"**{name}**: {price}")
            
            except Exception:
                results.append(f"**{name}**: Data unavailable")
        
        return "\n".join(results)

    async def get_stock_financials(self, symbol: str) -> str:
        """
        Get key financial metrics and ratios for a stock.
        
        :param symbol: Stock ticker symbol (e.g., AAPL, MSFT)
        :return: Key financial ratios, margins, and growth metrics
        """
        try:
            ticker = yf.Ticker(symbol.upper())
            info = ticker.info
            
            if not info:
                return f"Could not find data for symbol: {symbol}"
            
            name = info.get("shortName", symbol.upper())
            
            pe = info.get("trailingPE", "N/A")
            forward_pe = info.get("forwardPE", "N/A")
            peg = info.get("pegRatio", "N/A")
            pb = info.get("priceToBook", "N/A")
            ps = info.get("priceToSalesTrailing12Months", "N/A")
            
            profit_margin = info.get("profitMargins", "N/A")
            operating_margin = info.get("operatingMargins", "N/A")
            roe = info.get("returnOnEquity", "N/A")
            roa = info.get("returnOnAssets", "N/A")
            
            revenue_growth = info.get("revenueGrowth", "N/A")
            earnings_growth = info.get("earningsGrowth", "N/A")
            
            dividend_yield = info.get("dividendYield", "N/A")
            payout_ratio = info.get("payoutRatio", "N/A")
            
            def fmt_pct(val):
                if isinstance(val, (int, float)):
                    return f"{val * 100:.2f}%"
                return "N/A"
            
            def fmt_ratio(val):
                if isinstance(val, (int, float)):
                    return f"{val:.2f}"
                return "N/A"
            
            return f"""**{name} ({symbol.upper()}) - Financials**

**Valuation**
- P/E (TTM): {fmt_ratio(pe)}
- Forward P/E: {fmt_ratio(forward_pe)}
- PEG Ratio: {fmt_ratio(peg)}
- Price/Book: {fmt_ratio(pb)}
- Price/Sales: {fmt_ratio(ps)}

**Profitability**
- Profit Margin: {fmt_pct(profit_margin)}
- Operating Margin: {fmt_pct(operating_margin)}
- Return on Equity: {fmt_pct(roe)}
- Return on Assets: {fmt_pct(roa)}

**Growth**
- Revenue Growth: {fmt_pct(revenue_growth)}
- Earnings Growth: {fmt_pct(earnings_growth)}

**Dividends**
- Dividend Yield: {fmt_pct(dividend_yield)}
- Payout Ratio: {fmt_pct(payout_ratio)}"""
        
        except Exception as e:
            return f"Error fetching financials for {symbol}: {str(e)}"
