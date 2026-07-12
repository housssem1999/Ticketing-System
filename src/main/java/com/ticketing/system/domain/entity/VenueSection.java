package com.ticketing.system.domain.entity;

import jakarta.persistence.*;

import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "venue_sections", uniqueConstraints = {
        @UniqueConstraint(name = "uk_venue_sections_venue_code", columnNames = {"venue_id", "code"})
})
public class VenueSection {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    @JoinColumn(name = "venue_id", nullable = false)
    private Venue venue;

    @Column(nullable = false)
    private String code;

    @Column(nullable = false)
    private String name;

    @Column(name = "is_accessible", nullable = false)
    private boolean accessible;

    @OneToMany(mappedBy = "section")
    private List<VenueRow> rows = new ArrayList<>();
}
