import GRDB

enum DatabaseMigrations {
    static let permanentV1 = "permanent_v1_foundation"
    static let cacheV1 = "cache_v1_foundation"

    static func permanentMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(permanentV1) { db in
            try db.execute(sql: """
                CREATE TABLE schema_metadata (
                    store_kind TEXT PRIMARY KEY NOT NULL,
                    version INTEGER NOT NULL CHECK (version >= 1)
                )
                """)
            try db.execute(
                sql: "INSERT INTO schema_metadata (store_kind, version) VALUES ('permanent', 1)"
            )

            try db.execute(sql: """
                CREATE TABLE accounts (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL CHECK (length(name) > 0),
                    kind TEXT NOT NULL,
                    currency_code TEXT NOT NULL CHECK (currency_code IN ('CNY', 'USD'))
                )
                """)
            try db.execute(sql: """
                CREATE TABLE asset_containers (
                    id TEXT PRIMARY KEY NOT NULL,
                    account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
                    name TEXT NOT NULL CHECK (length(name) > 0),
                    kind TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE market_instrument_references (
                    id TEXT PRIMARY KEY NOT NULL,
                    symbol TEXT NOT NULL CHECK (length(symbol) > 0),
                    mic TEXT NOT NULL CHECK (length(mic) = 4),
                    currency_code TEXT NOT NULL CHECK (currency_code IN ('CNY', 'USD')),
                    UNIQUE(symbol, mic)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE assets (
                    id TEXT PRIMARY KEY NOT NULL,
                    container_id TEXT NOT NULL REFERENCES asset_containers(id) ON DELETE CASCADE,
                    name TEXT NOT NULL CHECK (length(name) > 0),
                    currency_code TEXT NOT NULL CHECK (currency_code IN ('CNY', 'USD')),
                    instrument_reference_id TEXT REFERENCES market_instrument_references(id) ON DELETE RESTRICT
                )
                """)
            try db.execute(sql: """
                CREATE TABLE wealth_transactions (
                    id TEXT PRIMARY KEY NOT NULL,
                    account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
                    civil_date TEXT NOT NULL CHECK (length(civil_date) = 10),
                    amount_minor INTEGER NOT NULL,
                    currency_code TEXT NOT NULL CHECK (currency_code IN ('CNY', 'USD')),
                    type TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE holdings (
                    id TEXT PRIMARY KEY NOT NULL,
                    account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
                    instrument_reference_id TEXT NOT NULL REFERENCES market_instrument_references(id) ON DELETE RESTRICT,
                    quantity_coefficient INTEGER NOT NULL,
                    cost_minor INTEGER NOT NULL,
                    cost_currency_code TEXT NOT NULL CHECK (cost_currency_code IN ('CNY', 'USD')),
                    UNIQUE(account_id, instrument_reference_id)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE trades (
                    id TEXT PRIMARY KEY NOT NULL,
                    holding_id TEXT NOT NULL REFERENCES holdings(id) ON DELETE CASCADE,
                    session_date TEXT NOT NULL CHECK (length(session_date) = 10),
                    mic TEXT NOT NULL CHECK (length(mic) = 4),
                    time_zone_id TEXT NOT NULL,
                    quantity_coefficient INTEGER NOT NULL,
                    price_coefficient INTEGER NOT NULL CHECK (price_coefficient >= 0),
                    price_currency_code TEXT NOT NULL CHECK (price_currency_code IN ('CNY', 'USD')),
                    type TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE snapshots (
                    id TEXT PRIMARY KEY NOT NULL,
                    civil_date TEXT NOT NULL UNIQUE CHECK (length(civil_date) = 10),
                    created_at_ms INTEGER NOT NULL,
                    total_cny_minor INTEGER NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE snapshot_valuations (
                    id TEXT PRIMARY KEY NOT NULL,
                    snapshot_id TEXT NOT NULL REFERENCES snapshots(id) ON DELETE CASCADE,
                    source_amount_minor INTEGER NOT NULL,
                    source_currency_code TEXT NOT NULL CHECK (source_currency_code IN ('CNY', 'USD')),
                    fx_coefficient INTEGER NOT NULL CHECK (fx_coefficient > 0),
                    fx_source_currency_code TEXT NOT NULL CHECK (fx_source_currency_code IN ('CNY', 'USD')),
                    fx_target_currency_code TEXT NOT NULL CHECK (fx_target_currency_code = 'CNY'),
                    converted_cny_minor INTEGER NOT NULL,
                    provider_identifier TEXT NOT NULL,
                    reference_date TEXT NOT NULL CHECK (length(reference_date) = 10),
                    fetched_at_ms INTEGER NOT NULL,
                    is_stale INTEGER NOT NULL CHECK (is_stale IN (0, 1))
                )
                """)
            try db.execute(sql: """
                CREATE TABLE portfolios (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL CHECK (length(name) > 0),
                    base_currency_code TEXT NOT NULL CHECK (base_currency_code = 'CNY')
                )
                """)
            try db.execute(sql: """
                CREATE TABLE goals (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL CHECK (length(name) > 0),
                    target_minor INTEGER NOT NULL,
                    currency_code TEXT NOT NULL CHECK (currency_code IN ('CNY', 'USD')),
                    target_date TEXT CHECK (target_date IS NULL OR length(target_date) = 10)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE insurance_policies (
                    id TEXT PRIMARY KEY NOT NULL,
                    asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
                    name TEXT NOT NULL CHECK (length(name) > 0),
                    premium_minor INTEGER NOT NULL,
                    currency_code TEXT NOT NULL CHECK (currency_code IN ('CNY', 'USD'))
                )
                """)
            try db.execute(sql: """
                CREATE TABLE categories (
                    id TEXT PRIMARY KEY NOT NULL,
                    parent_id TEXT REFERENCES categories(id) ON DELETE RESTRICT,
                    name TEXT NOT NULL CHECK (length(name) > 0)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE tags (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL UNIQUE CHECK (length(name) > 0)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE transaction_tags (
                    transaction_id TEXT NOT NULL REFERENCES wealth_transactions(id) ON DELETE CASCADE,
                    tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
                    PRIMARY KEY (transaction_id, tag_id)
                )
                """)
        }
        return migrator
    }

    static func cacheMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(cacheV1) { db in
            try db.execute(sql: """
                CREATE TABLE schema_metadata (
                    store_kind TEXT PRIMARY KEY NOT NULL,
                    version INTEGER NOT NULL CHECK (version >= 1)
                )
                """)
            try db.execute(
                sql: "INSERT INTO schema_metadata (store_kind, version) VALUES ('market_cache', 1)"
            )
            try db.execute(sql: """
                CREATE TABLE cached_instruments (
                    id TEXT PRIMARY KEY NOT NULL,
                    symbol TEXT NOT NULL,
                    mic TEXT NOT NULL CHECK (length(mic) = 4),
                    currency_code TEXT NOT NULL CHECK (currency_code IN ('CNY', 'USD')),
                    display_name TEXT NOT NULL,
                    provider_identifier TEXT NOT NULL,
                    fetched_at_ms INTEGER NOT NULL,
                    expires_at_ms INTEGER NOT NULL,
                    last_accessed_at_ms INTEGER NOT NULL,
                    byte_size INTEGER NOT NULL CHECK (byte_size >= 0),
                    UNIQUE(provider_identifier, symbol, mic)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE cached_prices (
                    id TEXT PRIMARY KEY NOT NULL,
                    instrument_id TEXT NOT NULL REFERENCES cached_instruments(id) ON DELETE CASCADE,
                    session_date TEXT NOT NULL CHECK (length(session_date) = 10),
                    open_coefficient INTEGER NOT NULL CHECK (open_coefficient >= 0),
                    high_coefficient INTEGER NOT NULL CHECK (high_coefficient >= 0),
                    low_coefficient INTEGER NOT NULL CHECK (low_coefficient >= 0),
                    close_coefficient INTEGER NOT NULL CHECK (close_coefficient >= 0),
                    volume_coefficient INTEGER NOT NULL CHECK (volume_coefficient >= 0),
                    quote_currency_code TEXT NOT NULL CHECK (quote_currency_code IN ('CNY', 'USD')),
                    provider_identifier TEXT NOT NULL,
                    fetched_at_ms INTEGER NOT NULL,
                    expires_at_ms INTEGER NOT NULL,
                    last_accessed_at_ms INTEGER NOT NULL,
                    byte_size INTEGER NOT NULL CHECK (byte_size >= 0),
                    UNIQUE(instrument_id, session_date)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE cache_metadata (
                    key TEXT PRIMARY KEY NOT NULL,
                    integer_value INTEGER,
                    text_value TEXT
                )
                """)
        }
        return migrator
    }
}
