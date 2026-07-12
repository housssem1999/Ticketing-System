-- Focused SQL checks for lifecycle transitions and reservation rule enforcement.
-- Run after loading db/schema.sql in PostgreSQL.

BEGIN;

INSERT INTO venues (name, timezone) VALUES ('Arena', 'UTC');
INSERT INTO venue_sections (venue_id, code, name, is_accessible) VALUES (1, 'A', 'Front', TRUE);
INSERT INTO venue_rows (section_id, code) VALUES (1, '1');
INSERT INTO venue_seats (row_id, seat_number, seat_type, min_age) VALUES
  (1, '1', 'STANDARD', 0),
  (1, '2', 'VIP', 21),
  (1, '3', 'ACCESSIBLE', 0),
  (1, '4', 'STANDARD', 0),
  (1, '5', 'STANDARD', 0);

INSERT INTO events (venue_id, name, start_at, end_at, sale_starts_at, sale_ends_at, min_age, status)
VALUES (1, 'Show', NOW() + INTERVAL '1 day', NOW() + INTERVAL '1 day 2 hour', NOW() - INTERVAL '1 hour', NOW() + INTERVAL '1 day', 18, 'PUBLISHED');

INSERT INTO tickets (event_id, seat_id, category, price, status, reservation_id)
VALUES
  (1, 1, 'STD', 100, 'AVAILABLE', NULL),
  (1, 2, 'VIP', 300, 'AVAILABLE', NULL),
  (1, 3, 'ACC', 80, 'AVAILABLE', NULL),
  (1, 4, 'STD', 100, 'AVAILABLE', NULL),
  (1, 5, 'STD', 100, 'AVAILABLE', NULL);

INSERT INTO reservations (user_id, event_id, status, hold_expires_at)
VALUES (10, 1, 'CREATED', NULL);

-- Event: valid transition should succeed.
UPDATE events SET status = 'ON_SALE' WHERE id = 1;

-- Event: invalid transition should fail.
DO $$
BEGIN
  BEGIN
    UPDATE events SET status = 'DRAFT' WHERE id = 1;
    RAISE EXCEPTION 'Expected invalid transition to fail';
  EXCEPTION
    WHEN OTHERS THEN
      IF POSITION('Invalid event transition' IN SQLERRM) = 0 THEN
        RAISE;
      END IF;
  END;
END;
$$;

-- Reservation and ticket setup for hold.
UPDATE reservations
SET status = 'HOLDING', hold_expires_at = NOW() + INTERVAL '10 minutes'
WHERE id = 1;

UPDATE tickets
SET status = 'LOCKED', reservation_id = 1
WHERE id IN (1, 2, 3, 4, 5);

INSERT INTO reservation_items (reservation_id, ticket_id)
VALUES (1, 1), (1, 2), (1, 3), (1, 4), (1, 5);

-- Non-VIP over limit should fail (5 tickets > 4).
DO $$
BEGIN
  BEGIN
    PERFORM validate_reservation_rules(1, FALSE, 25, FALSE);
    RAISE EXCEPTION 'Expected limit rule to fail for non-VIP';
  EXCEPTION
    WHEN OTHERS THEN
      IF POSITION('Ticket limit exceeded' IN SQLERRM) = 0 THEN
        RAISE;
      END IF;
  END;
END;
$$;

-- VIP override should pass.
SELECT validate_reservation_rules(1, TRUE, 25, FALSE);

-- Accessibility constraint should fail because not all seats are accessible.
DO $$
BEGIN
  BEGIN
    PERFORM validate_reservation_rules(1, TRUE, 25, TRUE);
    RAISE EXCEPTION 'Expected accessibility rule to fail';
  EXCEPTION
    WHEN OTHERS THEN
      IF POSITION('accessible seats only' IN SQLERRM) = 0 THEN
        RAISE;
      END IF;
  END;
END;
$$;

-- Age constraint should fail for user age below seat/event rule.
DO $$
BEGIN
  BEGIN
    PERFORM validate_reservation_rules(1, TRUE, 16, FALSE);
    RAISE EXCEPTION 'Expected age rule to fail';
  EXCEPTION
    WHEN OTHERS THEN
      IF POSITION('below restriction' IN SQLERRM) = 0 THEN
        RAISE;
      END IF;
  END;
END;
$$;

-- Valid confirmation path should succeed with VIP + adequate age.
SELECT confirm_reservation(1, TRUE, 25, FALSE);

-- Ensure states were updated by confirmation.
DO $$
DECLARE
  v_reservation_status reservation_status;
  v_confirmed_count INTEGER;
BEGIN
  SELECT status INTO v_reservation_status FROM reservations WHERE id = 1;
  IF v_reservation_status <> 'PAID' THEN
    RAISE EXCEPTION 'Reservation did not reach PAID';
  END IF;

  SELECT COUNT(*)
    INTO v_confirmed_count
  FROM tickets t
  JOIN reservation_items ri ON ri.ticket_id = t.id
  WHERE ri.reservation_id = 1
    AND t.status = 'CONFIRMED';

  IF v_confirmed_count <> 5 THEN
    RAISE EXCEPTION 'Not all tickets reached CONFIRMED';
  END IF;
END;
$$;

ROLLBACK;
