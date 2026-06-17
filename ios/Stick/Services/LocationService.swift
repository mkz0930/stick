//
//  LocationService.swift
//  CoreLocation 单例 — 省电模式定位 + 反向地理编码城市名
//
//  - requestWhenInUseAuthorization（不用 always）
//  - 100m 精度 + 500m 距离过滤，省电
//  - 反向地理编码缓存：同坐标短时间内不重复请求
//  - isTravel(now:)：距离 homeCity > 100km 或 isTravelUntil > now
//

import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    @Published private(set) var currentCity: String?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager: CLLocationManager
    private let geocoder = CLGeocoder()
    /// 上次反向地理编码的时间戳（同坐标不再请求）
    private var lastGeocodeAt: Date?
    private var lastGeocodeCoord: CLLocationCoordinate2D?

    override private init() {
        self.manager = CLLocationManager()
        self.authorizationStatus = self.manager.authorizationStatus
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.manager.distanceFilter = 500
    }

    /// 请求权限 + 启动定位。多次调用幂等。
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            // denied / restricted：不做事，让 isTravel 始终 false
            break
        }
    }

    /// 停止定位（节电）
    func stop() {
        manager.stopUpdatingLocation()
    }

    /// 是否处于出差状态。
    /// - 优先看 `isTravelUntil`：如果 userProfile 设了出差保持到 X 时刻 → true
    /// - 否则比较当前城市与常驻城市，距离 > 100km → true
    func isTravel(now: Date, homeCity: String?) -> Bool {
        let profile = UserProfileStore.shared.sleepHabit
        if let until = profile.isTravelUntil, until > now {
            return true
        }
        guard let home = homeCity ?? profile.homeCity else {
            return false
        }
        guard let cur = currentCity else { return false }
        return !cur.contains(home) && !home.contains(cur)
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let coord = loc.coordinate
        Task { @MainActor in
            self.currentCoordinate = coord
            // 节流：同坐标或 30s 内已请求过 → 不再 geocode
            if let lastCoord = self.lastGeocodeCoord,
               abs(lastCoord.latitude - coord.latitude) < 0.01,
               abs(lastCoord.longitude - coord.longitude) < 0.01 {
                return
            }
            if let lastAt = self.lastGeocodeAt, Date().timeIntervalSince(lastAt) < 30 {
                return
            }
            self.lastGeocodeAt = Date()
            self.lastGeocodeCoord = coord
            self.geocode(location: loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 静默失败
    }

    @MainActor
    private func geocode(location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            Task { @MainActor in
                guard let pm = placemarks?.first else { return }
                let city = pm.locality ?? pm.subAdministrativeArea ?? pm.administrativeArea
                if let city = city, !city.isEmpty {
                    self.currentCity = city
                }
            }
        }
    }
}
