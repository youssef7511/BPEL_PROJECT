#!/bin/bash
# Script de lancement des tests SoapUI pour la chorégraphie BPEL

set -e

echo "=========================================="
echo "  BPEL Supply Chain - Test Runner"
echo "=========================================="

# Variables
ODE_ENDPOINT="${ODE_ENDPOINT:-http://ode-bpel:8080/ode}"
PROJECT_FILE="${PROJECT_FILE:-/tests/StoreProcess-soapui-project.xml}"
RESULTS_DIR="/tests/results"

# Attendre que ODE soit disponible
echo "[INFO] Waiting for ODE to be ready..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -s -f "${ODE_ENDPOINT}/" > /dev/null 2>&1; then
        echo "[INFO] ODE is ready!"
        break
    fi
    attempt=$((attempt + 1))
    echo "[INFO] Attempt $attempt/$max_attempts - ODE not ready yet, waiting..."
    sleep 5
done

if [ $attempt -eq $max_attempts ]; then
    echo "[ERROR] ODE did not become ready in time"
    exit 1
fi

# Créer le répertoire de résultats
mkdir -p "${RESULTS_DIR}"

# Exécuter les tests
echo "[INFO] Running SoapUI tests..."
echo "[INFO] Project: ${PROJECT_FILE}"
echo "[INFO] Results: ${RESULTS_DIR}"

testrunner.sh \
    -r \
    -j \
    -f"${RESULTS_DIR}" \
    -PODE_ENDPOINT="${ODE_ENDPOINT}" \
    "${PROJECT_FILE}"

exit_code=$?

echo "=========================================="
if [ $exit_code -eq 0 ]; then
    echo "  Tests completed successfully!"
else
    echo "  Tests failed with exit code: $exit_code"
fi
echo "=========================================="

exit $exit_code
