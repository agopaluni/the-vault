//
//  ReverseGeocoder.swift
//  The Vault
//
//  Turns GPS coordinates into a readable "City, Landmark" string.
//  Uses CLGeocoder when network is available, and gracefully falls back to a
//  formatted coordinate string offline — core functionality never requires
//  the internet (see project constraints).
//
//  Requests are serialized and lightly cached because CLGeocoder rate-limits.
//

import Foundation
import CoreLocation

actor ReverseGeocoder {
    static let shared = ReverseGeocoder()

    private let geocoder = CLGeocoder()
    private var cache: [String: String] = [:]
    private var lastRequest = Date.distantPast

    /// Returns a display name for a coordinate, or a coordinate fallback.
    func name(latitude: Double, longitude: Double) async -> String {
        let key = String(format: "%.4f,%.4f", latitude, longitude)
        if let cached = cache[key] { return cached }

        // Be polite to the system geocoder — throttle to ~1 request/sec.
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < 1.0 {
            try? await Task.sleep(nanoseconds: UInt64((1.0 - elapsed) * 1_000_000_000))
        }
        lastRequest = Date()

        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let name = Self.format(placemark: placemarks.first) {
                cache[key] = name
                return name
            }
        } catch {
            // Offline / rate-limited / no result — fall through to coordinates.
        }

        let fallback = Self.coordinateString(latitude: latitude, longitude: longitude)
        cache[key] = fallback
        return fallback
    }

    private static func format(placemark: CLPlacemark?) -> String? {
        guard let p = placemark else { return nil }
        // Prefer "City, Landmark/POI"; degrade gracefully.
        let primary = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? p.country
        let landmark = p.name ?? p.areasOfInterest?.first ?? p.subLocality
        switch (primary, landmark) {
        case let (city?, place?) where city != place: return "\(city), \(place)"
        case let (city?, _): return city
        case let (_, place?): return place
        default: return nil
        }
    }

    static func coordinateString(latitude: Double, longitude: Double) -> String {
        let latDir = latitude >= 0 ? "N" : "S"
        let lonDir = longitude >= 0 ? "E" : "W"
        return String(format: "%.4f°%@, %.4f°%@",
                      abs(latitude), latDir, abs(longitude), lonDir)
    }
}
