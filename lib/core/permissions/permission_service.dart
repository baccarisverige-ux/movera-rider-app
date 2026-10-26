enum AppPermission {
  location,
  notifications,
  camera,
  photos,
  microphone,
  contacts,
}

enum PermissionPhase { notDetermined, granted, denied, permanentlyDenied }

class PermissionService {
  final Map<AppPermission, PermissionPhase> _status = {
    for (final p in AppPermission.values) p: PermissionPhase.notDetermined,
  };

  PermissionPhase statusOf(AppPermission permission) =>
      _status[permission] ?? PermissionPhase.notDetermined;

  void set(AppPermission permission, PermissionPhase phase) {
    _status[permission] = phase;
  }
}
