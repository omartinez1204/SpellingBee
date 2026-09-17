import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/cola_practica.dart';
import 'package:spelling_bee/core/monitor_conectividad.dart';
import 'package:spelling_bee/core/practica_service.dart';
import 'package:spelling_bee/core/registro_practica_pendiente.dart';
import 'package:spelling_bee/core/sincronizador_practica.dart';
import 'package:spelling_bee/widgets/indicador_sincronizacion.dart';

// T-064 (RF-34): testWidgets() (hay que dibujar el widget), así que a
// diferencia de sincronizador_practica_test.dart (plain test(), dart:io
// real), aquí ColaPractica y MonitorConectividad se sustituyen por fakes
// 100% en memoria — mismo criterio ya establecido en
// practica_palabra_screen_test.dart para sus propios seams. El
// SincronizadorPractica en sí es el objeto REAL: este archivo prueba que
// IndicadorSincronizacion lo refleja correctamente, no lo vuelve a probar
// a él (eso ya lo cubre sincronizador_practica_test.dart).
class _ColaPracticaMemoria implements ColaPractica {
  final List<RegistroPracticaPendiente> _registros = [];

  @override
  Future<void> agregar(RegistroPracticaPendiente registro) async {
    _registros.add(registro);
  }

  @override
  Future<List<RegistroPracticaPendiente>> listarPendientes() async =>
      List.unmodifiable(_registros);

  @override
  Future<void> eliminar(String id) async {
    _registros.removeWhere((registro) => registro.id == id);
  }
}

class _MonitorConectividadFalso implements MonitorConectividad {
  _MonitorConectividadFalso({EstadoConexion inicial = EstadoConexion.enLinea})
    : _actual = inicial;

  final EstadoConexion _actual;
  final _controlador = StreamController<EstadoConexion>.broadcast();

  @override
  Future<EstadoConexion> obtenerActual() async => _actual;

  @override
  Stream<EstadoConexion> get cambios => _controlador.stream;

  void cerrar() => _controlador.close();
}

class _ClienteHttpQueFalla extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'error': {'code': 'VALIDACION', 'message': 'no disponible'},
          }),
        ),
      ),
      404,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _ClienteHttpSiempreOk extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode('{}')),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

RegistroPracticaPendiente _registroDePrueba() => RegistroPracticaPendiente(
  id: 'id-1',
  idPalabra: 10,
  tiempoSegundos: 42,
  oracionAlumno: 'This is my business.',
  deletreoCorrecto: true,
  fechaLocal: '2026-09-17',
);

void main() {
  testWidgets(
    'RF-34: con conexión y sin pendientes, muestra el ícono de en línea sin badge de conteo',
    (tester) async {
      final sincronizador = SincronizadorPractica(
        cola: _ColaPracticaMemoria(),
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: _ClienteHttpSiempreOk()),
        ),
        monitorConectividad: _MonitorConectividadFalso(),
      );
      addTearDown(sincronizador.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [IndicadorSincronizacion(sincronizador: sincronizador)],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.wifi), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('indicador-sincronizacion')),
          matching: find.byType(Text),
        ),
        findsNothing,
        reason: 'sin pendientes no debe mostrarse ningún badge de conteo',
      );
    },
  );

  testWidgets(
    'RF-34: sin conexión y con pendientes, muestra el ícono de sin conexión y el conteo, y ambos se actualizan en vivo',
    (tester) async {
      final monitorFalso = _MonitorConectividadFalso(
        inicial: EstadoConexion.sinConexion,
      );
      final sincronizador = SincronizadorPractica(
        cola: _ColaPracticaMemoria(),
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: _ClienteHttpQueFalla()),
        ),
        monitorConectividad: monitorFalso,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [IndicadorSincronizacion(sincronizador: sincronizador)],
            ),
          ),
        ),
      );

      // Antes de iniciar(): valor optimista por defecto (en línea).
      expect(find.byIcon(Icons.wifi), findsOneWidget);

      await sincronizador.iniciar();
      await tester.pump();

      expect(
        find.byIcon(Icons.wifi_off),
        findsOneWidget,
        reason: 'iniciar() debió consultar MonitorConectividad y corregir el ícono',
      );

      await sincronizador.encolar(_registroDePrueba());
      await tester.pump();

      expect(
        find.text('1'),
        findsOneWidget,
        reason: 'un registro pendiente (el envío falla con _ClienteHttpQueFalla) debe reflejarse en el conteo',
      );

      // Deja asentar el intentarSincronizar() disparado por encolar() (falla
      // y no cambia nada, pero de cualquier forma toca el estado). Se
      // dispone AQUÍ, no vía addTearDown: iniciar() deja un Timer.periodic
      // real corriendo, y el invariante de AutomatedTestWidgetsFlutterBinding
      // ("no debe quedar ningún Timer pendiente") se revisa antes de que los
      // addTearDown lleguen a ejecutarse — solo llamar dispose() dentro del
      // propio cuerpo de la prueba lo cancela a tiempo.
      await tester.pumpAndSettle();
      sincronizador.dispose();
      monitorFalso.cerrar();
    },
  );

  testWidgets(
    'RF-34: aparece una confirmación transitoria apenas se sincroniza un lote pendiente con éxito',
    (tester) async {
      final sincronizador = SincronizadorPractica(
        cola: _ColaPracticaMemoria(),
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: _ClienteHttpSiempreOk()),
        ),
        monitorConectividad: _MonitorConectividadFalso(),
      );
      addTearDown(sincronizador.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [IndicadorSincronizacion(sincronizador: sincronizador)],
            ),
          ),
        ),
      );

      expect(
        find.text('Se sincronizó 1 práctica pendiente.'),
        findsNothing,
        reason: 'todavía no ha pasado nada que deba confirmarse',
      );

      await sincronizador.encolar(_registroDePrueba());
      await tester.pumpAndSettle();

      expect(find.text('Se sincronizó 1 práctica pendiente.'), findsOneWidget);
      expect(
        find.text('1'),
        findsNothing,
        reason: 'el envío tuvo éxito (cliente que siempre responde 200) — ya no debe quedar pendiente',
      );
    },
  );

  testWidgets(
    'RF-34: la confirmación transitoria usa plural cuando el lote sincronizado tiene más de un registro',
    (tester) async {
      final cola = _ColaPracticaMemoria();
      await cola.agregar(_registroDePrueba());
      await cola.agregar(
        RegistroPracticaPendiente(
          id: 'id-2',
          idPalabra: 11,
          tiempoSegundos: 30,
          oracionAlumno: 'Another sentence.',
          deletreoCorrecto: false,
          fechaLocal: '2026-09-17',
        ),
      );
      final sincronizador = SincronizadorPractica(
        cola: cola,
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: _ClienteHttpSiempreOk()),
        ),
        monitorConectividad: _MonitorConectividadFalso(),
      );
      addTearDown(sincronizador.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [IndicadorSincronizacion(sincronizador: sincronizador)],
            ),
          ),
        ),
      );

      await sincronizador.intentarSincronizar();
      await tester.pumpAndSettle();

      expect(
        find.text('Se sincronizaron 2 prácticas pendientes.'),
        findsOneWidget,
      );
    },
  );
}
