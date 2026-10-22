# Stock Assistant

AI-powered stock analysis using Ollama and real-time market data.

## Features

- **Real-time stock data** via Yahoo Finance (no API key required)
- **AI analysis** using your local Ollama models
- **News integration** via Finnhub (optional, requires free API key)
- **Dark mode UI** with simple web interface

## Requirements

- Ollama running with a model pulled (e.g., `llama3.1:8b`)
- Docker network `homelab` exists
- Traefik for routing (optional, can use port mapping)

## Quick Start

1. Make sure Ollama has a model:
   ```bash
   docker exec -it ollama ollama pull llama3.1:8b
   ```

2. Add to your `stacks/env` file:
   ```bash
   STOCK_OLLAMA_MODEL=llama3.1:8b
   # Optional:
   FINNHUB_API_KEY=your_key_here
   ```

3. Deploy:
   ```bash
   cd /path/to/homelab
   ansible-playbook -i ansible/inventory.ini ansible/deploy-stacks.yml \
     -e '{"stacks_to_deploy": ["stock-assistant"]}'
   ```

4. Access at `https://stocks.${DOMAIN}` or via port 8000.

## Usage

1. Enter stock symbols (e.g., `AAPL, MSFT, GOOGL`)
2. Ask a question about the stocks
3. The assistant fetches current market data and uses your Ollama model to analyze

## Example Questions

- "How is AAPL performing compared to its 52-week high?"
- "Compare the P/E ratios of MSFT, GOOGL, and META"
- "What's the recent trend for NVDA?"
- "Summarize the current state of TSLA stock"

## Data Sources

- **Stock prices & fundamentals**: Yahoo Finance (via yfinance)
- **News**: Finnhub (requires free API key)

## API Endpoints

- `GET /` - Web UI
- `POST /analyze` - Analyze stocks (form: query, symbols)
- `GET /quote/{symbol}` - Quick quote for a symbol
- `GET /health` - Health check

## Notes

- The LLM does not have real-time knowledge; all current data is fetched and injected into the prompt
- Analysis quality depends on your Ollama model
- This is for informational purposes only, not financial advice
