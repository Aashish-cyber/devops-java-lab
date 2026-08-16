#!/bin/bash

set -e

echo "==================="
echo "Building CI Build"
echo "=================="

echo "Building Java Application with Maven"
mvn clean package

echo "checking war file"
ls -lh target/*.war

echo "Buiilding Docker Image"
docker build -t devops-java-app:ci .

echo "====================================="
echo "CI BUILD SUCCESSFUL"
echo "====================================="