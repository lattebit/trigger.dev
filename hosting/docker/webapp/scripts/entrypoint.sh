#!/bin/sh
set -xe

if [ -n "$DATABASE_HOST" ]; then
  scripts/wait-for-it.sh ${DATABASE_HOST} -- echo "database is up"
fi

# Run migrations
echo "Running prisma migrations"
pnpm --filter @trigger.dev/database db:migrate:deploy
echo "Prisma migrations done"

if [ -n "$CLICKHOUSE_URL" ]; then
  # Run ClickHouse migrations
  echo "Running ClickHouse migrations..."
  export GOOSE_DRIVER=clickhouse
  
  # Extract host and credentials from CLICKHOUSE_URL (http://user:pass@host:8123)
  # Convert to goose format (tcp://user:pass@host:9000)
  if [ -n "$GOOSE_DBSTRING" ]; then
    # If GOOSE_DBSTRING is explicitly set, use it
    echo "Using provided GOOSE_DBSTRING"
  else
    # Extract components from CLICKHOUSE_URL and build tcp connection string
    # Pattern: http://user:password@host:8123 -> tcp://user:password@host:9000
    CLICKHOUSE_HOST=$(echo "$CLICKHOUSE_URL" | sed -E 's|https?://([^:]+):([^@]+)@([^:]+):.*|\3|')
    CLICKHOUSE_USER=$(echo "$CLICKHOUSE_URL" | sed -E 's|https?://([^:]+):([^@]+)@.*|\1|')
    CLICKHOUSE_PASS=$(echo "$CLICKHOUSE_URL" | sed -E 's|https?://([^:]+):([^@]+)@.*|\2|')
    
    # Default to clickhouse:9000 if extraction fails
    if [ -z "$CLICKHOUSE_HOST" ]; then
      CLICKHOUSE_HOST="clickhouse"
    fi
    if [ -z "$CLICKHOUSE_USER" ]; then
      CLICKHOUSE_USER="default"
    fi
    if [ -z "$CLICKHOUSE_PASS" ]; then
      CLICKHOUSE_PASS="password"
    fi
    
    export GOOSE_DBSTRING="tcp://${CLICKHOUSE_USER}:${CLICKHOUSE_PASS}@${CLICKHOUSE_HOST}:9000"
    echo "Generated GOOSE_DBSTRING from CLICKHOUSE_URL"
  fi
  
  export GOOSE_MIGRATION_DIR=/triggerdotdev/internal-packages/clickhouse/schema
  /usr/local/bin/goose up
  echo "ClickHouse migrations complete."
else
  echo "CLICKHOUSE_URL not set, skipping ClickHouse migrations."
fi

# Copy over required prisma files
cp internal-packages/database/prisma/schema.prisma apps/webapp/prisma/
cp node_modules/@prisma/engines/*.node apps/webapp/prisma/

cd /triggerdotdev/apps/webapp


# Decide how much old-space memory Node should get.
# Use $NODE_MAX_OLD_SPACE_SIZE if it’s set; otherwise fall back to 8192.
MAX_OLD_SPACE_SIZE="${NODE_MAX_OLD_SPACE_SIZE:-8192}"

echo "Setting max old space size to ${MAX_OLD_SPACE_SIZE}"

NODE_PATH='/triggerdotdev/node_modules/.pnpm/node_modules' exec dumb-init node --max-old-space-size=${MAX_OLD_SPACE_SIZE} ./build/server.js

