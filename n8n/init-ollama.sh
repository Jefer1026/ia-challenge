#!/bin/bash

# Iniciar el servicio de ollama en segundo plano
ollama serve &

# Guardar el PID del proceso de ollama
pid=$!

# Verificación inteligente del modelo
echo "Verificando si el modelo llama3.1 está instalado..."
if ollama list | grep -q "llama3.1"; then
    echo "✅ El modelo llama3.1 ya está disponible localmente."
else
    echo "⏳ Descargando modelo llama3.1 (esto puede tardar unos minutos)..."
    ollama pull llama3.1:8b-instruct-q4_K_M
    echo "✅ Modelo descargado correctamente."
fi

# Mantener el proceso principal activo
wait $PID