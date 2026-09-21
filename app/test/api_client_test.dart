import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/api_exception.dart';
import 'package:spelling_bee/core/monitor_conectividad.dart';

/// T-065 (RF-38): estas pruebas son la base de todo el manejo uniforme de
/// "backend no disponible" — si ApiClient no clasifica bien statusCode aquí,
/// ninguna pantalla que dependa de ApiException.esBackendNoDisponible podría
/// distinguir un 5xx/sin-conexión de un 4xx normal, sin importar qué tan
/// bien esté hecha la UI de cada una.
class _ClienteConRespuestaFija extends http.BaseClient {
  _ClienteConRespuestaFija(this.statusCode, this.cuerpo);

  final int statusCode;
  final String cuerpo;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(cuerpo)),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _ClienteQueNuncaResponde extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // Nunca completa dentro del timeout de 10s de ApiClient — simula un
    // servidor inalcanzable (a diferencia de uno que sí responde, aunque
    // sea con un error).
    return Completer<http.StreamedResponse>().future;
  }
}

class _ClienteQueLanzaExcepcionDeRed extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw const SocketExceptionFalsa();
  }
}

/// No se usa dart:io SocketException real a propósito — no hace falta un
/// socket de verdad para probar que ApiClient envuelve CUALQUIER excepción
/// de transporte (no solo SocketException) como SIN_CONEXION.
class SocketExceptionFalsa implements Exception {
  const SocketExceptionFalsa();
}

class _MonitorFijo implements MonitorConectividad {
  _MonitorFijo(this._estado);

  final EstadoConexion _estado;

  @override
  Future<EstadoConexion> obtenerActual() async => _estado;

  @override
  Stream<EstadoConexion> get cambios => const Stream.empty();
}

class _MonitorQueFalla implements MonitorConectividad {
  @override
  Future<EstadoConexion> obtenerActual() =>
      Future.error(StateError('sin canal de plataforma'));

  @override
  Stream<EstadoConexion> get cambios => const Stream.empty();
}

class _MonitorQueNuncaResponde implements MonitorConectividad {
  @override
  Future<EstadoConexion> obtenerActual() =>
      Completer<EstadoConexion>().future;

  @override
  Stream<EstadoConexion> get cambios => const Stream.empty();
}

