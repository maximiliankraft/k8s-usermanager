#!/bin/bash

# Script to get resource usage for a namespace
# Usage: ./get-resource-usage.sh <namespace>

set -e

NAMESPACE="${1}"

if [ -z "$NAMESPACE" ]; then
    echo "Namespace is required!"
    echo "Usage: $0 <namespace>"
    exit 1
fi

# Get pod resource usage
POD_USAGE=$(kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")

if [ -z "$POD_USAGE" ]; then
    echo '{"cpu": "0m", "memory": "0Mi"}'
    exit 0
fi

# Calculate total CPU and Memory
TOTAL_CPU=0
TOTAL_MEM=0

while read -r line; do
    CPU=$(echo "$line" | awk '{print $2}' | sed 's/m//')
    MEM=$(echo "$line" | awk '{print $3}' | sed 's/Mi//')
    TOTAL_CPU=$((TOTAL_CPU + CPU))
    TOTAL_MEM=$((TOTAL_MEM + MEM))
done <<< "$POD_USAGE"

echo "{\"cpu\": \"${TOTAL_CPU}m\", \"memory\": \"${TOTAL_MEM}Mi\"}"
