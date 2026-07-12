package com.ticketing.system.domain.entity;

import com.ticketing.system.domain.enums.EventStatus;
import jakarta.persistence.*;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "events")
public class Event {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    @JoinColumn(name = "venue_id", nullable = false)
    private Venue venue;

    @Column(nullable = false)
    private String name;

    @Column(name = "start_at", nullable = false)
    private OffsetDateTime startAt;

    @Column(name = "end_at", nullable = false)
    private OffsetDateTime endAt;

    @Column(name = "sale_starts_at")
    private OffsetDateTime saleStartsAt;

    @Column(name = "sale_ends_at")
    private OffsetDateTime saleEndsAt;

    @Column(name = "min_age", nullable = false)
    private short minAge;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private EventStatus status = EventStatus.DRAFT;

    @OneToMany(mappedBy = "event")
    private List<Ticket> tickets = new ArrayList<>();

    @OneToMany(mappedBy = "event")
    private List<Reservation> reservations = new ArrayList<>();
}
