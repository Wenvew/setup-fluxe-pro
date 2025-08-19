services:
  traefik:
    image: traefik:3.0.4
    command:
      - "--providers.swarm=true"
      - "--providers.swarm.exposedbydefault=false"
      - "--providers.swarm.network=${NETWORK_NAME}"

      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"

      - "--certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge.delaybeforecheck=0"

      - "--api.dashboard=true"
      - "--api.insecure=false"
      - "--log.level=INFO"

      - "--accesslog=true"
      - "--accesslog.format=json"
      - "--accesslog.filepath=/logs/access.log"
      - "--accesslog.fields.headers.defaultmode=drop"
      - "--accesslog.fields.headers.names.User-Agent=keep"
      - "--accesslog.fields.headers.names.X-Forwarded-For=keep"
      - "--accesslog.fields.headers.names.Authorization=redact"

    ports:
      - "80:80"
      - "443:443"

    networks: [ ${NETWORK_NAME} ]

    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "/srv/infra/traefik/acme:/letsencrypt"
      - "/srv/infra/traefik/logs:/logs"

    secrets:
      - cf_token_v2
    environment:
      - CF_DNS_API_TOKEN_FILE=/run/secrets/cf_token_v2

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [ "node.role == manager" ]
      labels:
        - "traefik.enable=true"
        - "traefik.http.services.traefik.loadbalancer.server.port=80"

        - "traefik.http.routers.traefik.rule=Host(`${TRAEFIK_HOST}`)"
        - "traefik.http.routers.traefik.entrypoints=websecure"
        - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
        - "traefik.http.routers.traefik.service=api@internal"

        - "traefik.http.middlewares.dashboard-auth.basicauth.usersfile=/usersfile"
        - "traefik.http.routers.traefik.middlewares=dashboard-auth@swarm"

    configs:
      - source: traefik_usersfile
        target: /usersfile
        mode: 0400

networks:
  ${NETWORK_NAME}:
    external: true

secrets:
  cf_token_v2:
    external: true

configs:
  traefik_usersfile:
    file: /srv/infra/traefik/usersfile
