import MapKit
import CoreLocation

enum MapKitCompatibility {
    static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) { return item.location.coordinate }
        return item.placemark.coordinate
    }

    static func mapItem(coordinate: CLLocationCoordinate2D, name: String?) -> MKMapItem {
        if #available(iOS 26.0, *) {
            let item = MKMapItem(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                address: nil
            )
            item.name = name
            return item
        }
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = name
        return item
    }
}
