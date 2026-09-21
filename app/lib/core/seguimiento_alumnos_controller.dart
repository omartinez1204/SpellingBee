import 'package:flutter/foundation.dart';

import 'admin_alumnos_service.dart';
import 'alumno_con_avance.dart';
import 'api_exception.dart';
import 'nivel.dart';
import 'niveles_service.dart';

/// Estado del panel de seguimiento docente (T-053, RF-28/RF-30, CU-03). Un
/// solo ChangeNotifier alcanza aquí, igual que AdminCatalogoController
/// (T-027) — mismo criterio de errores: cargarInicial()/aplicarFiltros()
/// atrapan los suyos porque una falla ahí es estado persistente de UI
/// ("no se pudo cargar, reintentar"); cargarMas() no, para no perder la
/// lista ya visible si falla solo la carga incremental.
class SeguimientoAlumnosController extends ChangeNotifier {
  SeguimientoAlumnosController({
    required this.token,
    AdminAlumnosService? adminAlumnosService,
    NivelesService? nivelesService,
  }) : _service = adminAlumnosService ?? AdminAlumnosService(),
       _nivelesService = nivelesService ?? NivelesService();

  static const _limitePorPagina = 20;

  final String token;
  final AdminAlumnosService _service;
  final NivelesService _nivelesService;

  /// Expuestos para que la pantalla reutilice los MISMOS servicios (y, en
  /// pruebas, el mismo http.Client falso) al navegar al detalle de un
  /// alumno (T-053) — sin esto, DetalleAlumnoController construiría los
  /// suyos propios con un ApiClient real.
  AdminAlumnosService get adminAlumnosService => _service;
  NivelesService get nivelesService => _nivelesService;

  List<AlumnoConAvance> _alumnos = [];
  List<AlumnoConAvance> get alumnos => List.unmodifiable(_alumnos);

  List<Nivel> _niveles = [];
  List<Nivel> get niveles => List.unmodifiable(_niveles);

  bool _cargando = false;
  bool get cargando => _cargando;

  bool _cargandoMas = false;
  bool get cargandoMas => _cargandoMas;

  String? _error;
  String? get error => _error;

  int _pagina = 1;
  int _totalPaginas = 1;
  bool get hayMasPaginas => _pagina < _totalPaginas;

  // T-070 (RNF-12): número de "reinicio" de la lista — sube cada vez que
  // cargarInicial() (y por tanto aplicarFiltros()) empieza. Una respuesta
  // que llega tras un reinicio pertenece a los filtros/lista VIEJOS y se
  // descarta: sin esto, una página lenta (o un cargarInicial() anterior) que
  // resuelve después de cambiar los filtros se sumaría o pisaría la lista
  // nueva, mostrando alumnos que no cumplen el filtro visible.
  int _generacion = 0;

  // RF-30 (T-052): filtros activos — null significa "sin ese filtro".
  int? _filtroNivel;
  int? get filtroNivel => _filtroNivel;
  String? _filtroCarrera;
  String? get filtroCarrera => _filtroCarrera;
  int? _filtroSemestre;
  int? get filtroSemestre => _filtroSemestre;

  Future<void> cargarInicial() async {
    final generacion = ++_generacion;
    _cargando = true;
    // Una cargarMas() en vuelo quedó obsoleta con este reinicio: su bandera
    // ya no debe impedir cargar la página 2 de la lista NUEVA.
    _cargandoMas = false;
    _error = null;
    notifyListeners();
    try {
      final niveles = await _nivelesService.listar();
      final lista = await _service.listar(
        token: token,
        pagina: 1,
        limite: _limitePorPagina,
        nivel: _filtroNivel,
        carrera: _filtroCarrera,
        semestre: _filtroSemestre,
      );
      if (generacion != _generacion) return;
      _niveles = niveles;
      _alumnos = lista.alumnos;
      _pagina = lista.pagina;
      _totalPaginas = lista.totalPaginas;
    } on ApiException catch (e) {
      if (generacion == _generacion) _error = e.message;
    } finally {
      if (generacion == _generacion) {
        _cargando = false;
        notifyListeners();
      }
    }
  }

  Future<void> cargarMas() async {
    if (!hayMasPaginas || _cargandoMas) return;
    final generacion = _generacion;
    _cargandoMas = true;
    notifyListeners();
    try {
      final lista = await _service.listar(
        token: token,
        pagina: _pagina + 1,
        limite: _limitePorPagina,
        nivel: _filtroNivel,
        carrera: _filtroCarrera,
        semestre: _filtroSemestre,
      );
      if (generacion != _generacion) return;
      _alumnos = [..._alumnos, ...lista.alumnos];
      _pagina = lista.pagina;
      _totalPaginas = lista.totalPaginas;
    } catch (_) {
      // Un fallo de una página ya obsoleta no le importa a quien está viendo
      // la lista nueva: no se propaga para no mostrar un error ajeno.
      if (generacion == _generacion) rethrow;
    } finally {
      if (generacion == _generacion) {
        _cargandoMas = false;
        notifyListeners();
      }
    }
  }

  // RF-30: los 3 filtros se aplican juntos, de una sola vez — cambiar
  // cualquiera reinicia la paginación y vuelve a cargar desde la página 1;
  // la lista ya visible fue calculada bajo los filtros VIEJOS y no tiene
  // sentido seguir acumulándola.
  Future<void> aplicarFiltros({int? nivel, String? carrera, int? semestre}) {
    _filtroNivel = nivel;
    _filtroCarrera = carrera;
    _filtroSemestre = semestre;
    return cargarInicial();
  }
}
