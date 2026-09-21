import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/admin_alumnos_service.dart';
import 'package:spelling_bee/core/admin_catalogo_controller.dart';
import 'package:spelling_bee/core/admin_palabras_service.dart';
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/api_exception.dart';
import 'package:spelling_bee/core/detalle_alumno_controller.dart';
import 'package:spelling_bee/core/monitor_conectividad.dart';
import 'package:spelling_bee/core/niveles_service.dart';
import 'package:spelling_bee/core/seguimiento_alumnos_controller.dart';

// T-070 (RNF-12): el backend ya pagina (T-024/T-050/T-051); estas pruebas
// cubren el CONSUMO de esas páginas desde Flutter — que sumar página tras
// página nunca repita ni contamine lo ya mostrado. Un backend falso que
// pagina igual que el real (skip/take sobre una lista en memoria), con un
// gancho para RETENER o hacer FALLAR una respuesta y así reproducir las
// carreras "llega tarde una página vieja" / "llegan fuera de orden".
const _limite = 20;

class _MonitorEnLinea implements MonitorConectividad {
  @override
  Future<EstadoConexion> obtenerActual() async => EstadoConexion.enLinea;

  @override
  Stream<EstadoConexion> get cambios => const Stream.empty();
}

class _Backend extends http.BaseClient {
  _Backend({
    this.palabras = const [],
    this.alumnos = const [],
    this.intentos = const [],
  });

  final List<Map<String, dynamic>> palabras;
  final List<Map<String, dynamic>> alumnos;
  final List<Map<String, dynamic>> intentos;

  /// Se ejecuta antes de responder cada petición: esperar a un Completer la
  /// RETIENE (respuesta lenta); lanzar la hace FALLAR.
  Future<void> Function(http.BaseRequest request)? antesDeResponder;
  final List<String> peticiones = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    peticiones.add(
      '${request.method} ${request.url.path}?${request.url.query}',
    );
    await antesDeResponder?.call(request);
    final q = request.url.queryParameters;
    final pagina = int.tryParse(q['pagina'] ?? '') ?? 1;
    final limite = int.tryParse(q['limite'] ?? '') ?? _limite;
    final ruta = request.url.path;

    if (ruta == '/niveles') {
      return _json([
        {'id': 2, 'nombre': 'Fácil', 'orden': 1},
        {'id': 3, 'nombre': 'Intermedio', 'orden': 2},
        {'id': 4, 'nombre': 'Difícil', 'orden': 3},
      ]);
    }

    if (ruta == '/admin/palabras' && request.method == 'GET') {
      return _json(_pagina('palabras', palabras, pagina, limite));
    }
    if (ruta == '/admin/palabras' && request.method == 'POST') {
      final cuerpo = jsonDecode((request as http.Request).body) as Map;
      final nueva = {
        'id': palabras.length + 1,
        'texto': cuerpo['texto'],
        'id_nivel': cuerpo['id_nivel'],
        'significado_es': null,
        'oracion_ejemplo': null,
        'url_audio': null,
        'completa': false,
        'oculta': false,
      };
      // Igual que el backend real: ORDER BY id asc — la nueva va AL FINAL.
      palabras.add(nueva);
      return _json(nueva, 201);
    }

    if (ruta == '/admin/alumnos') {
      final semestre = int.tryParse(q['semestre'] ?? '');
      final filtrados = semestre == null
          ? alumnos
          : alumnos.where((a) => a['semestre'] == semestre).toList();
      return _json(_pagina('alumnos', filtrados, pagina, limite));
    }

    if (ruta.startsWith('/admin/alumnos/')) {
      final nivel = int.tryParse(q['nivel'] ?? '');
      final filtrados = nivel == null
          ? intentos
          : intentos.where((i) => i['_nivel'] == nivel).toList();
      final cuerpo = _pagina('intentos', filtrados, pagina, limite);
      cuerpo['intentos'] = [
        for (final i in cuerpo['intentos'] as List)
          {
            for (final e in (i as Map<String, dynamic>).entries)
              if (e.key != '_nivel') e.key: e.value,
          },
      ];
      return _json(cuerpo);
    }

