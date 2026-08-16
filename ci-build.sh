#!/bin/bash

set -e

CONTAINER_NAME="devops-java-ci"
IMAGE_NAME="devops-java-app:ci"
HOST_PORT="8081"

cleanup() {
    echo ""
    echo "7. Cleaning Up"
    echo "---------------"

    docker rm -f $CONTAINER_NAME 2>/dev/null || true

    echo "Cleanup completed."
}

trap cleanup EXIT


echo "====================================="
echo "        DEVOPS LAB - CI BUILD"
echo "====================================="


echo ""
echo "1. Building and Testing Java Application"
echo "-----------------------------------------"

mvn clean package


echo ""
echo "2. Checking WAR Artifact"
echo "------------------------"

ls -lh target/*.war


echo ""
echo "3. Building Docker Image"
echo "------------------------"

docker build -t $IMAGE_NAME .


echo ""
echo "4. Starting Application Container"
echo "----------------------------------"

docker rm -f $CONTAINER_NAME 2>/dev/null || true

docker run -d \
    --name $CONTAINER_NAME \
    -p $HOST_PORT:8080 \
    $IMAGE_NAME


echo ""
echo "5. Waiting for Application Startup"
echo "-----------------------------------"

sleep 5


echo ""
echo "6. Running Smoke Test"
echo "---------------------"

curl -f http://localhost:$HOST_PORT/devops-lab/

echo ""
echo "Smoke test PASSED!"


echo ""
echo "====================================="
echo "        CI BUILD SUCCESSFUL"
echo "====================================="