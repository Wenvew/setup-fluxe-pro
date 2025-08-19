services:
  agent:
    image: portainer/agent:2.21.4
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks: [ ${NETWORK_NAME} ]
    deploy:
      mode: global
      placement:
        constraints: [ node.platform.os == linux ]

  portainer:
    image: portainer/portainer-ce:2.21.4
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data:/data
    networks: [ ${NETWORK_NAME} ]
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [ node.role == manager ]
      labels:
        - "traefik.enable=true"
        - "traefik.docker.network=${NETWORK_NAME}"
        - "traefik.http.routers.portainer.rule=Host(`${PORTAINER_HOST}`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"

networks:
  ${NETWORK_NAME}:
    external: true

volumes:
  portainer_data:
