function mipaas-create-key --argument account_name account_slug
    set -f api_key "urn:mipaas:api_key:$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)"
    set -f hashed (echo -n $api_key | sha256sum | cut -d' ' -f1)

    argparse 'd/db=' -- $argv; or return

    set -q _flag_db; or set _flag_db mipaas.db

    sqlite3 $_flag_db "INSERT OR IGNORE INTO accounts (slug, name) VALUES ('$account_slug', '$account_name');"
    sqlite3 $_flag_db "INSERT INTO api_keys (hashed_key, account_slug) VALUES ('$hashed', '$account_slug');"
    sqlite3 $_flag_db "INSERT OR IGNORE INTO usage (account_slug) VALUES ('$account_slug');"

    echo "API key for $account_name: $api_key"
    echo "Send this to the customer. It won't be shown again."
end

function mipaas-db-init
    argparse 'd/db=' 's/schema=' -- $argv
    or return

    set -q _flag_db; or set _flag_db mipaas.db
    set -q _flag_schema; or set _flag_schema ./schema.sql

    if not test -f $_flag_schema
        echo "Schema file not found: $_flag_schema"
        return 1
    end

    sqlite3 $_flag_db <$_flag_schema

    echo "Database initialised: $_flag_db (schema: $_flag_schema)"
end
