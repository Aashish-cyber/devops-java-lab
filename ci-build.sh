#!/bin/bash

set -e

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

docker build -t devops-java-app:ci .

echo ""
echo "====================================="
echo "        CI BUILD SUCCESSFUL"
echo "====================================="