    throw StateError('Ruta no simulada: ${request.method} $ruta');
  }

  Map<String, dynamic> _pagina(
    String clave,
    List<Map<String, dynamic>> todos,
    int pagina,
    int limite,
  ) {
    final inicio = (pagina - 1) * limite;
    final fin = (inicio + limite).clamp(0, todos.length);
    return {
      clave: inicio >= todos.length
          ? <Map<String, dynamic>>[]
          : todos.sublist(inicio, fin),
      'total': todos.length,
      'pagina': pagina,
      'limite': limite,
      'total_paginas': (todos.length / limite).ceil().clamp(1, 1 << 30),
    };
  }

  http.StreamedResponse _json(Object cuerpo, [int status = 200]) {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(cuerpo))),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

List<Map<String, dynamic>> _palabras(int n) => [
  for (var i = 1; i <= n; i++)
    {
      'id': i,
      'texto': 'palabra-$i',
      'id_nivel': 2,
      'significado_es': null,
      'oracion_ejemplo': null,
      'url_audio': null,
      'completa': false,
      'oculta': false,
    },
];

// Semestre 3 los pares, semestre 5 los impares.
List<Map<String, dynamic>> _alumnos(int n) => [
  for (var i = 1; i <= n; i++)
    {
      'id': i,
      'matricula': 'M$i',
      'nombre': 'Alumno$i',
      'apellido_paterno': 'P',
      'apellido_materno': 'M',
      'carrera': 'Ingeniería en Desarrollo de Software',
      'semestre': i.isEven ? 3 : 5,
      'avance': <Map<String, dynamic>>[],
    },
];

// Nivel 2 los pares, nivel 3 los impares (el campo interno _nivel solo lo
// usa el backend falso para filtrar; no viaja en la respuesta).
List<Map<String, dynamic>> _intentos(int n) => [
  for (var i = 1; i <= n; i++)
    {
      'id_palabra': i,
      'palabra': 'palabra-$i',
      'tiempo_segundos': 10,
      'oracion_alumno': 'intento-$i',
      '_nivel': i.isEven ? 2 : 3,
    },
];

ApiClient _api(_Backend backend) =>
    ApiClient(httpClient: backend, monitorConectividad: _MonitorEnLinea());

AdminCatalogoController _catalogo(_Backend backend) => AdminCatalogoController(
  token: 't',
  palabrasService: AdminPalabrasService(apiClient: _api(backend)),
  nivelesService: NivelesService(apiClient: _api(backend)),
);

SeguimientoAlumnosController _seguimiento(_Backend backend) =>
    SeguimientoAlumnosController(
      token: 't',
      adminAlumnosService: AdminAlumnosService(apiClient: _api(backend)),
      nivelesService: NivelesService(apiClient: _api(backend)),
    );

DetalleAlumnoController _detalle(_Backend backend) => DetalleAlumnoController(
  token: 't',
  idAlumno: 7,
  adminAlumnosService: AdminAlumnosService(apiClient: _api(backend)),
  nivelesService: NivelesService(apiClient: _api(backend)),
);

/// Retiene toda petición que cumpla [cuando] hasta que se libere el
/// Completer devuelto (con completeError la petición falla en su lugar).
Completer<void> _retener(
  _Backend backend,
  bool Function(http.BaseRequest) cuando,
) {
  final liberar = Completer<void>();
  backend.antesDeResponder = (request) async {
    if (cuando(request)) await liberar.future;
  };
  return liberar;
}

bool _esPagina2SinFiltro(http.BaseRequest r) =>
    r.url.queryParameters['pagina'] == '2' &&
    !r.url.queryParameters.containsKey('semestre') &&
    !r.url.queryParameters.containsKey('nivel');

