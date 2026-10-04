SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


--
-- Name: date_in_locked_period(bigint, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.date_in_locked_period(p_entity_id bigint, p_date date) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM accounting_period_locks l
    WHERE l.entity_id = p_entity_id AND (l.status = 0 OR (l.relock_at IS NOT NULL AND l.relock_at <= now())) AND p_date BETWEEN l.starts_on AND l.ends_on
  )
$$;


--
-- Name: enforce_double_entry_check(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_double_entry_check() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_debit  NUMERIC;
  v_credit NUMERIC;
BEGIN
  SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
    INTO v_debit, v_credit
    FROM accounting_journal_entry_lines
   WHERE journal_entry_id = NEW.journal_entry_id;

  IF ABS(v_debit - v_credit) > 0.005 THEN
    RAISE EXCEPTION 'Unbalanced entry (journal_entry_id=%): debit=% credit=%',
      NEW.journal_entry_id, v_debit, v_credit;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: enforce_period_lock_on_entries(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_period_lock_on_entries() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF current_setting('ledgerflow.lock_override', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 1 AND NEW.status = 2
   AND (to_jsonb(NEW) - 'status' - 'updated_at') = (to_jsonb(OLD) - 'status' - 'updated_at') THEN
    RETURN NEW;
  END IF;
  IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.status <> 0 AND date_in_locked_period(OLD.entity_id, OLD.entry_date) THEN
    RAISE EXCEPTION 'entry % is validated and inside a locked period', OLD.id USING ERRCODE = 'raise_exception';
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.status <> 0 AND date_in_locked_period(NEW.entity_id, NEW.entry_date) THEN
    RAISE EXCEPTION 'entry % cannot be validated inside a locked period', NEW.id USING ERRCODE = 'raise_exception';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: enforce_period_lock_on_lines(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_period_lock_on_lines() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF current_setting('ledgerflow.lock_override', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  -- lettering stays possible in a locked period: only these columns may change
  IF TG_OP = 'UPDATE' AND NEW.journal_entry_id = OLD.journal_entry_id
     AND (to_jsonb(NEW) - ARRAY['lettering_id', 'amount_residual', 'updated_at'])
       = (to_jsonb(OLD) - ARRAY['lettering_id', 'amount_residual', 'updated_at']) THEN
    RETURN NEW;
  END IF;
  IF TG_OP IN ('UPDATE', 'DELETE') AND entry_in_locked_period(OLD.journal_entry_id) THEN
    RAISE EXCEPTION 'line % belongs to a validated entry of a locked period', OLD.id USING ERRCODE = 'raise_exception';
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') AND entry_in_locked_period(NEW.journal_entry_id) THEN
    RAISE EXCEPTION 'a line cannot be added to a validated entry of a locked period' USING ERRCODE = 'raise_exception';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: entry_in_locked_period(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.entry_in_locked_period(p_entry_id bigint) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM accounting_journal_entries e
    JOIN accounting_period_locks l ON l.entity_id = e.entity_id AND (l.status = 0 OR (l.relock_at IS NOT NULL AND l.relock_at <= now()))
                                  AND e.entry_date BETWEEN l.starts_on AND l.ends_on
    WHERE e.id = p_entry_id AND e.status <> 0
  )
$$;


--
-- Name: f_unaccent(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f_unaccent(text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    AS $_$
  SELECT public.unaccent('public.unaccent', $1)
$_$;


--
-- Name: prevent_audit_log_modification(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_audit_log_modification() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'accounting_audit_logs are immutable';
END;
$$;


--
-- Name: prevent_bank_reconciliation_report_modification(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_bank_reconciliation_report_modification() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'accounting_bank_reconciliation_reports are immutable';
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounting_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_accounts (
    id bigint NOT NULL,
    code character varying(10) NOT NULL,
    label_fr character varying NOT NULL,
    label_nl character varying,
    account_class integer NOT NULL,
    account_type integer NOT NULL,
    normal_balance integer NOT NULL,
    reconcilable boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    is_leaf boolean DEFAULT true NOT NULL,
    vat_code_default integer,
    parent_id bigint,
    balance_debit numeric(15,2) DEFAULT 0.0,
    balance_credit numeric(15,2) DEFAULT 0.0,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    custom boolean DEFAULT false NOT NULL,
    entity_id bigint NOT NULL,
    fixed_cost boolean DEFAULT false NOT NULL,
    cash_flow_category character varying,
    CONSTRAINT chk_account_class CHECK (((account_class >= 1) AND (account_class <= 7)))
);


--
-- Name: accounting_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_accounts_id_seq OWNED BY public.accounting_accounts.id;


--
-- Name: accounting_accruals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_accruals (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    fiscal_year_id bigint NOT NULL,
    accrual_type integer NOT NULL,
    description character varying NOT NULL,
    total_amount numeric(15,2) NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    pl_account_id bigint NOT NULL,
    accrual_account_id bigint NOT NULL,
    source_journal_entry_id bigint,
    journal_entry_id bigint,
    reversal_entry_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT accruals_amount_positive CHECK ((total_amount > (0)::numeric)),
    CONSTRAINT accruals_period_order CHECK ((period_end >= period_start))
);


--
-- Name: accounting_accruals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_accruals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_accruals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_accruals_id_seq OWNED BY public.accounting_accruals.id;


--
-- Name: accounting_analytical_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_analytical_accounts (
    id bigint NOT NULL,
    analytical_axis_id bigint NOT NULL,
    code character varying(20) NOT NULL,
    label_fr character varying NOT NULL,
    label_nl character varying,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    entity_id bigint NOT NULL
);


--
-- Name: accounting_analytical_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_analytical_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_analytical_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_analytical_accounts_id_seq OWNED BY public.accounting_analytical_accounts.id;


--
-- Name: accounting_analytical_annotations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_analytical_annotations (
    id bigint NOT NULL,
    journal_entry_line_id bigint CONSTRAINT accounting_analytical_annotation_journal_entry_line_id_not_null NOT NULL,
    analytical_axis_id bigint NOT NULL,
    analytical_account_id bigint CONSTRAINT accounting_analytical_annotation_analytical_account_id_not_null NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    entity_id bigint NOT NULL,
    percentage numeric(5,2) DEFAULT 100.0 NOT NULL,
    CONSTRAINT analytical_annotations_percentage_range CHECK (((percentage > (0)::numeric) AND (percentage <= (100)::numeric)))
);


--
-- Name: accounting_analytical_annotations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_analytical_annotations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_analytical_annotations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_analytical_annotations_id_seq OWNED BY public.accounting_analytical_annotations.id;


--
-- Name: accounting_analytical_axes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_analytical_axes (
    id bigint NOT NULL,
    code character varying(10) NOT NULL,
    label_fr character varying NOT NULL,
    label_nl character varying,
    active boolean DEFAULT true NOT NULL,
    required_for_account_classes integer[] DEFAULT '{}'::integer[],
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    entity_id bigint NOT NULL
);


--
-- Name: accounting_analytical_axes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_analytical_axes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_analytical_axes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_analytical_axes_id_seq OWNED BY public.accounting_analytical_axes.id;


--
-- Name: accounting_audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_audit_logs (
    id bigint NOT NULL,
    auditable_type character varying NOT NULL,
    auditable_id bigint NOT NULL,
    action character varying NOT NULL,
    user_id bigint,
    user_email character varying,
    payload jsonb DEFAULT '{}'::jsonb,
    ip_address character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    entity_id bigint,
    previous_hash character varying,
    content_hash character varying,
    reason text,
    user_agent character varying,
    request_id character varying
);


--
-- Name: accounting_audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_audit_logs_id_seq OWNED BY public.accounting_audit_logs.id;


--
-- Name: accounting_bank_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_bank_accounts (
    id bigint NOT NULL,
    journal_id bigint NOT NULL,
    iban character varying NOT NULL,
    bic character varying,
    label_fr character varying NOT NULL,
    currency character varying DEFAULT 'EUR'::character varying NOT NULL,
    balance numeric(15,2) DEFAULT 0.0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    label_nl character varying,
    notes text,
    entity_id bigint NOT NULL
);


--
-- Name: accounting_bank_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_bank_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_bank_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_bank_accounts_id_seq OWNED BY public.accounting_bank_accounts.id;


--
-- Name: accounting_bank_reconciliation_reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_bank_reconciliation_reports (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    bank_account_id bigint NOT NULL,
    as_of date NOT NULL,
    result jsonb DEFAULT '{}'::jsonb NOT NULL,
    content_hash character varying NOT NULL,
    user_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_bank_reconciliation_reports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_bank_reconciliation_reports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_bank_reconciliation_reports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_bank_reconciliation_reports_id_seq OWNED BY public.accounting_bank_reconciliation_reports.id;


--
-- Name: accounting_bank_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_bank_rules (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    name character varying NOT NULL,
    condition_type character varying NOT NULL,
    condition_value character varying NOT NULL,
    account_id bigint NOT NULL,
    partner_id bigint,
    action character varying DEFAULT 'propose'::character varying NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    score integer DEFAULT 80 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_bank_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_bank_rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_bank_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_bank_rules_id_seq OWNED BY public.accounting_bank_rules.id;


--
-- Name: accounting_bank_statements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_bank_statements (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    bank_account_id bigint NOT NULL,
    import_batch_id bigint NOT NULL,
    sequence integer,
    old_balance_date date,
    old_balance numeric(15,2) NOT NULL,
    new_balance_date date,
    new_balance numeric(15,2),
    integrity_gap numeric(15,2) DEFAULT 0.0 NOT NULL,
    chain_gap numeric(15,2),
    status character varying DEFAULT 'ok'::character varying NOT NULL,
    messages jsonb DEFAULT '[]'::jsonb NOT NULL,
    header jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_bank_statements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_bank_statements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_bank_statements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_bank_statements_id_seq OWNED BY public.accounting_bank_statements.id;


--
-- Name: accounting_bank_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_bank_transactions (
    id bigint NOT NULL,
    bank_account_id bigint NOT NULL,
    journal_entry_id bigint,
    transaction_date date NOT NULL,
    value_date date,
    amount numeric(15,2) NOT NULL,
    currency character varying DEFAULT 'EUR'::character varying NOT NULL,
    description character varying,
    reference character varying,
    status integer DEFAULT 0 NOT NULL,
    raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    entity_id bigint NOT NULL,
    statement_id bigint,
    counterparty_name character varying,
    counterparty_iban character varying,
    structured_communication character varying,
    bank_reference character varying,
    transaction_code character varying,
    fingerprint character varying,
    match_data jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: accounting_bank_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_bank_transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_bank_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_bank_transactions_id_seq OWNED BY public.accounting_bank_transactions.id;


--
-- Name: accounting_cash_forecast_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_cash_forecast_items (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    label character varying NOT NULL,
    direction integer DEFAULT 1 NOT NULL,
    amount numeric(15,2) NOT NULL,
    recurrence integer DEFAULT 0 NOT NULL,
    first_date date NOT NULL,
    end_date date,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT cash_forecast_items_amount_positive CHECK ((amount > (0)::numeric))
);


--
-- Name: accounting_cash_forecast_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_cash_forecast_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_cash_forecast_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_cash_forecast_items_id_seq OWNED BY public.accounting_cash_forecast_items.id;


--
-- Name: accounting_consistency_acknowledgements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_consistency_acknowledgements (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    fingerprint character varying NOT NULL,
    comment text NOT NULL,
    user_id bigint,
    acknowledged_at timestamp(6) without time zone CONSTRAINT accounting_consistency_acknowledgement_acknowledged_at_not_null NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_consistency_acknowledgements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_consistency_acknowledgements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_consistency_acknowledgements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_consistency_acknowledgements_id_seq OWNED BY public.accounting_consistency_acknowledgements.id;


--
-- Name: accounting_consistency_findings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_consistency_findings (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    run_id bigint NOT NULL,
    check_id character varying NOT NULL,
    severity character varying NOT NULL,
    fingerprint character varying NOT NULL,
    subject_type character varying,
    subject_id bigint,
    message text NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_consistency_findings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_consistency_findings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_consistency_findings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_consistency_findings_id_seq OWNED BY public.accounting_consistency_findings.id;


--
-- Name: accounting_consistency_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_consistency_runs (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    trigger character varying DEFAULT 'manual'::character varying NOT NULL,
    started_at timestamp(6) without time zone NOT NULL,
    finished_at timestamp(6) without time zone,
    duration_ms integer,
    counts jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors_by_check jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_consistency_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_consistency_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_consistency_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_consistency_runs_id_seq OWNED BY public.accounting_consistency_runs.id;


--
-- Name: accounting_controlled_windows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_controlled_windows (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    opened_by_id bigint NOT NULL,
    closed_by_id bigint,
    purpose character varying NOT NULL,
    reason character varying NOT NULL,
    opens_at timestamp(6) without time zone NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    closed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_controlled_windows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_controlled_windows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_controlled_windows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_controlled_windows_id_seq OWNED BY public.accounting_controlled_windows.id;


--
-- Name: accounting_depreciation_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_depreciation_entries (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    fixed_asset_id bigint NOT NULL,
    fiscal_year_id bigint NOT NULL,
    journal_entry_id bigint NOT NULL,
    amount numeric(15,2) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_depreciation_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_depreciation_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_depreciation_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_depreciation_entries_id_seq OWNED BY public.accounting_depreciation_entries.id;


--
-- Name: accounting_document_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_document_links (
    id bigint NOT NULL,
    document_id bigint NOT NULL,
    target_type character varying NOT NULL,
    target_id bigint NOT NULL,
    created_by_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_document_links_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_document_links_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_document_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_document_links_id_seq OWNED BY public.accounting_document_links.id;


--
-- Name: accounting_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_documents (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    name character varying NOT NULL,
    content_type character varying,
    byte_size bigint NOT NULL,
    sha256 character varying(64) NOT NULL,
    origin integer DEFAULT 0 NOT NULL,
    kind integer DEFAULT 0 NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    search_text text,
    extracted_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    uploaded_by_id bigint,
    retention_until date,
    legal_hold boolean DEFAULT false NOT NULL,
    replaces_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    search_blob text GENERATED ALWAYS AS (lower(public.f_unaccent((((((COALESCE(name, ''::character varying))::text || ' '::text) || COALESCE(search_text, ''::text)) || ' '::text) || COALESCE((jsonb_path_query_array(extracted_data, '$."extraction"."fields".*."value"'::jsonpath))::text, ''::text))))) STORED,
    parent_id bigint,
    integrity_status character varying,
    integrity_checked_at timestamp(6) without time zone,
    legal_hold_reason text
);


--
-- Name: accounting_documents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_documents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_documents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_documents_id_seq OWNED BY public.accounting_documents.id;


--
-- Name: accounting_entry_template_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_entry_template_lines (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    entry_template_id bigint NOT NULL,
    account_id bigint NOT NULL,
    partner_id bigint,
    side integer NOT NULL,
    amount_kind integer NOT NULL,
    amount numeric(15,2),
    percentage numeric(7,3),
    vat_code integer,
    label character varying,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_entry_template_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_entry_template_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_entry_template_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_entry_template_lines_id_seq OWNED BY public.accounting_entry_template_lines.id;


--
-- Name: accounting_entry_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_entry_templates (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    name character varying NOT NULL,
    journal_id bigint NOT NULL,
    description character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_entry_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_entry_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_entry_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_entry_templates_id_seq OWNED BY public.accounting_entry_templates.id;


--
-- Name: accounting_exchange_rates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_exchange_rates (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    currency character varying(3) NOT NULL,
    rate_date date NOT NULL,
    rate numeric(14,6) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_exchange_rates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_exchange_rates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_exchange_rates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_exchange_rates_id_seq OWNED BY public.accounting_exchange_rates.id;


--
-- Name: accounting_fiscal_years; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_fiscal_years (
    id bigint NOT NULL,
    year integer NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    opening_balance numeric(15,2) DEFAULT 0.0,
    closed_at timestamp(6) without time zone,
    closed_by_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    entity_id bigint NOT NULL,
    CONSTRAINT chk_fiscal_year_dates CHECK ((start_date < end_date))
);


--
-- Name: accounting_fiscal_years_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_fiscal_years_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_fiscal_years_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_fiscal_years_id_seq OWNED BY public.accounting_fiscal_years.id;


--
-- Name: accounting_fixed_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_fixed_assets (
    id bigint NOT NULL,
    description character varying NOT NULL,
    acquisition_date date NOT NULL,
    vat_amount_initial numeric(15,2) DEFAULT 0.0 NOT NULL,
    prorata_at_acquisition numeric(5,2) DEFAULT 100.0 NOT NULL,
    asset_category integer DEFAULT 0 NOT NULL,
    disposed_on date,
    invoice_line_id bigint,
    entity_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    acquisition_value numeric(15,2),
    asset_account_id bigint,
    in_service_date date,
    useful_life_years integer,
    residual_value numeric(15,2) DEFAULT 0.0 NOT NULL,
    depreciation_method integer DEFAULT 0 NOT NULL,
    disposal_journal_entry_id bigint,
    disposal_price numeric(15,2)
);


--
-- Name: accounting_fixed_assets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_fixed_assets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_fixed_assets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_fixed_assets_id_seq OWNED BY public.accounting_fixed_assets.id;


--
-- Name: accounting_import_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_import_batches (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    user_id bigint,
    document_id bigint,
    parser character varying NOT NULL,
    source_name character varying,
    file_sha256 character varying NOT NULL,
    result character varying NOT NULL,
    statements_count integer DEFAULT 0 NOT NULL,
    lines_read integer DEFAULT 0 NOT NULL,
    lines_imported integer DEFAULT 0 NOT NULL,
    lines_skipped integer DEFAULT 0 NOT NULL,
    errors_list jsonb DEFAULT '[]'::jsonb NOT NULL,
    warnings_list jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_import_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_import_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_import_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_import_batches_id_seq OWNED BY public.accounting_import_batches.id;


--
-- Name: accounting_intracom_listing_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_intracom_listing_lines (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    intracom_listing_id bigint NOT NULL,
    partner_id bigint NOT NULL,
    code character varying NOT NULL,
    amount numeric(15,2) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_intracom_listing_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_intracom_listing_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_intracom_listing_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_intracom_listing_lines_id_seq OWNED BY public.accounting_intracom_listing_lines.id;


--
-- Name: accounting_intracom_listings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_intracom_listings (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    fiscal_year_id bigint NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_intracom_listings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_intracom_listings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_intracom_listings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_intracom_listings_id_seq OWNED BY public.accounting_intracom_listings.id;


--
-- Name: accounting_invoice_emails; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_invoice_emails (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    invoice_id bigint NOT NULL,
    sent_by_id bigint NOT NULL,
    recipient character varying NOT NULL,
    subject character varying NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    error text,
    sent_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_invoice_emails_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_invoice_emails_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_invoice_emails_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_invoice_emails_id_seq OWNED BY public.accounting_invoice_emails.id;


--
-- Name: accounting_invoice_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_invoice_events (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    invoice_id bigint NOT NULL,
    event_type character varying NOT NULL,
    occurred_at timestamp(6) without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_invoice_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_invoice_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_invoice_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_invoice_events_id_seq OWNED BY public.accounting_invoice_events.id;


--
-- Name: accounting_invoice_line_annotations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_invoice_line_annotations (
    id bigint NOT NULL,
    invoice_line_id bigint NOT NULL,
    analytical_axis_id bigint NOT NULL,
    analytical_account_id bigint CONSTRAINT accounting_invoice_line_annotati_analytical_account_id_not_null NOT NULL,
    entity_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_invoice_line_annotations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_invoice_line_annotations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_invoice_line_annotations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_invoice_line_annotations_id_seq OWNED BY public.accounting_invoice_line_annotations.id;


--
-- Name: accounting_invoice_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_invoice_lines (
    id bigint NOT NULL,
    invoice_id bigint NOT NULL,
    account_id bigint NOT NULL,
    description character varying NOT NULL,
    quantity numeric(10,3) DEFAULT 1.0 NOT NULL,
    unit_price numeric(15,2) DEFAULT 0.0 NOT NULL,
    vat_rate numeric(5,2) DEFAULT 21.0 NOT NULL,
    vat_code integer,
    subtotal_excl_vat numeric(15,2) DEFAULT 0.0 NOT NULL,
    vat_amount numeric(15,2) DEFAULT 0.0 NOT NULL,
    total_incl_vat numeric(15,2) DEFAULT 0.0 NOT NULL,
    "position" integer DEFAULT 1 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    entity_id bigint NOT NULL,
    service_start date,
    service_end date
);


--
-- Name: accounting_invoice_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_invoice_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_invoice_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_invoice_lines_id_seq OWNED BY public.accounting_invoice_lines.id;


--
-- Name: accounting_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_invoices (
    id bigint NOT NULL,
    invoice_type integer DEFAULT 0 NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    invoice_number character varying,
    invoice_date date NOT NULL,
    due_date date,
    currency character varying DEFAULT 'EUR'::character varying NOT NULL,
    subtotal_excl_vat numeric(15,2) DEFAULT 0.0 NOT NULL,
    vat_amount numeric(15,2) DEFAULT 0.0 NOT NULL,
    total_incl_vat numeric(15,2) DEFAULT 0.0 NOT NULL,
    description text,
    notes text,
    external_ref character varying,
    project_id integer,
    partner_id bigint NOT NULL,
    fiscal_year_id bigint NOT NULL,
    journal_entry_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    peppol_id character varying,
    peppol_status integer DEFAULT 0 NOT NULL,
    entity_id bigint NOT NULL,
    journal_id bigint,
    cash_journal_id bigint,
    exchange_rate numeric(10,6) DEFAULT 1.0 NOT NULL,
    vat_treatment integer DEFAULT 0 NOT NULL,
    document_type integer DEFAULT 0 NOT NULL,
    credited_invoice_id bigint,
    recurring_invoice_id bigint,
    revision integer DEFAULT 1 NOT NULL,
    external_digest character varying,
    external_project_name character varying,
    external_budget_line character varying,
    external_state_digest character varying,
    order_reference character varying,
    buyer_reference character varying,
    supplier_reference character varying,
    created_by_id bigint
);


--
-- Name: accounting_invoices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_invoices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_invoices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_invoices_id_seq OWNED BY public.accounting_invoices.id;


--
-- Name: accounting_journal_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_journal_entries (
    id bigint NOT NULL,
    journal_id bigint NOT NULL,
    fiscal_year_id bigint NOT NULL,
    entry_date date NOT NULL,
    reference character varying,
    description character varying,
    status integer DEFAULT 0 NOT NULL,
    source_type character varying,
    source_id bigint,
    reversal_of_id bigint,
    project_id integer,
    external_ref character varying,
    locked_by character varying,
    locked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    entity_id bigint NOT NULL,
    created_by_id bigint,
    auto_reverse_on date,
    reversal_reason character varying,
    vat_regularisation boolean DEFAULT false NOT NULL
);


--
-- Name: accounting_journal_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_journal_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_journal_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_journal_entries_id_seq OWNED BY public.accounting_journal_entries.id;


--
-- Name: accounting_journal_entry_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_journal_entry_lines (
    id bigint NOT NULL,
    journal_entry_id bigint NOT NULL,
    account_id bigint NOT NULL,
    partner_id bigint,
    debit numeric(15,2) DEFAULT 0.0 NOT NULL,
    credit numeric(15,2) DEFAULT 0.0 NOT NULL,
    label character varying,
    vat_code integer,
    vat_amount numeric(15,2),
    currency character varying DEFAULT 'EUR'::character varying NOT NULL,
    amount_currency numeric(15,2),
    exchange_rate numeric(10,6),
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    entity_id bigint NOT NULL,
    invoice_id bigint,
    lettering_id bigint,
    entry_date date,
    amount_residual numeric(15,2) NOT NULL,
    CONSTRAINT chk_at_least_one_side CHECK (((debit > (0)::numeric) OR (credit > (0)::numeric))),
    CONSTRAINT chk_credit_non_negative CHECK ((credit >= (0)::numeric)),
    CONSTRAINT chk_debit_non_negative CHECK ((debit >= (0)::numeric)),
    CONSTRAINT chk_not_both_sides CHECK ((NOT ((debit > (0)::numeric) AND (credit > (0)::numeric))))
);


--
-- Name: accounting_journal_entry_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_journal_entry_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_journal_entry_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_journal_entry_lines_id_seq OWNED BY public.accounting_journal_entry_lines.id;


--
-- Name: accounting_journals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_journals (
    id bigint NOT NULL,
    code character varying(8) NOT NULL,
    label_fr character varying NOT NULL,
    journal_type integer NOT NULL,
    default_account_id bigint,
    sequence_prefix character varying NOT NULL,
    current_sequence integer DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    entity_id bigint NOT NULL
);


--
-- Name: accounting_journals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_journals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_journals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_journals_id_seq OWNED BY public.accounting_journals.id;


--
-- Name: accounting_lettering_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_lettering_events (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    line_id bigint NOT NULL,
    action character varying NOT NULL,
    code character varying NOT NULL,
    user_id bigint,
    auto boolean DEFAULT false NOT NULL,
    reason character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_lettering_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_lettering_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_lettering_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_lettering_events_id_seq OWNED BY public.accounting_lettering_events.id;


--
-- Name: accounting_lettering_suggestions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_lettering_suggestions (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    account_id bigint NOT NULL,
    partner_id bigint,
    line_ids bigint[] NOT NULL,
    score integer NOT NULL,
    rule integer NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    fingerprint character varying NOT NULL,
    decided_by_id bigint,
    decided_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_lettering_suggestions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_lettering_suggestions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_lettering_suggestions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_lettering_suggestions_id_seq OWNED BY public.accounting_lettering_suggestions.id;


--
-- Name: accounting_lettering_write_offs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_lettering_write_offs (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    journal_entry_id bigint NOT NULL,
    line_ids bigint[] NOT NULL,
    created_by_id bigint,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_lettering_write_offs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_lettering_write_offs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_lettering_write_offs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_lettering_write_offs_id_seq OWNED BY public.accounting_lettering_write_offs.id;


--
-- Name: accounting_letterings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_letterings (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    account_id bigint NOT NULL,
    partner_id bigint,
    code character varying NOT NULL,
    lettered_on date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    kind character varying DEFAULT 'full'::character varying NOT NULL,
    auto boolean DEFAULT false NOT NULL,
    reason character varying,
    lettered_by_id bigint
);


--
-- Name: accounting_letterings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_letterings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_letterings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_letterings_id_seq OWNED BY public.accounting_letterings.id;


--
-- Name: accounting_line_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_line_allocations (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    debit_line_id bigint NOT NULL,
    credit_line_id bigint NOT NULL,
    amount numeric(15,2) NOT NULL,
    allocated_on date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_allocation_amount_positive CHECK ((amount > (0)::numeric))
);


--
-- Name: accounting_line_allocations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_line_allocations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_line_allocations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_line_allocations_id_seq OWNED BY public.accounting_line_allocations.id;


--
-- Name: accounting_partners; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_partners (
    id bigint NOT NULL,
    name character varying NOT NULL,
    partner_type integer DEFAULT 0 NOT NULL,
    vat_number character varying,
    email character varying,
    phone character varying,
    street character varying,
    city character varying,
    zip character varying,
    country character varying DEFAULT 'BE'::character varying NOT NULL,
    iban character varying,
    bic character varying,
    active boolean DEFAULT true NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    entity_id bigint NOT NULL,
    payment_terms_days integer DEFAULT 30 NOT NULL,
    peppol_participant_id character varying,
    external_ref character varying
);


--
-- Name: accounting_partners_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_partners_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_partners_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_partners_id_seq OWNED BY public.accounting_partners.id;


--
-- Name: accounting_payment_batch_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_payment_batch_lines (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    payment_batch_id bigint NOT NULL,
    invoice_id bigint NOT NULL,
    amount numeric(15,2) NOT NULL,
    remittance_information character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_payment_batch_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_payment_batch_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_payment_batch_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_payment_batch_lines_id_seq OWNED BY public.accounting_payment_batch_lines.id;


--
-- Name: accounting_payment_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_payment_batches (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    bank_account_id bigint NOT NULL,
    journal_entry_id bigint,
    status integer DEFAULT 0 NOT NULL,
    requested_execution_date date NOT NULL,
    message_id character varying,
    sepa_xml text,
    total_amount numeric(15,2) DEFAULT 0.0 NOT NULL,
    generated_at timestamp(6) without time zone,
    executed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_payment_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_payment_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_payment_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_payment_batches_id_seq OWNED BY public.accounting_payment_batches.id;


--
-- Name: accounting_payment_reminder_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_payment_reminder_items (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    payment_reminder_id bigint NOT NULL,
    invoice_id bigint NOT NULL,
    amount_due numeric(15,2) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_payment_reminder_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_payment_reminder_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_payment_reminder_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_payment_reminder_items_id_seq OWNED BY public.accounting_payment_reminder_items.id;


--
-- Name: accounting_payment_reminders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_payment_reminders (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    partner_id bigint NOT NULL,
    sent_by_id bigint NOT NULL,
    level integer NOT NULL,
    recipient character varying NOT NULL,
    subject character varying NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    error text,
    sent_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_payment_reminders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_payment_reminders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_payment_reminders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_payment_reminders_id_seq OWNED BY public.accounting_payment_reminders.id;


--
-- Name: accounting_peppol_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_peppol_events (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    invoice_id bigint NOT NULL,
    kind integer NOT NULL,
    message text,
    occurred_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_peppol_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_peppol_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_peppol_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_peppol_events_id_seq OWNED BY public.accounting_peppol_events.id;


--
-- Name: accounting_period_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_period_locks (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    kind integer DEFAULT 0 NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    locked_by_id bigint NOT NULL,
    locked_at timestamp(6) without time zone NOT NULL,
    lock_reason character varying,
    unlocked_by_id bigint,
    unlocked_at timestamp(6) without time zone,
    unlock_reason character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    relock_at timestamp(6) without time zone,
    CONSTRAINT chk_period_lock_range CHECK ((ends_on >= starts_on))
);


--
-- Name: accounting_period_locks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_period_locks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_period_locks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_period_locks_id_seq OWNED BY public.accounting_period_locks.id;


--
-- Name: accounting_recurring_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_recurring_entries (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    entry_template_id bigint NOT NULL,
    name character varying NOT NULL,
    frequency integer DEFAULT 0 NOT NULL,
    day_of_month integer,
    starts_on date NOT NULL,
    ends_on date,
    max_occurrences integer,
    occurrences_count integer DEFAULT 0 NOT NULL,
    next_due_on date NOT NULL,
    lead_days integer DEFAULT 0 NOT NULL,
    mode integer DEFAULT 0 NOT NULL,
    base_amount numeric(15,2),
    indexation_percent numeric(6,3),
    indexed_year integer,
    feeds_cash_forecast boolean DEFAULT false NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    blocked_reason character varying,
    post_approved_by_id bigint,
    post_approved_at timestamp(6) without time zone,
    created_by_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_recurring_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_recurring_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_recurring_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_recurring_entries_id_seq OWNED BY public.accounting_recurring_entries.id;


--
-- Name: accounting_recurring_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_recurring_invoices (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    source_invoice_id bigint NOT NULL,
    frequency integer DEFAULT 0 NOT NULL,
    start_on date NOT NULL,
    end_on date,
    active boolean DEFAULT true NOT NULL,
    runs_count integer DEFAULT 0 NOT NULL,
    last_run_on date,
    last_error text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_recurring_invoices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_recurring_invoices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_recurring_invoices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_recurring_invoices_id_seq OWNED BY public.accounting_recurring_invoices.id;


--
-- Name: accounting_recurring_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_recurring_runs (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    recurring_entry_id bigint,
    recurring_name character varying NOT NULL,
    due_on date NOT NULL,
    journal_entry_id bigint,
    status integer DEFAULT 0 NOT NULL,
    amount numeric(15,2),
    error character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_recurring_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_recurring_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_recurring_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_recurring_runs_id_seq OWNED BY public.accounting_recurring_runs.id;


--
-- Name: accounting_vat_account_grid_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_vat_account_grid_rules (
    id bigint NOT NULL,
    sens integer NOT NULL,
    account_prefix character varying NOT NULL,
    base_grid integer NOT NULL,
    credit_note_recap_grid integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_vat_account_grid_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_vat_account_grid_rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_vat_account_grid_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_vat_account_grid_rules_id_seq OWNED BY public.accounting_vat_account_grid_rules.id;


--
-- Name: accounting_vat_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_vat_codes (
    id bigint NOT NULL,
    code character varying NOT NULL,
    label character varying NOT NULL,
    sens integer NOT NULL,
    nature integer NOT NULL,
    rate numeric(5,2),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounting_vat_codes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_vat_codes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_vat_codes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_vat_codes_id_seq OWNED BY public.accounting_vat_codes.id;


--
-- Name: accounting_vat_declarations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_vat_declarations (
    id bigint NOT NULL,
    fiscal_year_id bigint NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    period_type integer DEFAULT 0 NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    grids jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    entity_id bigint NOT NULL
);


--
-- Name: accounting_vat_declarations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_vat_declarations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_vat_declarations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_vat_declarations_id_seq OWNED BY public.accounting_vat_declarations.id;


--
-- Name: accounting_vat_grid_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_vat_grid_mappings (
    id bigint NOT NULL,
    vat_code_id bigint NOT NULL,
    document_type integer NOT NULL,
    base_grid integer,
    due_vat_grid integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deductible_vat_grid integer,
    credit_note_recap_grid integer
);


--
-- Name: accounting_vat_grid_mappings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounting_vat_grid_mappings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounting_vat_grid_mappings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounting_vat_grid_mappings_id_seq OWNED BY public.accounting_vat_grid_mappings.id;


--
-- Name: action_mailbox_inbound_emails; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.action_mailbox_inbound_emails (
    id bigint NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    message_id character varying NOT NULL,
    message_checksum character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: action_mailbox_inbound_emails_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.action_mailbox_inbound_emails_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: action_mailbox_inbound_emails_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.action_mailbox_inbound_emails_id_seq OWNED BY public.action_mailbox_inbound_emails.id;


--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: api_clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_clients (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    name character varying NOT NULL,
    key_digest character varying NOT NULL,
    scopes character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    active boolean DEFAULT true NOT NULL,
    last_used_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    owner_id bigint
);


--
-- Name: api_clients_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.api_clients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_clients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.api_clients_id_seq OWNED BY public.api_clients.id;


--
-- Name: api_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_requests (
    id bigint NOT NULL,
    api_client_id bigint NOT NULL,
    http_method character varying NOT NULL,
    path character varying NOT NULL,
    status integer NOT NULL,
    duration_ms integer,
    external_ref character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: api_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.api_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.api_requests_id_seq OWNED BY public.api_requests.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: custom_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.custom_roles (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    name character varying NOT NULL,
    permissions text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: custom_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.custom_roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: custom_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.custom_roles_id_seq OWNED BY public.custom_roles.id;


--
-- Name: entities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entities (
    id bigint NOT NULL,
    name character varying NOT NULL,
    legal_name character varying NOT NULL,
    vat_number character varying,
    country character varying DEFAULT 'BE'::character varying NOT NULL,
    legal_form character varying,
    address_line1 character varying,
    address_line2 character varying,
    city character varying,
    zip_code character varying,
    active boolean DEFAULT true NOT NULL,
    created_by_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    vat_filing_frequency integer DEFAULT 1 NOT NULL,
    vat_regime integer DEFAULT 0 NOT NULL,
    vat_scheme integer DEFAULT 0 NOT NULL,
    vat_prorata_rate numeric(5,2),
    peppol_access_point integer,
    peppol_participant_id character varying,
    peppol_credentials text,
    peppol_webhook_token character varying,
    budgetflow_enabled boolean DEFAULT false NOT NULL,
    four_eyes boolean DEFAULT false NOT NULL,
    four_eyes_threshold numeric(15,2),
    features jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_only_export boolean DEFAULT false NOT NULL,
    documents_mail_token character varying NOT NULL,
    auto_post_exact_bank_matches boolean DEFAULT false NOT NULL,
    bank_rounding_tolerance numeric(15,2) DEFAULT 0.05 NOT NULL,
    auto_reconcile_exact boolean DEFAULT false NOT NULL
);


--
-- Name: entities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entities_id_seq OWNED BY public.entities.id;


--
-- Name: posted_lines; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.posted_lines AS
 SELECT l.id,
    l.entity_id,
    e.id AS journal_entry_id,
    e.fiscal_year_id,
    e.journal_id,
    e.entry_date,
    e.reference,
    l.account_id,
    l.partner_id,
    l.debit,
    l.credit,
    l.label,
    l.vat_code,
    l.lettering_id,
    l.currency,
    l.amount_currency
   FROM (public.accounting_journal_entry_lines l
     JOIN public.accounting_journal_entries e ON ((e.id = l.journal_entry_id)))
  WHERE (e.status = ANY (ARRAY[1, 2]));


--
-- Name: recovery_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recovery_codes (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    code_digest character varying NOT NULL,
    used_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    kind character varying DEFAULT 'passkey'::character varying NOT NULL
);


--
-- Name: recovery_codes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recovery_codes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recovery_codes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recovery_codes_id_seq OWNED BY public.recovery_codes.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: user_entities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_entities (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    entity_id bigint NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    valid_from date,
    valid_until date,
    journal_ids bigint[],
    custom_role_id bigint
);


--
-- Name: user_entities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_entities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_entities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_entities_id_seq OWNED BY public.user_entities.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) without time zone,
    remember_created_at timestamp(6) without time zone,
    sign_in_count integer DEFAULT 0 NOT NULL,
    current_sign_in_at timestamp(6) without time zone,
    last_sign_in_at timestamp(6) without time zone,
    current_sign_in_ip character varying,
    last_sign_in_ip character varying,
    failed_attempts integer DEFAULT 0 NOT NULL,
    unlock_token character varying,
    locked_at timestamp(6) without time zone,
    role integer DEFAULT 3 NOT NULL,
    full_name character varying DEFAULT ''::character varying NOT NULL,
    locale character varying DEFAULT 'en'::character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    webauthn_id character varying,
    totp_secret character varying,
    totp_enabled_at timestamp(6) without time zone,
    totp_last_step bigint
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.versions (
    id bigint NOT NULL,
    whodunnit character varying,
    created_at timestamp(6) without time zone,
    item_id bigint NOT NULL,
    item_type character varying NOT NULL,
    event character varying NOT NULL,
    object text,
    entity_id bigint
);


--
-- Name: versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.versions_id_seq OWNED BY public.versions.id;


--
-- Name: webauthn_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webauthn_credentials (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    external_id character varying NOT NULL,
    public_key character varying NOT NULL,
    nickname character varying NOT NULL,
    sign_count bigint DEFAULT 0 NOT NULL,
    last_used_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: webauthn_credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.webauthn_credentials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: webauthn_credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.webauthn_credentials_id_seq OWNED BY public.webauthn_credentials.id;


--
-- Name: accounting_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_accounts ALTER COLUMN id SET DEFAULT nextval('public.accounting_accounts_id_seq'::regclass);


--
-- Name: accounting_accruals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_accruals ALTER COLUMN id SET DEFAULT nextval('public.accounting_accruals_id_seq'::regclass);


--
-- Name: accounting_analytical_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_analytical_accounts ALTER COLUMN id SET DEFAULT nextval('public.accounting_analytical_accounts_id_seq'::regclass);


--
-- Name: accounting_analytical_annotations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_analytical_annotations ALTER COLUMN id SET DEFAULT nextval('public.accounting_analytical_annotations_id_seq'::regclass);


--
-- Name: accounting_analytical_axes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_analytical_axes ALTER COLUMN id SET DEFAULT nextval('public.accounting_analytical_axes_id_seq'::regclass);


--
-- Name: accounting_audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_audit_logs ALTER COLUMN id SET DEFAULT nextval('public.accounting_audit_logs_id_seq'::regclass);


--
-- Name: accounting_bank_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_accounts ALTER COLUMN id SET DEFAULT nextval('public.accounting_bank_accounts_id_seq'::regclass);


--
-- Name: accounting_bank_reconciliation_reports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_reconciliation_reports ALTER COLUMN id SET DEFAULT nextval('public.accounting_bank_reconciliation_reports_id_seq'::regclass);


--
-- Name: accounting_bank_rules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_rules ALTER COLUMN id SET DEFAULT nextval('public.accounting_bank_rules_id_seq'::regclass);


--
-- Name: accounting_bank_statements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_statements ALTER COLUMN id SET DEFAULT nextval('public.accounting_bank_statements_id_seq'::regclass);


--
-- Name: accounting_bank_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_transactions ALTER COLUMN id SET DEFAULT nextval('public.accounting_bank_transactions_id_seq'::regclass);


--
-- Name: accounting_cash_forecast_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_cash_forecast_items ALTER COLUMN id SET DEFAULT nextval('public.accounting_cash_forecast_items_id_seq'::regclass);


--
-- Name: accounting_consistency_acknowledgements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_consistency_acknowledgements ALTER COLUMN id SET DEFAULT nextval('public.accounting_consistency_acknowledgements_id_seq'::regclass);


--
-- Name: accounting_consistency_findings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_consistency_findings ALTER COLUMN id SET DEFAULT nextval('public.accounting_consistency_findings_id_seq'::regclass);


--
-- Name: accounting_consistency_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_consistency_runs ALTER COLUMN id SET DEFAULT nextval('public.accounting_consistency_runs_id_seq'::regclass);


--
-- Name: accounting_controlled_windows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_controlled_windows ALTER COLUMN id SET DEFAULT nextval('public.accounting_controlled_windows_id_seq'::regclass);


--
-- Name: accounting_depreciation_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_depreciation_entries ALTER COLUMN id SET DEFAULT nextval('public.accounting_depreciation_entries_id_seq'::regclass);


--
-- Name: accounting_document_links id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_document_links ALTER COLUMN id SET DEFAULT nextval('public.accounting_document_links_id_seq'::regclass);


--
-- Name: accounting_documents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_documents ALTER COLUMN id SET DEFAULT nextval('public.accounting_documents_id_seq'::regclass);


--
-- Name: accounting_entry_template_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_entry_template_lines ALTER COLUMN id SET DEFAULT nextval('public.accounting_entry_template_lines_id_seq'::regclass);


--
-- Name: accounting_entry_templates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_entry_templates ALTER COLUMN id SET DEFAULT nextval('public.accounting_entry_templates_id_seq'::regclass);


--
-- Name: accounting_exchange_rates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_exchange_rates ALTER COLUMN id SET DEFAULT nextval('public.accounting_exchange_rates_id_seq'::regclass);


--
-- Name: accounting_fiscal_years id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_fiscal_years ALTER COLUMN id SET DEFAULT nextval('public.accounting_fiscal_years_id_seq'::regclass);


--
-- Name: accounting_fixed_assets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_fixed_assets ALTER COLUMN id SET DEFAULT nextval('public.accounting_fixed_assets_id_seq'::regclass);


--
-- Name: accounting_import_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_import_batches ALTER COLUMN id SET DEFAULT nextval('public.accounting_import_batches_id_seq'::regclass);


--
-- Name: accounting_intracom_listing_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_intracom_listing_lines ALTER COLUMN id SET DEFAULT nextval('public.accounting_intracom_listing_lines_id_seq'::regclass);


--
-- Name: accounting_intracom_listings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_intracom_listings ALTER COLUMN id SET DEFAULT nextval('public.accounting_intracom_listings_id_seq'::regclass);


--
-- Name: accounting_invoice_emails id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_emails ALTER COLUMN id SET DEFAULT nextval('public.accounting_invoice_emails_id_seq'::regclass);


--
-- Name: accounting_invoice_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_events ALTER COLUMN id SET DEFAULT nextval('public.accounting_invoice_events_id_seq'::regclass);


--
-- Name: accounting_invoice_line_annotations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_line_annotations ALTER COLUMN id SET DEFAULT nextval('public.accounting_invoice_line_annotations_id_seq'::regclass);


--
-- Name: accounting_invoice_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_lines ALTER COLUMN id SET DEFAULT nextval('public.accounting_invoice_lines_id_seq'::regclass);


--
-- Name: accounting_invoices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoices ALTER COLUMN id SET DEFAULT nextval('public.accounting_invoices_id_seq'::regclass);


--
-- Name: accounting_journal_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entries ALTER COLUMN id SET DEFAULT nextval('public.accounting_journal_entries_id_seq'::regclass);


--
-- Name: accounting_journal_entry_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entry_lines ALTER COLUMN id SET DEFAULT nextval('public.accounting_journal_entry_lines_id_seq'::regclass);


--
-- Name: accounting_journals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journals ALTER COLUMN id SET DEFAULT nextval('public.accounting_journals_id_seq'::regclass);


--
-- Name: accounting_lettering_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_events ALTER COLUMN id SET DEFAULT nextval('public.accounting_lettering_events_id_seq'::regclass);


--
-- Name: accounting_lettering_suggestions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_suggestions ALTER COLUMN id SET DEFAULT nextval('public.accounting_lettering_suggestions_id_seq'::regclass);


--
-- Name: accounting_lettering_write_offs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_write_offs ALTER COLUMN id SET DEFAULT nextval('public.accounting_lettering_write_offs_id_seq'::regclass);


--
-- Name: accounting_letterings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_letterings ALTER COLUMN id SET DEFAULT nextval('public.accounting_letterings_id_seq'::regclass);


--
-- Name: accounting_line_allocations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_line_allocations ALTER COLUMN id SET DEFAULT nextval('public.accounting_line_allocations_id_seq'::regclass);


--
-- Name: accounting_partners id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_partners ALTER COLUMN id SET DEFAULT nextval('public.accounting_partners_id_seq'::regclass);


--
-- Name: accounting_payment_batch_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_batch_lines ALTER COLUMN id SET DEFAULT nextval('public.accounting_payment_batch_lines_id_seq'::regclass);


--
-- Name: accounting_payment_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_batches ALTER COLUMN id SET DEFAULT nextval('public.accounting_payment_batches_id_seq'::regclass);


--
-- Name: accounting_payment_reminder_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_reminder_items ALTER COLUMN id SET DEFAULT nextval('public.accounting_payment_reminder_items_id_seq'::regclass);


--
-- Name: accounting_payment_reminders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_reminders ALTER COLUMN id SET DEFAULT nextval('public.accounting_payment_reminders_id_seq'::regclass);


--
-- Name: accounting_peppol_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_peppol_events ALTER COLUMN id SET DEFAULT nextval('public.accounting_peppol_events_id_seq'::regclass);


--
-- Name: accounting_period_locks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_period_locks ALTER COLUMN id SET DEFAULT nextval('public.accounting_period_locks_id_seq'::regclass);


--
-- Name: accounting_recurring_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_entries ALTER COLUMN id SET DEFAULT nextval('public.accounting_recurring_entries_id_seq'::regclass);


--
-- Name: accounting_recurring_invoices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_invoices ALTER COLUMN id SET DEFAULT nextval('public.accounting_recurring_invoices_id_seq'::regclass);


--
-- Name: accounting_recurring_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_runs ALTER COLUMN id SET DEFAULT nextval('public.accounting_recurring_runs_id_seq'::regclass);


--
-- Name: accounting_vat_account_grid_rules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_vat_account_grid_rules ALTER COLUMN id SET DEFAULT nextval('public.accounting_vat_account_grid_rules_id_seq'::regclass);


--
-- Name: accounting_vat_codes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_vat_codes ALTER COLUMN id SET DEFAULT nextval('public.accounting_vat_codes_id_seq'::regclass);


--
-- Name: accounting_vat_declarations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_vat_declarations ALTER COLUMN id SET DEFAULT nextval('public.accounting_vat_declarations_id_seq'::regclass);


--
-- Name: accounting_vat_grid_mappings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_vat_grid_mappings ALTER COLUMN id SET DEFAULT nextval('public.accounting_vat_grid_mappings_id_seq'::regclass);


--
-- Name: action_mailbox_inbound_emails id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_mailbox_inbound_emails ALTER COLUMN id SET DEFAULT nextval('public.action_mailbox_inbound_emails_id_seq'::regclass);


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: api_clients id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_clients ALTER COLUMN id SET DEFAULT nextval('public.api_clients_id_seq'::regclass);


--
-- Name: api_requests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_requests ALTER COLUMN id SET DEFAULT nextval('public.api_requests_id_seq'::regclass);


--
-- Name: custom_roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_roles ALTER COLUMN id SET DEFAULT nextval('public.custom_roles_id_seq'::regclass);


--
-- Name: entities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entities ALTER COLUMN id SET DEFAULT nextval('public.entities_id_seq'::regclass);


--
-- Name: recovery_codes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recovery_codes ALTER COLUMN id SET DEFAULT nextval('public.recovery_codes_id_seq'::regclass);


--
-- Name: user_entities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_entities ALTER COLUMN id SET DEFAULT nextval('public.user_entities_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions ALTER COLUMN id SET DEFAULT nextval('public.versions_id_seq'::regclass);


--
-- Name: webauthn_credentials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webauthn_credentials ALTER COLUMN id SET DEFAULT nextval('public.webauthn_credentials_id_seq'::regclass);


--
-- Name: accounting_accounts accounting_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_accounts
    ADD CONSTRAINT accounting_accounts_pkey PRIMARY KEY (id);


--
-- Name: accounting_accruals accounting_accruals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_accruals
    ADD CONSTRAINT accounting_accruals_pkey PRIMARY KEY (id);


--
-- Name: accounting_analytical_accounts accounting_analytical_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_analytical_accounts
    ADD CONSTRAINT accounting_analytical_accounts_pkey PRIMARY KEY (id);


--
-- Name: accounting_analytical_annotations accounting_analytical_annotations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_analytical_annotations
    ADD CONSTRAINT accounting_analytical_annotations_pkey PRIMARY KEY (id);


--
-- Name: accounting_analytical_axes accounting_analytical_axes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_analytical_axes
    ADD CONSTRAINT accounting_analytical_axes_pkey PRIMARY KEY (id);


--
-- Name: accounting_audit_logs accounting_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_audit_logs
    ADD CONSTRAINT accounting_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: accounting_bank_accounts accounting_bank_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_accounts
    ADD CONSTRAINT accounting_bank_accounts_pkey PRIMARY KEY (id);


--
-- Name: accounting_bank_reconciliation_reports accounting_bank_reconciliation_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_reconciliation_reports
    ADD CONSTRAINT accounting_bank_reconciliation_reports_pkey PRIMARY KEY (id);


--
-- Name: accounting_bank_rules accounting_bank_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_rules
    ADD CONSTRAINT accounting_bank_rules_pkey PRIMARY KEY (id);


--
-- Name: accounting_bank_statements accounting_bank_statements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_statements
    ADD CONSTRAINT accounting_bank_statements_pkey PRIMARY KEY (id);


--
-- Name: accounting_bank_transactions accounting_bank_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_transactions
    ADD CONSTRAINT accounting_bank_transactions_pkey PRIMARY KEY (id);


--
-- Name: accounting_cash_forecast_items accounting_cash_forecast_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_cash_forecast_items
    ADD CONSTRAINT accounting_cash_forecast_items_pkey PRIMARY KEY (id);


--
-- Name: accounting_consistency_acknowledgements accounting_consistency_acknowledgements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_consistency_acknowledgements
    ADD CONSTRAINT accounting_consistency_acknowledgements_pkey PRIMARY KEY (id);


--
-- Name: accounting_consistency_findings accounting_consistency_findings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_consistency_findings
    ADD CONSTRAINT accounting_consistency_findings_pkey PRIMARY KEY (id);


--
-- Name: accounting_consistency_runs accounting_consistency_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_consistency_runs
    ADD CONSTRAINT accounting_consistency_runs_pkey PRIMARY KEY (id);


--
-- Name: accounting_controlled_windows accounting_controlled_windows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_controlled_windows
    ADD CONSTRAINT accounting_controlled_windows_pkey PRIMARY KEY (id);


--
-- Name: accounting_depreciation_entries accounting_depreciation_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_depreciation_entries
    ADD CONSTRAINT accounting_depreciation_entries_pkey PRIMARY KEY (id);


--
-- Name: accounting_document_links accounting_document_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_document_links
    ADD CONSTRAINT accounting_document_links_pkey PRIMARY KEY (id);


--
-- Name: accounting_documents accounting_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_documents
    ADD CONSTRAINT accounting_documents_pkey PRIMARY KEY (id);


--
-- Name: accounting_entry_template_lines accounting_entry_template_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_entry_template_lines
    ADD CONSTRAINT accounting_entry_template_lines_pkey PRIMARY KEY (id);


--
-- Name: accounting_entry_templates accounting_entry_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_entry_templates
    ADD CONSTRAINT accounting_entry_templates_pkey PRIMARY KEY (id);


--
-- Name: accounting_exchange_rates accounting_exchange_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_exchange_rates
    ADD CONSTRAINT accounting_exchange_rates_pkey PRIMARY KEY (id);


--
-- Name: accounting_fiscal_years accounting_fiscal_years_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_fiscal_years
    ADD CONSTRAINT accounting_fiscal_years_pkey PRIMARY KEY (id);


--
-- Name: accounting_fixed_assets accounting_fixed_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_fixed_assets
    ADD CONSTRAINT accounting_fixed_assets_pkey PRIMARY KEY (id);


--
-- Name: accounting_import_batches accounting_import_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_import_batches
    ADD CONSTRAINT accounting_import_batches_pkey PRIMARY KEY (id);


--
-- Name: accounting_intracom_listing_lines accounting_intracom_listing_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_intracom_listing_lines
    ADD CONSTRAINT accounting_intracom_listing_lines_pkey PRIMARY KEY (id);


--
-- Name: accounting_intracom_listings accounting_intracom_listings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_intracom_listings
    ADD CONSTRAINT accounting_intracom_listings_pkey PRIMARY KEY (id);


--
-- Name: accounting_invoice_emails accounting_invoice_emails_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_emails
    ADD CONSTRAINT accounting_invoice_emails_pkey PRIMARY KEY (id);


--
-- Name: accounting_invoice_events accounting_invoice_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_events
    ADD CONSTRAINT accounting_invoice_events_pkey PRIMARY KEY (id);


--
-- Name: accounting_invoice_line_annotations accounting_invoice_line_annotations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_line_annotations
    ADD CONSTRAINT accounting_invoice_line_annotations_pkey PRIMARY KEY (id);


--
-- Name: accounting_invoice_lines accounting_invoice_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_lines
    ADD CONSTRAINT accounting_invoice_lines_pkey PRIMARY KEY (id);


--
-- Name: accounting_invoices accounting_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoices
    ADD CONSTRAINT accounting_invoices_pkey PRIMARY KEY (id);


--
-- Name: accounting_journal_entries accounting_journal_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entries
    ADD CONSTRAINT accounting_journal_entries_pkey PRIMARY KEY (id);


--
-- Name: accounting_journal_entry_lines accounting_journal_entry_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entry_lines
    ADD CONSTRAINT accounting_journal_entry_lines_pkey PRIMARY KEY (id);


--
-- Name: accounting_journals accounting_journals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journals
    ADD CONSTRAINT accounting_journals_pkey PRIMARY KEY (id);


--
-- Name: accounting_lettering_events accounting_lettering_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_events
    ADD CONSTRAINT accounting_lettering_events_pkey PRIMARY KEY (id);


--
-- Name: accounting_lettering_suggestions accounting_lettering_suggestions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_suggestions
    ADD CONSTRAINT accounting_lettering_suggestions_pkey PRIMARY KEY (id);


--
-- Name: accounting_lettering_write_offs accounting_lettering_write_offs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_write_offs
    ADD CONSTRAINT accounting_lettering_write_offs_pkey PRIMARY KEY (id);


--
-- Name: accounting_letterings accounting_letterings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_letterings
    ADD CONSTRAINT accounting_letterings_pkey PRIMARY KEY (id);


--
-- Name: accounting_line_allocations accounting_line_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_line_allocations
    ADD CONSTRAINT accounting_line_allocations_pkey PRIMARY KEY (id);


--
-- Name: accounting_partners accounting_partners_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_partners
    ADD CONSTRAINT accounting_partners_pkey PRIMARY KEY (id);


--
-- Name: accounting_payment_batch_lines accounting_payment_batch_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_batch_lines
    ADD CONSTRAINT accounting_payment_batch_lines_pkey PRIMARY KEY (id);


--
-- Name: accounting_payment_batches accounting_payment_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_batches
    ADD CONSTRAINT accounting_payment_batches_pkey PRIMARY KEY (id);


--
-- Name: accounting_payment_reminder_items accounting_payment_reminder_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_reminder_items
    ADD CONSTRAINT accounting_payment_reminder_items_pkey PRIMARY KEY (id);


--
-- Name: accounting_payment_reminders accounting_payment_reminders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_reminders
    ADD CONSTRAINT accounting_payment_reminders_pkey PRIMARY KEY (id);


--
-- Name: accounting_peppol_events accounting_peppol_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_peppol_events
    ADD CONSTRAINT accounting_peppol_events_pkey PRIMARY KEY (id);


--
-- Name: accounting_period_locks accounting_period_locks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_period_locks
    ADD CONSTRAINT accounting_period_locks_pkey PRIMARY KEY (id);


--
-- Name: accounting_recurring_entries accounting_recurring_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_entries
    ADD CONSTRAINT accounting_recurring_entries_pkey PRIMARY KEY (id);


--
-- Name: accounting_recurring_invoices accounting_recurring_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_invoices
    ADD CONSTRAINT accounting_recurring_invoices_pkey PRIMARY KEY (id);


--
-- Name: accounting_recurring_runs accounting_recurring_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_runs
    ADD CONSTRAINT accounting_recurring_runs_pkey PRIMARY KEY (id);


--
-- Name: accounting_vat_account_grid_rules accounting_vat_account_grid_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_vat_account_grid_rules
    ADD CONSTRAINT accounting_vat_account_grid_rules_pkey PRIMARY KEY (id);


--
-- Name: accounting_vat_codes accounting_vat_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_vat_codes
    ADD CONSTRAINT accounting_vat_codes_pkey PRIMARY KEY (id);


--
-- Name: accounting_vat_declarations accounting_vat_declarations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_vat_declarations
    ADD CONSTRAINT accounting_vat_declarations_pkey PRIMARY KEY (id);


--
-- Name: accounting_vat_grid_mappings accounting_vat_grid_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_vat_grid_mappings
    ADD CONSTRAINT accounting_vat_grid_mappings_pkey PRIMARY KEY (id);


--
-- Name: action_mailbox_inbound_emails action_mailbox_inbound_emails_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_mailbox_inbound_emails
    ADD CONSTRAINT action_mailbox_inbound_emails_pkey PRIMARY KEY (id);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: api_clients api_clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_clients
    ADD CONSTRAINT api_clients_pkey PRIMARY KEY (id);


--
-- Name: api_requests api_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_requests
    ADD CONSTRAINT api_requests_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: custom_roles custom_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_roles
    ADD CONSTRAINT custom_roles_pkey PRIMARY KEY (id);


--
-- Name: entities entities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entities
    ADD CONSTRAINT entities_pkey PRIMARY KEY (id);


--
-- Name: recovery_codes recovery_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recovery_codes
    ADD CONSTRAINT recovery_codes_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: user_entities user_entities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_entities
    ADD CONSTRAINT user_entities_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: versions versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT versions_pkey PRIMARY KEY (id);


--
-- Name: webauthn_credentials webauthn_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webauthn_credentials
    ADD CONSTRAINT webauthn_credentials_pkey PRIMARY KEY (id);


--
-- Name: idx_accounting_fiscal_years_one_open_per_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_accounting_fiscal_years_one_open_per_entity ON public.accounting_fiscal_years USING btree (entity_id) WHERE (status = 0);


--
-- Name: idx_audit_object; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_object ON public.accounting_audit_logs USING btree (auditable_type, auditable_id, created_at);


--
-- Name: idx_bank_transactions_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_bank_transactions_fingerprint ON public.accounting_bank_transactions USING btree (bank_account_id, fingerprint) WHERE (fingerprint IS NOT NULL);


--
-- Name: idx_bank_transactions_on_account_and_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_bank_transactions_on_account_and_ref ON public.accounting_bank_transactions USING btree (bank_account_id, reference) WHERE (reference IS NOT NULL);


--
-- Name: idx_document_links_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_document_links_target ON public.accounting_document_links USING btree (target_type, target_id);


--
-- Name: idx_document_links_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_document_links_unique ON public.accounting_document_links USING btree (document_id, target_type, target_id);


--
-- Name: idx_documents_entity_sha256; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_documents_entity_sha256 ON public.accounting_documents USING btree (entity_id, sha256);


--
-- Name: idx_documents_entity_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_documents_entity_status ON public.accounting_documents USING btree (entity_id, status, created_at);


--
-- Name: idx_documents_integrity_failed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_documents_integrity_failed ON public.accounting_documents USING btree (integrity_status) WHERE ((integrity_status)::text = ANY (ARRAY[('mismatch'::character varying)::text, ('missing'::character varying)::text]));


--
-- Name: idx_documents_search_blob; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_documents_search_blob ON public.accounting_documents USING gin (search_blob public.gin_trgm_ops);


--
-- Name: idx_entries_auto_reverse_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entries_auto_reverse_on ON public.accounting_journal_entries USING btree (auto_reverse_on) WHERE (auto_reverse_on IS NOT NULL);


--
-- Name: idx_entries_entity_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entries_entity_period ON public.accounting_journal_entries USING btree (entity_id, fiscal_year_id, entry_date) WHERE (status = 1);


--
-- Name: idx_entries_journal_reference; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entries_journal_reference ON public.accounting_journal_entries USING btree (journal_id, fiscal_year_id, reference);


--
-- Name: idx_exchange_rates_on_entity_currency_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_exchange_rates_on_entity_currency_date ON public.accounting_exchange_rates USING btree (entity_id, currency, rate_date);


--
-- Name: idx_invoice_line_annotations_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_invoice_line_annotations_uniqueness ON public.accounting_invoice_line_annotations USING btree (invoice_line_id, analytical_axis_id);


--
-- Name: idx_lines_account_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lines_account_date ON public.accounting_journal_entry_lines USING btree (account_id, entry_date, id);


--
-- Name: idx_lines_lettering; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lines_lettering ON public.accounting_journal_entry_lines USING btree (lettering_id) WHERE (lettering_id IS NOT NULL);


--
-- Name: idx_lines_partner_open; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lines_partner_open ON public.accounting_journal_entry_lines USING btree (partner_id, account_id) WHERE (lettering_id IS NULL);


--
-- Name: idx_on_analytical_account_id_287261de69; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_analytical_account_id_287261de69 ON public.accounting_invoice_line_annotations USING btree (analytical_account_id);


--
-- Name: idx_on_analytical_account_id_5dc54f9ad9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_analytical_account_id_5dc54f9ad9 ON public.accounting_analytical_annotations USING btree (analytical_account_id);


--
-- Name: idx_on_analytical_axis_id_ff3e21bbcb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_analytical_axis_id_ff3e21bbcb ON public.accounting_invoice_line_annotations USING btree (analytical_axis_id);


--
-- Name: idx_on_bank_account_id_as_of_1bbd9c6237; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_bank_account_id_as_of_1bbd9c6237 ON public.accounting_bank_reconciliation_reports USING btree (bank_account_id, as_of);


--
-- Name: idx_on_bank_account_id_ef8d5b8375; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_bank_account_id_ef8d5b8375 ON public.accounting_bank_reconciliation_reports USING btree (bank_account_id);


--
-- Name: idx_on_bank_account_id_new_balance_date_4441da131d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_bank_account_id_new_balance_date_4441da131d ON public.accounting_bank_statements USING btree (bank_account_id, new_balance_date);


--
-- Name: idx_on_debit_line_id_credit_line_id_f925f5c66a; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_debit_line_id_credit_line_id_f925f5c66a ON public.accounting_line_allocations USING btree (debit_line_id, credit_line_id);


--
-- Name: idx_on_entity_id_account_id_code_b0055f39aa; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_entity_id_account_id_code_b0055f39aa ON public.accounting_letterings USING btree (entity_id, account_id, code);


--
-- Name: idx_on_entity_id_active_priority_e7ac68ff08; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_entity_id_active_priority_e7ac68ff08 ON public.accounting_bank_rules USING btree (entity_id, active, priority);


--
-- Name: idx_on_entity_id_expires_at_07ed8d110c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_entity_id_expires_at_07ed8d110c ON public.accounting_controlled_windows USING btree (entity_id, expires_at);


--
-- Name: idx_on_entity_id_fingerprint_49aa41669e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_entity_id_fingerprint_49aa41669e ON public.accounting_consistency_findings USING btree (entity_id, fingerprint);


--
-- Name: idx_on_entity_id_fingerprint_e37fdec9cd; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_entity_id_fingerprint_e37fdec9cd ON public.accounting_lettering_suggestions USING btree (entity_id, fingerprint);


--
-- Name: idx_on_entity_id_status_next_due_on_ca6acf9cb4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_entity_id_status_next_due_on_ca6acf9cb4 ON public.accounting_recurring_entries USING btree (entity_id, status, next_due_on);


--
-- Name: idx_on_entity_id_status_score_3232f53987; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_entity_id_status_score_3232f53987 ON public.accounting_lettering_suggestions USING btree (entity_id, status, score);


--
-- Name: idx_on_journal_entry_line_id_307850d4ba; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_journal_entry_line_id_307850d4ba ON public.accounting_analytical_annotations USING btree (journal_entry_line_id);


--
-- Name: idx_on_recurring_entry_id_due_on_121642b48a; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_recurring_entry_id_due_on_121642b48a ON public.accounting_recurring_runs USING btree (recurring_entry_id, due_on);


--
-- Name: idx_period_locks_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_period_locks_active ON public.accounting_period_locks USING btree (entity_id, starts_on, ends_on) WHERE (status = 0);


--
-- Name: idx_vat_account_grid_rules_sens_prefix; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_vat_account_grid_rules_sens_prefix ON public.accounting_vat_account_grid_rules USING btree (sens, account_prefix);


--
-- Name: idx_vat_grid_mappings_code_doctype; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_vat_grid_mappings_code_doctype ON public.accounting_vat_grid_mappings USING btree (vat_code_id, document_type);


--
-- Name: index_accounting_accounts_on_account_class; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_accounts_on_account_class ON public.accounting_accounts USING btree (account_class);


--
-- Name: index_accounting_accounts_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_accounts_on_active ON public.accounting_accounts USING btree (active);


--
-- Name: index_accounting_accounts_on_entity_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_accounts_on_entity_and_code ON public.accounting_accounts USING btree (entity_id, code);


--
-- Name: index_accounting_accounts_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_accounts_on_entity_id ON public.accounting_accounts USING btree (entity_id);


--
-- Name: index_accounting_accounts_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_accounts_on_parent_id ON public.accounting_accounts USING btree (parent_id);


--
-- Name: index_accounting_accruals_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_accruals_on_entity_id ON public.accounting_accruals USING btree (entity_id);


--
-- Name: index_accounting_accruals_on_fiscal_year_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_accruals_on_fiscal_year_id ON public.accounting_accruals USING btree (fiscal_year_id);


--
-- Name: index_accounting_analytical_accounts_on_analytical_axis_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_analytical_accounts_on_analytical_axis_id ON public.accounting_analytical_accounts USING btree (analytical_axis_id);


--
-- Name: index_accounting_analytical_accounts_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_analytical_accounts_on_entity_id ON public.accounting_analytical_accounts USING btree (entity_id);


--
-- Name: index_accounting_analytical_annotations_on_analytical_axis_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_analytical_annotations_on_analytical_axis_id ON public.accounting_analytical_annotations USING btree (analytical_axis_id);


--
-- Name: index_accounting_analytical_annotations_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_analytical_annotations_on_entity_id ON public.accounting_analytical_annotations USING btree (entity_id);


--
-- Name: index_accounting_analytical_axes_on_entity_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_analytical_axes_on_entity_and_code ON public.accounting_analytical_axes USING btree (entity_id, code);


--
-- Name: index_accounting_analytical_axes_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_analytical_axes_on_entity_id ON public.accounting_analytical_axes USING btree (entity_id);


--
-- Name: index_accounting_audit_logs_on_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_audit_logs_on_action ON public.accounting_audit_logs USING btree (action);


--
-- Name: index_accounting_audit_logs_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_audit_logs_on_created_at ON public.accounting_audit_logs USING btree (created_at);


--
-- Name: index_accounting_audit_logs_on_entity_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_audit_logs_on_entity_and_id ON public.accounting_audit_logs USING btree (entity_id, id);


--
-- Name: index_accounting_audit_logs_on_entity_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_audit_logs_on_entity_id_and_created_at ON public.accounting_audit_logs USING btree (entity_id, created_at);


--
-- Name: index_accounting_audit_logs_on_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_audit_logs_on_request_id ON public.accounting_audit_logs USING btree (request_id);


--
-- Name: index_accounting_audit_logs_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_audit_logs_on_user_id ON public.accounting_audit_logs USING btree (user_id);


--
-- Name: index_accounting_bank_accounts_on_entity_and_iban; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_bank_accounts_on_entity_and_iban ON public.accounting_bank_accounts USING btree (entity_id, iban);


--
-- Name: index_accounting_bank_accounts_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_bank_accounts_on_entity_id ON public.accounting_bank_accounts USING btree (entity_id);


--
-- Name: index_accounting_bank_accounts_on_journal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_bank_accounts_on_journal_id ON public.accounting_bank_accounts USING btree (journal_id);


--
-- Name: index_accounting_bank_reconciliation_reports_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_bank_reconciliation_reports_on_entity_id ON public.accounting_bank_reconciliation_reports USING btree (entity_id);


--
-- Name: index_accounting_bank_rules_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_bank_rules_on_account_id ON public.accounting_bank_rules USING btree (account_id);


--
-- Name: index_accounting_bank_rules_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_bank_rules_on_entity_id ON public.accounting_bank_rules USING btree (entity_id);


--
-- Name: index_accounting_bank_rules_on_partner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_bank_rules_on_partner_id ON public.accounting_bank_rules USING btree (partner_id);


--
-- Name: index_accounting_bank_statements_on_bank_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_bank_statements_on_bank_account_id ON public.accounting_bank_statements USING btree (bank_account_id);


--
-- Name: index_accounting_bank_statements_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_bank_statements_on_entity_id ON public.accounting_bank_statements USING btree (entity_id);


--
-- Name: index_accounting_bank_statements_on_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_bank_statements_on_import_batch_id ON public.accounting_bank_statements USING btree (import_batch_id);


--
-- Name: index_accounting_bank_transactions_on_bank_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_bank_transactions_on_bank_account_id ON public.accounting_bank_transactions USING btree (bank_account_id);


--
-- Name: index_accounting_bank_transactions_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_bank_transactions_on_entity_id ON public.accounting_bank_transactions USING btree (entity_id);


--
-- Name: index_accounting_bank_transactions_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_bank_transactions_on_journal_entry_id ON public.accounting_bank_transactions USING btree (journal_entry_id);


--
-- Name: index_accounting_bank_transactions_on_statement_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_bank_transactions_on_statement_id ON public.accounting_bank_transactions USING btree (statement_id);


--
-- Name: index_accounting_cash_forecast_items_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_cash_forecast_items_on_entity_id ON public.accounting_cash_forecast_items USING btree (entity_id);


--
-- Name: index_accounting_consistency_findings_on_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_consistency_findings_on_run_id ON public.accounting_consistency_findings USING btree (run_id);


--
-- Name: index_accounting_consistency_runs_on_entity_id_and_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_consistency_runs_on_entity_id_and_started_at ON public.accounting_consistency_runs USING btree (entity_id, started_at);


--
-- Name: index_accounting_controlled_windows_on_closed_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_controlled_windows_on_closed_by_id ON public.accounting_controlled_windows USING btree (closed_by_id);


--
-- Name: index_accounting_controlled_windows_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_controlled_windows_on_entity_id ON public.accounting_controlled_windows USING btree (entity_id);


--
-- Name: index_accounting_controlled_windows_on_opened_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_controlled_windows_on_opened_by_id ON public.accounting_controlled_windows USING btree (opened_by_id);


--
-- Name: index_accounting_depreciation_entries_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_depreciation_entries_on_entity_id ON public.accounting_depreciation_entries USING btree (entity_id);


--
-- Name: index_accounting_depreciation_entries_on_fiscal_year_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_depreciation_entries_on_fiscal_year_id ON public.accounting_depreciation_entries USING btree (fiscal_year_id);


--
-- Name: index_accounting_depreciation_entries_on_fixed_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_depreciation_entries_on_fixed_asset_id ON public.accounting_depreciation_entries USING btree (fixed_asset_id);


--
-- Name: index_accounting_depreciation_entries_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_depreciation_entries_on_journal_entry_id ON public.accounting_depreciation_entries USING btree (journal_entry_id);


--
-- Name: index_accounting_document_links_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_document_links_on_created_by_id ON public.accounting_document_links USING btree (created_by_id);


--
-- Name: index_accounting_document_links_on_document_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_document_links_on_document_id ON public.accounting_document_links USING btree (document_id);


--
-- Name: index_accounting_documents_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_documents_on_entity_id ON public.accounting_documents USING btree (entity_id);


--
-- Name: index_accounting_documents_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_documents_on_parent_id ON public.accounting_documents USING btree (parent_id);


--
-- Name: index_accounting_documents_on_replaces_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_documents_on_replaces_id ON public.accounting_documents USING btree (replaces_id);


--
-- Name: index_accounting_documents_on_uploaded_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_documents_on_uploaded_by_id ON public.accounting_documents USING btree (uploaded_by_id);


--
-- Name: index_accounting_entry_template_lines_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_entry_template_lines_on_account_id ON public.accounting_entry_template_lines USING btree (account_id);


--
-- Name: index_accounting_entry_template_lines_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_entry_template_lines_on_entity_id ON public.accounting_entry_template_lines USING btree (entity_id);


--
-- Name: index_accounting_entry_template_lines_on_entry_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_entry_template_lines_on_entry_template_id ON public.accounting_entry_template_lines USING btree (entry_template_id);


--
-- Name: index_accounting_entry_template_lines_on_partner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_entry_template_lines_on_partner_id ON public.accounting_entry_template_lines USING btree (partner_id);


--
-- Name: index_accounting_entry_templates_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_entry_templates_on_entity_id ON public.accounting_entry_templates USING btree (entity_id);


--
-- Name: index_accounting_entry_templates_on_entity_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_entry_templates_on_entity_id_and_name ON public.accounting_entry_templates USING btree (entity_id, name);


--
-- Name: index_accounting_entry_templates_on_journal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_entry_templates_on_journal_id ON public.accounting_entry_templates USING btree (journal_id);


--
-- Name: index_accounting_exchange_rates_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_exchange_rates_on_entity_id ON public.accounting_exchange_rates USING btree (entity_id);


--
-- Name: index_accounting_fiscal_years_on_entity_and_year; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_fiscal_years_on_entity_and_year ON public.accounting_fiscal_years USING btree (entity_id, year);


--
-- Name: index_accounting_fiscal_years_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_fiscal_years_on_entity_id ON public.accounting_fiscal_years USING btree (entity_id);


--
-- Name: index_accounting_fixed_assets_on_asset_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_fixed_assets_on_asset_account_id ON public.accounting_fixed_assets USING btree (asset_account_id);


--
-- Name: index_accounting_fixed_assets_on_disposal_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_fixed_assets_on_disposal_journal_entry_id ON public.accounting_fixed_assets USING btree (disposal_journal_entry_id);


--
-- Name: index_accounting_fixed_assets_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_fixed_assets_on_entity_id ON public.accounting_fixed_assets USING btree (entity_id);


--
-- Name: index_accounting_fixed_assets_on_invoice_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_fixed_assets_on_invoice_line_id ON public.accounting_fixed_assets USING btree (invoice_line_id);


--
-- Name: index_accounting_fixed_assets_on_invoice_line_id_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_fixed_assets_on_invoice_line_id_unique ON public.accounting_fixed_assets USING btree (invoice_line_id) WHERE (invoice_line_id IS NOT NULL);


--
-- Name: index_accounting_import_batches_on_document_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_import_batches_on_document_id ON public.accounting_import_batches USING btree (document_id);


--
-- Name: index_accounting_import_batches_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_import_batches_on_entity_id ON public.accounting_import_batches USING btree (entity_id);


--
-- Name: index_accounting_import_batches_on_entity_id_and_file_sha256; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_import_batches_on_entity_id_and_file_sha256 ON public.accounting_import_batches USING btree (entity_id, file_sha256);


--
-- Name: index_accounting_import_batches_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_import_batches_on_user_id ON public.accounting_import_batches USING btree (user_id);


--
-- Name: index_accounting_intracom_listing_lines_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_intracom_listing_lines_on_entity_id ON public.accounting_intracom_listing_lines USING btree (entity_id);


--
-- Name: index_accounting_intracom_listing_lines_on_intracom_listing_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_intracom_listing_lines_on_intracom_listing_id ON public.accounting_intracom_listing_lines USING btree (intracom_listing_id);


--
-- Name: index_accounting_intracom_listing_lines_on_partner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_intracom_listing_lines_on_partner_id ON public.accounting_intracom_listing_lines USING btree (partner_id);


--
-- Name: index_accounting_intracom_listings_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_intracom_listings_on_entity_id ON public.accounting_intracom_listings USING btree (entity_id);


--
-- Name: index_accounting_intracom_listings_on_fiscal_year_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_intracom_listings_on_fiscal_year_id ON public.accounting_intracom_listings USING btree (fiscal_year_id);


--
-- Name: index_accounting_invoice_emails_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_emails_on_entity_id ON public.accounting_invoice_emails USING btree (entity_id);


--
-- Name: index_accounting_invoice_emails_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_emails_on_invoice_id ON public.accounting_invoice_emails USING btree (invoice_id);


--
-- Name: index_accounting_invoice_emails_on_sent_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_emails_on_sent_by_id ON public.accounting_invoice_emails USING btree (sent_by_id);


--
-- Name: index_accounting_invoice_events_on_entity_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_events_on_entity_id_and_id ON public.accounting_invoice_events USING btree (entity_id, id);


--
-- Name: index_accounting_invoice_events_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_events_on_invoice_id ON public.accounting_invoice_events USING btree (invoice_id);


--
-- Name: index_accounting_invoice_line_annotations_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_line_annotations_on_entity_id ON public.accounting_invoice_line_annotations USING btree (entity_id);


--
-- Name: index_accounting_invoice_line_annotations_on_invoice_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_line_annotations_on_invoice_line_id ON public.accounting_invoice_line_annotations USING btree (invoice_line_id);


--
-- Name: index_accounting_invoice_lines_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_lines_on_account_id ON public.accounting_invoice_lines USING btree (account_id);


--
-- Name: index_accounting_invoice_lines_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_lines_on_entity_id ON public.accounting_invoice_lines USING btree (entity_id);


--
-- Name: index_accounting_invoice_lines_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_lines_on_invoice_id ON public.accounting_invoice_lines USING btree (invoice_id);


--
-- Name: index_accounting_invoice_lines_on_invoice_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_lines_on_invoice_id_and_position ON public.accounting_invoice_lines USING btree (invoice_id, "position");


--
-- Name: index_accounting_invoices_on_cash_journal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_cash_journal_id ON public.accounting_invoices USING btree (cash_journal_id);


--
-- Name: index_accounting_invoices_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_created_by_id ON public.accounting_invoices USING btree (created_by_id);


--
-- Name: index_accounting_invoices_on_credited_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_credited_invoice_id ON public.accounting_invoices USING btree (credited_invoice_id);


--
-- Name: index_accounting_invoices_on_entity_and_invoice_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_invoices_on_entity_and_invoice_number ON public.accounting_invoices USING btree (entity_id, invoice_number) WHERE (invoice_number IS NOT NULL);


--
-- Name: index_accounting_invoices_on_entity_and_order_reference; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_entity_and_order_reference ON public.accounting_invoices USING btree (entity_id, order_reference) WHERE (order_reference IS NOT NULL);


--
-- Name: index_accounting_invoices_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_entity_id ON public.accounting_invoices USING btree (entity_id);


--
-- Name: index_accounting_invoices_on_entity_partner_supplier_reference; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_entity_partner_supplier_reference ON public.accounting_invoices USING btree (entity_id, partner_id, supplier_reference) WHERE (supplier_reference IS NOT NULL);


--
-- Name: index_accounting_invoices_on_entity_ref_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_invoices_on_entity_ref_revision ON public.accounting_invoices USING btree (entity_id, external_ref, revision) WHERE (external_digest IS NOT NULL);


--
-- Name: index_accounting_invoices_on_fiscal_year_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_fiscal_year_id ON public.accounting_invoices USING btree (fiscal_year_id);


--
-- Name: index_accounting_invoices_on_invoice_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_invoice_date ON public.accounting_invoices USING btree (invoice_date);


--
-- Name: index_accounting_invoices_on_invoice_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_invoice_type ON public.accounting_invoices USING btree (invoice_type);


--
-- Name: index_accounting_invoices_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_journal_entry_id ON public.accounting_invoices USING btree (journal_entry_id);


--
-- Name: index_accounting_invoices_on_journal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_journal_id ON public.accounting_invoices USING btree (journal_id);


--
-- Name: index_accounting_invoices_on_partner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_partner_id ON public.accounting_invoices USING btree (partner_id);


--
-- Name: index_accounting_invoices_on_peppol_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_invoices_on_peppol_id ON public.accounting_invoices USING btree (peppol_id) WHERE (peppol_id IS NOT NULL);


--
-- Name: index_accounting_invoices_on_recurring_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_recurring_invoice_id ON public.accounting_invoices USING btree (recurring_invoice_id);


--
-- Name: index_accounting_invoices_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_status ON public.accounting_invoices USING btree (status);


--
-- Name: index_accounting_journal_entries_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entries_on_created_by_id ON public.accounting_journal_entries USING btree (created_by_id);


--
-- Name: index_accounting_journal_entries_on_entity_and_reference; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_journal_entries_on_entity_and_reference ON public.accounting_journal_entries USING btree (entity_id, reference) WHERE (reference IS NOT NULL);


--
-- Name: index_accounting_journal_entries_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entries_on_entity_id ON public.accounting_journal_entries USING btree (entity_id);


--
-- Name: index_accounting_journal_entries_on_entry_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entries_on_entry_date ON public.accounting_journal_entries USING btree (entry_date);


--
-- Name: index_accounting_journal_entries_on_fiscal_year_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entries_on_fiscal_year_id ON public.accounting_journal_entries USING btree (fiscal_year_id);


--
-- Name: index_accounting_journal_entries_on_journal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entries_on_journal_id ON public.accounting_journal_entries USING btree (journal_id);


--
-- Name: index_accounting_journal_entries_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entries_on_project_id ON public.accounting_journal_entries USING btree (project_id);


--
-- Name: index_accounting_journal_entries_on_source_type_and_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entries_on_source_type_and_source_id ON public.accounting_journal_entries USING btree (source_type, source_id);


--
-- Name: index_accounting_journal_entries_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entries_on_status ON public.accounting_journal_entries USING btree (status);


--
-- Name: index_accounting_journal_entry_lines_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entry_lines_on_account_id ON public.accounting_journal_entry_lines USING btree (account_id);


--
-- Name: index_accounting_journal_entry_lines_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entry_lines_on_entity_id ON public.accounting_journal_entry_lines USING btree (entity_id);


--
-- Name: index_accounting_journal_entry_lines_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entry_lines_on_invoice_id ON public.accounting_journal_entry_lines USING btree (invoice_id);


--
-- Name: index_accounting_journal_entry_lines_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entry_lines_on_journal_entry_id ON public.accounting_journal_entry_lines USING btree (journal_entry_id);


--
-- Name: index_accounting_journal_entry_lines_on_partner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entry_lines_on_partner_id ON public.accounting_journal_entry_lines USING btree (partner_id);


--
-- Name: index_accounting_journals_on_entity_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_journals_on_entity_and_code ON public.accounting_journals USING btree (entity_id, code);


--
-- Name: index_accounting_journals_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journals_on_entity_id ON public.accounting_journals USING btree (entity_id);


--
-- Name: index_accounting_lettering_events_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_lettering_events_on_entity_id ON public.accounting_lettering_events USING btree (entity_id);


--
-- Name: index_accounting_lettering_events_on_entity_id_and_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_lettering_events_on_entity_id_and_line_id ON public.accounting_lettering_events USING btree (entity_id, line_id);


--
-- Name: index_accounting_lettering_events_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_lettering_events_on_user_id ON public.accounting_lettering_events USING btree (user_id);


--
-- Name: index_accounting_lettering_suggestions_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_lettering_suggestions_on_account_id ON public.accounting_lettering_suggestions USING btree (account_id);


--
-- Name: index_accounting_lettering_suggestions_on_decided_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_lettering_suggestions_on_decided_by_id ON public.accounting_lettering_suggestions USING btree (decided_by_id);


--
-- Name: index_accounting_lettering_suggestions_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_lettering_suggestions_on_entity_id ON public.accounting_lettering_suggestions USING btree (entity_id);


--
-- Name: index_accounting_lettering_suggestions_on_partner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_lettering_suggestions_on_partner_id ON public.accounting_lettering_suggestions USING btree (partner_id);


--
-- Name: index_accounting_lettering_write_offs_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_lettering_write_offs_on_created_by_id ON public.accounting_lettering_write_offs USING btree (created_by_id);


--
-- Name: index_accounting_lettering_write_offs_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_lettering_write_offs_on_entity_id ON public.accounting_lettering_write_offs USING btree (entity_id);


--
-- Name: index_accounting_lettering_write_offs_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_lettering_write_offs_on_journal_entry_id ON public.accounting_lettering_write_offs USING btree (journal_entry_id);


--
-- Name: index_accounting_letterings_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_letterings_on_account_id ON public.accounting_letterings USING btree (account_id);


--
-- Name: index_accounting_letterings_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_letterings_on_entity_id ON public.accounting_letterings USING btree (entity_id);


--
-- Name: index_accounting_letterings_on_lettered_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_letterings_on_lettered_by_id ON public.accounting_letterings USING btree (lettered_by_id);


--
-- Name: index_accounting_letterings_on_partner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_letterings_on_partner_id ON public.accounting_letterings USING btree (partner_id);


--
-- Name: index_accounting_line_allocations_on_credit_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_line_allocations_on_credit_line_id ON public.accounting_line_allocations USING btree (credit_line_id);


--
-- Name: index_accounting_line_allocations_on_debit_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_line_allocations_on_debit_line_id ON public.accounting_line_allocations USING btree (debit_line_id);


--
-- Name: index_accounting_line_allocations_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_line_allocations_on_entity_id ON public.accounting_line_allocations USING btree (entity_id);


--
-- Name: index_accounting_partners_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_partners_on_active ON public.accounting_partners USING btree (active);


--
-- Name: index_accounting_partners_on_entity_and_external_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_partners_on_entity_and_external_ref ON public.accounting_partners USING btree (entity_id, external_ref) WHERE (external_ref IS NOT NULL);


--
-- Name: index_accounting_partners_on_entity_and_vat_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_partners_on_entity_and_vat_number ON public.accounting_partners USING btree (entity_id, vat_number) WHERE (vat_number IS NOT NULL);


--
-- Name: index_accounting_partners_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_partners_on_entity_id ON public.accounting_partners USING btree (entity_id);


--
-- Name: index_accounting_partners_on_partner_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_partners_on_partner_type ON public.accounting_partners USING btree (partner_type);


--
-- Name: index_accounting_payment_batch_lines_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_payment_batch_lines_on_entity_id ON public.accounting_payment_batch_lines USING btree (entity_id);


--
-- Name: index_accounting_payment_batch_lines_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_payment_batch_lines_on_invoice_id ON public.accounting_payment_batch_lines USING btree (invoice_id);


--
-- Name: index_accounting_payment_batch_lines_on_payment_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_payment_batch_lines_on_payment_batch_id ON public.accounting_payment_batch_lines USING btree (payment_batch_id);


--
-- Name: index_accounting_payment_batches_on_bank_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_payment_batches_on_bank_account_id ON public.accounting_payment_batches USING btree (bank_account_id);


--
-- Name: index_accounting_payment_batches_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_payment_batches_on_entity_id ON public.accounting_payment_batches USING btree (entity_id);


--
-- Name: index_accounting_payment_batches_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_payment_batches_on_journal_entry_id ON public.accounting_payment_batches USING btree (journal_entry_id);


--
-- Name: index_accounting_payment_batches_on_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_payment_batches_on_message_id ON public.accounting_payment_batches USING btree (message_id);


--
-- Name: index_accounting_payment_reminder_items_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_payment_reminder_items_on_entity_id ON public.accounting_payment_reminder_items USING btree (entity_id);


--
-- Name: index_accounting_payment_reminder_items_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_payment_reminder_items_on_invoice_id ON public.accounting_payment_reminder_items USING btree (invoice_id);


--
-- Name: index_accounting_payment_reminder_items_on_payment_reminder_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_payment_reminder_items_on_payment_reminder_id ON public.accounting_payment_reminder_items USING btree (payment_reminder_id);


--
-- Name: index_accounting_payment_reminders_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_payment_reminders_on_entity_id ON public.accounting_payment_reminders USING btree (entity_id);


--
-- Name: index_accounting_payment_reminders_on_partner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_payment_reminders_on_partner_id ON public.accounting_payment_reminders USING btree (partner_id);


--
-- Name: index_accounting_payment_reminders_on_sent_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_payment_reminders_on_sent_by_id ON public.accounting_payment_reminders USING btree (sent_by_id);


--
-- Name: index_accounting_peppol_events_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_peppol_events_on_entity_id ON public.accounting_peppol_events USING btree (entity_id);


--
-- Name: index_accounting_peppol_events_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_peppol_events_on_invoice_id ON public.accounting_peppol_events USING btree (invoice_id);


--
-- Name: index_accounting_peppol_events_on_invoice_id_and_occurred_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_peppol_events_on_invoice_id_and_occurred_at ON public.accounting_peppol_events USING btree (invoice_id, occurred_at);


--
-- Name: index_accounting_period_locks_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_period_locks_on_entity_id ON public.accounting_period_locks USING btree (entity_id);


--
-- Name: index_accounting_period_locks_on_locked_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_period_locks_on_locked_by_id ON public.accounting_period_locks USING btree (locked_by_id);


--
-- Name: index_accounting_period_locks_on_unlocked_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_period_locks_on_unlocked_by_id ON public.accounting_period_locks USING btree (unlocked_by_id);


--
-- Name: index_accounting_recurring_entries_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_recurring_entries_on_created_by_id ON public.accounting_recurring_entries USING btree (created_by_id);


--
-- Name: index_accounting_recurring_entries_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_recurring_entries_on_entity_id ON public.accounting_recurring_entries USING btree (entity_id);


--
-- Name: index_accounting_recurring_entries_on_entry_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_recurring_entries_on_entry_template_id ON public.accounting_recurring_entries USING btree (entry_template_id);


--
-- Name: index_accounting_recurring_entries_on_post_approved_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_recurring_entries_on_post_approved_by_id ON public.accounting_recurring_entries USING btree (post_approved_by_id);


--
-- Name: index_accounting_recurring_invoices_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_recurring_invoices_on_entity_id ON public.accounting_recurring_invoices USING btree (entity_id);


--
-- Name: index_accounting_recurring_invoices_on_source_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_recurring_invoices_on_source_invoice_id ON public.accounting_recurring_invoices USING btree (source_invoice_id);


--
-- Name: index_accounting_recurring_runs_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_recurring_runs_on_entity_id ON public.accounting_recurring_runs USING btree (entity_id);


--
-- Name: index_accounting_recurring_runs_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_recurring_runs_on_journal_entry_id ON public.accounting_recurring_runs USING btree (journal_entry_id);


--
-- Name: index_accounting_recurring_runs_on_recurring_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_recurring_runs_on_recurring_entry_id ON public.accounting_recurring_runs USING btree (recurring_entry_id);


--
-- Name: index_accounting_vat_codes_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_vat_codes_on_code ON public.accounting_vat_codes USING btree (code);


--
-- Name: index_accounting_vat_declarations_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_vat_declarations_on_entity_id ON public.accounting_vat_declarations USING btree (entity_id);


--
-- Name: index_accounting_vat_declarations_on_fiscal_year_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_vat_declarations_on_fiscal_year_id ON public.accounting_vat_declarations USING btree (fiscal_year_id);


--
-- Name: index_accounting_vat_grid_mappings_on_vat_code_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_vat_grid_mappings_on_vat_code_id ON public.accounting_vat_grid_mappings USING btree (vat_code_id);


--
-- Name: index_action_mailbox_inbound_emails_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_action_mailbox_inbound_emails_uniqueness ON public.action_mailbox_inbound_emails USING btree (message_id, message_checksum);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_analytical_accounts_on_axis_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_analytical_accounts_on_axis_and_code ON public.accounting_analytical_accounts USING btree (analytical_axis_id, code);


--
-- Name: index_analytical_annotations_on_line_axis_account; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_analytical_annotations_on_line_axis_account ON public.accounting_analytical_annotations USING btree (journal_entry_line_id, analytical_axis_id, analytical_account_id);


--
-- Name: index_api_clients_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_clients_on_entity_id ON public.api_clients USING btree (entity_id);


--
-- Name: index_api_clients_on_key_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_clients_on_key_digest ON public.api_clients USING btree (key_digest);


--
-- Name: index_api_clients_on_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_clients_on_owner_id ON public.api_clients USING btree (owner_id);


--
-- Name: index_api_requests_on_api_client_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_requests_on_api_client_id_and_created_at ON public.api_requests USING btree (api_client_id, created_at);


--
-- Name: index_consistency_acks_on_entity_and_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_consistency_acks_on_entity_and_fingerprint ON public.accounting_consistency_acknowledgements USING btree (entity_id, fingerprint);


--
-- Name: index_custom_roles_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_custom_roles_on_entity_id ON public.custom_roles USING btree (entity_id);


--
-- Name: index_custom_roles_on_entity_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_custom_roles_on_entity_id_and_name ON public.custom_roles USING btree (entity_id, name);


--
-- Name: index_depreciation_entries_on_asset_and_fiscal_year; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_depreciation_entries_on_asset_and_fiscal_year ON public.accounting_depreciation_entries USING btree (fixed_asset_id, fiscal_year_id);


--
-- Name: index_entities_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entities_on_created_by_id ON public.entities USING btree (created_by_id);


--
-- Name: index_entities_on_documents_mail_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_entities_on_documents_mail_token ON public.entities USING btree (documents_mail_token);


--
-- Name: index_entities_on_peppol_participant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_entities_on_peppol_participant_id ON public.entities USING btree (peppol_participant_id) WHERE (peppol_participant_id IS NOT NULL);


--
-- Name: index_entities_on_peppol_webhook_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_entities_on_peppol_webhook_token ON public.entities USING btree (peppol_webhook_token);


--
-- Name: index_entities_on_vat_number_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_entities_on_vat_number_unique ON public.entities USING btree (vat_number) WHERE (vat_number IS NOT NULL);


--
-- Name: index_recovery_codes_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recovery_codes_on_user_id ON public.recovery_codes USING btree (user_id);


--
-- Name: index_recovery_codes_on_user_id_and_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recovery_codes_on_user_id_and_kind ON public.recovery_codes USING btree (user_id, kind);


--
-- Name: index_user_entities_on_custom_role_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_entities_on_custom_role_id ON public.user_entities USING btree (custom_role_id);


--
-- Name: index_user_entities_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_entities_on_entity_id ON public.user_entities USING btree (entity_id);


--
-- Name: index_user_entities_on_user_and_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_entities_on_user_and_entity ON public.user_entities USING btree (user_id, entity_id);


--
-- Name: index_user_entities_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_entities_on_user_id ON public.user_entities USING btree (user_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: index_users_on_unlock_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_unlock_token ON public.users USING btree (unlock_token);


--
-- Name: index_users_on_webauthn_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_webauthn_id ON public.users USING btree (webauthn_id);


--
-- Name: index_versions_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_versions_on_entity_id ON public.versions USING btree (entity_id);


--
-- Name: index_versions_on_item_type_and_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_versions_on_item_type_and_item_id ON public.versions USING btree (item_type, item_id);


--
-- Name: index_webauthn_credentials_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_webauthn_credentials_on_external_id ON public.webauthn_credentials USING btree (external_id);


--
-- Name: index_webauthn_credentials_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_webauthn_credentials_on_user_id ON public.webauthn_credentials USING btree (user_id);


--
-- Name: index_webauthn_credentials_on_user_id_and_nickname; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_webauthn_credentials_on_user_id_and_nickname ON public.webauthn_credentials USING btree (user_id, nickname);


--
-- Name: accounting_audit_logs enforce_audit_log_immutability; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER enforce_audit_log_immutability BEFORE DELETE OR UPDATE ON public.accounting_audit_logs FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_modification();


--
-- Name: accounting_bank_reconciliation_reports enforce_bank_reconciliation_report_immutability; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER enforce_bank_reconciliation_report_immutability BEFORE DELETE OR UPDATE ON public.accounting_bank_reconciliation_reports FOR EACH ROW EXECUTE FUNCTION public.prevent_bank_reconciliation_report_modification();


--
-- Name: accounting_journal_entry_lines enforce_double_entry; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER enforce_double_entry AFTER INSERT OR UPDATE ON public.accounting_journal_entry_lines DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION public.enforce_double_entry_check();


--
-- Name: accounting_journal_entries enforce_period_lock_entries; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER enforce_period_lock_entries BEFORE INSERT OR DELETE OR UPDATE ON public.accounting_journal_entries FOR EACH ROW EXECUTE FUNCTION public.enforce_period_lock_on_entries();


--
-- Name: accounting_journal_entry_lines enforce_period_lock_lines; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER enforce_period_lock_lines BEFORE INSERT OR DELETE OR UPDATE ON public.accounting_journal_entry_lines FOR EACH ROW EXECUTE FUNCTION public.enforce_period_lock_on_lines();


--
-- Name: accounting_invoices fk_rails_0010c52c65; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoices
    ADD CONSTRAINT fk_rails_0010c52c65 FOREIGN KEY (cash_journal_id) REFERENCES public.accounting_journals(id);


--
-- Name: accounting_invoice_emails fk_rails_00a167c998; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_emails
    ADD CONSTRAINT fk_rails_00a167c998 FOREIGN KEY (invoice_id) REFERENCES public.accounting_invoices(id);


--
-- Name: accounting_recurring_runs fk_rails_020f47ceee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_runs
    ADD CONSTRAINT fk_rails_020f47ceee FOREIGN KEY (recurring_entry_id) REFERENCES public.accounting_recurring_entries(id) ON DELETE SET NULL;


--
-- Name: accounting_entry_template_lines fk_rails_03540d0728; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_entry_template_lines
    ADD CONSTRAINT fk_rails_03540d0728 FOREIGN KEY (account_id) REFERENCES public.accounting_accounts(id);


--
-- Name: accounting_bank_statements fk_rails_04d068db3c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_statements
    ADD CONSTRAINT fk_rails_04d068db3c FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_payment_batches fk_rails_0bc5bca68a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_batches
    ADD CONSTRAINT fk_rails_0bc5bca68a FOREIGN KEY (journal_entry_id) REFERENCES public.accounting_journal_entries(id);


--
-- Name: accounting_invoice_lines fk_rails_0ef5226c55; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_lines
    ADD CONSTRAINT fk_rails_0ef5226c55 FOREIGN KEY (invoice_id) REFERENCES public.accounting_invoices(id);


--
-- Name: accounting_analytical_axes fk_rails_13dea0cb3e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_analytical_axes
    ADD CONSTRAINT fk_rails_13dea0cb3e FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_vat_declarations fk_rails_14867a239f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_vat_declarations
    ADD CONSTRAINT fk_rails_14867a239f FOREIGN KEY (fiscal_year_id) REFERENCES public.accounting_fiscal_years(id);


--
-- Name: accounting_journal_entries fk_rails_15d7ff9705; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entries
    ADD CONSTRAINT fk_rails_15d7ff9705 FOREIGN KEY (fiscal_year_id) REFERENCES public.accounting_fiscal_years(id);


--
-- Name: accounting_entry_template_lines fk_rails_16b413916b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_entry_template_lines
    ADD CONSTRAINT fk_rails_16b413916b FOREIGN KEY (entry_template_id) REFERENCES public.accounting_entry_templates(id) ON DELETE CASCADE;


--
-- Name: accounting_letterings fk_rails_17df05ba4f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_letterings
    ADD CONSTRAINT fk_rails_17df05ba4f FOREIGN KEY (lettered_by_id) REFERENCES public.users(id);


--
-- Name: accounting_partners fk_rails_18e4531b08; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_partners
    ADD CONSTRAINT fk_rails_18e4531b08 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_bank_rules fk_rails_1c0ebe51cb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_rules
    ADD CONSTRAINT fk_rails_1c0ebe51cb FOREIGN KEY (account_id) REFERENCES public.accounting_accounts(id);


--
-- Name: accounting_journal_entry_lines fk_rails_1e6c3311fa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entry_lines
    ADD CONSTRAINT fk_rails_1e6c3311fa FOREIGN KEY (journal_entry_id) REFERENCES public.accounting_journal_entries(id);


--
-- Name: accounting_entry_templates fk_rails_209ac7afcb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_entry_templates
    ADD CONSTRAINT fk_rails_209ac7afcb FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_bank_accounts fk_rails_215e10200e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_accounts
    ADD CONSTRAINT fk_rails_215e10200e FOREIGN KEY (journal_id) REFERENCES public.accounting_journals(id);


--
-- Name: custom_roles fk_rails_2167468372; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_roles
    ADD CONSTRAINT fk_rails_2167468372 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_period_locks fk_rails_216c0a1533; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_period_locks
    ADD CONSTRAINT fk_rails_216c0a1533 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_invoice_events fk_rails_21a060b812; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_events
    ADD CONSTRAINT fk_rails_21a060b812 FOREIGN KEY (invoice_id) REFERENCES public.accounting_invoices(id);


--
-- Name: accounting_lettering_suggestions fk_rails_252f372366; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_suggestions
    ADD CONSTRAINT fk_rails_252f372366 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_import_batches fk_rails_2592d87f1d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_import_batches
    ADD CONSTRAINT fk_rails_2592d87f1d FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: accounting_invoice_line_annotations fk_rails_2671676b6d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_line_annotations
    ADD CONSTRAINT fk_rails_2671676b6d FOREIGN KEY (invoice_line_id) REFERENCES public.accounting_invoice_lines(id);


--
-- Name: accounting_analytical_annotations fk_rails_2f1aa54d01; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_analytical_annotations
    ADD CONSTRAINT fk_rails_2f1aa54d01 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_lettering_write_offs fk_rails_2f86761346; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_write_offs
    ADD CONSTRAINT fk_rails_2f86761346 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_invoice_emails fk_rails_310b9a27ad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_emails
    ADD CONSTRAINT fk_rails_310b9a27ad FOREIGN KEY (sent_by_id) REFERENCES public.users(id);


--
-- Name: accounting_bank_statements fk_rails_31c90e7265; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_statements
    ADD CONSTRAINT fk_rails_31c90e7265 FOREIGN KEY (bank_account_id) REFERENCES public.accounting_bank_accounts(id);


--
-- Name: accounting_import_batches fk_rails_32015dce50; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_import_batches
    ADD CONSTRAINT fk_rails_32015dce50 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_documents fk_rails_32af54cabb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_documents
    ADD CONSTRAINT fk_rails_32af54cabb FOREIGN KEY (parent_id) REFERENCES public.accounting_documents(id) ON DELETE SET NULL;


--
-- Name: accounting_exchange_rates fk_rails_349168c3df; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_exchange_rates
    ADD CONSTRAINT fk_rails_349168c3df FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_invoice_line_annotations fk_rails_35cd3761f9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_line_annotations
    ADD CONSTRAINT fk_rails_35cd3761f9 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_recurring_entries fk_rails_363e936719; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_entries
    ADD CONSTRAINT fk_rails_363e936719 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_accounts fk_rails_3656d9eddb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_accounts
    ADD CONSTRAINT fk_rails_3656d9eddb FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_lettering_suggestions fk_rails_3b7eb4f554; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_suggestions
    ADD CONSTRAINT fk_rails_3b7eb4f554 FOREIGN KEY (decided_by_id) REFERENCES public.users(id);


--
-- Name: accounting_document_links fk_rails_3df36a68ba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_document_links
    ADD CONSTRAINT fk_rails_3df36a68ba FOREIGN KEY (document_id) REFERENCES public.accounting_documents(id);


--
-- Name: accounting_invoice_line_annotations fk_rails_3f22d8b430; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_line_annotations
    ADD CONSTRAINT fk_rails_3f22d8b430 FOREIGN KEY (analytical_axis_id) REFERENCES public.accounting_analytical_axes(id);


--
-- Name: accounting_payment_reminder_items fk_rails_40a5661100; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_reminder_items
    ADD CONSTRAINT fk_rails_40a5661100 FOREIGN KEY (invoice_id) REFERENCES public.accounting_invoices(id);


--
-- Name: accounting_journal_entry_lines fk_rails_42f8a23db1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entry_lines
    ADD CONSTRAINT fk_rails_42f8a23db1 FOREIGN KEY (invoice_id) REFERENCES public.accounting_invoices(id);


--
-- Name: accounting_depreciation_entries fk_rails_4416ad5edd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_depreciation_entries
    ADD CONSTRAINT fk_rails_4416ad5edd FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_fixed_assets fk_rails_44960acfb0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_fixed_assets
    ADD CONSTRAINT fk_rails_44960acfb0 FOREIGN KEY (invoice_line_id) REFERENCES public.accounting_invoice_lines(id);


--
-- Name: accounting_invoices fk_rails_470177bd08; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoices
    ADD CONSTRAINT fk_rails_470177bd08 FOREIGN KEY (credited_invoice_id) REFERENCES public.accounting_invoices(id);


--
-- Name: accounting_entry_template_lines fk_rails_477c89b68c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_entry_template_lines
    ADD CONSTRAINT fk_rails_477c89b68c FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_invoices fk_rails_479b19d12c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoices
    ADD CONSTRAINT fk_rails_479b19d12c FOREIGN KEY (fiscal_year_id) REFERENCES public.accounting_fiscal_years(id);


--
-- Name: accounting_analytical_annotations fk_rails_4883ca45d6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_analytical_annotations
    ADD CONSTRAINT fk_rails_4883ca45d6 FOREIGN KEY (journal_entry_line_id) REFERENCES public.accounting_journal_entry_lines(id);


--
-- Name: accounting_payment_reminders fk_rails_4d0dea3e8f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_reminders
    ADD CONSTRAINT fk_rails_4d0dea3e8f FOREIGN KEY (sent_by_id) REFERENCES public.users(id);


--
-- Name: accounting_bank_rules fk_rails_56cc6f71fd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_rules
    ADD CONSTRAINT fk_rails_56cc6f71fd FOREIGN KEY (partner_id) REFERENCES public.accounting_partners(id);


--
-- Name: accounting_analytical_accounts fk_rails_59baa8ed4d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_analytical_accounts
    ADD CONSTRAINT fk_rails_59baa8ed4d FOREIGN KEY (analytical_axis_id) REFERENCES public.accounting_analytical_axes(id);


--
-- Name: accounting_documents fk_rails_5ad0383653; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_documents
    ADD CONSTRAINT fk_rails_5ad0383653 FOREIGN KEY (replaces_id) REFERENCES public.accounting_documents(id);


--
-- Name: user_entities fk_rails_5adfb6b489; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_entities
    ADD CONSTRAINT fk_rails_5adfb6b489 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: accounting_bank_transactions fk_rails_5c6e43e656; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_transactions
    ADD CONSTRAINT fk_rails_5c6e43e656 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_controlled_windows fk_rails_5d9749f6a8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_controlled_windows
    ADD CONSTRAINT fk_rails_5d9749f6a8 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_documents fk_rails_5f348b6a57; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_documents
    ADD CONSTRAINT fk_rails_5f348b6a57 FOREIGN KEY (uploaded_by_id) REFERENCES public.users(id);


--
-- Name: accounting_analytical_accounts fk_rails_67d9b95568; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_analytical_accounts
    ADD CONSTRAINT fk_rails_67d9b95568 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_invoices fk_rails_67f38d74d3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoices
    ADD CONSTRAINT fk_rails_67f38d74d3 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_journal_entry_lines fk_rails_6f6e1949f4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entry_lines
    ADD CONSTRAINT fk_rails_6f6e1949f4 FOREIGN KEY (partner_id) REFERENCES public.accounting_partners(id);


--
-- Name: accounting_payment_reminder_items fk_rails_708d3ff286; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_reminder_items
    ADD CONSTRAINT fk_rails_708d3ff286 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_intracom_listing_lines fk_rails_70ee9c6548; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_intracom_listing_lines
    ADD CONSTRAINT fk_rails_70ee9c6548 FOREIGN KEY (partner_id) REFERENCES public.accounting_partners(id);


--
-- Name: accounting_intracom_listings fk_rails_720bd52763; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_intracom_listings
    ADD CONSTRAINT fk_rails_720bd52763 FOREIGN KEY (fiscal_year_id) REFERENCES public.accounting_fiscal_years(id);


--
-- Name: accounting_payment_batches fk_rails_73ac73592a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_batches
    ADD CONSTRAINT fk_rails_73ac73592a FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_recurring_entries fk_rails_75a5595564; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_entries
    ADD CONSTRAINT fk_rails_75a5595564 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: accounting_recurring_entries fk_rails_760f537da9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_entries
    ADD CONSTRAINT fk_rails_760f537da9 FOREIGN KEY (entry_template_id) REFERENCES public.accounting_entry_templates(id);


--
-- Name: accounting_bank_rules fk_rails_77c6b626d4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_rules
    ADD CONSTRAINT fk_rails_77c6b626d4 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: api_requests fk_rails_7d5aab56e7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_requests
    ADD CONSTRAINT fk_rails_7d5aab56e7 FOREIGN KEY (api_client_id) REFERENCES public.api_clients(id);


--
-- Name: accounting_journal_entry_lines fk_rails_804019e4cc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entry_lines
    ADD CONSTRAINT fk_rails_804019e4cc FOREIGN KEY (account_id) REFERENCES public.accounting_accounts(id);


--
-- Name: accounting_invoices fk_rails_82184e0761; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoices
    ADD CONSTRAINT fk_rails_82184e0761 FOREIGN KEY (journal_entry_id) REFERENCES public.accounting_journal_entries(id);


--
-- Name: entities fk_rails_828926881c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entities
    ADD CONSTRAINT fk_rails_828926881c FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: accounting_recurring_invoices fk_rails_8736d3c032; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_invoices
    ADD CONSTRAINT fk_rails_8736d3c032 FOREIGN KEY (source_invoice_id) REFERENCES public.accounting_invoices(id);


--
-- Name: accounting_fixed_assets fk_rails_89ceae2139; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_fixed_assets
    ADD CONSTRAINT fk_rails_89ceae2139 FOREIGN KEY (disposal_journal_entry_id) REFERENCES public.accounting_journal_entries(id);


--
-- Name: accounting_line_allocations fk_rails_8bda82b65e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_line_allocations
    ADD CONSTRAINT fk_rails_8bda82b65e FOREIGN KEY (debit_line_id) REFERENCES public.accounting_journal_entry_lines(id);


--
-- Name: accounting_line_allocations fk_rails_8d50efd843; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_line_allocations
    ADD CONSTRAINT fk_rails_8d50efd843 FOREIGN KEY (credit_line_id) REFERENCES public.accounting_journal_entry_lines(id);


--
-- Name: accounting_journal_entries fk_rails_8d8da34615; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entries
    ADD CONSTRAINT fk_rails_8d8da34615 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: user_entities fk_rails_8e87e2e2aa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_entities
    ADD CONSTRAINT fk_rails_8e87e2e2aa FOREIGN KEY (custom_role_id) REFERENCES public.custom_roles(id) ON DELETE RESTRICT;


--
-- Name: accounting_import_batches fk_rails_8fab1a57a6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_import_batches
    ADD CONSTRAINT fk_rails_8fab1a57a6 FOREIGN KEY (document_id) REFERENCES public.accounting_documents(id);


--
-- Name: accounting_recurring_entries fk_rails_902421d7af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_entries
    ADD CONSTRAINT fk_rails_902421d7af FOREIGN KEY (post_approved_by_id) REFERENCES public.users(id);


--
-- Name: accounting_invoices fk_rails_9168abe1d0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoices
    ADD CONSTRAINT fk_rails_9168abe1d0 FOREIGN KEY (recurring_invoice_id) REFERENCES public.accounting_recurring_invoices(id);


--
-- Name: accounting_invoices fk_rails_93cf61efdd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoices
    ADD CONSTRAINT fk_rails_93cf61efdd FOREIGN KEY (journal_id) REFERENCES public.accounting_journals(id);


--
-- Name: accounting_invoices fk_rails_9602ee956d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoices
    ADD CONSTRAINT fk_rails_9602ee956d FOREIGN KEY (partner_id) REFERENCES public.accounting_partners(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: accounting_journals fk_rails_9aaf5b2621; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journals
    ADD CONSTRAINT fk_rails_9aaf5b2621 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_depreciation_entries fk_rails_9e0e230664; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_depreciation_entries
    ADD CONSTRAINT fk_rails_9e0e230664 FOREIGN KEY (fiscal_year_id) REFERENCES public.accounting_fiscal_years(id);


--
-- Name: accounting_payment_batch_lines fk_rails_a27948dec1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_batch_lines
    ADD CONSTRAINT fk_rails_a27948dec1 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: webauthn_credentials fk_rails_a4355aef77; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webauthn_credentials
    ADD CONSTRAINT fk_rails_a4355aef77 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: accounting_period_locks fk_rails_a58d738482; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_period_locks
    ADD CONSTRAINT fk_rails_a58d738482 FOREIGN KEY (unlocked_by_id) REFERENCES public.users(id);


--
-- Name: accounting_entry_templates fk_rails_a85a054ffc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_entry_templates
    ADD CONSTRAINT fk_rails_a85a054ffc FOREIGN KEY (journal_id) REFERENCES public.accounting_journals(id);


--
-- Name: api_clients fk_rails_aadf4d1f14; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_clients
    ADD CONSTRAINT fk_rails_aadf4d1f14 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_invoice_emails fk_rails_ac5f94ed94; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_emails
    ADD CONSTRAINT fk_rails_ac5f94ed94 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_analytical_annotations fk_rails_addec3672a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_analytical_annotations
    ADD CONSTRAINT fk_rails_addec3672a FOREIGN KEY (analytical_account_id) REFERENCES public.accounting_analytical_accounts(id);


--
-- Name: accounting_vat_declarations fk_rails_af4787f084; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_vat_declarations
    ADD CONSTRAINT fk_rails_af4787f084 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_bank_transactions fk_rails_b1db769153; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_transactions
    ADD CONSTRAINT fk_rails_b1db769153 FOREIGN KEY (bank_account_id) REFERENCES public.accounting_bank_accounts(id);


--
-- Name: accounting_lettering_events fk_rails_b37f1265d5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_events
    ADD CONSTRAINT fk_rails_b37f1265d5 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: accounting_line_allocations fk_rails_b66f2461eb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_line_allocations
    ADD CONSTRAINT fk_rails_b66f2461eb FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_payment_reminders fk_rails_b7ad850a2e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_reminders
    ADD CONSTRAINT fk_rails_b7ad850a2e FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_lettering_write_offs fk_rails_b803c3de6f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_write_offs
    ADD CONSTRAINT fk_rails_b803c3de6f FOREIGN KEY (journal_entry_id) REFERENCES public.accounting_journal_entries(id) ON DELETE CASCADE;


--
-- Name: accounting_bank_accounts fk_rails_bd15e59b6a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_accounts
    ADD CONSTRAINT fk_rails_bd15e59b6a FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_lettering_suggestions fk_rails_beefef422f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_suggestions
    ADD CONSTRAINT fk_rails_beefef422f FOREIGN KEY (account_id) REFERENCES public.accounting_accounts(id);


--
-- Name: accounting_journal_entry_lines fk_rails_bf2911afa6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entry_lines
    ADD CONSTRAINT fk_rails_bf2911afa6 FOREIGN KEY (lettering_id) REFERENCES public.accounting_letterings(id);


--
-- Name: accounting_depreciation_entries fk_rails_c32703c58c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_depreciation_entries
    ADD CONSTRAINT fk_rails_c32703c58c FOREIGN KEY (fixed_asset_id) REFERENCES public.accounting_fixed_assets(id);


--
-- Name: accounting_payment_batch_lines fk_rails_c341f8f34d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_batch_lines
    ADD CONSTRAINT fk_rails_c341f8f34d FOREIGN KEY (payment_batch_id) REFERENCES public.accounting_payment_batches(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: accounting_recurring_invoices fk_rails_c3df00e397; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_invoices
    ADD CONSTRAINT fk_rails_c3df00e397 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_invoice_events fk_rails_c545c3aa7e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_events
    ADD CONSTRAINT fk_rails_c545c3aa7e FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_letterings fk_rails_c7d391d5f5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_letterings
    ADD CONSTRAINT fk_rails_c7d391d5f5 FOREIGN KEY (account_id) REFERENCES public.accounting_accounts(id);


--
-- Name: accounting_fixed_assets fk_rails_c7d3e0d904; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_fixed_assets
    ADD CONSTRAINT fk_rails_c7d3e0d904 FOREIGN KEY (asset_account_id) REFERENCES public.accounting_accounts(id);


--
-- Name: accounting_payment_reminders fk_rails_c7d51f3532; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_reminders
    ADD CONSTRAINT fk_rails_c7d51f3532 FOREIGN KEY (partner_id) REFERENCES public.accounting_partners(id);


--
-- Name: accounting_lettering_suggestions fk_rails_c7e1bb19c6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_suggestions
    ADD CONSTRAINT fk_rails_c7e1bb19c6 FOREIGN KEY (partner_id) REFERENCES public.accounting_partners(id);


--
-- Name: accounting_journal_entry_lines fk_rails_ccc90aef29; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entry_lines
    ADD CONSTRAINT fk_rails_ccc90aef29 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_fixed_assets fk_rails_cd5d96ebe8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_fixed_assets
    ADD CONSTRAINT fk_rails_cd5d96ebe8 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_peppol_events fk_rails_cdf528e0a8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_peppol_events
    ADD CONSTRAINT fk_rails_cdf528e0a8 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: recovery_codes fk_rails_cf7d76c04b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recovery_codes
    ADD CONSTRAINT fk_rails_cf7d76c04b FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: accounting_invoice_lines fk_rails_d08162bbbf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_lines
    ADD CONSTRAINT fk_rails_d08162bbbf FOREIGN KEY (account_id) REFERENCES public.accounting_accounts(id);


--
-- Name: accounting_recurring_runs fk_rails_d08db517d9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_runs
    ADD CONSTRAINT fk_rails_d08db517d9 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_documents fk_rails_d1eb99157d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_documents
    ADD CONSTRAINT fk_rails_d1eb99157d FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_controlled_windows fk_rails_d2b0779305; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_controlled_windows
    ADD CONSTRAINT fk_rails_d2b0779305 FOREIGN KEY (opened_by_id) REFERENCES public.users(id);


--
-- Name: accounting_invoice_line_annotations fk_rails_d3bee1dc29; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_line_annotations
    ADD CONSTRAINT fk_rails_d3bee1dc29 FOREIGN KEY (analytical_account_id) REFERENCES public.accounting_analytical_accounts(id);


--
-- Name: accounting_controlled_windows fk_rails_d41f0525a4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_controlled_windows
    ADD CONSTRAINT fk_rails_d41f0525a4 FOREIGN KEY (closed_by_id) REFERENCES public.users(id);


--
-- Name: accounting_intracom_listings fk_rails_d6237e4acb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_intracom_listings
    ADD CONSTRAINT fk_rails_d6237e4acb FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_recurring_runs fk_rails_da9af52fce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_recurring_runs
    ADD CONSTRAINT fk_rails_da9af52fce FOREIGN KEY (journal_entry_id) REFERENCES public.accounting_journal_entries(id) ON DELETE SET NULL;


--
-- Name: accounting_journal_entries fk_rails_daa313bbd9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entries
    ADD CONSTRAINT fk_rails_daa313bbd9 FOREIGN KEY (journal_id) REFERENCES public.accounting_journals(id);


--
-- Name: api_clients fk_rails_dcea944c33; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_clients
    ADD CONSTRAINT fk_rails_dcea944c33 FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- Name: accounting_fiscal_years fk_rails_dd957818bc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_fiscal_years
    ADD CONSTRAINT fk_rails_dd957818bc FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_peppol_events fk_rails_df7afcf17c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_peppol_events
    ADD CONSTRAINT fk_rails_df7afcf17c FOREIGN KEY (invoice_id) REFERENCES public.accounting_invoices(id);


--
-- Name: accounting_invoice_lines fk_rails_df9325f489; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_lines
    ADD CONSTRAINT fk_rails_df9325f489 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_letterings fk_rails_e58df8b924; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_letterings
    ADD CONSTRAINT fk_rails_e58df8b924 FOREIGN KEY (partner_id) REFERENCES public.accounting_partners(id);


--
-- Name: user_entities fk_rails_e74f70b397; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_entities
    ADD CONSTRAINT fk_rails_e74f70b397 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_lettering_write_offs fk_rails_e7c80d2bdd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_write_offs
    ADD CONSTRAINT fk_rails_e7c80d2bdd FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: accounting_bank_statements fk_rails_e8b9869d2b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_statements
    ADD CONSTRAINT fk_rails_e8b9869d2b FOREIGN KEY (import_batch_id) REFERENCES public.accounting_import_batches(id);


--
-- Name: accounting_intracom_listing_lines fk_rails_ebb9da0d3a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_intracom_listing_lines
    ADD CONSTRAINT fk_rails_ebb9da0d3a FOREIGN KEY (intracom_listing_id) REFERENCES public.accounting_intracom_listings(id);


--
-- Name: accounting_payment_reminder_items fk_rails_ebe2fc3d8a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_reminder_items
    ADD CONSTRAINT fk_rails_ebe2fc3d8a FOREIGN KEY (payment_reminder_id) REFERENCES public.accounting_payment_reminders(id);


--
-- Name: accounting_lettering_events fk_rails_ed5166addb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_lettering_events
    ADD CONSTRAINT fk_rails_ed5166addb FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_letterings fk_rails_ed96a62b21; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_letterings
    ADD CONSTRAINT fk_rails_ed96a62b21 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_payment_batch_lines fk_rails_f036501dd6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_batch_lines
    ADD CONSTRAINT fk_rails_f036501dd6 FOREIGN KEY (invoice_id) REFERENCES public.accounting_invoices(id);


--
-- Name: accounting_intracom_listing_lines fk_rails_f227b86af3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_intracom_listing_lines
    ADD CONSTRAINT fk_rails_f227b86af3 FOREIGN KEY (entity_id) REFERENCES public.entities(id);


--
-- Name: accounting_payment_batches fk_rails_f29405861c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_payment_batches
    ADD CONSTRAINT fk_rails_f29405861c FOREIGN KEY (bank_account_id) REFERENCES public.accounting_bank_accounts(id);


--
-- Name: accounting_period_locks fk_rails_f44208b691; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_period_locks
    ADD CONSTRAINT fk_rails_f44208b691 FOREIGN KEY (locked_by_id) REFERENCES public.users(id);


--
-- Name: accounting_document_links fk_rails_f4edfdbfdf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_document_links
    ADD CONSTRAINT fk_rails_f4edfdbfdf FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: accounting_bank_transactions fk_rails_f51db8c122; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_transactions
    ADD CONSTRAINT fk_rails_f51db8c122 FOREIGN KEY (statement_id) REFERENCES public.accounting_bank_statements(id);


--
-- Name: accounting_bank_transactions fk_rails_f5872c5e07; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_bank_transactions
    ADD CONSTRAINT fk_rails_f5872c5e07 FOREIGN KEY (journal_entry_id) REFERENCES public.accounting_journal_entries(id);


--
-- Name: accounting_entry_template_lines fk_rails_f80805823c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_entry_template_lines
    ADD CONSTRAINT fk_rails_f80805823c FOREIGN KEY (partner_id) REFERENCES public.accounting_partners(id);


--
-- Name: accounting_vat_grid_mappings fk_rails_f8460edd74; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_vat_grid_mappings
    ADD CONSTRAINT fk_rails_f8460edd74 FOREIGN KEY (vat_code_id) REFERENCES public.accounting_vat_codes(id);


--
-- Name: accounting_invoices fk_rails_f89f08860c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoices
    ADD CONSTRAINT fk_rails_f89f08860c FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: accounting_depreciation_entries fk_rails_f91c2bc427; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_depreciation_entries
    ADD CONSTRAINT fk_rails_f91c2bc427 FOREIGN KEY (journal_entry_id) REFERENCES public.accounting_journal_entries(id);


--
-- Name: accounting_analytical_annotations fk_rails_fec4fb0e51; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_analytical_annotations
    ADD CONSTRAINT fk_rails_fec4fb0e51 FOREIGN KEY (analytical_axis_id) REFERENCES public.accounting_analytical_axes(id);


--
-- Name: accounting_journal_entries fk_rails_ffd2ccf3ea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entries
    ADD CONSTRAINT fk_rails_ffd2ccf3ea FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261004140000'),
('20261004130000'),
('20261004120000'),
('20261004110000'),
('20261004100000'),
('20261003290000'),
('20261003280000'),
('20261003270000'),
('20261003260000'),
('20261003250000'),
('20261003240000'),
('20261003230000'),
('20261003220000'),
('20261003210000'),
('20261003200000'),
('20261003190000'),
('20261003180000'),
('20261003170000'),
('20261003160000'),
('20261003150000'),
('20261003140000'),
('20261003130001'),
('20261003130000'),
('20261003120000'),
('20261003110000'),
('20261003100000'),
('20261003090000'),
('20261002160000'),
('20261002150000'),
('20261002140000'),
('20261002130000'),
('20261002120000'),
('20261002110000'),
('20261002100000'),
('20261002090000'),
('20261001080000'),
('20261001070000'),
('20261001060000'),
('20261001054757'),
('20260930000300'),
('20260930000200'),
('20260930000100'),
('20260929001100'),
('20260929001000'),
('20260929000900'),
('20260929000800'),
('20260929000700'),
('20260929000600'),
('20260929000500'),
('20260929000400'),
('20260929000300'),
('20260929000200'),
('20260929000100'),
('20260929000000'),
('20260928000100'),
('20260928000000'),
('20260927000400'),
('20260927000300'),
('20260927000200'),
('20260927000100'),
('20260927000000'),
('20260926180020'),
('20260926180010'),
('20260926180000'),
('20260926170000'),
('20260926160000'),
('20260926150000'),
('20260926140000'),
('20260925160000'),
('20260925150000'),
('20260925140000'),
('20260925130000'),
('20260925120000'),
('20260925110000'),
('20260925100000'),
('20260925091000'),
('20260925090000'),
('20260924210000'),
('20260924100000'),
('20260923150000'),
('20260923140000'),
('20260923130000'),
('20260923120000'),
('20260923110000'),
('20260923100000'),
('20260922100000'),
('20260921100000'),
('20260920200000'),
('20260920100100'),
('20260920100000'),
('20260919100000'),
('20260718164144'),
('20260718122123'),
('20260709000001'),
('20260628163629'),
('20260628000001'),
('20260627000008'),
('20260627000007'),
('20260627000006'),
('20260627000005'),
('20260627000004'),
('20260627000003'),
('20260627000002'),
('20260627000001'),
('20260517095526'),
('20260517095525'),
('20260517095504'),
('20260517093633'),
('20260517091153'),
('20260515200000'),
('20260515195133'),
('20260515195131'),
('20260515194227'),
('20260515140000'),
('20260515130001'),
('20260515130000'),
('20260515120001'),
('20260515120000'),
('20260514211346'),
('20260514211345'),
('20260514185027'),
('20260514185019'),
('20260514184323'),
('20260514183529'),
('20260514183527'),
('20260514183520');

