package com.ticketing.system.domain.entity;

import com.ticketing.system.domain.enums.SeatType;
import jakarta.persistence.*;

@Entity
@Table(name = "venue_seats", uniqueConstraints = {
        @UniqueConstraint(name = "uk_venue_seats_row_seat_number", columnNames = {"row_id", "seat_number"})
})
public class VenueSeat {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    @JoinColumn(name = "row_id", nullable = false)
    private VenueRow row;

    @Column(name = "seat_number", nullable = false)
    private String seatNumber;

    @Enumerated(EnumType.STRING)
    @Column(name = "seat_type", nullable = false)
    private SeatType seatType = SeatType.STANDARD;

    @Column(name = "min_age", nullable = false)
    private short minAge;
}
