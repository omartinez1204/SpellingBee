import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_exception.dart';
import 'cola_practica.dart';
import 'monitor_conectividad.dart';
import 'monitor_conectividad_connectivity_plus.dart';
import 'practica_service.dart';
import 'registro_practica_pendiente.dart';

/// RF-33 (T-062): motor de sincronización de la cola de práctica offline.
/// Vive UNA sola vez por sesión de alumno — HomeScreen la crea al entrar y
/// la cierra al cerrar sesión (ver ese archivo) — no una por pantalla, para
/// que el reintento de 5 minutos siga corriendo aunque el alumno navegue
/// entre NivelesScreen/PracticaPalabraScreen, tal como pide el criterio de
/// RF-33 ("sin necesidad de que el alumno abra la app de nuevo").
///
/// RF-34 (T-064): además del reintento periódico, esta clase también
/// escucha el estado REAL de conectividad del dispositivo (ver
/// MonitorConectividad) para exponerlo a la UI (estadoConexion) y para
/// intentar sincronizar de inmediato apenas el dispositivo reconecta, sin
/// esperar al siguiente tick de 5 minutos. Antes de T-064, esta clase
/// inferían conectividad solo de forma indirecta — si un intento de
/// sincronización fallaba o tenía éxito — lo cual bastaba para RF-33 a
/// secas, pero no para RF-34: su criterio exige que el indicador visual
/// "cambie correctamente al desconectar/reconectar el dispositivo durante
/// una prueba manual", una señal que solo el sistema operativo puede dar
/// (RF-33 y RF-34 son señales relacionadas pero distintas — la segunda no
/// depende de que haya algo pendiente que sincronizar).
///
/// "Mientras el proceso siga vivo" sigue siendo el límite real: si el
/// sistema operativo mata la app por completo, tanto el reintento periódico
/// como la escucha de conectividad se detienen hasta que alguien vuelva a
/// abrirla — igual que CUALQUIER otra función de esta app hoy, no una
/// limitación nueva de esta tarea. Si se necesitara sincronizar con la app
/// completamente cerrada, eso es un alcance mucho mayor (señalarlo antes de
/// asumirlo).
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
    MonitorConectividad? monitorConectividad,
    Duration intervaloReintento = const Duration(minutes: 5),
  }) : _cola = cola, // ignore: prefer_initializing_formals
       _token = token, // ignore: prefer_initializing_formals
       _practicaService = practicaService ?? PracticaService(),
       _monitorConectividad = monitorConectividad ?? MonitorConectividadReal(),
       // ignore: prefer_initializing_formals
       _intervaloReintento = intervaloReintento;

  final ColaPractica _cola;
  final String _token;
  final PracticaService _practicaService;
  final MonitorConectividad _monitorConectividad;
  final Duration _intervaloReintento;
  Timer? _temporizador;
  StreamSubscription<EstadoConexion>? _suscripcionConectividad;
  bool _sincronizando = false;
  Completer<void>? _intentoEnCurso;

  int _pendientes = 0;

  // RF-34: optimista (en línea) hasta que iniciar() alcance a consultar el
  // estado real (ver más abajo) — evita un parpadeo de "sin conexión" al
  // arrancar en el caso común (el alumno sí tiene conexión), y de cualquier
  // forma se corrige de inmediato porque obtenerActual() es una consulta
  // local al sistema operativo, no una llamada de red.
  EstadoConexion _estadoConexion = EstadoConexion.enLinea;

  /// Consumido por IndicadorSincronizacion (RF-34, T-064) para el conteo de
  /// registros pendientes de sincronizar.
  int get pendientes => _pendientes;

  bool get sincronizando => _sincronizando;

  /// RF-34 (T-064): estado real de conectividad del dispositivo, para
  /// IndicadorSincronizacion.
  EstadoConexion get estadoConexion => _estadoConexion;

  final _controladorSincronizacionExitosa = StreamController<int>.broadcast();

  /// RF-34 (T-064): confirmación transitoria — emite la cantidad de
  /// registros justo después de que un lote se sincroniza con éxito (nunca
  /// en un intento vacío o fallido), para que IndicadorSincronizacion pueda
  /// mostrar un aviso breve sin tener que inferirlo comparando el valor
  /// anterior y nuevo de `pendientes`.
  Stream<int> get sincronizacionesExitosas =>
      _controladorSincronizacionExitosa.stream;

  // RF-33: "intentar enviarlos... en cuanto detecta conectividad" cubre dos
  // momentos naturales de reconexión — abrir la app con cola pendiente de
  // antes (aquí) y justo después de que un intento nuevo se quede pendiente
  // (encolar(), abajo) — y "reintentarlo cada 5 minutos... hasta lograrlo"
  // es este temporizador. Entre ambos, ningún registro depende de que el
  // alumno abra la práctica de nuevo para que se intente reenviar.
  //
  // RF-34: también arranca aquí la escucha de conectividad real (ver
  // _alCambiarConectividad) — vive mientras viva este objeto, igual que el
  // temporizador de arriba, y se cierra en dispose().
  Future<void> iniciar() async {
    _estadoConexion = await _monitorConectividad.obtenerActual();
    await _actualizarConteo();
    _suscripcionConectividad?.cancel();
    _suscripcionConectividad = _monitorConectividad.cambios.listen(
      _alCambiarConectividad,
    );
    unawaited(intentarSincronizar());
    _temporizador?.cancel();
    _temporizador = Timer.periodic(
      _intervaloReintento,
      (_) => intentarSincronizar(),
    );
  }

  void _alCambiarConectividad(EstadoConexion estado) {
    _estadoConexion = estado;
    notifyListeners();
    // RF-33/RF-34: reconectar es la oportunidad natural de vaciar la cola de
    // inmediato, sin esperar hasta el próximo tick de 5 minutos.
    if (estado.hayConexion) unawaited(intentarSincronizar());
  }

  Future<void> encolar(RegistroPracticaPendiente registro) async {
    await _cola.agregar(registro);
    await _actualizarConteo();
    unawaited(intentarSincronizar());
  }

  /// Idempotente frente a llamadas solapadas (el temporizador de 5 minutos,
  /// un encolar() reciente, un guardarPractica() en línea exitoso y ahora
  /// también una reconexión detectada por MonitorConectividad pueden
  /// coincidir): _sincronizando evita mandar el mismo lote dos veces en
  /// paralelo — aunque el servidor (T-063) ya deduplica por su cuenta vía el
  /// id de cliente, evitar el envío duplicado de entrada ahorra la vuelta de
  /// red. El check-y-marca (`if (_sincronizando) return; _sincronizando
  /// = true;`) queda completo antes del primer await, a propósito — con un
  /// await de por medio entre ambas líneas, dos llamadas solapadas podrían
  /// pasar las dos la comprobación antes de que cualquiera alcanzara a
  /// marcarla.
  Future<void> intentarSincronizar() async {
    if (_sincronizando) return;
    await _sincronizarUnaVez();
  }

  /// RF-38 (T-065): reintento MANUAL de lo que quedó en la cola — lo usa el
  /// botón "Reintentar" que aparece cuando guardar una práctica no llegó al
  /// servidor. A diferencia de intentarSincronizar() (que descarta la
  /// llamada si ya hay un envío en vuelo, y traga cualquier error):
  ///  - ESPERA a que termine un envío en vuelo (típicamente el que lanzó
  ///    encolar() un instante antes) en vez de descartarse, para que el
  ///    resultado que regresa refleje el estado real de la cola y no el de
  ///    una llamada ignorada; y
  ///  - REGRESA el error del intento (null si la cola quedó vacía) para que
  ///    quien lo llamó pueda volver a mostrar el mensaje si sigue sin poder
  ///    enviar, en vez de que el botón parezca no haber hecho nada.
  ///
  /// Sigue siendo el mismo envío idempotente de siempre (T-063): reintentar
  /// las veces que sea necesario nunca duplica un registro.
  Future<ApiException?> sincronizarAhora() async {
    while (_intentoEnCurso != null) {
      await _intentoEnCurso!.future;
    }
    return _sincronizarUnaVez();
  }

  /// Cuerpo compartido por intentarSincronizar() y sincronizarAhora(). Marca
  /// _sincronizando de forma síncrona (antes del primer await) — ver el
  /// comentario de intentarSincronizar(). Regresa el error del intento, o
  /// null si no hubo nada que enviar o el envío tuvo éxito.
  Future<ApiException?> _sincronizarUnaVez() async {
    _sincronizando = true;
    final enCurso = _intentoEnCurso = Completer<void>();
    ApiException? errorDelIntento;
    try {
      final pendientesActuales = await _cola.listarPendientes();
      if (pendientesActuales.isEmpty) return null;

      await _practicaService.sincronizarLote(pendientesActuales, _token);
      // Solo se elimina lo que de verdad viajó en ESTE lote — un registro
      // encolado a medio envío (mientras este await estaba en vuelo) no
      // estaba en pendientesActuales y por tanto no se toca aquí; el
      // próximo intento lo recoge (RF-33: nunca se descarta sin confirmar).
      for (final registro in pendientesActuales) {
        await _cola.eliminar(registro.id);
      }
      // RF-34: la confirmación transitoria SOLO corresponde a un lote que de
      // verdad se envió y se limpió arriba — nunca a un intento vacío (ya se
      // salió arriba) ni a uno fallido (ver catch).
      _controladorSincronizacionExitosa.add(pendientesActuales.length);
      return null;
    } on ApiException catch (e) {
      // Sin conexión, backend no disponible, o cualquier otro fallo: la
      // cola se queda tal cual. El próximo tick de 5 minutos (o el próximo
      // encolar()/iniciar()) vuelve a intentar — sin intervención del
      // alumno, tal como pide el criterio de RF-33. El error solo se
      // devuelve (no se propaga) para quien lo pidió, ver sincronizarAhora().
      errorDelIntento = e;
      return e;
    } catch (_) {
      // Mismo criterio para un fallo que no vino de la API (p. ej. leer o
      // borrar de la cola en disco): la cola se queda tal cual.
      errorDelIntento = const ApiException(
        'ERROR',
        'No se pudo enviar tu práctica. Inténtalo de nuevo en unos minutos.',
      );
      return errorDelIntento;
    } finally {
      _sincronizando = false;
      await _actualizarConteo();
      _intentoEnCurso = null;
      enCurso.complete();
    }
  }

  Future<void> _actualizarConteo() async {
    _pendientes = (await _cola.listarPendientes()).length;
    notifyListeners();
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    _suscripcionConectividad?.cancel();
    _controladorSincronizacionExitosa.close();
    super.dispose();
  }
}
