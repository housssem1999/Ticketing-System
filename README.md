# Ticketing System Design Blueprint

This repository documents a production-grade ticketing platform architecture for high-demand events.
The app is intended to be developed using the Spring Boot framework.

## 1) Business Domain

### Core entities
- **Venue** → sections → rows → seats
- **Event** → date, artist, status
- **Ticket** → seat, price, category, status
- **Reservation** → user, hold expiration, status
- **Order** → payment, invoice, status

### Ticket lifecycle
`AVAILABLE → LOCKED → PAYMENT_PENDING → CONFIRMED → ISSUED → USED`

Rollback paths:
- `LOCKED --(hold timeout)--> AVAILABLE`
- `PAYMENT_PENDING --(payment failed)--> AVAILABLE`
- `CONFIRMED --(cancellation)--> REFUNDED`

### Reservation lifecycle
`CREATED → HOLDING → EXPIRED | PAID | CANCELLED`

### Payment lifecycle
`INITIATED → PROCESSING → AUTHORIZED → CAPTURED | FAILED | REFUNDED`

### Event lifecycle
`DRAFT → PUBLISHED → ON_SALE → SOLD_OUT → COMPLETED | CANCELLED`

## 2) Business Rules

- A seat can belong to only one **active** reservation.
- Hold duration defaults to **10 minutes**; expired holds auto-release seats.
- Purchase limit defaults to **4 tickets per user per event** unless VIP override applies.
- Support age restrictions (18+, kids), VIP, accessibility allocations.
- Pricing supports VIP, Early Bird, Last Minute, demand-based, coupons/promotions.
- Refund policy supports 100% / 50% / no refund by cancellation window.
- Transfer policy defines ownership transfer, QR regeneration, and auditability.

## 3) Search System

Search is isolated from booking writes:
- Search service indexes events, artists, venues, dates, categories, prices.
- Use Elasticsearch/OpenSearch for low-latency filtering.
- Booking database remains optimized for transactional consistency.

## 4) Seat Selection Models

- **Reserved seating**: user picks exact seats (cinema, concert, theater).
- **General admission**: user buys quantity without fixed seat mapping.

## 5) Booking Algorithm

1. User clicks Buy
2. Authenticate user
3. Validate event status + sale window
4. Validate ticket limits
5. Check availability
6. Acquire lock
7. Create reservation with expiration
8. Start payment session
9. On payment success: confirm tickets, generate QR, notify user
10. On payment failure: release reservation and seats

## 6) Concurrency Control

### Pessimistic locking
- Pro: strongest double-booking prevention
- Con: reduced throughput, lock contention
- Good fit for very small high-value inventory

### Optimistic locking
- Use row version checks (`version` column)
- Detect update conflicts and force retry path

### Redis distributed locks
- `SET seat-123 token NX PX 10000`
- TTL prevents deadlocks from crashed workers
- Consider Redlock/quorum when multi-node Redis is required

## 7) Waiting Room

Queue traffic before booking:
`100,000 users → waiting room → 5,000 admitted → booking service`

Benefits: fairness, overload protection, smoother latency.

## 8) Queue/Event-Driven Processing

Decouple critical path via Kafka/RabbitMQ/SQS:
`Booking → Payment → Ticketing → Email/SMS/Push → Analytics`

## 9) Saga Pattern

Distributed workflow with compensations:
`Reserve seat → Process payment → Generate ticket → Notify`

Compensate on failure:
`Refund payment → Release reservation/seat`

## 10) Idempotency

All mutation APIs require `Idempotency-Key`.

Store key + request hash + response snapshot to prevent duplicate bookings during retries/timeouts.

## 11) Rate Limiting

Apply per-user and per-IP rate limits (e.g., token bucket in Redis), such as `10 requests/sec/user`.

## 12) Anti-Bot Protection

Use layered controls:
- CAPTCHA/challenge
- device fingerprinting
- IP/device reputation
- behavior anomaly scoring
- mandatory waiting room for hot events

## 13) Payment Gateway Integration

Trusted flow:
`Booking service → payment provider (e.g., Stripe) → webhook → order confirmation`

Never trust frontend success callbacks without verified webhook signatures.

## 14) QR Code Generation

QR payload includes signed claims:
- ticket reference (opaque ID)
- expiry (if applicable)
- cryptographic signature

Avoid exposing sequential/raw internal IDs.

## 15) Ticket Validation at Entrance

`Scan QR → atomic check (unused?) → mark USED → allow/deny`

Atomicity is mandatory to prevent replay at multiple gates.

## 16) Notifications

Asynchronous fan-out for booking lifecycle events:
- Email
- SMS
- Push notifications

## 17) Caching

Use Redis for hot reads:
- popular events
- venue layouts
- pricing snapshots
- availability snapshots (short TTL)

## 18) Data Model (Minimum)

Tables/collections:
- users
- venues
- venue_sections/rows/seats
- events
- tickets
- reservations
- orders
- payments
- audit_logs

Critical indexes:
- `(event_id, seat_id, status)`
- `(user_id, event_id)`
- `(reservation_expires_at, status)`
- payment provider references/webhook IDs

## 19) Failure Recovery

Plan for:
- Redis outage / lock loss
- payment timeout
- duplicate webhooks
- process restart during hold/payment
- clock skew and delayed jobs

Run recovery/reconciliation workers for expired holds, orphaned payments, and stuck sagas.

## 20) Monitoring & Observability

Track metrics:
- booking latency
- payment latency
- reservation timeout rate
- success/failure ratio
- queue depth
- lock contention
- DB deadlocks/timeouts

Include tracing with `request_id`, `correlation_id`, `booking_id`.

## 21) Security

- JWT/OAuth2 authentication
- RBAC authorization
- signed QR tokens
- encryption in transit/at rest
- PCI-aware payment boundaries
- secret management and rotation
- immutable audit logs

## 22) Scalability Strategy

Example independent scaling:
- Search: 10 replicas
- Booking API: 50 replicas
- Payment workers: 20 replicas
- Notification workers: 100 replicas
- DB primary + read replicas
- Redis cluster + CDN edge caching

## 23) Disaster Recovery

- Multi-region deployment strategy
- database replication
- Redis Sentinel/Cluster
- frequent backups + point-in-time recovery
- tested failover runbooks

## 24) Testing Strategy

- Unit tests (domain rules/state machines)
- Integration tests (booking + payment + webhook)
- Contract tests (gateway/webhook schemas)
- Load tests (flash sale, 100k+ virtual users)
- Chaos/failure injection (Redis fail, DB failover, payment delay)

## 25) Non-Functional Requirements (NFRs)

| Category | Target |
| --- | --- |
| Availability | 99.99% uptime |
| Booking latency (pre-payment) | < 200 ms |
| Payment confirmation | < 5 s |
| Throughput | 50,000+ booking req/s |
| Peak concurrency | 500,000 users |
| Seat allocation consistency | Strong consistency |
| Search latency | < 100 ms |
| RTO | < 15 min |
| RPO | < 1 min |

## End-to-End Production Flow

`Waiting room → slot assignment → auth → validate event/sale window → validate limits → seat map → seat selection → distributed lock → reservation (TTL) → payment session → trusted webhook → confirm reservation → issue ticket → signed QR generation → audit log → publish events → notify user → release lock`

This blueprint is intentionally implementation-ready and gives enough context for building a robust, fair, secure, and observable ticketing platform.
