import 'registro_practica_pendiente.dart';

/// Cola persistente de registros de práctica generados sin conexión (RF-33,
/// T-062), pendientes de enviar a POST /practica/sync (T-063).
abstract class ColaPractica {
  Future<void> agregar(RegistroPracticaPendiente registro);
  Future<List<RegistroPracticaPendiente>> listarPendientes();
  Future<void> eliminar(String id);
}
