import GRDB

enum SyntheticFoundationSeeder {
    static let cnyAccountID = "00000000-0000-4000-8000-000000000301"
    static let usdAccountID = "00000000-0000-4000-8000-000000000302"

    static func seedPermanent(_ db: Database) throws {
        try db.execute(sql: """
            INSERT OR IGNORE INTO accounts (id, name, kind, currency_code) VALUES
            ('00000000-0000-4000-8000-000000000301', 'Synthetic CNY Vault', 'bank', 'CNY'),
            ('00000000-0000-4000-8000-000000000302', 'Synthetic USD Sandbox', 'brokerage', 'USD')
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO asset_containers (
                id, account_id, name, kind, primary_currency_code, created_date, updated_date
            ) VALUES (
                '00000000-0000-4000-8000-000000000303',
                '00000000-0000-4000-8000-000000000302',
                'Synthetic Securities Container', 'stock', 'USD', '2026-01-15', '2026-01-15'
            )
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO market_instrument_references (id, symbol, mic, currency_code) VALUES
            ('00000000-0000-4000-8000-000000000304', 'SYN-AUR', 'XSYN', 'USD')
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO assets (id, container_id, name, currency_code, instrument_reference_id) VALUES
            ('00000000-0000-4000-8000-000000000305', '00000000-0000-4000-8000-000000000303', 'Synthetic Aureus Share', 'USD', '00000000-0000-4000-8000-000000000304')
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO wealth_transactions (id, account_id, civil_date, amount_minor, currency_code, type) VALUES
            ('00000000-0000-4000-8000-000000000306', '00000000-0000-4000-8000-000000000301', '2026-01-15', 12345, 'CNY', 'income')
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO holdings (id, account_id, instrument_reference_id, quantity_coefficient, cost_minor, cost_currency_code) VALUES
            ('00000000-0000-4000-8000-000000000307', '00000000-0000-4000-8000-000000000302', '00000000-0000-4000-8000-000000000304', 125000000, 10000, 'USD')
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO trades (id, holding_id, session_date, mic, time_zone_id, quantity_coefficient, price_coefficient, price_currency_code, type) VALUES
            ('00000000-0000-4000-8000-000000000308', '00000000-0000-4000-8000-000000000307', '2026-01-15', 'XSYN', 'Asia/Shanghai', 125000000, 8000000000, 'USD', 'buy')
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO snapshots (id, civil_date, created_at_ms, total_cny_minor) VALUES
            ('00000000-0000-4000-8000-000000000309', '2026-01-15', 1768435200000, 71250)
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO snapshot_valuations (
                id, snapshot_id, source_amount_minor, source_currency_code,
                fx_coefficient, fx_source_currency_code, fx_target_currency_code,
                converted_cny_minor, provider_identifier, reference_date, fetched_at_ms, is_stale
            ) VALUES (
                '00000000-0000-4000-8000-000000000310',
                '00000000-0000-4000-8000-000000000309',
                10000, 'USD', 71250000000, 'USD', 'CNY', 71250,
                'synthetic.stage2.fx', '2026-01-15', 1768435200000, 0
            )
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO portfolios (id, name, base_currency_code) VALUES
            ('00000000-0000-4000-8000-000000000311', 'Synthetic Foundation Portfolio', 'CNY')
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO goals (id, name, target_minor, currency_code, target_date) VALUES
            ('00000000-0000-4000-8000-000000000312', 'Synthetic Foundation Goal', 50000000, 'CNY', '2030-12-31')
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO insurance_policies (id, asset_id, name, premium_minor, currency_code) VALUES
            ('00000000-0000-4000-8000-000000000313', '00000000-0000-4000-8000-000000000305', 'Synthetic Policy Placeholder', 1000, 'USD')
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO categories (id, parent_id, name) VALUES
            ('00000000-0000-4000-8000-000000000314', NULL, 'Synthetic Income')
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO tags (id, name) VALUES
            ('00000000-0000-4000-8000-000000000315', 'synthetic-stage2')
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO transaction_tags (transaction_id, tag_id) VALUES
            ('00000000-0000-4000-8000-000000000306', '00000000-0000-4000-8000-000000000315')
            """)
    }
}
