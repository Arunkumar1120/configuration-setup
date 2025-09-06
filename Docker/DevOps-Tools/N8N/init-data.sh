#!/bin/bash
set -e;
if [ -n "${POSTGRES_NON_ROOT_USER:-}" ] && [ -n "${POSTGRES_NON_ROOT_PASSWORD:-}" ]; then
	psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
		CREATE USER ${POSTGRES_NON_ROOT_USER} WITH PASSWORD '${POSTGRES_NON_ROOT_PASSWORD}';
		GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_NON_ROOT_USER};
		
		-- Connect to the specific database to modify schema permissions
		\c ${POSTGRES_DB}
		
		-- Grant all privileges on schema public to the non-root user
		GRANT ALL PRIVILEGES ON SCHEMA public TO ${POSTGRES_NON_ROOT_USER};
		
		-- Make the non-root user the owner of the public schema
		ALTER SCHEMA public OWNER TO ${POSTGRES_NON_ROOT_USER};
		
		-- Grant privileges on all tables in the public schema
		GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${POSTGRES_NON_ROOT_USER};
		GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${POSTGRES_NON_ROOT_USER};
		GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${POSTGRES_NON_ROOT_USER};
		
		-- Set default privileges for future objects
		ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${POSTGRES_NON_ROOT_USER};
		ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${POSTGRES_NON_ROOT_USER};
		ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${POSTGRES_NON_ROOT_USER};
	EOSQL
else
	echo "SETUP INFO: No Environment variables given!"
fi

