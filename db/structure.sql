SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

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
-- Name: prevent_audit_log_modification(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_audit_log_modification() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'accounting_audit_logs are immutable';
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
    updated_at timestamp(6) without time zone NOT NULL
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
    updated_at timestamp(6) without time zone NOT NULL
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
    updated_at timestamp(6) without time zone NOT NULL
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
    updated_at timestamp(6) without time zone NOT NULL
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
    code character varying(5) NOT NULL,
    label_fr character varying NOT NULL,
    journal_type integer NOT NULL,
    default_account_id bigint,
    sequence_prefix character varying NOT NULL,
    current_sequence integer DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
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
    updated_at timestamp(6) without time zone NOT NULL
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
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


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
    locale character varying DEFAULT 'fr'::character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
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
    object text
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
-- Name: accounting_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_accounts ALTER COLUMN id SET DEFAULT nextval('public.accounting_accounts_id_seq'::regclass);


--
-- Name: accounting_audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_audit_logs ALTER COLUMN id SET DEFAULT nextval('public.accounting_audit_logs_id_seq'::regclass);


--
-- Name: accounting_fiscal_years id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_fiscal_years ALTER COLUMN id SET DEFAULT nextval('public.accounting_fiscal_years_id_seq'::regclass);


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
-- Name: accounting_partners id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_partners ALTER COLUMN id SET DEFAULT nextval('public.accounting_partners_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions ALTER COLUMN id SET DEFAULT nextval('public.versions_id_seq'::regclass);


--
-- Name: accounting_accounts accounting_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_accounts
    ADD CONSTRAINT accounting_accounts_pkey PRIMARY KEY (id);


--
-- Name: accounting_audit_logs accounting_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_audit_logs
    ADD CONSTRAINT accounting_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: accounting_fiscal_years accounting_fiscal_years_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_fiscal_years
    ADD CONSTRAINT accounting_fiscal_years_pkey PRIMARY KEY (id);


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
-- Name: accounting_partners accounting_partners_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_partners
    ADD CONSTRAINT accounting_partners_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


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
-- Name: idx_accounting_fiscal_years_one_open; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_accounting_fiscal_years_one_open ON public.accounting_fiscal_years USING btree (status) WHERE (status = 0);


--
-- Name: index_accounting_accounts_on_account_class; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_accounts_on_account_class ON public.accounting_accounts USING btree (account_class);


--
-- Name: index_accounting_accounts_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_accounts_on_active ON public.accounting_accounts USING btree (active);


--
-- Name: index_accounting_accounts_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_accounts_on_code ON public.accounting_accounts USING btree (code);


--
-- Name: index_accounting_accounts_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_accounts_on_parent_id ON public.accounting_accounts USING btree (parent_id);


--
-- Name: index_accounting_audit_logs_on_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_audit_logs_on_action ON public.accounting_audit_logs USING btree (action);


--
-- Name: index_accounting_audit_logs_on_auditable_type_and_auditable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_audit_logs_on_auditable_type_and_auditable_id ON public.accounting_audit_logs USING btree (auditable_type, auditable_id);


--
-- Name: index_accounting_audit_logs_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_audit_logs_on_created_at ON public.accounting_audit_logs USING btree (created_at);


--
-- Name: index_accounting_audit_logs_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_audit_logs_on_user_id ON public.accounting_audit_logs USING btree (user_id);


--
-- Name: index_accounting_fiscal_years_on_year; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_fiscal_years_on_year ON public.accounting_fiscal_years USING btree (year);


--
-- Name: index_accounting_invoice_lines_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_lines_on_account_id ON public.accounting_invoice_lines USING btree (account_id);


--
-- Name: index_accounting_invoice_lines_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_lines_on_invoice_id ON public.accounting_invoice_lines USING btree (invoice_id);


--
-- Name: index_accounting_invoice_lines_on_invoice_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoice_lines_on_invoice_id_and_position ON public.accounting_invoice_lines USING btree (invoice_id, "position");


--
-- Name: index_accounting_invoices_on_fiscal_year_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_fiscal_year_id ON public.accounting_invoices USING btree (fiscal_year_id);


--
-- Name: index_accounting_invoices_on_invoice_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_invoice_date ON public.accounting_invoices USING btree (invoice_date);


--
-- Name: index_accounting_invoices_on_invoice_number_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_invoices_on_invoice_number_unique ON public.accounting_invoices USING btree (invoice_number) WHERE (invoice_number IS NOT NULL);


--
-- Name: index_accounting_invoices_on_invoice_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_invoice_type ON public.accounting_invoices USING btree (invoice_type);


--
-- Name: index_accounting_invoices_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_journal_entry_id ON public.accounting_invoices USING btree (journal_entry_id);


--
-- Name: index_accounting_invoices_on_partner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_partner_id ON public.accounting_invoices USING btree (partner_id);


--
-- Name: index_accounting_invoices_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_invoices_on_status ON public.accounting_invoices USING btree (status);


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
-- Name: index_accounting_journal_entries_on_reference; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_journal_entries_on_reference ON public.accounting_journal_entries USING btree (reference);


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
-- Name: index_accounting_journal_entry_lines_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entry_lines_on_journal_entry_id ON public.accounting_journal_entry_lines USING btree (journal_entry_id);


--
-- Name: index_accounting_journal_entry_lines_on_partner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_journal_entry_lines_on_partner_id ON public.accounting_journal_entry_lines USING btree (partner_id);


--
-- Name: index_accounting_journals_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_journals_on_code ON public.accounting_journals USING btree (code);


--
-- Name: index_accounting_partners_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_partners_on_active ON public.accounting_partners USING btree (active);


--
-- Name: index_accounting_partners_on_partner_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounting_partners_on_partner_type ON public.accounting_partners USING btree (partner_type);


--
-- Name: index_accounting_partners_on_vat_number_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounting_partners_on_vat_number_unique ON public.accounting_partners USING btree (vat_number) WHERE (vat_number IS NOT NULL);


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
-- Name: index_versions_on_item_type_and_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_versions_on_item_type_and_item_id ON public.versions USING btree (item_type, item_id);


--
-- Name: accounting_audit_logs enforce_audit_log_immutability; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER enforce_audit_log_immutability BEFORE DELETE OR UPDATE ON public.accounting_audit_logs FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_modification();


--
-- Name: accounting_journal_entry_lines enforce_double_entry; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER enforce_double_entry AFTER INSERT OR UPDATE ON public.accounting_journal_entry_lines DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION public.enforce_double_entry_check();


--
-- Name: accounting_invoice_lines fk_rails_0ef5226c55; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_lines
    ADD CONSTRAINT fk_rails_0ef5226c55 FOREIGN KEY (invoice_id) REFERENCES public.accounting_invoices(id);


--
-- Name: accounting_journal_entries fk_rails_15d7ff9705; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entries
    ADD CONSTRAINT fk_rails_15d7ff9705 FOREIGN KEY (fiscal_year_id) REFERENCES public.accounting_fiscal_years(id);


--
-- Name: accounting_journal_entry_lines fk_rails_1e6c3311fa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entry_lines
    ADD CONSTRAINT fk_rails_1e6c3311fa FOREIGN KEY (journal_entry_id) REFERENCES public.accounting_journal_entries(id);


--
-- Name: accounting_invoices fk_rails_479b19d12c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoices
    ADD CONSTRAINT fk_rails_479b19d12c FOREIGN KEY (fiscal_year_id) REFERENCES public.accounting_fiscal_years(id);


--
-- Name: accounting_journal_entry_lines fk_rails_6f6e1949f4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entry_lines
    ADD CONSTRAINT fk_rails_6f6e1949f4 FOREIGN KEY (partner_id) REFERENCES public.accounting_partners(id);


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
-- Name: accounting_invoices fk_rails_9602ee956d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoices
    ADD CONSTRAINT fk_rails_9602ee956d FOREIGN KEY (partner_id) REFERENCES public.accounting_partners(id);


--
-- Name: accounting_invoice_lines fk_rails_d08162bbbf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_invoice_lines
    ADD CONSTRAINT fk_rails_d08162bbbf FOREIGN KEY (account_id) REFERENCES public.accounting_accounts(id);


--
-- Name: accounting_journal_entries fk_rails_daa313bbd9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_journal_entries
    ADD CONSTRAINT fk_rails_daa313bbd9 FOREIGN KEY (journal_id) REFERENCES public.accounting_journals(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
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

