package com.ticketing.system.domain.entity;

import jakarta.persistence.*;

import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "venue_rows", uniqueConstraints = {
        @UniqueConstraint(name = "uk_venue_rows_section_code", columnNames = {"section_id", "code"})
})
public class VenueRow {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    @JoinColumn(name = "section_id", nullable = false)
    private VenueSection section;

    @Column(nullable = false)
    private String code;

    @OneToMany(mappedBy = "row")
    private List<VenueSeat> seats = new ArrayList<>();
}