/// Falla de transporte cualquiera (ApiClient la convierte en ApiException).
class _FallaDeRed implements Exception {
  const _FallaDeRed();
}

void main() {
  group('AdminCatalogoController — consumo paginado (RNF-12)', () {
    test('cargarInicial() trae solo la primera página, no todo el catálogo', () async {
      final backend = _Backend(palabras: _palabras(45));
      final controller = _catalogo(backend);

      await controller.cargarInicial();

      expect(controller.palabras, hasLength(_limite));
      expect(controller.hayMasPaginas, isTrue);
      final pedidas = backend.peticiones.where(
        (p) => p.contains('/admin/palabras'),
      );
      expect(pedidas, hasLength(1));
      expect(pedidas.single, contains('limite=$_limite'));
    });

    test('cargarMas() suma página tras página hasta agotarlas, sin repetir ninguna', () async {
      final backend = _Backend(palabras: _palabras(45));
      final controller = _catalogo(backend);
      await controller.cargarInicial();

      while (controller.hayMasPaginas) {
        await controller.cargarMas();
      }

      final ids = controller.palabras.map((p) => p.id).toList();
      expect(ids, hasLength(45));
      expect(ids.toSet(), hasLength(45), reason: 'ninguna palabra repetida');
    });

    test(
      'una palabra recién creada NO aparece dos veces cuando después se cargan más páginas (se muestra al inicio, pero el backend la entrega al final)',
      () async {
        final backend = _Backend(palabras: _palabras(25));
        final controller = _catalogo(backend);
        await controller.cargarInicial();

        await controller.crear(texto: 'nueva', idNivel: 2);
        while (controller.hayMasPaginas) {
          await controller.cargarMas();
        }

        final ids = controller.palabras.map((p) => p.id).toList();
        expect(
          ids.toSet(),
          hasLength(ids.length),
          reason: 'ids repetidos: $ids',
        );
        expect(ids, hasLength(26));
        expect(
          ids.first,
          26,
          reason: 'sigue mostrándose al inicio, como en T-027',
        );
      },
    );
  });

  group('SeguimientoAlumnosController — consumo paginado (RNF-12)', () {
    test('cargarMas() suma página tras página sin repetir alumnos', () async {
      final backend = _Backend(alumnos: _alumnos(45));
      final controller = _seguimiento(backend);
      await controller.cargarInicial();
      expect(controller.alumnos, hasLength(_limite));

      while (controller.hayMasPaginas) {
        await controller.cargarMas();
      }

      final ids = controller.alumnos.map((a) => a.id).toSet();
      expect(controller.alumnos, hasLength(45));
      expect(ids, hasLength(45));
    });

    test(
      'una página vieja que llega DESPUÉS de cambiar los filtros no contamina la lista nueva',
      () async {
        final backend = _Backend(alumnos: _alumnos(25));
        final controller = _seguimiento(backend);
        await controller.cargarInicial();
        expect(controller.hayMasPaginas, isTrue);

        // La página 2 SIN filtros queda en vuelo...
        final liberar = _retener(backend, _esPagina2SinFiltro);
        final enVuelo = controller.cargarMas();
        await Future<void>.delayed(Duration.zero);

        // ...la persona aplica un filtro (semestre 3: solo los pares)...
        await controller.aplicarFiltros(semestre: 3);
        expect(controller.alumnos.every((a) => a.semestre == 3), isTrue);

        // ...y RECIÉN entonces llega la página vieja (con alumnos de semestre 5).
        liberar.complete();
        await enVuelo;

        expect(
          controller.alumnos.every((a) => a.semestre == 3),
          isTrue,
          reason:
              'la lista filtrada quedó con alumnos que no cumplen el filtro: '
              '${controller.alumnos.map((a) => "${a.id}(s${a.semestre})").join(", ")}',
        );
        expect(controller.alumnos, hasLength(12));
        expect(controller.cargandoMas, isFalse);
      },
    );

    test(
      'la carga vieja en vuelo no bloquea seguir paginando la lista nueva',
      () async {
        final backend = _Backend(alumnos: _alumnos(45));
        final controller = _seguimiento(backend);
        await controller.cargarInicial();

        final liberar = _retener(backend, _esPagina2SinFiltro);
        final enVuelo = controller.cargarMas();
        await Future<void>.delayed(Duration.zero);

        // Filtro semestre 3 => 22 alumnos = 2 páginas. La página 2 FILTRADA
        // no está retenida (el gancho solo retiene la página 2 sin filtro).
        await controller.aplicarFiltros(semestre: 3);
        expect(controller.hayMasPaginas, isTrue);
        await controller.cargarMas();

        expect(controller.alumnos, hasLength(22));
        expect(controller.alumnos.every((a) => a.semestre == 3), isTrue);

        liberar.complete();
        await enVuelo;
        expect(controller.alumnos, hasLength(22));
      },
    );

    test(
      'dos cambios de filtro seguidos: la respuesta lenta del PRIMERO no pisa a la del último',
      () async {
        final backend = _Backend(alumnos: _alumnos(25));
        final controller = _seguimiento(backend);

        // El primer filtro (semestre 3) responde LENTO; el segundo (5), rápido.
        final liberar = _retener(
          backend,
          (r) =>
              r.url.path == '/admin/alumnos' &&
              r.url.queryParameters['semestre'] == '3',
        );
        final primero = controller.aplicarFiltros(semestre: 3);
        await Future<void>.delayed(Duration.zero);
        await controller.aplicarFiltros(semestre: 5);
        expect(controller.alumnos.every((a) => a.semestre == 5), isTrue);

        liberar.complete();
        await primero;

        expect(controller.filtroSemestre, 5);
        expect(
          controller.alumnos.every((a) => a.semestre == 5),
          isTrue,
          reason:
              'el chip dice semestre 5 pero la lista quedó con: '
              '${controller.alumnos.map((a) => "${a.id}(s${a.semestre})").join(", ")}',
        );
        expect(controller.alumnos, hasLength(13));
        expect(controller.cargando, isFalse);
      },
    );

    test(
      'el FALLO de una página vieja (ya reemplazada por otro filtro) no se propaga como error',
      () async {
        final backend = _Backend(alumnos: _alumnos(25));
        final controller = _seguimiento(backend);
        await controller.cargarInicial();

        final liberar = _retener(backend, _esPagina2SinFiltro);
        final enVuelo = controller.cargarMas();
        await Future<void>.delayed(Duration.zero);
        await controller.aplicarFiltros(semestre: 3);

        // El backend falla justo con la petición vieja.
        liberar.completeError(const _FallaDeRed());
        await expectLater(enVuelo, completes);

        expect(controller.error, isNull);
        expect(controller.alumnos, hasLength(12));
        expect(controller.cargandoMas, isFalse);
      },
    );

    test(
      'el fallo de la página ACTUAL sí se propaga (la pantalla lo muestra con Reintentar) y deja la lista intacta',
      () async {
        final backend = _Backend(alumnos: _alumnos(45));
        final controller = _seguimiento(backend);
        await controller.cargarInicial();

        final liberar = _retener(backend, _esPagina2SinFiltro);
        final enVuelo = controller.cargarMas();
        liberar.completeError(const _FallaDeRed());

        await expectLater(enVuelo, throwsA(isA<ApiException>()));
        expect(controller.alumnos, hasLength(_limite));
        expect(controller.cargandoMas, isFalse);

        // Reintentar (la misma operación) funciona una vez que el backend vuelve.
        backend.antesDeResponder = null;
        await controller.cargarMas();
        expect(controller.alumnos, hasLength(2 * _limite));
      },
    );
  });

  group('DetalleAlumnoController — consumo paginado (RNF-12)', () {
    test('cargarMas() suma página tras página con todos los intentos', () async {
      final backend = _Backend(intentos: _intentos(45));
      final controller = _detalle(backend);
      await controller.cargarInicial();
      expect(controller.intentos, hasLength(_limite));

      while (controller.hayMasPaginas) {
        await controller.cargarMas();
      }

      expect(controller.intentos, hasLength(45));
      expect(
        controller.intentos.map((i) => i.oracionAlumno).toSet(),
        hasLength(45),
      );
    });

    test(
      'una página vieja que llega DESPUÉS de cambiar los filtros no contamina la lista nueva',
      () async {
        final backend = _Backend(intentos: _intentos(25));
        final controller = _detalle(backend);
        await controller.cargarInicial();
        expect(controller.hayMasPaginas, isTrue);

        final liberar = _retener(backend, _esPagina2SinFiltro);
        final enVuelo = controller.cargarMas();
        await Future<void>.delayed(Duration.zero);

        await controller.aplicarFiltros(nivel: 2);
        expect(controller.intentos, hasLength(12));

        liberar.complete();
        await enVuelo;

        // Con nivel 2 solo deben quedar los intentos pares (12 en total).
        final numeros = controller.intentos
            .map((i) => int.parse(i.oracionAlumno.split('-').last))
            .toList();
        expect(
          numeros.every((n) => n.isEven),
          isTrue,
          reason: 'la lista filtrada quedó con intentos de otro nivel: $numeros',
        );
        expect(controller.intentos, hasLength(12));
        expect(controller.cargandoMas, isFalse);
      },
    );

    test(
      'dos cambios de filtro seguidos: la respuesta lenta del PRIMERO no pisa a la del último',
      () async {
        final backend = _Backend(intentos: _intentos(25));
        final controller = _detalle(backend);

        final liberar = _retener(
          backend,
          (r) =>
              r.url.path.startsWith('/admin/alumnos/') &&
              r.url.queryParameters['nivel'] == '2',
        );
        final primero = controller.aplicarFiltros(nivel: 2);
        await Future<void>.delayed(Duration.zero);
        await controller.aplicarFiltros(nivel: 3);

        liberar.complete();
        await primero;

        final numeros = controller.intentos
            .map((i) => int.parse(i.oracionAlumno.split('-').last))
            .toList();
        expect(controller.filtroNivel, 3);
        expect(
          numeros.every((n) => n.isOdd),
          isTrue,
          reason:
              'el filtro es nivel 3 (impares) pero la lista quedó con: $numeros',
        );
        expect(controller.intentos, hasLength(13));
        expect(controller.cargando, isFalse);
      },
    );

    test(
      'el FALLO de una página vieja (ya reemplazada por otro filtro) no se propaga como error',
      () async {
        final backend = _Backend(intentos: _intentos(25));
        final controller = _detalle(backend);
        await controller.cargarInicial();

        final liberar = _retener(backend, _esPagina2SinFiltro);
        final enVuelo = controller.cargarMas();
        await Future<void>.delayed(Duration.zero);
        await controller.aplicarFiltros(nivel: 2);

        liberar.completeError(const _FallaDeRed());
        await expectLater(enVuelo, completes);

        expect(controller.error, isNull);
        expect(controller.intentos, hasLength(12));
        expect(controller.cargandoMas, isFalse);
      },
    );
  });

  // Los puntos donde una paginación suele romperse: lista vacía, justo una
  // página, una página + 1, múltiplo exacto, el umbral de RNF-12 (50/51).
  // Para cada total, cada controlador debe pedir EXACTAMENTE las páginas
  // 1..N (ni una de más —una vacía extra— ni una de menos), con el límite de
  // 20, y terminar con los elementos en orden, sin repetidos ni omitidos.
  group('bordes de la paginación (RNF-12): ni una página de más ni una de menos', () {
    List<int> paginasPedidas(_Backend backend, String ruta) => [
      for (final p in backend.peticiones)
        if (p.startsWith('GET $ruta?'))
          int.parse(RegExp(r'pagina=(\d+)').firstMatch(p)!.group(1)!),
    ];

    for (final total in [0, 1, 19, 20, 21, 39, 40, 41, 50, 51, 100, 101]) {
      final paginas = total == 0 ? 1 : (total / _limite).ceil();
      final esperadas = [for (var p = 1; p <= paginas; p++) p];

      test('catálogo con $total palabras: pide las páginas $esperadas y nada más', () async {
        final backend = _Backend(palabras: _palabras(total));
        final controller = _catalogo(backend);
        await controller.cargarInicial();
        for (var i = 0; controller.hayMasPaginas && i < paginas + 2; i++) {
          await controller.cargarMas();
        }
        await controller.cargarMas(); // ya no hay más: no debe pedir nada

        expect(controller.hayMasPaginas, isFalse);
        expect(controller.palabras.map((p) => p.id), [
          for (var i = 1; i <= total; i++) i,
        ]);
        expect(paginasPedidas(backend, '/admin/palabras'), esperadas);
      });

      test('seguimiento con $total alumnos: pide las páginas $esperadas y nada más', () async {
        final backend = _Backend(alumnos: _alumnos(total));
        final controller = _seguimiento(backend);
        await controller.cargarInicial();
        for (var i = 0; controller.hayMasPaginas && i < paginas + 2; i++) {
          await controller.cargarMas();
        }
        await controller.cargarMas();

        expect(controller.hayMasPaginas, isFalse);
        expect(controller.alumnos.map((a) => a.id), [
          for (var i = 1; i <= total; i++) i,
        ]);
        expect(paginasPedidas(backend, '/admin/alumnos'), esperadas);
      });

      test('detalle con $total intentos: pide las páginas $esperadas y nada más', () async {
        final backend = _Backend(intentos: _intentos(total));
        final controller = _detalle(backend);
        await controller.cargarInicial();
        for (var i = 0; controller.hayMasPaginas && i < paginas + 2; i++) {
          await controller.cargarMas();
        }
        await controller.cargarMas();

        expect(controller.hayMasPaginas, isFalse);
        expect(controller.intentos.map((i) => i.oracionAlumno), [
          for (var i = 1; i <= total; i++) 'intento-$i',
        ]);
        expect(paginasPedidas(backend, '/admin/alumnos/7'), esperadas);
      });
    }

    // El listener de scroll puede disparar cargarMas() varias veces seguidas
    // mientras la primera sigue en vuelo: la página 2 se pide UNA sola vez.
    test('dos cargarMas() simultáneos (scroll rápido) piden la página 2 una sola vez, en los 3 listados', () async {
      final catalogoBackend = _Backend(palabras: _palabras(45));
      final catalogo = _catalogo(catalogoBackend);
      await catalogo.cargarInicial();
      await Future.wait([catalogo.cargarMas(), catalogo.cargarMas()]);
      expect(paginasPedidas(catalogoBackend, '/admin/palabras'), [1, 2]);
      expect(catalogo.palabras.map((p) => p.id), [for (var i = 1; i <= 40; i++) i]);

      final alumnosBackend = _Backend(alumnos: _alumnos(45));
      final seguimiento = _seguimiento(alumnosBackend);
      await seguimiento.cargarInicial();
      await Future.wait([seguimiento.cargarMas(), seguimiento.cargarMas()]);
      expect(paginasPedidas(alumnosBackend, '/admin/alumnos'), [1, 2]);
      expect(seguimiento.alumnos.map((a) => a.id), [for (var i = 1; i <= 40; i++) i]);

      final detalleBackend = _Backend(intentos: _intentos(45));
      final detalle = _detalle(detalleBackend);
      await detalle.cargarInicial();
      await Future.wait([detalle.cargarMas(), detalle.cargarMas()]);
      expect(paginasPedidas(detalleBackend, '/admin/alumnos/7'), [1, 2]);
      expect(
        detalle.intentos.map((i) => i.oracionAlumno),
        [for (var i = 1; i <= 40; i++) 'intento-$i'],
      );
    });
  });
}
