# IA Challenge — Asistente RAG con n8n, Python y Ollama

![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)
![Ollama](https://img.shields.io/badge/Ollama-LLM-black)
![n8n](https://img.shields.io/badge/n8n-Automation-EA4B71)

Plataforma de automatización conversacional que combina **n8n** (orquestación), un **agente Python con RAG** (FastAPI + ChromaDB) y **Ollama** (LLM local). Permite chatear con un asistente ("Jeferson") que responde usando documentos PDF indexados y conocimiento general del modelo `llama3.1:8b-instruct-q4_K_M`.

**Valor:** stack 100 % local, sin APIs externas de pago, desplegable en minutos con un solo comando Docker Compose.

---

## Requisitos previos

| Requisito | Versión mínima recomendada | Notas |
|-----------|---------------------------|-------|
| [Docker](https://docs.docker.com/get-docker/) | 24+ | Con soporte Compose v2 |
| [Docker Compose](https://docs.docker.com/compose/) | v2+ | Incluido en Docker Desktop |
| [Git](https://git-scm.com/) | 2.x | Para clonar el repositorio |
| RAM | 8 GB+ | El modelo Ollama ocupa ~4–5 GB |
| Disco libre | ~10 GB | Modelo + imágenes Docker + índice ChromaDB |

> **Windows/macOS:** instala [Docker Desktop](https://www.docker.com/products/docker-desktop/) y asegúrate de que el daemon esté en ejecución antes de continuar.

---

## Instalación

### 1. Clonar el repositorio

```bash
git clone https://github.com/Jefer1026/ia-challenge.git
cd ia-challenge
```

### 2. Variables de entorno

**No se requiere archivo `.env`.** Toda la configuración está definida en `docker-compose.yml`:

| Servicio | Variables relevantes |
|----------|---------------------|
| **n8n** | `N8N_HOST`, `N8N_PORT`, `N8N_PROTOCOL`, `WEBHOOK_URL`, `N8N_DEFAULT_FLOWS_PATH` |
| **ollama** | `OLLAMA_HOST=0.0.0.0` |
| **python-agent** | Sin variables externas; conecta a Ollama vía `http://ollama:11434` |

Si necesitas personalizar puertos o URLs, edita directamente `docker-compose.yml`.

### 3. Estructura del proyecto

```
ia-challenge/
├── agent/                  # Agente Python (FastAPI + RAG)
│   ├── agent.py
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── documents/          # PDFs indexados al arrancar (ej. lumina_store.pdf)
│   └── chroma_db/          # Índice vectorial persistente
├── n8n/
│   ├── init-ollama.sh      # Arranque de Ollama + descarga del modelo
│   └── ollama_data/        # Modelos Ollama (persistente, en .gitignore)
├── workflows/
│   └── challenge.json      # Workflow n8n (Chat → HTTP → python-agent)
├── .n8n/n8n_data/          # Base de datos y datos de n8n (persistente)
└── docker-compose.yml
```

---

## Puesta en marcha

Desde la raíz del proyecto:

```bash
docker compose up -d --build
```

| Servicio | Puerto host | URL / endpoint |
|----------|-------------|----------------|
| n8n | `5678` | http://localhost:5678 |
| python-agent | `8000` | http://localhost:8000 |
| ollama | `11434` | http://localhost:11434 |

Verifica que los tres contenedores estén activos:

```bash
docker compose ps
```

---

## ⚠️ Inicialización de n8n (importante)

En el **primer acceso** a http://localhost:5678, n8n solicitará crear una **cuenta de propietario (owner)**. Este paso **inicializa la base de datos SQLite** en `.n8n/n8n_data/` (`database.sqlite`).

- **No elimines** la carpeta `.n8n/n8n_data/` una vez configurada: perderás credenciales, workflows y claves de cifrado.
- Si el contenedor se reinicia antes de completar el registro, espera a que n8n termine de escribir la BD antes de volver a acceder.
- Tras el registro, **importa y activa** el workflow `workflows/challenge.json`:
  1. En n8n: **Workflows → Import from File** (o arrastra el JSON).
  2. Abre el workflow **challenge** y pulsa **Activate** (viene con `"active": false`).

> La primera ejecución de **Ollama** puede tardar varios minutos mientras descarga `llama3.1:8b-instruct-q4_K_M`. Revisa los logs: `docker compose logs -f ollama`.

---

## Guía de uso básico

### n8n (interfaz de chat)

1. Accede a http://localhost:5678 e inicia sesión.
2. Importa y activa `workflows/challenge.json`.
3. Abre el workflow **challenge** y usa el nodo **Chat Trigger** para probar mensajes.
4. El flujo envía cada mensaje a `POST http://python-agent:8000/chat` con el cuerpo `{ "message": "<texto>" }`.

### Agente Python (API directa)

**Chat:**

```bash
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "¿Cuáles son las políticas de la tienda Lumina?"}'
```

Respuesta esperada:

```json
{ "response": "..." }
```

**Subir un PDF adicional:**

```bash
curl -X POST http://localhost:8000/upload \
  -F "file=@./agent/documents/mi_documento.pdf"
```

Al arrancar, el agente escanea automáticamente `agent/documents/*.pdf` y los indexa en ChromaDB.

**Documentación interactiva:** http://localhost:8000/docs

### Ollama

```bash
# Listar modelos instalados
curl http://localhost:11434/api/tags

# Ver logs de descarga / arranque
docker compose logs -f ollama
```

El script `n8n/init-ollama.sh` inicia `ollama serve` y descarga el modelo si no existe localmente.

---

## Arquitectura

Todos los servicios comparten la red Docker **`ai-network`** (driver `bridge`).

```mermaid
flowchart LR
    User([Usuario]) -->|Chat UI| n8n[n8n :5678]
    n8n -->|POST /chat| Agent[python-agent :8000]
    Agent -->|RAG query| Chroma[(ChromaDB)]
    Agent -->|chat API| Ollama[ollama :11434]
    Chroma -.->|PDFs| Docs[agent/documents/]
```

| Componente | Rol |
|------------|-----|
| **n8n** | Recibe mensajes del chat y los reenvía al agente vía HTTP Request |
| **python-agent** | FastAPI: indexa PDFs, recupera contexto (RAG) y genera respuestas con historial |
| **Ollama** | Servidor LLM local con `llama3.1:8b-instruct-q4_K_M` |
| **ChromaDB** | Almacén vectorial persistente en `agent/chroma_db/` |

Flujo de una pregunta:

1. Usuario escribe en el chat de n8n.
2. n8n llama a `http://python-agent:8000/chat`.
3. Si el mensaje tiene ≥ 20 caracteres, el agente busca contexto relevante en ChromaDB.
4. El agente envía el prompt (con contexto opcional) a Ollama.
5. La respuesta JSON vuelve a n8n y se muestra al usuario.

---

## Solución de problemas

### Permisos de Docker

```bash
# Linux: añadir tu usuario al grupo docker
sudo usermod -aG docker $USER
# Cierra sesión y vuelve a entrar
```

En Windows, ejecuta Docker Desktop como administrador si hay errores de volumen.

### Puertos ocupados

| Puerto | Servicio |
|--------|----------|
| 5678 | n8n |
| 8000 | python-agent |
| 11434 | ollama |

```bash
# Windows (PowerShell)
netstat -ano | findstr :5678

# Linux/macOS
lsof -i :5678
```

Cambia el mapeo en `docker-compose.yml` (ej. `"5679:5678"`) si hay conflicto.

### Contenedores no arrancan

```bash
docker compose ps
docker compose logs n8n
docker compose logs python-agent
docker compose logs ollama
```

Reconstruir desde cero:

```bash
docker compose down
docker compose up -d --build
```

### Ollama: modelo no disponible

- Primera ejecución: espera la descarga (`docker compose logs -f ollama`).
- Verifica: `curl http://localhost:11434/api/tags` debe listar `llama3.1:8b-instruct-q4_K_M`.

### Agente no responde / error de conexión a Ollama

El agente usa el hostname interno `ollama` (no `localhost`) dentro de la red Docker:

```python
client = ollama.Client(host='http://ollama:11434')
```

Asegúrate de que `python-agent` tenga `depends_on: ollama` y que ambos estén en `ai-network`.

### n8n: workflow sin respuesta

- Confirma que el workflow está **activado**.
- La URL interna debe ser `http://python-agent:8000/chat` (nombre del servicio Compose, no `localhost`).
- Prueba el agente directamente con `curl` antes de depurar n8n.

### ChromaDB / PDFs no indexados

- Coloca PDFs en `agent/documents/`.
- Reinicia el agente: `docker compose restart python-agent`.
- O sube vía `POST /upload`.

---

## Comandos útiles

```bash
# Detener servicios
docker compose down

# Detener y eliminar volúmenes (⚠️ borra datos de n8n si eliminas .n8n/n8n_data)
docker compose down -v

# Rebuild solo del agente
docker compose up -d --build python-agent

# Seguir logs en tiempo real
docker compose logs -f
```

---

## Licencia

Consulta el repositorio para información de licencia.
