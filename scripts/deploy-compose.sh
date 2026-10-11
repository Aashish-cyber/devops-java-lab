#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="/home/ranaa/devops-lab/java-tomcat"
NGINX_CONFIG="$PROJECT_DIR/nginx/nginx.conf"
ENV_FILE="$PROJECT_DIR/.env"

cd "$PROJECT_DIR"

NEW_IMAGE="${1:?Usage: deploy-compose.sh <image:tag>}"

echo "=================================="
echo "Docker Compose Blue/Green Deploy"
echo "=================================="

echo "New image: $NEW_IMAGE"

# Detect active production environment
if grep -q 'server devops-java-deploy:8080;' "$NGINX_CONFIG"; then
    ACTIVE_SLOT="blue"
    TARGET_SLOT="green"
    TARGET_PORT="8083"
elif grep -q 'server devops-java-green:8080;' "$NGINX_CONFIG"; then
    ACTIVE_SLOT="green"
    TARGET_SLOT="blue"
    TARGET_PORT="8082"
else
    echo "ERROR: Cannot identify active production slot."
    exit 1
fi

echo "Active slot: $ACTIVE_SLOT"
echo "Target slot: $TARGET_SLOT"
echo "Target port: $TARGET_PORT"

# ----------------------------------------
# Backup current deployment configuration
# ----------------------------------------

BACKUP_DIR="$(mktemp -d)"

cp "$NGINX_CONFIG" "$BACKUP_DIR/nginx.conf"
cp "$ENV_FILE" "$BACKUP_DIR/.env"

echo "Deployment backup created: $BACKUP_DIR"

# Verify active production before deployment
ACTIVE_RESPONSE="$BACKUP_DIR/active.html"

curl -fsS \
  "http://localhost:8080/devops-lab/" \
  > "$ACTIVE_RESPONSE"

echo "Current production is healthy."

echo "Previous production response saved."

# Confirm the existing production backend is healthy
if [ "$ACTIVE_SLOT" = "blue" ]; then
    ACTIVE_PORT="8082"
else
    ACTIVE_PORT="8083"
fi

curl -fsS \
    --connect-timeout 3 \
    --max-time 5 \
    "http://localhost:$ACTIVE_PORT/devops-lab/" \
    > "$BACKUP_DIR/active-direct.html"

if ! cmp -s "$ACTIVE_RESPONSE" "$BACKUP_DIR/active-direct.html"; then
    echo "ERROR: Nginx production response does not match active backend."
    exit 1
fi

echo "Active production routing verified."

# ----------------------------------------
# Automatic rollback on deployment failure
# ----------------------------------------

rollback() {
    local original_exit_code=$?
    local rollback_failed=0

    trap - ERR
    set +e

    echo "=================================="
    echo "DEPLOYMENT FAILED - ROLLING BACK"
    echo "=================================="

    # Restore previous image configuration
    if cp "$BACKUP_DIR/.env" "$ENV_FILE"; then
        echo "Previous image configuration restored."
    else
        echo "ERROR: Failed to restore .env"
        rollback_failed=1
    fi

    # Restore previous Nginx routing
    if cat "$BACKUP_DIR/nginx.conf" > "$NGINX_CONFIG"; then
        echo "Previous Nginx configuration restored."
    else
        echo "ERROR: Failed to restore Nginx configuration."
        rollback_failed=1
    fi

    # Validate and reload Nginx
    if docker exec devops-nginx nginx -t &&
       docker exec devops-nginx nginx -s reload; then
        echo "Nginx rollback reload successful."
    else
        echo "ERROR: Nginx rollback reload failed."
        rollback_failed=1
    fi

    # Restore previous inactive-slot container
    if docker compose -p java-devops-lab up -d --no-deps "$TARGET_SLOT"; then
        echo "Previous target-slot image restored."
    else
        echo "ERROR: Failed to restore target-slot container."
        rollback_failed=1
    fi

    # Verify production response
    if curl -fsS \
        --connect-timeout 3 \
        --max-time 5 \
        "http://localhost:8080/devops-lab/" \
        > "$BACKUP_DIR/rollback.html" &&
       cmp -s "$ACTIVE_RESPONSE" "$BACKUP_DIR/rollback.html"; then

        echo "Rollback production verification successful."
    else
        echo "ERROR: Production response not restored correctly."
        rollback_failed=1
    fi

    if [ "$rollback_failed" -eq 0 ]; then
        echo "ROLLBACK SUCCESSFUL"
    else
        echo "ROLLBACK INCOMPLETE - MANUAL INVESTIGATION REQUIRED"
    fi

    exit "$original_exit_code"
}

