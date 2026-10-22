import os
import httpx
import yfinance as yf
from datetime import datetime, timedelta

ALPHA_VANTAGE_KEY = os.getenv("ALPHA_VANTAGE_API_KEY", "")
FINNHUB_KEY = os.getenv("FINNHUB_API_KEY", "")


async def get_stock_data(symbol: str) -> str | None:
    """Fetch stock data using yfinance (no API key required)."""
    try:
        ticker = yf.Ticker(symbol)
        info = ticker.info
        
        if not info or "regularMarketPrice" not in info:
            return None
        
        current_price = info.get("regularMarketPrice", "N/A")
        prev_close = info.get("previousClose", "N/A")
        open_price = info.get("open", "N/A")
        day_high = info.get("dayHigh", "N/A")
        day_low = info.get("dayLow", "N/A")
        volume = info.get("volume", "N/A")
        market_cap = info.get("marketCap", "N/A")
        pe_ratio = info.get("trailingPE", "N/A")
        week_52_high = info.get("fiftyTwoWeekHigh", "N/A")
        week_52_low = info.get("fiftyTwoWeekLow", "N/A")
        name = info.get("shortName", symbol)
        
        if isinstance(volume, (int, float)):
            volume = f"{volume:,.0f}"
        if isinstance(market_cap, (int, float)):
            market_cap = f"${market_cap/1e9:.2f}B" if market_cap > 1e9 else f"${market_cap/1e6:.2f}M"
        
        change = ""
        if isinstance(current_price, (int, float)) and isinstance(prev_close, (int, float)):
            diff = current_price - prev_close
            pct = (diff / prev_close) * 100
            direction = "+" if diff >= 0 else ""
            change = f"{direction}{diff:.2f} ({direction}{pct:.2f}%)"
        
        hist = ticker.history(period="5d")
        recent_trend = ""
        if not hist.empty and len(hist) >= 2:
            closes = hist["Close"].tolist()
            if closes[-1] > closes[0]:
                recent_trend = "Trending UP over last 5 days"
            else:
                recent_trend = "Trending DOWN over last 5 days"
        
        return f"""**{name} ({symbol})**
- Current Price: ${current_price}
- Change: {change}
- Open: ${open_price} | High: ${day_high} | Low: ${day_low}
- Previous Close: ${prev_close}
- Volume: {volume}
- Market Cap: {market_cap}
- P/E Ratio: {pe_ratio}
- 52-Week Range: ${week_52_low} - ${week_52_high}
- {recent_trend}"""
    
    except Exception as e:
        print(f"Error fetching {symbol}: {e}")
        return None


async def get_market_news(symbol: str) -> str | None:
    """Fetch recent news for a symbol using Finnhub (if API key provided)."""
    if not FINNHUB_KEY:
        return None
    
    try:
        today = datetime.now()
        week_ago = today - timedelta(days=7)
        
        url = "https://finnhub.io/api/v1/company-news"
        params = {
            "symbol": symbol,
            "from": week_ago.strftime("%Y-%m-%d"),
            "to": today.strftime("%Y-%m-%d"),
            "token": FINNHUB_KEY,
        }
        
        async with httpx.AsyncClient() as client:
            resp = await client.get(url, params=params, timeout=10)
            if resp.status_code != 200:
                return None
            
            articles = resp.json()[:5]
            if not articles:
                return None
            
            news_text = ""
            for article in articles:
                headline = article.get("headline", "")
                summary = article.get("summary", "")[:200]
                date = datetime.fromtimestamp(article.get("datetime", 0)).strftime("%Y-%m-%d")
                news_text += f"\n- **{date}**: {headline}\n  {summary}...\n"
            
            return news_text
    
    except Exception as e:
        print(f"Error fetching news for {symbol}: {e}")
        return None


async def get_market_overview() -> str:
    """Get overview of major indices."""
    indices = ["^GSPC", "^DJI", "^IXIC", "^VIX"]
    names = {"^GSPC": "S&P 500", "^DJI": "Dow Jones", "^IXIC": "NASDAQ", "^VIX": "VIX"}
    
    overview = "## Market Overview\n"
    for idx in indices:
        try:
            ticker = yf.Ticker(idx)
            info = ticker.info
            price = info.get("regularMarketPrice", "N/A")
            prev = info.get("previousClose", 0)
            if isinstance(price, (int, float)) and prev:
                change = ((price - prev) / prev) * 100
                direction = "+" if change >= 0 else ""
                overview += f"- **{names.get(idx, idx)}**: {price:.2f} ({direction}{change:.2f}%)\n"
        except:
            continue
    
    return overview
