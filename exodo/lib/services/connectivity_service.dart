import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// [Punto 43] Servicio de monitoreo de conectividad.
/// Escucha cambios de red (WiFi, datos móviles, ninguno) y expone
/// un stream booleano para que la UI reaccione en tiempo real.
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._();
  factory ConnectivityService() => _instance;
  ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  StreamController<bool> _controller = StreamController<bool>.broadcast();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Stream<bool> get onConnectivityChanged => _controller.stream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  void init() {
    // Proteger contra re-init tras dispose: recrear controller si fue cerrado.
    if (_controller.isClosed) {
      _controller = StreamController<bool>.broadcast();
    }
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final online = !results.contains(ConnectivityResult.none);
      if (online != _isOnline) {
        _isOnline = online;
        if (!_controller.isClosed) _controller.add(online);
      }
    });
    // Consulta inicial
    _connectivity.checkConnectivity().then((results) {
      _isOnline = !results.contains(ConnectivityResult.none);
      if (!_controller.isClosed) _controller.add(_isOnline);
    });
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
