#!/bin/bash

# Update image tag in Helm values file
# Usage: ./update-image-tag.sh <component> <environment> <new-tag>
# Example: ./update-image-tag.sh backend dev abc123

set -e

COMPONENT=$1
ENVIRONMENT=$2
NEW_TAG=$3

if [ -z "$COMPONENT" ] || [ -z "$ENVIRONMENT" ] || [ -z "$NEW_TAG" ]; then
    echo "Usage: $0 <component> <environment> <new-tag>"
    echo "Example: $0 backend dev abc123"
    exit 1
fi

VALUES_FILE="helm/${COMPONENT}/values-${ENVIRONMENT}.yaml"

if [ ! -f "$VALUES_FILE" ]; then
    echo "Error: Values file not found: $VALUES_FILE"
    exit 1
fi

echo "Updating $VALUES_FILE with tag: $NEW_TAG"

# Update image tag using yq or sed
if command -v yq &> /dev/null; then
    yq eval ".image.tag = \"$NEW_TAG\"" -i "$VALUES_FILE"
else
    # Fallback to sed if yq is not available
    sed -i.bak "s/tag: \".*\"/tag: \"$NEW_TAG\"/" "$VALUES_FILE"
    rm "${VALUES_FILE}.bak"
fi

echo "Successfully updated image tag to: $NEW_TAG"
