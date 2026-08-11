import GRDB

enum WealthMigrationError: Error, Equatable {
    case unsupportedLegacyContainerKind
}

enum DatabaseMigrations {
    static let permanentV1 = "permanent_v1_foundation"
    static let permanentV2 = "permanent_v2_wealth"
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
        migrator.registerMigration(permanentV2) { db in
            try db.execute(sql: """
                ALTER TABLE asset_containers
                ADD COLUMN institution TEXT
                """)
            try db.execute(sql: """
                ALTER TABLE asset_containers
                ADD COLUMN primary_currency_code TEXT NOT NULL DEFAULT 'CNY'
                    CHECK (primary_currency_code IN ('CNY', 'USD'))
                """)
            try db.execute(sql: """
                ALTER TABLE asset_containers
                ADD COLUMN notes TEXT
                """)
            try db.execute(sql: """
                ALTER TABLE asset_containers
                ADD COLUMN created_date TEXT NOT NULL DEFAULT '1970-01-01'
                    CHECK (length(created_date) = 10)
                """)
            try db.execute(sql: """
                ALTER TABLE asset_containers
                ADD COLUMN updated_date TEXT NOT NULL DEFAULT '1970-01-01'
                    CHECK (length(updated_date) = 10)
                """)

            try db.execute(sql: """
                UPDATE asset_containers
                SET primary_currency_code = COALESCE(
                    (SELECT currency_code FROM accounts WHERE accounts.id = asset_containers.account_id),
                    (SELECT currency_code FROM assets WHERE assets.container_id = asset_containers.id LIMIT 1),
                    'CNY'
                )
                """)
            try db.execute(sql: """
                UPDATE asset_containers
                SET kind = CASE kind
                    WHEN 'cash' THEN 'bankCash'
                    WHEN 'security' THEN 'stock'
                    WHEN 'other' THEN 'otherAsset'
                    ELSE kind
                END
                """)

            let invalidKindCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM asset_containers
                    WHERE kind NOT IN (
                        'bankCash', 'stock', 'etf', 'fund',
                        'insurance', 'otherAsset', 'liability'
                    )
                    """
            ) ?? 0
            guard invalidKindCount == 0 else {
                throw WealthMigrationError.unsupportedLegacyContainerKind
            }

            try db.execute(sql: """
                CREATE TRIGGER asset_containers_kind_insert
                BEFORE INSERT ON asset_containers
                WHEN NEW.kind NOT IN (
                    'bankCash', 'stock', 'etf', 'fund',
                    'insurance', 'otherAsset', 'liability'
                )
                BEGIN
                    SELECT RAISE(ABORT, 'invalid asset container kind');
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER asset_containers_kind_update
                BEFORE UPDATE OF kind ON asset_containers
                WHEN NEW.kind NOT IN (
                    'bankCash', 'stock', 'etf', 'fund',
                    'insurance', 'otherAsset', 'liability'
                )
                BEGIN
                    SELECT RAISE(ABORT, 'invalid asset container kind');
                END
                """)

            try db.execute(sql: """
                CREATE TABLE wealth_records (
                    container_id TEXT PRIMARY KEY NOT NULL
                        REFERENCES asset_containers(id) ON DELETE CASCADE,
                    record_kind TEXT NOT NULL CHECK (record_kind IN (
                        'bankCash', 'stock', 'etf', 'fund',
                        'insurance', 'otherAsset', 'liability'
                    )),
                    original_minor INTEGER NOT NULL CHECK (original_minor >= 0),
                    original_currency_code TEXT NOT NULL
                        CHECK (original_currency_code IN ('CNY', 'USD')),
                    converted_cny_minor INTEGER NOT NULL CHECK (converted_cny_minor >= 0),
                    fx_coefficient INTEGER NOT NULL CHECK (fx_coefficient > 0),
                    fx_source_currency_code TEXT NOT NULL
                        CHECK (fx_source_currency_code IN ('CNY', 'USD')),
                    fx_target_currency_code TEXT NOT NULL
                        CHECK (fx_target_currency_code = 'CNY'),
                    fx_source TEXT NOT NULL CHECK (length(fx_source) > 0),
                    fx_reference_date TEXT NOT NULL CHECK (length(fx_reference_date) = 10),
                    fx_recorded_at_ms INTEGER NOT NULL,
                    fx_is_manual INTEGER NOT NULL CHECK (fx_is_manual IN (0, 1)),
                    fx_is_stale INTEGER NOT NULL CHECK (fx_is_stale IN (0, 1)),
                    interest_rate_coefficient INTEGER CHECK (
                        interest_rate_coefficient IS NULL OR interest_rate_coefficient >= 0
                    ),
                    ticker TEXT,
                    mic TEXT CHECK (mic IS NULL OR length(mic) = 4),
                    quantity_coefficient INTEGER CHECK (
                        quantity_coefficient IS NULL OR quantity_coefficient >= 0
                    ),
                    manual_price_coefficient INTEGER CHECK (
                        manual_price_coefficient IS NULL OR manual_price_coefficient >= 0
                    ),
                    insurance_company TEXT,
                    insurance_product_name TEXT,
                    premium_minor INTEGER CHECK (premium_minor IS NULL OR premium_minor >= 0),
                    payment_frequency TEXT CHECK (
                        payment_frequency IS NULL OR payment_frequency IN (
                            'monthly', 'quarterly', 'semiAnnual', 'annual', 'single'
                        )
                    ),
                    coverage_minor INTEGER CHECK (coverage_minor IS NULL OR coverage_minor >= 0),
                    start_date TEXT CHECK (start_date IS NULL OR length(start_date) = 10),
                    maturity_date TEXT CHECK (maturity_date IS NULL OR length(maturity_date) = 10),
                    category_description TEXT,
                    CHECK (
                        (original_currency_code = 'CNY'
                            AND fx_source_currency_code = 'CNY'
                            AND fx_coefficient = 10000000000
                            AND converted_cny_minor = original_minor
                            AND fx_source = 'identity'
                            AND fx_is_manual = 0)
                        OR
                        (original_currency_code = 'USD'
                            AND fx_source_currency_code = 'USD'
                            AND fx_is_manual = 1
                            AND instr(lower(fx_source), 'manual') > 0)
                    ),
                    CHECK (
                        (record_kind = 'bankCash')
                        OR
                        (record_kind IN ('stock', 'etf', 'fund')
                            AND ticker IS NOT NULL AND length(ticker) > 0
                            AND quantity_coefficient IS NOT NULL
                            AND manual_price_coefficient IS NOT NULL)
                        OR
                        (record_kind = 'insurance'
                            AND insurance_company IS NOT NULL AND length(insurance_company) > 0
                            AND insurance_product_name IS NOT NULL AND length(insurance_product_name) > 0
                            AND premium_minor IS NOT NULL
                            AND payment_frequency IS NOT NULL
                            AND coverage_minor IS NOT NULL
                            AND start_date IS NOT NULL)
                        OR
                        (record_kind = 'otherAsset'
                            AND category_description IS NOT NULL
                            AND length(category_description) > 0)
                        OR
                        (record_kind = 'liability')
                    )
                )
                """)

            try db.execute(sql: """
                CREATE TRIGGER wealth_records_kind_insert
                BEFORE INSERT ON wealth_records
                WHEN (SELECT kind FROM asset_containers WHERE id = NEW.container_id) != NEW.record_kind
                BEGIN
                    SELECT RAISE(ABORT, 'wealth record kind does not match container');
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER wealth_records_kind_update
                BEFORE UPDATE OF record_kind, container_id ON wealth_records
                WHEN (SELECT kind FROM asset_containers WHERE id = NEW.container_id) != NEW.record_kind
                BEGIN
                    SELECT RAISE(ABORT, 'wealth record kind does not match container');
                END
                """)

            try db.execute(sql: """
                CREATE INDEX asset_containers_kind_index
                ON asset_containers(kind)
                """)
            try db.execute(sql: """
                CREATE INDEX asset_containers_currency_index
                ON asset_containers(primary_currency_code)
                """)
            try db.execute(sql: """
                CREATE INDEX asset_containers_updated_date_index
                ON asset_containers(updated_date DESC)
                """)
            try db.execute(sql: """
                CREATE INDEX wealth_records_kind_index
                ON wealth_records(record_kind)
                """)

            try db.execute(
                sql: "UPDATE schema_metadata SET version = 2 WHERE store_kind = 'permanent'"
            )
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
