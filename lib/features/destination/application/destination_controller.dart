import 'package:movera_rider/features/destination/data/destination_repository.dart';

class DestinationController {
  DestinationController({DestinationRepository? store})
    : _store = store ?? DestinationRepository.instance;
  final DestinationRepository _store;

  void remember({String? address, double? lat, double? lng}) {
    _store.remember(address: address, lat: lat, lng: lng);
  }
}