trap 'rollback' ERR

# ----------------------------------------
# Deploy new image to inactive slot
# ----------------------------------------

echo "Deploying $NEW_IMAGE to $TARGET_SLOT"

# Verify new image exists locally
docker image inspect "$NEW_IMAGE" >/dev/null || \
  docker pull "$NEW_IMAGE"

# Save the new image in the deployment state
if [ "$TARGET_SLOT" = "green" ]; then
    sed -i "s|^GREEN_IMAGE=.*|GREEN_IMAGE=$NEW_IMAGE|" "$ENV_FILE"
else
    sed -i "s|^BLUE_IMAGE=.*|BLUE_IMAGE=$NEW_IMAGE|" "$ENV_FILE"
fi

# Recreate only the inactive service
docker compose -p java-devops-lab up -d --no-deps "$TARGET_SLOT"

echo "Deployment command completed."

# Show the new container
docker compose -p java-devops-lab ps "$TARGET_SLOT"


# ----------------------------------------
# Health check newly deployed application
# ----------------------------------------

echo "=================================="
echo "HEALTH CHECK: $TARGET_SLOT"
echo "=================================="

TARGET_URL="http://localhost:$TARGET_PORT/devops-lab/"
NEW_RESPONSE="$BACKUP_DIR/new-version.html"

HEALTHY=false

for i in {1..12}; do
    echo "Health check attempt $i/12"

    if curl -fsS \
        --connect-timeout 3 \
        --max-time 5 \
        "$TARGET_URL" > "$NEW_RESPONSE"; then

        HEALTHY=true
        echo "Application is healthy."
        break
    fi

    sleep 5
done

if [ "$HEALTHY" != "true" ]; then
    echo "ERROR: Application health check failed."

    docker compose -p java-devops-lab logs --tail=50 "$TARGET_SLOT" || true

    false
fi

echo "New application response:"
cat "$NEW_RESPONSE"

# ----------------------------------------
# Switch production traffic to new slot
# ----------------------------------------

echo "=================================="
echo "SWITCHING PRODUCTION TRAFFIC"
echo "=================================="

if [ "$TARGET_SLOT" = "green" ]; then
    OLD_BACKEND="devops-java-deploy:8080"
    NEW_BACKEND="devops-java-green:8080"
else
    OLD_BACKEND="devops-java-green:8080"
    NEW_BACKEND="devops-java-deploy:8080"
fi

# Prepare updated Nginx configuration
TEMP_NGINX_CONFIG="$BACKUP_DIR/nginx-new.conf"

sed \
    "s|server $OLD_BACKEND;|server $NEW_BACKEND;|" \
    "$NGINX_CONFIG" > "$TEMP_NGINX_CONFIG"

# Verify the new backend exists in the generated config
grep -Fq "server $NEW_BACKEND;" "$TEMP_NGINX_CONFIG"

# Update the existing bind-mounted file without replacing it
cat "$TEMP_NGINX_CONFIG" > "$NGINX_CONFIG"

# Validate and reload Nginx
docker exec devops-nginx nginx -t
docker exec devops-nginx nginx -s reload

echo "Nginx switched to $TARGET_SLOT."

# ----------------------------------------
# Verify new version in production
# ----------------------------------------

echo "=================================="
echo "VERIFYING PRODUCTION"
echo "=================================="

PRODUCTION_URL="http://localhost:8080/devops-lab/"
PRODUCTION_RESPONSE="$BACKUP_DIR/production.html"

VERIFIED=false

for i in {1..6}; do
    echo "Production verification attempt $i/6"

    if curl -fsS \
        --connect-timeout 3 \
        --max-time 5 \
        "$PRODUCTION_URL" > "$PRODUCTION_RESPONSE"; then

        if cmp -s "$NEW_RESPONSE" "$PRODUCTION_RESPONSE"; then
            VERIFIED=true
            break
        fi
    fi

    sleep 2
done

if [ "$VERIFIED" != "true" ]; then
    echo "ERROR: Production verification failed."
    false
fi



echo "=================================="
echo "DEPLOYMENT SUCCESSFUL"
echo "Active production slot: $TARGET_SLOT"
echo "Image: $NEW_IMAGE"
echo "=================================="