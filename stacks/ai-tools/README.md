# AI Tools stack

Local AI stack:

- `ollama` (local model runtime)
- `open-webui` (chat web UI)

## Prerequisites

- Core stack running (Traefik + `homelab` network)
- `DOMAIN` set in `stacks/env`

## Deploy

```bash
cd ansible
ansible-playbook -i inventory.ini deploy-stacks.yml \
  --limit homelab-1 \
  -e '{"stacks_to_deploy":["ai-tools"]}'
```

## Pull a small CPU model

```bash
docker exec -it ollama ollama pull qwen2.5:1.5b
```

Other lightweight options:
- `llama3.2:1b`
- `phi3:mini`
