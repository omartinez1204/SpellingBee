/// RF-34 (T-064): estado de conectividad REAL del dispositivo (el radio de
/// red del sistema operativo). T-062/T-063 (SincronizadorPractica) hasta
/// ahora solo inferían conectividad de forma indirecta — si un intento de
/// sincronización tenía éxito o fallaba — lo cual bastaba para RF-33, pero
/// no alcanza para RF-34: su criterio exige que el indicador visual "cambie
/// correctamente al desconectar/reconectar el dispositivo durante una
/// prueba manual", es decir, que refleje la señal del sistema operativo en
/// tiempo real, incluso si el alumno nunca llega a intentar sincronizar
/// nada mientras está sin conexión.
enum EstadoConexion {
  enLinea,
  sinConexion;

  bool get hayConexion => this == EstadoConexion.enLinea;
}

/// Interfaz inyectable — mismo motivo que ColaPractica/ReproductorAudio/
/// GrabadorAudio en el resto de la app: permite una implementación real
/// (MonitorConectividadReal, sobre connectivity_plus) y una falsa 100% en
/// memoria para pruebas, sin canal de plataforma de por medio.
abstract class MonitorConectividad {
  /// Estado actual, consultado bajo demanda (p. ej. al arrancar).
  Future<EstadoConexion> obtenerActual();

  /// Emite cada vez que cambia el estado de conectividad del dispositivo.
  /// La implementación real nunca repite el mismo valor dos veces seguidas.
  Stream<EstadoConexion> get cambios;
}
