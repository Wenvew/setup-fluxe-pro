# Setup Fluxe Pro — Painel de Setup via Terminal

Painel interativo em **Bash** para preparar uma VPS do zero com **Docker**, **Swarm**, **Traefik v3** (ACME DNS-01 via **Cloudflare**) e **Portainer**.
Feito para uso repetível, modular e seguro (solicita segredos no terminal).

## Requisitos
- Distribuição testada: Ubuntu 22.04/24.04 (root).
- Domínio gerenciado pela Cloudflare (ACME DNS-01).
- Acesso root ao servidor via SSH.

## Instalação rápida
```bash
# copie o projeto para a VPS (ex.: usando scp) ou baixe o zip e extraia
cd /root
unzip setup-fluxe-pro.zip -d setup-fluxe-pro
cd setup-fluxe-pro

# dê permissão de execução
chmod +x setup.sh modules/*.sh

# execute
./setup.sh
```

## Estrutura
```
setup-fluxe-pro/
├─ setup.sh                # menu principal
├─ .env                    # variáveis persistentes (opcional; gera no 1º uso)
├─ lib/
│  └─ common.sh            # funções utilitárias
├─ modules/
│  ├─ 01-system-update.sh  # atualiza VPS e configura DNS do host
│  ├─ 02-install-traefik.sh# instala Traefik v3 + Swarm + Cloudflare DNS-01
│  └─ 03-install-portainer.sh # instala Portainer roteado pelo Traefik
└─ templates/
   └─ traefik-stack.yml.tpl # template do stack (preenchido pelo módulo)
```

## Logs
Todos os comandos são registrados em `/var/log/setup-fluxe-pro.log`.

## Dicas de uso
- Rode primeiro **01 - Atualizar VPS** em uma máquina nova.
- Depois **02 - Instalar Traefik**. Ele pedirá domínio, subdomínio do dashboard e token da Cloudflare.
- Por fim, **03 - Portainer**, se desejar.

> O painel tenta ser idempotente (repete ações sem quebrar). Ainda assim, sempre mantenha **backups**.