void main() {
  group('ApiClient._enviar() — clasificación de errores (RF-38, T-065)', () {
    test('2xx: regresa el cuerpo normalmente, sin lanzar nada', () async {
      final cliente = ApiClient(
        httpClient: _ClienteConRespuestaFija(200, '{"ok": true}'),
      );

      final resultado = await cliente.get('/algo');

      expect(resultado, {'ok': true});
    });

    test(
      '4xx con {error:{code,message}}: ApiException con ese code/message, esBackendNoDisponible=false',
      () async {
        final cliente = ApiClient(
          httpClient: _ClienteConRespuestaFija(
            400,
            jsonEncode({
              'error': {
                'code': 'VALIDACION',
                'message': 'La matrícula es obligatoria.',
              },
            }),
          ),
        );

        try {
          await cliente.get('/algo');
          fail('Debió lanzar ApiException');
        } on ApiException catch (e) {
          expect(e.code, 'VALIDACION');
          expect(e.message, 'La matrícula es obligatoria.');
          expect(e.statusCode, 400);
          expect(
            e.esBackendNoDisponible,
            isFalse,
            reason: 'un 4xx es un error sobre lo que la persona hizo, no del backend',
          );
        }
      },
    );

    test(
      '401/403: tampoco cuentan como backend no disponible',
      () async {
        final cliente = ApiClient(
          httpClient: _ClienteConRespuestaFija(
            403,
            jsonEncode({
              'error': {'code': 'PROHIBIDO', 'message': 'No autorizado.'},
            }),
          ),
        );

        try {
          await cliente.get('/algo');
          fail('Debió lanzar ApiException');
        } on ApiException catch (e) {
          expect(e.statusCode, 403);
          expect(e.esBackendNoDisponible, isFalse);
        }
      },
    );

    test(
      'RF-38: un 500 (ERROR_INTERNO, ver HttpExceptionFilter) SÍ cuenta como backend no disponible',
      () async {
        final cliente = ApiClient(
          httpClient: _ClienteConRespuestaFija(
            500,
            jsonEncode({
              'error': {
                'code': 'ERROR_INTERNO',
                'message': 'Ocurrió un error inesperado. Intenta de nuevo más tarde.',
              },
            }),
          ),
        );

        try {
          await cliente.get('/algo');
          fail('Debió lanzar ApiException');
        } on ApiException catch (e) {
          expect(e.statusCode, 500);
          expect(e.esBackendNoDisponible, isTrue);
        }
      },
    );

    test(
      'RF-38: un 503 también cuenta, aunque el body no traiga la forma {error:{...}} esperada',
      () async {
        // Un 503 real (p. ej. de un proxy/balanceador delante del backend,
        // no del propio NestJS) puede no traer el contrato JSON uniforme —
        // esBackendNoDisponible no debe depender de que sí lo traiga.
        final cliente = ApiClient(
          httpClient: _ClienteConRespuestaFija(503, 'Service Unavailable'),
        );

        try {
          await cliente.get('/algo');
          fail('Debió lanzar ApiException');
        } on ApiException catch (e) {
          expect(e.statusCode, 503);
          expect(e.esBackendNoDisponible, isTrue);
        }
      },
    );

    test(
      'RF-38: timeout (servidor inalcanzable) da SIN_CONEXION con statusCode null y esBackendNoDisponible=true — con el dispositivo en línea, dice que es el SERVIDOR el que tarda',
      () async {
        final cliente = ApiClient(
          httpClient: _ClienteQueNuncaResponde(),
          monitorConectividad: _MonitorFijo(EstadoConexion.enLinea),
        );

        try {
          await cliente.get('/algo');
          fail('Debió lanzar ApiException');
        } on ApiException catch (e) {
          expect(e.code, 'SIN_CONEXION');
          expect(e.statusCode, isNull);
          expect(e.esBackendNoDisponible, isTrue);
          expect(
            e.message,
            'El servidor tardó demasiado en responder. Inténtalo de nuevo en unos minutos.',
          );
        }
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'RF-38: una excepción de transporte (sin red) da SIN_CONEXION con statusCode null',
      () async {
        final cliente = ApiClient(
          httpClient: _ClienteQueLanzaExcepcionDeRed(),
          monitorConectividad: _MonitorFijo(EstadoConexion.enLinea),
        );

        try {
          await cliente.get('/algo');
          fail('Debió lanzar ApiException');
        } on ApiException catch (e) {
          expect(e.code, 'SIN_CONEXION');
          expect(e.statusCode, isNull);
          expect(e.esBackendNoDisponible, isTrue);
        }
      },
    );
  });

  // T-071 (RNF-01): un cuerpo de error que NO cumple { error: { code, message } }
  // — lo que mandaría un gateway o la forma por defecto de Nest — no debe
  // reventar con un TypeError de Dart (la persona no veía ningún mensaje) ni
  // dejar pasar su texto, que suele venir en inglés.
  group('ApiClient._enviar() — cuerpos de error fuera del contrato (T-071)', () {
    const mensajeGenerico = 'Ocurrió un error inesperado.';

    Future<ApiException> fallar(int status, String cuerpo) async {
      final cliente = ApiClient(
        httpClient: _ClienteConRespuestaFija(status, cuerpo),
      );
      try {
        await cliente.get('/algo');
      } on ApiException catch (e) {
        return e;
      }
      fail('Debió lanzar ApiException');
    }

    test(
      'forma por defecto de Nest ("error" es una cadena): mensaje genérico en español, no el texto en inglés ni un TypeError',
      () async {
        final e = await fallar(
          404,
          '{"statusCode":404,"message":"Cannot GET /x","error":"Not Found"}',
        );

        expect(e.code, 'ERROR');
        expect(e.message, mensajeGenerico);
        expect(e.statusCode, 404);
        expect(e.esBackendNoDisponible, isFalse);
      },
    );

    test('la misma forma con un 5xx sigue contando como backend no disponible', () async {
      final e = await fallar(
        502,
        '{"statusCode":502,"message":"Bad Gateway","error":"Bad Gateway"}',
      );

      expect(e.message, mensajeGenerico);
      expect(e.statusCode, 502);
      expect(e.esBackendNoDisponible, isTrue);
    });

    test('{"error": "texto"} sin más: no se muestra el texto ajeno', () async {
      final e = await fallar(401, '{"error":"Unauthorized"}');

      expect(e.message, mensajeGenerico);
      expect(e.message, isNot(contains('Unauthorized')));
    });

    test('"code" o "message" que no son cadenas, o vacíos, caen a los valores por defecto', () async {
      final e = await fallar(
        400,
        '{"error":{"code":42,"message":{"texto":"Bad request"}}}',
      );
      expect(e.code, 'ERROR');
      expect(e.message, mensajeGenerico);

      final vacio = await fallar(400, '{"error":{"code":"","message":""}}');
      expect(vacio.code, 'ERROR');
      expect(vacio.message, mensajeGenerico);
    });

    test('la raíz del cuerpo no es un objeto (arreglo, null, número): mensaje genérico', () async {
      for (final cuerpo in ['[]', 'null', '7', '"Internal Server Error"']) {
        final e = await fallar(500, cuerpo);
        expect(e.message, mensajeGenerico, reason: 'cuerpo: $cuerpo');
        expect(e.statusCode, 500);
      }
    });

    test('con "code" válido y sin "message": conserva el code y usa el mensaje genérico', () async {
      final e = await fallar(409, '{"error":{"code":"CONFLICTO"}}');

      expect(e.code, 'CONFLICTO');
      expect(e.message, mensajeGenerico);
    });
  });

  // RF-38 (T-065): "no tienes conexión" (el dispositivo no tiene red — lo que
  // el indicador de T-064 ya muestra) y "el servidor no responde" (hay red,
  // pero el backend está caído) llegan a ApiClient como la MISMA falla de
  // transporte; el mensaje se decide por el estado real del dispositivo.
  group('ApiClient — mensaje según el estado real de la conexión (RF-38)', () {
    Future<ApiException> fallar(MonitorConectividad? monitor) async {
      final cliente = ApiClient(
        httpClient: _ClienteQueLanzaExcepcionDeRed(),
        monitorConectividad: monitor,
      );
      try {
        await cliente.get('/algo');
      } on ApiException catch (e) {
        return e;
      }
      fail('Debió lanzar ApiException');
    }

    test('sin red en el dispositivo: dice que no hay conexión a internet', () async {
      final e = await fallar(_MonitorFijo(EstadoConexion.sinConexion));

      expect(
        e.message,
        'No tienes conexión a internet. Conéctate e inténtalo de nuevo.',
      );
      expect(e.code, 'SIN_CONEXION');
    });

    test(
      'con red en el dispositivo (servidor caído): dice que es el SERVIDOR el que no responde, sin mandar a "verificar la conexión"',
      () async {
        final e = await fallar(_MonitorFijo(EstadoConexion.enLinea));

        expect(
          e.message,
          'El servidor no responde en este momento. Inténtalo de nuevo en unos minutos.',
        );
        expect(
          e.message,
          isNot(contains('conexión')),
          reason: 'con el indicador de T-064 en verde, pedir "verifica tu conexión" se contradice',
        );
        expect(
          e.code,
          'SIN_CONEXION',
          reason: 'el code no cambia: la cola de práctica offline (T-062) se activa igual en ambos casos',
        );
      },
    );

    test(
      'si no se puede consultar el estado (error de plataforma), cae al mensaje neutro de siempre en vez de fallar al reportar la falla',
      () async {
        final e = await fallar(_MonitorQueFalla());

        expect(
          e.message,
          'No se pudo conectar con el servidor. Verifica tu conexión e intenta de nuevo.',
        );
        expect(e.code, 'SIN_CONEXION');
      },
    );

    test(
      'si consultar el estado tarda más de 1 s, tampoco se cuelga el reporte del error',
      () async {
        final e = await fallar(_MonitorQueNuncaResponde());

        expect(
          e.message,
          'No se pudo conectar con el servidor. Verifica tu conexión e intenta de nuevo.',
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('sin monitor inyectado y sin plataforma (plain test), tampoco truena', () async {
      final e = await fallar(null);

      expect(e.code, 'SIN_CONEXION');
      expect(e.esBackendNoDisponible, isTrue);
    });
  });
}
