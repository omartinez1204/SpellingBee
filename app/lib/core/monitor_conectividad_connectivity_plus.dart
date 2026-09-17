import 'package:connectivity_plus/connectivity_plus.dart';

import 'monitor_conectividad.dart';

/// Implementación real de MonitorConectividad (RF-34, T-064), sobre el
/// plugin connectivity_plus — ver el comentario en pubspec.yaml sobre la
/// versión pineada contra compileSdk=36.
class MonitorConectividadReal implements MonitorConectividad {
  MonitorConectividadReal({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  // connectivity_plus reporta una LISTA porque un dispositivo puede tener
  // más de una interfaz activa a la vez (p. ej. wifi + datos móviles). Para
  // RF-34 solo importa si AL MENOS una implica salida de red real —
  // ConnectivityResult.none es el único valor que no cuenta como conexión.
  EstadoConexion _resolver(List<ConnectivityResult> resultados) =>
      resultados.any((resultado) => resultado != ConnectivityResult.none)
      ? EstadoConexion.enLinea
      : EstadoConexion.sinConexion;

  @override
  Future<EstadoConexion> obtenerActual() async =>
      _resolver(await _connectivity.checkConnectivity());

  @override
  Stream<EstadoConexion> get cambios =>
      _connectivity.onConnectivityChanged.map(_resolver).distinct();
}
