-- Epic A — Core Domain & Lifecycle
-- PostgreSQL schema + lifecycle guards + business rule checks.

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_status') THEN
    CREATE TYPE event_status AS ENUM ('DRAFT', 'PUBLISHED', 'ON_SALE', 'SOLD_OUT', 'COMPLETED', 'CANCELLED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ticket_status') THEN
    CREATE TYPE ticket_status AS ENUM (
      'AVAILABLE',
      'LOCKED',
      'PAYMENT_PENDING',
      'CONFIRMED',
      'ISSUED',
      'USED',
      'REFUNDED'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'reservation_status') THEN
    CREATE TYPE reservation_status AS ENUM ('CREATED', 'HOLDING', 'EXPIRED', 'PAID', 'CANCELLED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_status') THEN
    CREATE TYPE order_status AS ENUM ('CREATED', 'PAYMENT_PENDING', 'PAID', 'FAILED', 'CANCELLED', 'REFUNDED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_status') THEN
    CREATE TYPE payment_status AS ENUM ('INITIATED', 'PROCESSING', 'AUTHORIZED', 'CAPTURED', 'FAILED', 'REFUNDED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'seat_type') THEN
    CREATE TYPE seat_type AS ENUM ('STANDARD', 'VIP', 'ACCESSIBLE');
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS venues (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name TEXT NOT NULL,
  timezone TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS venue_sections (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  venue_id BIGINT NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  is_accessible BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (venue_id, code)
);

CREATE TABLE IF NOT EXISTS venue_rows (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  section_id BIGINT NOT NULL REFERENCES venue_sections(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  UNIQUE (section_id, code)
);

CREATE TABLE IF NOT EXISTS venue_seats (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  row_id BIGINT NOT NULL REFERENCES venue_rows(id) ON DELETE CASCADE,
  seat_number TEXT NOT NULL,
  seat_type seat_type NOT NULL DEFAULT 'STANDARD',
  min_age SMALLINT NOT NULL DEFAULT 0 CHECK (min_age >= 0),
  UNIQUE (row_id, seat_number)
);

CREATE TABLE IF NOT EXISTS events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  venue_id BIGINT NOT NULL REFERENCES venues(id),
  name TEXT NOT NULL,
  start_at TIMESTAMPTZ NOT NULL,
  end_at TIMESTAMPTZ NOT NULL,
  sale_starts_at TIMESTAMPTZ,
  sale_ends_at TIMESTAMPTZ,
  min_age SMALLINT NOT NULL DEFAULT 0 CHECK (min_age >= 0),
  status event_status NOT NULL DEFAULT 'DRAFT',
  CHECK (end_at > start_at),
  CHECK (sale_ends_at IS NULL OR sale_starts_at IS NULL OR sale_ends_at > sale_starts_at)
);

CREATE TABLE IF NOT EXISTS reservations (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL,
  event_id BIGINT NOT NULL REFERENCES events(id),
  status reservation_status NOT NULL DEFAULT 'CREATED',
  hold_expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK ((status = 'HOLDING' AND hold_expires_at IS NOT NULL) OR (status <> 'HOLDING'))
);

CREATE TABLE IF NOT EXISTS tickets (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_id BIGINT NOT NULL REFERENCES events(id),
  seat_id BIGINT NOT NULL REFERENCES venue_seats(id),
  reservation_id BIGINT REFERENCES reservations(id) ON DELETE SET NULL,
  category TEXT NOT NULL,
  price NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
  status ticket_status NOT NULL DEFAULT 'AVAILABLE',
  issued_at TIMESTAMPTZ,
  used_at TIMESTAMPTZ,
  UNIQUE (event_id, seat_id),
  CHECK ((status = 'AVAILABLE' AND reservation_id IS NULL) OR status <> 'AVAILABLE'),
  CHECK ((status = 'LOCKED' AND reservation_id IS NOT NULL) OR status <> 'LOCKED')
);

CREATE TABLE IF NOT EXISTS reservation_items (
  reservation_id BIGINT NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
  ticket_id BIGINT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  PRIMARY KEY (reservation_id, ticket_id)
);

CREATE TABLE IF NOT EXISTS orders (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reservation_id BIGINT NOT NULL UNIQUE REFERENCES reservations(id),
  user_id BIGINT NOT NULL,
  event_id BIGINT NOT NULL REFERENCES events(id),
  total_amount NUMERIC(12, 2) NOT NULL CHECK (total_amount >= 0),
  status order_status NOT NULL DEFAULT 'CREATED',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS payments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  provider_reference TEXT,
  amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
  status payment_status NOT NULL DEFAULT 'INITIATED',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (provider_reference)
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id BIGINT NOT NULL,
  action TEXT NOT NULL,
  payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tickets_event_status ON tickets(event_id, status);
CREATE INDEX IF NOT EXISTS idx_reservations_user_event_status ON reservations(user_id, event_id, status);
CREATE INDEX IF NOT EXISTS idx_reservations_hold_expiry ON reservations(hold_expires_at, status);
CREATE INDEX IF NOT EXISTS idx_payments_provider_reference ON payments(provider_reference);

CREATE TABLE IF NOT EXISTS allowed_transitions (
  machine TEXT NOT NULL,
  from_state TEXT NOT NULL,
  to_state TEXT NOT NULL,
  PRIMARY KEY (machine, from_state, to_state)
);

INSERT INTO allowed_transitions (machine, from_state, to_state) VALUES
  ('event', 'DRAFT', 'PUBLISHED'),
  ('event', 'PUBLISHED', 'ON_SALE'),
  ('event', 'PUBLISHED', 'CANCELLED'),
  ('event', 'ON_SALE', 'SOLD_OUT'),
  ('event', 'ON_SALE', 'CANCELLED'),
  ('event', 'SOLD_OUT', 'COMPLETED'),
  ('event', 'SOLD_OUT', 'CANCELLED'),

  ('ticket', 'AVAILABLE', 'LOCKED'),
  ('ticket', 'LOCKED', 'PAYMENT_PENDING'),
  ('ticket', 'LOCKED', 'AVAILABLE'),
  ('ticket', 'PAYMENT_PENDING', 'CONFIRMED'),
  ('ticket', 'PAYMENT_PENDING', 'AVAILABLE'),
  ('ticket', 'CONFIRMED', 'ISSUED'),
  ('ticket', 'CONFIRMED', 'REFUNDED'),
  ('ticket', 'ISSUED', 'USED'),

  ('reservation', 'CREATED', 'HOLDING'),
  ('reservation', 'CREATED', 'CANCELLED'),
  ('reservation', 'HOLDING', 'PAID'),
  ('reservation', 'HOLDING', 'EXPIRED'),
  ('reservation', 'HOLDING', 'CANCELLED'),

  ('payment', 'INITIATED', 'PROCESSING'),
  ('payment', 'PROCESSING', 'AUTHORIZED'),
  ('payment', 'PROCESSING', 'FAILED'),
  ('payment', 'AUTHORIZED', 'CAPTURED'),
  ('payment', 'AUTHORIZED', 'FAILED'),
  ('payment', 'CAPTURED', 'REFUNDED')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION assert_valid_transition(
  p_machine TEXT,
  p_from TEXT,
  p_to TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF p_from = p_to THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM allowed_transitions
    WHERE machine = p_machine
      AND from_state = p_from
      AND to_state = p_to
  ) THEN
    RAISE EXCEPTION 'Invalid % transition: % -> %', p_machine, p_from, p_to;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION guard_event_transition() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  PERFORM assert_valid_transition('event', OLD.status::TEXT, NEW.status::TEXT);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION guard_ticket_transition() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  PERFORM assert_valid_transition('ticket', OLD.status::TEXT, NEW.status::TEXT);

  IF NEW.status = 'LOCKED' AND NEW.reservation_id IS NULL THEN
    RAISE EXCEPTION 'LOCKED ticket requires reservation_id';
  END IF;

  IF NEW.status = 'AVAILABLE' AND NEW.reservation_id IS NOT NULL THEN
    RAISE EXCEPTION 'AVAILABLE ticket cannot reference reservation_id';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION guard_reservation_transition() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  PERFORM assert_valid_transition('reservation', OLD.status::TEXT, NEW.status::TEXT);

  IF NEW.status = 'HOLDING' AND NEW.hold_expires_at IS NULL THEN
    NEW.hold_expires_at := NOW() + INTERVAL '10 minutes';
  END IF;

  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION guard_payment_transition() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  PERFORM assert_valid_transition('payment', OLD.status::TEXT, NEW.status::TEXT);
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_event_transition ON events;
CREATE TRIGGER trg_guard_event_transition
BEFORE UPDATE OF status ON events
FOR EACH ROW
EXECUTE FUNCTION guard_event_transition();

DROP TRIGGER IF EXISTS trg_guard_ticket_transition ON tickets;
CREATE TRIGGER trg_guard_ticket_transition
BEFORE UPDATE OF status, reservation_id ON tickets
FOR EACH ROW
EXECUTE FUNCTION guard_ticket_transition();

DROP TRIGGER IF EXISTS trg_guard_reservation_transition ON reservations;
CREATE TRIGGER trg_guard_reservation_transition
BEFORE UPDATE OF status, hold_expires_at ON reservations
FOR EACH ROW
EXECUTE FUNCTION guard_reservation_transition();

DROP TRIGGER IF EXISTS trg_guard_payment_transition ON payments;
CREATE TRIGGER trg_guard_payment_transition
BEFORE UPDATE OF status ON payments
FOR EACH ROW
EXECUTE FUNCTION guard_payment_transition();

CREATE OR REPLACE FUNCTION validate_reservation_rules(
  p_reservation_id BIGINT,
  p_is_vip BOOLEAN DEFAULT FALSE,
  p_user_age SMALLINT DEFAULT NULL,
  p_requires_accessible BOOLEAN DEFAULT FALSE
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  v_event_status event_status;
  v_event_min_age SMALLINT;
  v_hold_expires_at TIMESTAMPTZ;
  v_ticket_count INTEGER;
  v_max_seat_min_age SMALLINT;
  v_accessible_count INTEGER;
BEGIN
  SELECT e.status, e.min_age, r.hold_expires_at
    INTO v_event_status, v_event_min_age, v_hold_expires_at
  FROM reservations r
  JOIN events e ON e.id = r.event_id
  WHERE r.id = p_reservation_id
    AND r.status = 'HOLDING';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reservation % not in HOLDING state', p_reservation_id;
  END IF;

  IF v_event_status <> 'ON_SALE' THEN
    RAISE EXCEPTION 'Event must be ON_SALE before confirming reservation %', p_reservation_id;
  END IF;

  IF v_hold_expires_at IS NULL OR v_hold_expires_at <= NOW() THEN
    RAISE EXCEPTION 'Reservation % hold already expired', p_reservation_id;
  END IF;

  IF v_hold_expires_at > NOW() + INTERVAL '10 minutes' THEN
    RAISE EXCEPTION 'Reservation % hold exceeds 10-minute policy', p_reservation_id;
  END IF;

  SELECT COUNT(*)
    INTO v_ticket_count
  FROM reservation_items ri
  JOIN tickets t ON t.id = ri.ticket_id
  WHERE ri.reservation_id = p_reservation_id
    AND t.status = 'LOCKED'
    AND t.reservation_id = p_reservation_id;

  IF v_ticket_count = 0 THEN
    RAISE EXCEPTION 'Reservation % has no locked seats', p_reservation_id;
  END IF;

  IF NOT p_is_vip AND v_ticket_count > 4 THEN
    RAISE EXCEPTION 'Ticket limit exceeded for reservation % (max 4)', p_reservation_id;
  END IF;

  IF p_requires_accessible THEN
    SELECT COUNT(*)
      INTO v_accessible_count
    FROM reservation_items ri
    JOIN tickets t ON t.id = ri.ticket_id
    JOIN venue_seats s ON s.id = t.seat_id
    WHERE ri.reservation_id = p_reservation_id
      AND s.seat_type = 'ACCESSIBLE';

    IF v_accessible_count <> v_ticket_count THEN
      RAISE EXCEPTION 'Reservation % must use accessible seats only when accessibility is requested', p_reservation_id;
    END IF;
  END IF;

  IF p_user_age IS NOT NULL THEN
    SELECT COALESCE(MAX(s.min_age), 0)
      INTO v_max_seat_min_age
    FROM reservation_items ri
    JOIN tickets t ON t.id = ri.ticket_id
    JOIN venue_seats s ON s.id = t.seat_id
    WHERE ri.reservation_id = p_reservation_id;

    IF p_user_age < GREATEST(v_event_min_age, v_max_seat_min_age) THEN
      RAISE EXCEPTION 'User age is below restriction for reservation %', p_reservation_id;
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION confirm_reservation(
  p_reservation_id BIGINT,
  p_is_vip BOOLEAN DEFAULT FALSE,
  p_user_age SMALLINT DEFAULT NULL,
  p_requires_accessible BOOLEAN DEFAULT FALSE
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  PERFORM validate_reservation_rules(
    p_reservation_id,
    p_is_vip,
    p_user_age,
    p_requires_accessible
  );

  UPDATE reservations
     SET status = 'PAID'
   WHERE id = p_reservation_id;

  UPDATE tickets t
     SET status = 'CONFIRMED'
   WHERE t.id IN (
     SELECT ticket_id
     FROM reservation_items
     WHERE reservation_id = p_reservation_id
   );
END;
$$;

COMMIT;
