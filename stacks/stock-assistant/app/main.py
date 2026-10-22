import os
from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from .stock_data import get_stock_data, get_market_news
from .llm import query_ollama

app = FastAPI(title="Stock Assistant")
templates = Jinja2Templates(directory="app/templates")


@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/analyze", response_class=HTMLResponse)
async def analyze(request: Request, query: str = Form(...), symbols: str = Form("")):
    """Analyze stocks based on user query."""
    symbol_list = [s.strip().upper() for s in symbols.split(",") if s.strip()]
    
    stock_context = ""
    news_context = ""
    
    if symbol_list:
        for symbol in symbol_list[:5]:
            data = await get_stock_data(symbol)
            if data:
                stock_context += f"\n\n## {symbol} Stock Data\n{data}"
        
        news = await get_market_news(symbol_list[0])
        if news:
            news_context = f"\n\n## Recent News for {symbol_list[0]}\n{news}"
    
    prompt = build_prompt(query, stock_context, news_context)
    response = await query_ollama(prompt)
    
    return templates.TemplateResponse("result.html", {
        "request": request,
        "query": query,
        "symbols": symbols,
        "response": response,
        "stock_data": stock_context,
    })


@app.get("/quote/{symbol}")
async def quote(symbol: str):
    """Get quick quote for a symbol."""
    data = await get_stock_data(symbol.upper())
    if not data:
        return {"error": f"Could not fetch data for {symbol}"}
    return {"symbol": symbol.upper(), "data": data}


def build_prompt(query: str, stock_data: str, news: str) -> str:
    """Build a prompt combining user query with market data."""
    system = """You are a helpful stock market assistant. You analyze market data and provide insights.
Always be clear about uncertainty. Do not give specific buy/sell recommendations.
Focus on explaining trends, fundamentals, and helping the user understand the data.
If asked about predictions, explain that past performance doesn't guarantee future results."""

    context = ""
    if stock_data:
        context += f"\n\nCurrent Market Data:{stock_data}"
    if news:
        context += f"\n\nRecent News:{news}"
    
    return f"""{system}
{context}

User Question: {query}

Please provide a helpful analysis based on the data above."""
