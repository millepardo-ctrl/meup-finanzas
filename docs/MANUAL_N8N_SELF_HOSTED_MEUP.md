# Manual de Instalación · n8n Self-Hosted para MeUp
**Servidor: Hetzner Cloud · Dominio: meup.co · Subdominio: n8n.meup.co**
Tiempo estimado: 2–3 horas · Costo resultante: ~€4/mes

---

## Visión general de lo que vas a hacer

1. Crear un servidor en Hetzner (5 min)
2. Apuntar el subdominio `n8n.meup.co` al servidor (5 min)
3. Conectarte al servidor y prepararlo (15 min)
4. Instalar Docker y n8n con Docker Compose (20 min)
5. Activar HTTPS automático con Caddy (10 min)
6. Migrar tus flujos desde n8n Cloud (30 min)
7. Reconectar Telegram y verificar todo (20 min)

Al terminar tendrás n8n corriendo en `https://n8n.meup.co` con ejecuciones ilimitadas.

---

## PASO 1 — Crear el servidor en Hetzner

**1.1** Ve a [hetzner.com/cloud](https://www.hetzner.com/cloud) y crea una cuenta. Necesitarás tarjeta de crédito o PayPal.

**1.2** Una vez dentro, clic en **"Add Server"** y configura:
- **Location:** Falkenstein (EU) o cualquiera — elige el más cercano a Colombia disponible (Helsinki o Ashburn si aparece)
- **Image:** Ubuntu 24.04
- **Type:** CX22 (2 vCPU, 4 GB RAM) — €3.79/mes. No necesitas más para este sistema.
- **Networking:** IPv4 activado (por defecto)
- **SSH keys:** clic en "Add SSH key". Si nunca has creado una, ve al paso 1.3 primero.
- **Name:** `meup-n8n`
- Clic en **"Create & Buy Now"**

**1.3** Crear tu llave SSH (si no tienes una):
Abre la terminal de tu computador (Mac: busca "Terminal"; Windows: busca "PowerShell") y escribe:
```bash
ssh-keygen -t ed25519 -C "meup-n8n"
```
Presiona Enter tres veces (sin contraseña para simplificar). Esto crea dos archivos. Para ver la llave pública que pegas en Hetzner:
```bash
cat ~/.ssh/id_ed25519.pub
```
Copia todo ese texto (empieza con `ssh-ed25519`) y pégalo en el campo de Hetzner.

**1.4** Anota la IP del servidor — aparece en el panel de Hetzner después de crearlo. La necesitas en el paso 2. Se ve así: `65.108.xxx.xxx`

---

## PASO 2 — Apuntar el subdominio al servidor

Entra al panel donde administras el DNS de `meup.co` (puede ser GoDaddy, Namecheap, Cloudflare, o quien te vendió el dominio).

Busca la sección **DNS** o **Zone Editor** y agrega un registro nuevo:
- **Tipo:** A
- **Nombre:** `n8n` (esto crea `n8n.meup.co`)
- **Valor:** la IP del servidor de Hetzner
- **TTL:** 300 (o el mínimo que permita)

Guarda. Los cambios de DNS pueden tardar entre 5 minutos y 2 horas en propagarse. Para verificar que ya propagó, escribe esto en tu terminal:
```bash
nslookup n8n.meup.co
```
Cuando la respuesta muestre la IP de tu servidor, continúa al paso 3.

---

## PASO 3 — Conectarte al servidor

En tu terminal local escribe (reemplaza con la IP real de tu servidor):
```bash
ssh root@65.108.xxx.xxx
```
La primera vez preguntará "Are you sure you want to continue connecting?" — escribe `yes` y Enter.

Ya estás dentro del servidor. Verás algo como `root@meup-n8n:~#`

Primero actualiza el sistema:
```bash
apt update && apt upgrade -y
```
Espera que termine (1–2 minutos). Si pregunta algo sobre configuración de servicios, presiona Enter para mantener la versión instalada.

---

## PASO 4 — Instalar Docker

Docker es el sistema que corre n8n en un contenedor aislado. Instálalo con estos comandos, uno por uno:

```bash
curl -fsSL https://get.docker.com | sh
```

Verifica que quedó instalado:
```bash
docker --version
```
Debe mostrar algo como `Docker version 26.x.x`

---

## PASO 5 — Crear la estructura de archivos de n8n

Crea la carpeta de trabajo:
```bash
mkdir -p /opt/meup-n8n && cd /opt/meup-n8n
```

Crea el archivo de variables de entorno. Este archivo guarda tus configuraciones privadas:
```bash
nano .env
```

Se abre el editor. Escribe exactamente esto (reemplaza los valores entre < >):

```
# Dominio
DOMAIN_NAME=n8n.meup.co
SUBDOMAIN=n8n

# Usuario administrador de n8n
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=<inventa una contraseña segura, ej: MeUp2026$Finanzas>

# Zona horaria
GENERIC_TIMEZONE=America/Bogota
TZ=America/Bogota

# Seguridad interna (genera una clave aleatoria larga — puedes usar la de abajo como base)
N8N_ENCRYPTION_KEY=<cadena aleatoria de 32+ caracteres, ej: mEup2024K3y$FinAnZ4s!xYz9>

# Email para el certificado HTTPS
SSL_EMAIL=<tu email, ej: milena@meup.co>
```

Para guardar en nano: `Ctrl + O` → Enter → `Ctrl + X`

---

## PASO 6 — Crear el archivo Docker Compose

Este archivo define cómo corren n8n y Caddy (el servidor web con HTTPS automático):

```bash
nano docker-compose.yml
```

Pega exactamente esto:

```yaml
version: "3.8"

services:
  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - caddy_data:/data
      - caddy_config:/config
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
    depends_on:
      - n8n
    networks:
      - meup_net

  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    environment:
      - N8N_HOST=${DOMAIN_NAME}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN_NAME}/
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - TZ=${TZ}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=168
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - meup_net

volumes:
  caddy_data:
  caddy_config:
  n8n_data:

networks:
  meup_net:
    driver: bridge
```

Guarda: `Ctrl + O` → Enter → `Ctrl + X`

---

## PASO 7 — Crear el archivo Caddyfile (HTTPS automático)

```bash
nano Caddyfile
```

Pega esto (reemplaza el email con el tuyo):

```
n8n.meup.co {
    reverse_proxy n8n:5678 {
        flush_interval -1
    }
    tls tu@email.com
}
```

Reemplaza `tu@email.com` con tu correo real. Guarda con `Ctrl + O` → Enter → `Ctrl + X`

---

## PASO 8 — Arrancar n8n

```bash
cd /opt/meup-n8n
docker compose up -d
```

Esto descarga las imágenes (puede tardar 2–3 minutos la primera vez) y arranca los contenedores. Para ver que todo corrió bien:

```bash
docker compose ps
```

Deben aparecer dos servicios con estado `running` o `Up`:
```
NAME      STATUS
caddy     Up
n8n       Up
```

Para ver los logs en tiempo real (útil si algo falla):
```bash
docker compose logs -f n8n
```
Presiona `Ctrl + C` para salir del log sin detener nada.

**Verificación:** abre el navegador y ve a `https://n8n.meup.co`. Debe aparecer la pantalla de login de n8n. Si el navegador dice que el certificado no es válido, espera 2 minutos más — Caddy lo genera automáticamente la primera vez.

Entra con el usuario y contraseña que pusiste en el `.env`.

---

## PASO 9 — Migrar tus flujos desde n8n Cloud

**9.1 Exportar desde n8n Cloud**

En tu n8n Cloud actual:
- Ve a cada workflow → menú de tres puntos → **Download** → guarda el JSON
- Necesitas los 11 flujos: WF-01 v4, WF-02, WF-03, WF-04, WF-05, WF-06, WF-07 v2, WF-08, WF-09, WF-10, WF-11

Alternativamente usa los JSON que ya tienes descargados de esta conversación — esos son la versión más reciente y corregida.

**9.2 Exportar las credenciales**

Las credenciales (Google, Telegram, Anthropic) NO se exportan con los flujos por seguridad. Tendrás que volver a crearlas en el n8n nuevo. Guarda a mano:
- Token del bot de Telegram
- API key de Anthropic
- Client ID y Client Secret de Google (desde Google Cloud Console)

**9.3 Importar en el n8n nuevo**

En tu n8n nuevo (`https://n8n.meup.co`):
1. Crea las credenciales primero (menú izquierdo → Credentials → Add)
2. Luego importa los workflows: menú → Workflows → Import from file
3. Abre cada workflow importado y reasigna las credenciales en los nodos rojos
4. Recuerda: importa WF-07 antes que WF-01, copia el ID de WF-07 y pégalo en el nodo "Enviar a WF-07" de WF-01

**9.4 Reconectar Telegram**

Los webhooks de Telegram deben apuntar a tu nueva URL. En Telegram, el webhook se configura automáticamente cuando activas el Telegram Trigger en n8n — pero primero debes registrarlo. Activa WF-01 v4 y envía un mensaje al grupo de prueba. Si llega en Executions, el webhook está activo.

Si no llega, forzarlo manualmente (reemplaza TOKEN con el token de tu bot):
```bash
curl "https://api.telegram.org/botTOKEN/setWebhook?url=https://n8n.meup.co/webhook/meup-finanzas-data"
```

---

## PASO 10 — Configurar respaldos automáticos

Los datos de n8n (flujos, credenciales, historial) viven en el volumen `n8n_data`. Crea un respaldo diario automático:

```bash
nano /opt/meup-n8n/backup.sh
```

Pega esto:
```bash
#!/bin/bash
DATE=$(date +%Y-%m-%d)
BACKUP_DIR="/opt/backups/n8n"
mkdir -p $BACKUP_DIR
docker run --rm \
  -v meup-n8n_n8n_data:/data \
  -v $BACKUP_DIR:/backup \
  alpine tar czf /backup/n8n-$DATE.tar.gz /data
# Mantener solo los últimos 14 días
find $BACKUP_DIR -name "*.tar.gz" -mtime +14 -delete
echo "Backup completado: n8n-$DATE.tar.gz"
```

Guarda y dale permisos:
```bash
chmod +x /opt/meup-n8n/backup.sh
```

Programa que corra cada día a las 2am:
```bash
crontab -e
```
Agrega esta línea al final:
```
0 2 * * * /opt/meup-n8n/backup.sh >> /var/log/n8n-backup.log 2>&1
```
Guarda y sal.

---

## PASO 11 — Mantenimiento rutinario

**Actualizar n8n** (cada 1–2 meses, cuando quieras):
```bash
cd /opt/meup-n8n
docker compose pull
docker compose up -d
```
Esto descarga la versión más nueva y reinicia sin perder datos.

**Ver consumo de recursos:**
```bash
docker stats
```
Presiona `Ctrl + C` para salir.

**Reiniciar n8n si algo falla:**
```bash
cd /opt/meup-n8n
docker compose restart n8n
```

**Ver logs del último día:**
```bash
docker compose logs --since 24h n8n
```

**Apagar todo (solo si necesitas):**
```bash
docker compose down
```
Para volver a arrancar: `docker compose up -d`

---

## Resumen de costos finales

| Concepto | Costo |
|---|---|
| Servidor Hetzner CX22 | €3.79/mes |
| Dominio meup.co (ya lo tienes) | $0 adicional |
| n8n self-hosted | Gratis, ilimitado |
| **Total mensual** | **≈ €4/mes** |
| **Ahorro vs n8n Cloud (plan necesario)** | **€46/mes = €552/año** |

---

## Solución de problemas comunes

**"No puedo conectarme por SSH"**
→ Verifica que la IP del servidor en Hetzner es correcta. Espera 1 minuto después de crear el servidor.

**"El certificado HTTPS no carga"**
→ Verifica que el DNS propagó: `nslookup n8n.meup.co` debe mostrar la IP del servidor. Caddy necesita que el dominio resuelva antes de emitir el certificado.

**"n8n arrancó pero los webhooks de Telegram no llegan"**
→ En n8n Cloud el webhook era una URL diferente. Activa el flujo en el n8n nuevo — al activarse, n8n registra automáticamente el webhook con Telegram. Si no, usa el comando curl del paso 9.4.

**"Olvidé la contraseña de n8n"**
→ Edita el archivo `.env` en `/opt/meup-n8n`, cambia `N8N_BASIC_AUTH_PASSWORD`, y reinicia: `docker compose restart n8n`

**"El servidor se quedó sin espacio"**
→ Limpiar imágenes Docker viejas: `docker system prune -a` (no borra los volúmenes con tus datos)
