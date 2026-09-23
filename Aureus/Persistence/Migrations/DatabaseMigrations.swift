import Foundation
import GRDB

enum WealthMigrationError: Error, Equatable {
    case unsupportedLegacyContainerKind
}

enum DatabaseMigrations {
    static let permanentV1 = "permanent_v1_foundation"
    static let permanentV2 = "permanent_v2_wealth"
    static let permanentV3 = "permanent_v3_ledger"
    static let permanentV4 = "permanent_v4_ledger_semantic_fingerprint"
    static let permanentV5 = "permanent_v5_dashboard_snapshots"
    static let permanentV6 = "permanent_v6_portfolio"
    static let permanentV7 = "permanent_v7_evidence_import"
    static let permanentV8 = "permanent_v8_ledger_correction_history"
    static let cacheV1 = "cache_v1_foundation"
    static let cacheV2 = "cache_v2_market_data"

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
        migrator.registerMigration(permanentV3) { db in
            // The v1 wealth_transactions table remains an immutable foundation artifact.
            // Stage 4's active Ledger source of truth starts with ledger_transactions.
            try db.execute(sql: "ALTER TABLE categories ADD COLUMN normalized_name TEXT")
            try db.execute(sql: "ALTER TABLE tags ADD COLUMN normalized_name TEXT")
            try backfillNormalizedNames(in: db, table: "categories")
            try backfillNormalizedNames(in: db, table: "tags")
            try db.execute(sql: "CREATE UNIQUE INDEX categories_normalized_name_unique ON categories(normalized_name)")
            try db.execute(sql: "CREATE UNIQUE INDEX tags_normalized_name_unique ON tags(normalized_name)")

            try db.execute(sql: """
                CREATE TABLE ledger_transactions (
                    id TEXT PRIMARY KEY NOT NULL,
                    kind TEXT NOT NULL CHECK (kind IN (
                        'income', 'expense', 'transfer', 'buy', 'sell',
                        'dividend', 'interest', 'fee'
                    )),
                    civil_date TEXT NOT NULL CHECK (length(civil_date) = 10),
                    recorded_at_ms INTEGER NOT NULL,
                    description TEXT NOT NULL CHECK (length(trim(description)) > 0),
                    payee TEXT,
                    category_id TEXT REFERENCES categories(id) ON DELETE RESTRICT,
                    note TEXT,
                    import_fingerprint TEXT UNIQUE,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    CHECK (kind != 'transfer' OR category_id IS NULL)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE ledger_postings (
                    id TEXT PRIMARY KEY NOT NULL,
                    transaction_id TEXT NOT NULL
                        REFERENCES ledger_transactions(id) ON DELETE CASCADE,
                    role TEXT NOT NULL CHECK (role IN ('primary', 'transferSource', 'transferTarget')),
                    container_id TEXT NOT NULL
                        REFERENCES asset_containers(id) ON DELETE RESTRICT,
                    original_minor INTEGER NOT NULL CHECK (original_minor > 0),
                    original_currency_code TEXT NOT NULL
                        CHECK (original_currency_code IN ('CNY', 'USD')),
                    converted_cny_minor INTEGER NOT NULL CHECK (converted_cny_minor > 0),
                    fx_coefficient INTEGER NOT NULL CHECK (fx_coefficient > 0),
                    fx_source_currency_code TEXT NOT NULL
                        CHECK (fx_source_currency_code IN ('CNY', 'USD')),
                    fx_target_currency_code TEXT NOT NULL CHECK (fx_target_currency_code = 'CNY'),
                    fx_source TEXT NOT NULL CHECK (length(fx_source) > 0),
                    fx_reference_date TEXT NOT NULL CHECK (length(fx_reference_date) = 10),
                    fx_recorded_at_ms INTEGER NOT NULL,
                    fx_is_manual INTEGER NOT NULL CHECK (fx_is_manual IN (0, 1)),
                    fx_is_stale INTEGER NOT NULL CHECK (fx_is_stale IN (0, 1)),
                    UNIQUE(transaction_id, role),
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
                    )
                )
                """)
            try db.execute(sql: """
                CREATE TABLE ledger_transaction_tags (
                    transaction_id TEXT NOT NULL
                        REFERENCES ledger_transactions(id) ON DELETE CASCADE,
                    tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE RESTRICT,
                    PRIMARY KEY (transaction_id, tag_id)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE classification_rules (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
                    priority INTEGER NOT NULL,
                    is_enabled INTEGER NOT NULL CHECK (is_enabled IN (0, 1)),
                    match_mode TEXT NOT NULL CHECK (match_mode IN ('exact', 'contains')),
                    payee_pattern TEXT,
                    kind TEXT CHECK (kind IS NULL OR kind IN (
                        'income', 'expense', 'transfer', 'buy', 'sell',
                        'dividend', 'interest', 'fee'
                    )),
                    source_container_id TEXT
                        REFERENCES asset_containers(id) ON DELETE RESTRICT,
                    amount_direction TEXT CHECK (
                        amount_direction IS NULL OR amount_direction IN ('inflow', 'outflow')
                    ),
                    result_category_id TEXT REFERENCES categories(id) ON DELETE RESTRICT,
                    UNIQUE(priority, id)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE classification_rule_tags (
                    rule_id TEXT NOT NULL REFERENCES classification_rules(id) ON DELETE CASCADE,
                    tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE RESTRICT,
                    PRIMARY KEY (rule_id, tag_id)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE ledger_import_batches (
                    id TEXT PRIMARY KEY NOT NULL,
                    schema_version TEXT NOT NULL CHECK (schema_version = 'AUREUS_LEDGER_V1'),
                    imported_at_ms INTEGER NOT NULL,
                    transaction_count INTEGER NOT NULL CHECK (transaction_count > 0)
                )
                """)
            try db.execute(sql: "CREATE INDEX ledger_transactions_date_index ON ledger_transactions(civil_date DESC, id)")
            try db.execute(sql: "CREATE INDEX ledger_transactions_kind_index ON ledger_transactions(kind)")
            try db.execute(sql: "CREATE INDEX ledger_postings_container_index ON ledger_postings(container_id)")
            try db.execute(sql: "CREATE INDEX ledger_transaction_tags_tag_index ON ledger_transaction_tags(tag_id)")
            try db.execute(sql: "UPDATE schema_metadata SET version = 3 WHERE store_kind = 'permanent'")
        }
        migrator.registerMigration(permanentV4) { db in
            try LedgerImportFingerprintRepair.migrateCandidateFingerprints(in: db)
            try db.execute(sql: "UPDATE schema_metadata SET version = 4 WHERE store_kind = 'permanent'")
        }
        migrator.registerMigration(permanentV5) { db in
            // The v1 rows remain preserved as legacy/incomplete evidence. The table is
            // rebuilt only to remove its global date uniqueness and add complete-header
            // semantics; a partial index enforces one complete Dashboard snapshot per day.
            try db.execute(sql: """
                CREATE TABLE snapshots_v5 (
                    id TEXT PRIMARY KEY NOT NULL,
                    civil_date TEXT NOT NULL CHECK (length(civil_date) = 10),
                    created_at_ms INTEGER NOT NULL,
                    total_cny_minor INTEGER NOT NULL,
                    total_assets_cny_minor INTEGER,
                    total_liabilities_cny_minor INTEGER,
                    net_worth_cny_minor INTEGER,
                    capture_schema TEXT NOT NULL DEFAULT 'foundation_v1',
                    capture_status TEXT NOT NULL DEFAULT 'legacyIncomplete'
                        CHECK (capture_status IN ('legacyIncomplete', 'complete')),
                    is_complete INTEGER NOT NULL DEFAULT 0 CHECK (is_complete IN (0, 1)),
                    CHECK (
                        (is_complete = 0
                            AND capture_status = 'legacyIncomplete'
                            AND total_assets_cny_minor IS NULL
                            AND total_liabilities_cny_minor IS NULL
                            AND net_worth_cny_minor IS NULL)
                        OR
                        (is_complete = 1
                            AND capture_status = 'complete'
                            AND total_assets_cny_minor IS NOT NULL
                            AND total_assets_cny_minor >= 0
                            AND total_liabilities_cny_minor IS NOT NULL
                            AND total_liabilities_cny_minor >= 0
                            AND net_worth_cny_minor IS NOT NULL
                            AND net_worth_cny_minor = total_assets_cny_minor - total_liabilities_cny_minor)
                    )
                )
                """)
            try db.execute(sql: """
                INSERT INTO snapshots_v5 (
                    id, civil_date, created_at_ms, total_cny_minor,
                    total_assets_cny_minor, total_liabilities_cny_minor,
                    net_worth_cny_minor, capture_schema, capture_status, is_complete
                )
                SELECT id, civil_date, created_at_ms, total_cny_minor,
                       NULL, NULL, NULL, 'foundation_v1', 'legacyIncomplete', 0
                FROM snapshots
                """)
            // Copy legacy valuation payloads into a constraint-free staging table.
            // The final child table is created only after the new parent has its
            // production name so its foreign key can never retain a temporary name.
            try db.execute(sql: """
                CREATE TABLE snapshot_valuations_v5_staging AS
                SELECT id, snapshot_id, source_amount_minor, source_currency_code,
                       fx_coefficient, fx_source_currency_code, fx_target_currency_code,
                       converted_cny_minor, provider_identifier, reference_date,
                       fetched_at_ms, is_stale
                FROM snapshot_valuations
                """)
            try db.execute(sql: "DROP TABLE snapshot_valuations")
            try db.execute(sql: "DROP TABLE snapshots")
            try db.execute(sql: "ALTER TABLE snapshots_v5 RENAME TO snapshots")
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
                INSERT INTO snapshot_valuations (
                    id, snapshot_id, source_amount_minor, source_currency_code,
                    fx_coefficient, fx_source_currency_code, fx_target_currency_code,
                    converted_cny_minor, provider_identifier, reference_date,
                    fetched_at_ms, is_stale
                )
                SELECT id, snapshot_id, source_amount_minor, source_currency_code,
                       fx_coefficient, fx_source_currency_code, fx_target_currency_code,
                       converted_cny_minor, provider_identifier, reference_date,
                       fetched_at_ms, is_stale
                FROM snapshot_valuations_v5_staging
                """)
            try db.execute(sql: "DROP TABLE snapshot_valuations_v5_staging")
            try db.execute(sql: """
                CREATE UNIQUE INDEX snapshots_complete_date_unique
                ON snapshots(civil_date)
                WHERE is_complete = 1
                """)
            try db.execute(sql: """
                CREATE INDEX snapshots_complete_history_index
                ON snapshots(is_complete, civil_date, created_at_ms)
                """)

            try db.execute(sql: """
                CREATE TABLE snapshot_items (
                    id TEXT PRIMARY KEY NOT NULL,
                    snapshot_id TEXT NOT NULL REFERENCES snapshots(id) ON DELETE CASCADE,
                    container_id TEXT NOT NULL,
                    container_name TEXT NOT NULL CHECK (length(trim(container_name)) > 0),
                    container_kind TEXT NOT NULL CHECK (container_kind IN (
                        'bankCash', 'stock', 'etf', 'fund',
                        'insurance', 'otherAsset', 'liability'
                    )),
                    is_liability INTEGER NOT NULL CHECK (is_liability IN (0, 1)),
                    original_minor INTEGER NOT NULL CHECK (original_minor >= 0),
                    original_currency_code TEXT NOT NULL CHECK (original_currency_code IN ('CNY', 'USD')),
                    fx_coefficient INTEGER NOT NULL CHECK (fx_coefficient > 0),
                    fx_source_currency_code TEXT NOT NULL CHECK (fx_source_currency_code IN ('CNY', 'USD')),
                    fx_target_currency_code TEXT NOT NULL CHECK (fx_target_currency_code = 'CNY'),
                    converted_cny_minor INTEGER NOT NULL CHECK (converted_cny_minor >= 0),
                    fx_source TEXT NOT NULL CHECK (length(trim(fx_source)) > 0),
                    fx_reference_date TEXT NOT NULL CHECK (length(fx_reference_date) = 10),
                    fx_recorded_at_ms INTEGER NOT NULL,
                    fx_is_manual INTEGER NOT NULL CHECK (fx_is_manual IN (0, 1)),
                    fx_is_stale INTEGER NOT NULL CHECK (fx_is_stale IN (0, 1)),
                    UNIQUE(snapshot_id, container_id),
                    CHECK (is_liability = CASE WHEN container_kind = 'liability' THEN 1 ELSE 0 END),
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
                    )
                )
                """)
            try db.execute(sql: """
                CREATE INDEX snapshot_items_snapshot_index
                ON snapshot_items(snapshot_id, is_liability, container_kind)
                """)
            try db.execute(sql: "UPDATE schema_metadata SET version = 5 WHERE store_kind = 'permanent'")
        }
        migrator.registerMigration(permanentV6) { db in
            try db.execute(sql: """
                CREATE TABLE portfolio_definitions (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
                    base_currency_code TEXT NOT NULL CHECK (base_currency_code = 'CNY'),
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    sort_order INTEGER NOT NULL,
                    UNIQUE(sort_order, id)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE portfolio_security_links (
                    id TEXT PRIMARY KEY NOT NULL,
                    portfolio_id TEXT NOT NULL REFERENCES portfolio_definitions(id) ON DELETE CASCADE,
                    wealth_container_id TEXT NOT NULL REFERENCES asset_containers(id) ON DELETE RESTRICT,
                    symbol TEXT NOT NULL CHECK (length(trim(symbol)) > 0),
                    raw_mic TEXT NOT NULL CHECK (
                        length(raw_mic) = 4 AND raw_mic NOT GLOB '*[^A-Z0-9]*'
                    ),
                    currency_code TEXT NOT NULL CHECK (currency_code IN ('CNY', 'USD')),
                    asset_kind TEXT NOT NULL CHECK (asset_kind IN ('stock', 'etf', 'fund')),
                    sort_order INTEGER NOT NULL,
                    UNIQUE(portfolio_id, wealth_container_id),
                    UNIQUE(portfolio_id, symbol, raw_mic)
                )
                """)
            try db.execute(sql: "CREATE INDEX portfolio_security_links_portfolio_index ON portfolio_security_links(portfolio_id, sort_order, id)")
            try db.execute(sql: """
                CREATE TABLE portfolio_activities (
                    id TEXT PRIMARY KEY NOT NULL,
                    portfolio_id TEXT NOT NULL REFERENCES portfolio_definitions(id) ON DELETE CASCADE,
                    security_link_id TEXT NOT NULL REFERENCES portfolio_security_links(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL CHECK (kind IN ('openingLot', 'buy', 'sell', 'manualSplit')),
                    civil_date TEXT NOT NULL CHECK (length(civil_date) = 10),
                    recorded_at_ms INTEGER NOT NULL,
                    exchange_time_zone_id TEXT NOT NULL CHECK (length(trim(exchange_time_zone_id)) > 0),
                    ledger_entry_id TEXT REFERENCES ledger_transactions(id) ON DELETE SET NULL,
                    quantity_coefficient INTEGER,
                    unit_price_coefficient INTEGER,
                    fee_minor INTEGER,
                    total_original_minor INTEGER,
                    currency_code TEXT CHECK (currency_code IS NULL OR currency_code IN ('CNY', 'USD')),
                    converted_cny_minor INTEGER,
                    fx_coefficient INTEGER,
                    fx_source TEXT,
                    fx_reference_date TEXT,
                    fx_recorded_at_ms INTEGER,
                    fx_is_manual INTEGER CHECK (fx_is_manual IS NULL OR fx_is_manual IN (0, 1)),
                    fx_is_stale INTEGER CHECK (fx_is_stale IS NULL OR fx_is_stale IN (0, 1)),
                    split_from_coefficient INTEGER,
                    split_to_coefficient INTEGER,
                    sanitized_note TEXT CHECK (sanitized_note IS NULL OR length(sanitized_note) <= 500),
                    CHECK (
                        (kind = 'manualSplit'
                            AND quantity_coefficient IS NULL
                            AND unit_price_coefficient IS NULL
                            AND fee_minor IS NULL
                            AND total_original_minor IS NULL
                            AND currency_code IS NULL
                            AND converted_cny_minor IS NULL
                            AND fx_coefficient IS NULL
                            AND fx_source IS NULL
                            AND fx_reference_date IS NULL
                            AND fx_recorded_at_ms IS NULL
                            AND fx_is_manual IS NULL
                            AND fx_is_stale IS NULL
                            AND split_from_coefficient > 0
                            AND split_to_coefficient > 0)
                        OR
                        (kind IN ('openingLot', 'buy', 'sell')
                            AND quantity_coefficient > 0
                            AND total_original_minor >= 0
                            AND converted_cny_minor >= 0
                            AND currency_code IS NOT NULL
                            AND fx_coefficient > 0
                            AND length(trim(fx_source)) > 0
                            AND length(fx_reference_date) = 10
                            AND fx_recorded_at_ms IS NOT NULL
                            AND fx_is_manual IS NOT NULL
                            AND fx_is_stale IS NOT NULL
                            AND split_from_coefficient IS NULL
                            AND split_to_coefficient IS NULL
                            AND ((kind = 'openingLot' AND unit_price_coefficient IS NULL AND fee_minor IS NULL)
                                OR (kind IN ('buy', 'sell') AND unit_price_coefficient >= 0 AND fee_minor >= 0)))
                    )
                )
                """)
            try db.execute(sql: "CREATE INDEX portfolio_activities_replay_index ON portfolio_activities(portfolio_id, security_link_id, civil_date, recorded_at_ms, id)")
            try db.execute(sql: """
                CREATE TABLE portfolio_nav_snapshots (
                    id TEXT PRIMARY KEY NOT NULL,
                    portfolio_id TEXT NOT NULL REFERENCES portfolio_definitions(id) ON DELETE CASCADE,
                    civil_date TEXT NOT NULL CHECK (length(civil_date) = 10),
                    created_at_ms INTEGER NOT NULL,
                    total_cny_minor INTEGER NOT NULL CHECK (total_cny_minor >= 0),
                    is_complete INTEGER NOT NULL CHECK (is_complete = 1),
                    UNIQUE(portfolio_id, civil_date)
                )
                """)
            try db.execute(sql: "CREATE INDEX portfolio_nav_history_index ON portfolio_nav_snapshots(portfolio_id, civil_date, created_at_ms)")
            try db.execute(sql: """
                CREATE TABLE portfolio_nav_snapshot_items (
                    id TEXT PRIMARY KEY NOT NULL,
                    snapshot_id TEXT NOT NULL REFERENCES portfolio_nav_snapshots(id) ON DELETE CASCADE,
                    security_link_id TEXT NOT NULL,
                    quantity_coefficient INTEGER NOT NULL CHECK (quantity_coefficient >= 0),
                    manual_mark_coefficient INTEGER NOT NULL CHECK (manual_mark_coefficient >= 0),
                    original_market_value_minor INTEGER NOT NULL CHECK (original_market_value_minor >= 0),
                    original_currency_code TEXT NOT NULL CHECK (original_currency_code IN ('CNY', 'USD')),
                    fx_coefficient INTEGER NOT NULL CHECK (fx_coefficient > 0),
                    fx_source TEXT NOT NULL CHECK (length(trim(fx_source)) > 0),
                    fx_reference_date TEXT NOT NULL CHECK (length(fx_reference_date) = 10),
                    fx_recorded_at_ms INTEGER NOT NULL,
                    fx_is_manual INTEGER NOT NULL CHECK (fx_is_manual IN (0, 1)),
                    fx_is_stale INTEGER NOT NULL CHECK (fx_is_stale IN (0, 1)),
                    converted_cny_minor INTEGER NOT NULL CHECK (converted_cny_minor >= 0),
                    remaining_cny_basis_minor INTEGER NOT NULL CHECK (remaining_cny_basis_minor >= 0),
                    reconciliation TEXT NOT NULL CHECK (reconciliation IN ('matched', 'quantityMismatch')),
                    UNIQUE(snapshot_id, security_link_id)
                )
                """)
            try db.execute(sql: "UPDATE schema_metadata SET version = 6 WHERE store_kind = 'permanent'")
        }
        migrator.registerMigration(permanentV7) { db in
            for statement in evidenceTables { try db.execute(sql: statement.sql) }
            for target in [EvidenceTarget.ledger(UUID()), .container(UUID()), .portfolioActivity(UUID())] {
                try db.execute(sql: "CREATE INDEX \(target.linkTable)_target ON \(target.linkTable)(\(target.column))")
            }
            try db.execute(sql: "UPDATE schema_metadata SET version = 7 WHERE store_kind = 'permanent'")
        }
        migrator.registerMigration(permanentV8) { db in
            for (_, statement) in LedgerCorrectionSQL.declarations { try db.execute(sql: statement) }
            try db.execute(sql: "UPDATE schema_metadata SET version = 8 WHERE store_kind = 'permanent'")
        }
        return migrator
    }

    // Fixed schema declarations are also the validator's exact constraint contract.
    static var evidenceTables: [(name: String, sql: String)] {
        func uuid(_ name: String) -> String {
            "length(\(name)) = 36 AND \(name) = upper(\(name)) AND substr(\(name),9,1) = '-' AND substr(\(name),14,1) = '-' AND substr(\(name),19,1) = '-' AND substr(\(name),24,1) = '-' AND length(replace(\(name),'-','')) = 32 AND replace(\(name),'-','') NOT GLOB '*[^0-9A-F]*'"
        }
        let hash = "length(sha256) = 64 AND sha256 NOT GLOB '*[^0-9a-f]*'"
        let filename = "length(original_filename) > 0 AND instr(original_filename, char(0)) = 0"
        let documents = """
            CREATE TABLE evidence_documents (
                id TEXT PRIMARY KEY NOT NULL CHECK (\(uuid("id"))),
                original_filename TEXT NOT NULL CHECK (\(filename)),
                relative_reference TEXT NOT NULL UNIQUE CHECK (relative_reference = lower(id) || '.original'),
                byte_count INTEGER NOT NULL CHECK (typeof(byte_count) = 'integer' AND byte_count >= 0),
                sha256 TEXT NOT NULL CHECK (\(hash)),
                copied_at_ms INTEGER NOT NULL CHECK (typeof(copied_at_ms) = 'integer'),
                registered_at_ms INTEGER NOT NULL CHECK (typeof(registered_at_ms) = 'integer')
            )
            """
        var tables = [(name: "evidence_documents", sql: documents)]
        for target in [EvidenceTarget.ledger(UUID()), .container(UUID()), .portfolioActivity(UUID())] {
            tables.append((target.linkTable, """
                CREATE TABLE \(target.linkTable) (
                    document_id TEXT NOT NULL REFERENCES evidence_documents(id) ON DELETE RESTRICT CHECK (\(uuid("document_id"))),
                    \(target.column) TEXT NOT NULL REFERENCES \(target.table)(id) ON DELETE CASCADE CHECK (\(uuid(target.column))),
                    link_id TEXT NOT NULL UNIQUE CHECK (\(uuid("link_id"))),
                    created_at_ms INTEGER NOT NULL CHECK (typeof(created_at_ms) = 'integer'),
                    meaning TEXT NOT NULL CHECK (instr(meaning, char(0)) = 0),
                    PRIMARY KEY (document_id, \(target.column))
                )
                """))
        }
        func inode(_ name: String) -> String {
            "length(\(name)) BETWEEN 1 AND 20 AND \(name) NOT GLOB '*[^0-9]*' AND (\(name) = '0' OR substr(\(name),1,1) != '0') AND (length(\(name)) < 20 OR \(name) <= '18446744073709551615')"
        }
        tables.append(("evidence_import_operations", """
            CREATE TABLE evidence_import_operations (
                operation_id TEXT PRIMARY KEY NOT NULL CHECK (\(uuid("operation_id"))),
                document_id TEXT NOT NULL UNIQUE CHECK (\(uuid("document_id"))),
                ledger_entry_id TEXT CHECK (ledger_entry_id IS NULL OR (\(uuid("ledger_entry_id")))),
                container_id TEXT CHECK (container_id IS NULL OR (\(uuid("container_id")))),
                portfolio_activity_id TEXT CHECK (portfolio_activity_id IS NULL OR (\(uuid("portfolio_activity_id")))),
                intended_meaning TEXT NOT NULL CHECK (instr(intended_meaning, char(0)) = 0),
                original_filename TEXT NOT NULL CHECK (\(filename)),
                relative_reference TEXT NOT NULL UNIQUE CHECK (relative_reference = lower(document_id) || '.original'),
                registered_at_ms INTEGER NOT NULL CHECK (typeof(registered_at_ms) = 'integer'),
                updated_at_ms INTEGER NOT NULL CHECK (typeof(updated_at_ms) = 'integer'),
                state TEXT NOT NULL CHECK (state IN ('registered','stagingOwned','prepared','committed','cancelled','recoveryRequired')),
                root_device INTEGER CHECK (root_device IS NULL OR (typeof(root_device) = 'integer' AND root_device BETWEEN -2147483648 AND 2147483647)),
                root_inode TEXT CHECK (root_inode IS NULL OR (\(inode("root_inode")))),
                file_device INTEGER CHECK (file_device IS NULL OR (typeof(file_device) = 'integer' AND file_device BETWEEN -2147483648 AND 2147483647)),
                file_inode TEXT CHECK (file_inode IS NULL OR (\(inode("file_inode")))),
                byte_count INTEGER CHECK (byte_count IS NULL OR (typeof(byte_count) = 'integer' AND byte_count >= 0)),
                sha256 TEXT CHECK (sha256 IS NULL OR (\(hash))),
                copied_at_ms INTEGER CHECK (copied_at_ms IS NULL OR typeof(copied_at_ms) = 'integer'),
                last_error TEXT CHECK (last_error IS NULL OR last_error IN ('disabled','invalidValue','unsafeRoot','ownerConflict','maintenanceUnavailable','targetMissing','operationConflict','materialUnavailable','relationshipChanged','inconsistentRegistration','recoveryRequired','legacyFormatUnsupported')),
                CHECK ((ledger_entry_id IS NOT NULL) + (container_id IS NOT NULL) + (portfolio_activity_id IS NOT NULL) = 1),
                CHECK ((root_device IS NULL AND root_inode IS NULL AND file_device IS NULL AND file_inode IS NULL)
                    OR (root_device IS NOT NULL AND root_inode IS NOT NULL AND file_device IS NOT NULL AND file_inode IS NOT NULL)),
                CHECK ((byte_count IS NULL AND sha256 IS NULL AND copied_at_ms IS NULL)
                    OR (byte_count IS NOT NULL AND sha256 IS NOT NULL AND copied_at_ms IS NOT NULL)),
                CHECK (state != 'stagingOwned' OR root_device IS NOT NULL),
                CHECK (state NOT IN ('prepared','committed') OR (root_device IS NOT NULL AND byte_count IS NOT NULL))
            )
            """))
        return tables
    }

    private static func backfillNormalizedNames(in db: Database, table: String) throws {
        precondition(table == "categories" || table == "tags")
        let rows = try Row.fetchAll(db, sql: "SELECT id, name FROM \(table) ORDER BY id")
        var used = Set<String>()
        for row in rows {
            let id: String = row["id"]
            let name: String = row["name"]
            let base = (try? LedgerNameNormalization.key(name)) ?? "legacy-empty"
            var key = base
            if used.contains(key) {
                var attempt = 0
                repeat {
                    let suffix = attempt == 0 ? "" : ":\(attempt)"
                    key = "\(base)\u{1f}legacy:\(id.lowercased())\(suffix)"
                    attempt += 1
                } while used.contains(key)
            }
            used.insert(key)
            try db.execute(
                sql: "UPDATE \(table) SET normalized_name = ? WHERE id = ?",
                arguments: [key, id]
            )
        }
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
        migrator.registerMigration(cacheV2) { db in
            try db.execute(sql: """
                CREATE TABLE market_cache_entries (
                    id TEXT PRIMARY KEY NOT NULL,
                    provider_identifier TEXT NOT NULL CHECK (length(provider_identifier) > 0),
                    logical_key TEXT NOT NULL CHECK (length(logical_key) > 0),
                    data_type TEXT NOT NULL CHECK (data_type IN (
                        'latest_quote', 'market_status', 'symbol_search', 'symbol_metadata',
                        'eod_recent', 'eod_historical', 'intraday', 'corporate_action',
                        'derived_heatmap', 'derived_indicator', 'fx_rate'
                    )),
                    payload BLOB NOT NULL,
                    payload_format TEXT NOT NULL CHECK (payload_format = 'validated-domain-json-v1'),
                    byte_size INTEGER NOT NULL CHECK (byte_size >= 0),
                    created_at_ms INTEGER NOT NULL,
                    fetched_at_ms INTEGER NOT NULL,
                    expires_at_ms INTEGER NOT NULL,
                    last_accessed_at_ms INTEGER NOT NULL,
                    source_revision TEXT,
                    entitlement_context TEXT NOT NULL,
                    freshness TEXT NOT NULL CHECK (freshness IN (
                        'realTime', 'delayed', 'endOfDay', 'stale', 'missing', 'unknown'
                    )),
                    deletion_policy TEXT NOT NULL CHECK (deletion_policy IN (
                        'recoverable', 'disconnect', 'termination'
                    )),
                    UNIQUE(provider_identifier, logical_key, data_type)
                )
                """)
            try db.execute(sql: """
                CREATE INDEX market_cache_cleanup_index
                ON market_cache_entries(expires_at_ms, data_type, last_accessed_at_ms)
                """)
            try db.execute(sql: """
                CREATE INDEX market_cache_provider_index
                ON market_cache_entries(provider_identifier, data_type)
                """)
            try db.execute(
                sql: "UPDATE schema_metadata SET version = 2 WHERE store_kind = 'market_cache'"
            )
        }
        return migrator
    }
}
