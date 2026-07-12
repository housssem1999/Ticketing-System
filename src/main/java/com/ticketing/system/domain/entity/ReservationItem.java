package com.ticketing.system.domain.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "reservation_items")
public class ReservationItem {

    @EmbeddedId
    private ReservationItemId id;

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    @MapsId("reservationId")
    @JoinColumn(name = "reservation_id", nullable = false)
    private Reservation reservation;

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    @MapsId("ticketId")
    @JoinColumn(name = "ticket_id", nullable = false)
    private Ticket ticket;
}
