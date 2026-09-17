import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cola_practica.dart';
import 'practica_service.dart';
import 'registro_practica_pendiente.dart';

/// RF-33 (T-062): motor de sincronización de la cola de práctica offline.
/// Vive UNA sola vez por sesión de alumno — HomeScreen la crea al entrar y
/// la cierra al cerrar sesión (ver ese archivo) — no una por pantalla, para
/// que el reintento de 5 minutos siga corriendo aunque el alumno navegue
/// entre NivelesScreen/PracticaPalabraScreen, tal como pide el criterio de
/// RF-33 ("sin necesidad de que el alumno abra la app de nuevo").
///
/// [DECISIÓN DE DISEÑO, A CONFIRMAR]: esta app no tiene ningún plugin de
/// estado de conectividad (connectivity_plus u otro) ni infraestructura de
/// tarea en segundo plano tipo WorkManager/BGTaskScheduler — nada de eso
/// existía antes de T-062 y no se agregó aquí. "Detectar conectividad" se
/// resuelve con la propia llamada de sincronización: si tiene éxito, había
/// conectividad; si falla, no la había (o el endpoint de T-063 todavía no
/// existe). Esto cubre el texto literal de RF-33 sin depender de una señal
/// de radio del sistema operativo (que además no garantiza que el backend
/// en sí sea alcanzable). Y "mientras el proceso siga vivo" es el límite
/// real: si el sistema operativo mata la app por completo, el reintento se
/// detiene hasta que alguien vuelva a abrirla — igual que CUALQUIER otra
/// función de esta app hoy, no una limitación nueva de esta tarea. Si se
/// necesitara sincronizar con la app completamente cerrada, eso es un
/// alcance mucho mayor (señalarlo antes de asumirlo).
class SincronizadorPractica extends ChangeNotifier {
  // No usa initializing formals (this._cola, etc.) a propósito: los campos
  // son privados pero el parámetro debe seguir siendo público para que otros
  // archivos (practica_palabra_screen.dart, niveles_screen.dart,
  // home_screen.dart) puedan seguir construyendo esta clase — un
  // initializing formal sobre un campo privado ata el nombre del parámetro
  // al del campo, que ningún otro archivo podría referenciar.
  SincronizadorPractica({
    required ColaPractica cola,
    required String token,
    PracticaService? practicaService,
    Duration intervaloReintento = const Duration(minutes: 5),
  }) : _cola = cola, // ignore: prefer_initializing_formals
       _token = token, // ignore: prefer_initializing_formals
       _practicaService = practicaService ?? PracticaService(),
       // ignore: prefer_initializing_formals
       _intervaloReintento = intervaloReintento;

  final ColaPractica _cola;
  final String _token;
  final PracticaService _practicaService;
  final Duration _intervaloReintento;
  Timer? _temporizador;
  bool _sincronizando = false;

  int _pendientes = 0;

  /// Expuesto para un futuro indicador visual (RF-34, T-064) — esta tarea no
  /// agrega ninguna UI propia, solo mantiene el conteo al día vía
  /// notifyListeners() para que quien lo necesite después ya lo encuentre
  /// disponible.
  int get pendientes => _pendientes;

  bool get sincronizando => _sincronizando;

  // RF-33: "intentar enviarlos... en cuanto detecta conectividad" cubre dos
  // momentos naturales de reconexión — abrir la app con cola pendiente de
  // antes (aquí) y justo después de que un intento nuevo se quede pendiente
  // (encolar(), abajo) — y "reintentarlo cada 5 minutos... hasta lograrlo"
  // es este temporizador. Entre ambos, ningún registro depende de que el
  // alumno abra la práctica de nuevo para que se intente reenviar.
  Future<void> iniciar() async {
    await _actualizarConteo();
    unawaited(intentarSincronizar());
    _temporizador?.cancel();
    _temporizador = Timer.periodic(
      _intervaloReintento,
      (_) => intentarSincronizar(),
    );
  }

  Future<void> encolar(RegistroPracticaPendiente registro) async {
    await _cola.agregar(registro);
    await _actualizarConteo();
    unawaited(intentarSincronizar());
  }

  /// Idempotente frente a llamadas solapadas (el temporizador de 5 minutos,
  /// un encolar() reciente y un guardarPractica() en línea exitoso pueden
  /// coincidir): _sincronizando evita mandar el mismo lote dos veces en
  /// paralelo mientras T-063 todavía no exista para deduplicar del lado del
  /// servidor. El check-y-marca (`if (_sincronizando) return; _sincronizando
  /// = true;`) queda completo antes del primer await, a propósito — con un
  /// await de por medio entre ambas líneas, dos llamadas solapadas podrían
  /// pasar las dos la comprobación antes de que cualquiera alcanzara a
  /// marcarla.
  Future<void> intentarSincronizar() async {
    if (_sincronizando) return;
    _sincronizando = true;
    try {
      final pendientesActuales = await _cola.listarPendientes();
      if (pendientesActuales.isEmpty) return;

      await _practicaService.sincronizarLote(pendientesActuales, _token);
      // Solo se elimina lo que de verdad viajó en ESTE lote — un registro
      // encolado a medio envío (mientras este await estaba en vuelo) no
      // estaba en pendientesActuales y por tanto no se toca aquí; el
      // próximo intento lo recoge (RF-33: nunca se descarta sin confirmar).
      for (final registro in pendientesActuales) {
        await _cola.eliminar(registro.id);
      }
    } catch (_) {
      // Sin conexión, o el endpoint de T-063 todavía no existe: la cola se
      // queda tal cual. El próximo tick de 5 minutos (o el próximo
      // encolar()/iniciar()) vuelve a intentar — sin intervención del
      // alumno, tal como pide el criterio de RF-33.
    } finally {
      _sincronizando = false;
      await _actualizarConteo();
    }
  }

  Future<void> _actualizarConteo() async {
    _pendientes = (await _cola.listarPendientes()).length;
    notifyListeners();
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }
}
