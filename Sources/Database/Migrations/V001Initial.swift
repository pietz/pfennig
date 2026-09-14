import Foundation
import GRDB

/// The schema. Mirrors spec section 17 table by table; tables are created in
/// dependency order so that foreign keys resolve immediately.
///
/// Before the first public release this is the single schema definition:
/// a change is made here and the development archive is rewritten once, rather
/// than added as a forward migration. Once a schema has shipped publicly,
/// every later change becomes a numbered `v00x_...` migration (spec 47).
enum V001Initial {
    static func migrate(_ db: Database) throws {
        for statement in statements {
            try db.execute(sql: statement)
        }
        try SystemCategories.seed(db)
    }

    static let statements: [String] = [
        // 17.1 business_profiles
        """
        CREATE TABLE business_profiles (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            legal_name TEXT,
            country_code TEXT NOT NULL DEFAULT 'DE',
            tax_number TEXT,
            vat_id TEXT,
            vat_status TEXT NOT NULL,
            vat_accounting_method TEXT NOT NULL,
            ustva_period TEXT NOT NULL,
            business_type TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """,
        // 17.4 categories
        """
        CREATE TABLE categories (
            id TEXT PRIMARY KEY,
            name_de TEXT NOT NULL,
            kind TEXT NOT NULL,
            document_expected INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0,
            archived_at TEXT
        )
        """,
        // 17.3 counterparties
        """
        CREATE TABLE counterparties (
            id TEXT PRIMARY KEY,
            normalized_name TEXT NOT NULL,
            display_name TEXT NOT NULL,
            country_code TEXT,
            vat_id TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """,
        "CREATE UNIQUE INDEX idx_counterparties_normalized ON counterparties(normalized_name)",
        // 17.10 documents
        """
        CREATE TABLE documents (
            id TEXT PRIMARY KEY,
            original_filename TEXT NOT NULL,
            stored_filename TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            mime_type TEXT,
            sha256 TEXT NOT NULL UNIQUE,
            byte_size INTEGER NOT NULL,
            document_type TEXT,
            source TEXT NOT NULL,
            imported_at TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
        """,
        // 17.5 transactions
        """
        CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            business_profile_id TEXT NOT NULL REFERENCES business_profiles(id),
            counterparty_id TEXT REFERENCES counterparties(id),

            direction TEXT NOT NULL,
            transaction_type TEXT NOT NULL,

            title TEXT,
            invoice_number TEXT,
            invoice_date TEXT,
            service_period_start TEXT,
            service_period_end TEXT,
            is_advance_payment INTEGER NOT NULL DEFAULT 0,

            original_currency TEXT NOT NULL DEFAULT 'EUR',
            original_net_minor INTEGER,
            original_tax_minor INTEGER,
            original_gross_minor INTEGER,

            booked_currency TEXT NOT NULL DEFAULT 'EUR',
            booked_net_minor INTEGER,
            booked_tax_minor INTEGER,
            booked_gross_minor INTEGER,
            exchange_rate TEXT,

            eur_year_override INTEGER,

            workflow_status TEXT NOT NULL,
            review_status TEXT NOT NULL,

            notes TEXT,
            deleted_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """,
        // 17.6 bookkeeping_allocations
        """
        CREATE TABLE bookkeeping_allocations (
            id TEXT PRIMARY KEY,
            transaction_id TEXT NOT NULL REFERENCES transactions(id),
            category_id TEXT NOT NULL REFERENCES categories(id),
            amount_minor INTEGER NOT NULL,
            currency TEXT NOT NULL DEFAULT 'EUR',
            description TEXT,
            asset_flag INTEGER NOT NULL DEFAULT 0,
            private_share_percent TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """,
        "CREATE INDEX idx_alloc_transaction ON bookkeeping_allocations(transaction_id)",
        "CREATE INDEX idx_alloc_category ON bookkeeping_allocations(category_id)",
        // 17.7 tax_components
        """
        CREATE TABLE tax_components (
            id TEXT PRIMARY KEY,
            transaction_id TEXT NOT NULL REFERENCES transactions(id),
            kind TEXT NOT NULL,
            rate TEXT,
            net_minor INTEGER NOT NULL,
            tax_minor INTEGER NOT NULL,
            currency TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
        )
        """,
        "CREATE INDEX idx_taxcomp_transaction ON tax_components(transaction_id)",
        // 17.8 tax_assessments
        """
        CREATE TABLE tax_assessments (
            id TEXT PRIMARY KEY,
            transaction_id TEXT NOT NULL REFERENCES transactions(id),

            treatment TEXT NOT NULL,
            customer_type TEXT NOT NULL DEFAULT 'unknown',
            supply_type TEXT NOT NULL DEFAULT 'unknown',
            customer_vat_id TEXT,

            taxable_base_minor INTEGER,
            self_assessed_vat_minor INTEGER,
            currency TEXT NOT NULL DEFAULT 'EUR',

            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """,
        "CREATE UNIQUE INDEX idx_taxassess_transaction ON tax_assessments(transaction_id)",
        // 17.11 transaction_documents
        """
        CREATE TABLE transaction_documents (
            transaction_id TEXT NOT NULL REFERENCES transactions(id),
            document_id TEXT NOT NULL REFERENCES documents(id),
            role TEXT NOT NULL,
            created_at TEXT NOT NULL,
            PRIMARY KEY (transaction_id, document_id)
        )
        """,
        // 17.13 payments
        """
        CREATE TABLE payments (
            id TEXT PRIMARY KEY,
            direction TEXT NOT NULL,
            payment_date TEXT NOT NULL,

            original_currency TEXT NOT NULL,
            original_amount_minor INTEGER NOT NULL,
            booked_currency TEXT NOT NULL DEFAULT 'EUR',
            booked_amount_minor INTEGER,
            exchange_rate TEXT,

            counterparty_name_raw TEXT,
            reference TEXT,
            payment_method TEXT,
            source TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """,
        "CREATE INDEX idx_payments_date ON payments(payment_date)",
        // 17.12 statement_lines
        """
        CREATE TABLE statement_lines (
            id TEXT PRIMARY KEY,
            account_iban TEXT NOT NULL,
            document_id TEXT REFERENCES documents(id),
            line_fingerprint TEXT NOT NULL,
            external_id TEXT,

            booking_date TEXT NOT NULL,
            value_date TEXT,
            amount_minor INTEGER NOT NULL,
            -- The processor fee contained in amount_minor, non-negative, when
            -- the export reports it separately (PayPal, Stripe, Revolut). The
            -- matcher books it; it is not a second movement.
            fee_minor INTEGER,
            currency TEXT NOT NULL,
            counterparty_raw TEXT,
            counterparty_iban TEXT,
            reference TEXT,
            booking_text TEXT,
            raw_json TEXT,

            classification TEXT NOT NULL,
            classification_subtype TEXT,
            payment_id TEXT REFERENCES payments(id),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(account_iban, line_fingerprint)
        )
        """,
        "CREATE INDEX idx_stmt_account_date ON statement_lines(account_iban, booking_date)",
        "CREATE INDEX idx_stmt_classification ON statement_lines(classification)",
        // 17.14 payment_allocations
        """
        CREATE TABLE payment_allocations (
            id TEXT PRIMARY KEY,
            payment_id TEXT NOT NULL REFERENCES payments(id),
            transaction_id TEXT NOT NULL REFERENCES transactions(id),
            allocated_minor INTEGER NOT NULL,
            currency TEXT NOT NULL DEFAULT 'EUR',
            match_method TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
        """,
        "CREATE INDEX idx_payalloc_transaction ON payment_allocations(transaction_id)",
        "CREATE INDEX idx_payalloc_payment ON payment_allocations(payment_id)",
        // 17.16 import_batches
        """
        CREATE TABLE import_batches (
            id TEXT PRIMARY KEY,
            started_at TEXT NOT NULL,
            completed_at TEXT,
            status TEXT NOT NULL,
            file_count INTEGER NOT NULL
        )
        """,
        // 17.17 import_items
        """
        CREATE TABLE import_items (
            id TEXT PRIMARY KEY,
            batch_id TEXT NOT NULL REFERENCES import_batches(id),
            document_id TEXT REFERENCES documents(id),
            original_filename TEXT NOT NULL,
            status TEXT NOT NULL,
            error_code TEXT,
            error_message TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """,
        "CREATE INDEX idx_import_items_batch ON import_items(batch_id)",
        // 17.18 model_runs
        """
        CREATE TABLE model_runs (
            id TEXT PRIMARY KEY,
            import_item_id TEXT REFERENCES import_items(id),
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            operation TEXT NOT NULL,
            prompt_version TEXT NOT NULL,
            schema_version TEXT NOT NULL,
            request_metadata_json TEXT,
            response_json TEXT,
            input_tokens INTEGER, output_tokens INTEGER,
            started_at TEXT NOT NULL,
            completed_at TEXT,
            status TEXT NOT NULL
        )
        """,
        // 17.15 field_provenance
        """
        CREATE TABLE field_provenance (
            id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            field_name TEXT NOT NULL,
            provenance TEXT NOT NULL,
            is_manual_override INTEGER NOT NULL DEFAULT 0,
            source_document_id TEXT REFERENCES documents(id),
            model_run_id TEXT REFERENCES model_runs(id),
            created_at TEXT NOT NULL,
            superseded_at TEXT
        )
        """,
        "CREATE UNIQUE INDEX idx_prov_current ON field_provenance(entity_type, entity_id, field_name) WHERE superseded_at IS NULL",
        // 17.19 proposals
        """
        CREATE TABLE proposals (
            id TEXT PRIMARY KEY,
            import_item_id TEXT REFERENCES import_items(id),
            idempotency_key TEXT NOT NULL UNIQUE,
            kind TEXT NOT NULL,
            operations_json TEXT NOT NULL,
            summary_json TEXT NOT NULL,
            issues_json TEXT NOT NULL,
            policy_decision TEXT NOT NULL,
            status TEXT NOT NULL,
            committed_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """,
        "CREATE INDEX idx_proposals_status ON proposals(status)",
        // 17.20 validation_issues
        """
        CREATE TABLE validation_issues (
            id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            severity TEXT NOT NULL,
            code TEXT NOT NULL,
            message_key TEXT NOT NULL,
            params_json TEXT,
            field_name TEXT,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            resolved_at TEXT
        )
        """,
        "CREATE INDEX idx_issues_entity ON validation_issues(entity_type, entity_id, status)",
        // 17.22 audit_events
        """
        CREATE TABLE audit_events (
            id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            action TEXT NOT NULL,
            actor TEXT NOT NULL,
            proposal_id TEXT,
            before_json TEXT,
            after_json TEXT,
            reason TEXT,
            created_at TEXT NOT NULL
        )
        """,
        "CREATE INDEX idx_audit_entity ON audit_events(entity_type, entity_id)",
        // 17.23 settings
        """
        CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """,
        // submitted_returns: one row per UStVA period the user marked as filed.
        """
        CREATE TABLE submitted_returns (
            id TEXT PRIMARY KEY,
            business_profile_id TEXT NOT NULL REFERENCES business_profiles(id),
            year INTEGER NOT NULL,
            kind TEXT NOT NULL,
            period_index INTEGER NOT NULL,
            submitted_at TEXT NOT NULL,
            payable_minor INTEGER NOT NULL,
            content_hash TEXT NOT NULL,
            created_at TEXT NOT NULL,
            UNIQUE(business_profile_id, year, kind, period_index)
        )
        """,
        // 17.25 derived status view
        """
        CREATE VIEW v_transaction_status AS
        SELECT t.id,
          CASE
            WHEN t.booked_gross_minor IS NULL THEN 'unknown'
            WHEN settled.transaction_id IS NULL THEN 'unpaid'
            WHEN settled.net_allocated = 0 THEN 'refunded'
            WHEN ABS(settled.net_allocated) < ABS(t.booked_gross_minor) THEN 'partiallyPaid'
            ELSE 'paid' END AS payment_status,
          CASE
            WHEN td.doc_count IS NULL AND t.transaction_type IN ('paymentOnly') THEN 'missing'
            WHEN td.doc_count IS NULL THEN 'missing'
            ELSE 'complete' END AS document_status,
          COALESCE(ta.status, 'unknown') AS tax_status
        FROM transactions t
        LEFT JOIN (\(TransactionQueryRules.settledAllocationsSubquery)) settled ON settled.transaction_id = t.id
        LEFT JOIN (SELECT transaction_id, COUNT(*) AS doc_count FROM transaction_documents GROUP BY transaction_id) td ON td.transaction_id = t.id
        LEFT JOIN tax_assessments ta ON ta.transaction_id = t.id
        WHERE t.deleted_at IS NULL
        """
    ]
}
