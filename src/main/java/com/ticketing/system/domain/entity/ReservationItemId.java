package com.ticketing.system.domain.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;

import java.io.Serializable;
import java.util.Objects;

@Embeddable
public class ReservationItemId implements Serializable {

    @Column(name = "reservation_id")
    private Long reservationId;

    @Column(name = "ticket_id")
    private Long ticketId;

    protected ReservationItemId() {
    }

    public ReservationItemId(Long reservationId, Long ticketId) {
        this.reservationId = reservationId;
        this.ticketId = ticketId;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        ReservationItemId that = (ReservationItemId) o;
        return Objects.equals(reservationId, that.reservationId) && Objects.equals(ticketId, that.ticketId);
    }

    @Override
    public int hashCode() {
        return Objects.hash(reservationId, ticketId);
    }
}
