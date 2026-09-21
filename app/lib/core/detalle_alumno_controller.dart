import 'package:flutter/foundation.dart';

import 'admin_alumnos_service.dart';
import 'api_exception.dart';
import 'intento_practica.dart';
import 'nivel.dart';
import 'niveles_service.dart';

/// Estado de la pantalla de detalle de un alumno (T-053, RF-29, CU-03), con
/// los mismos filtros combinables de nivel/carrera/semestre que la lista
/// (T-052, RF-30) — el ERS no distingue "la lista sí filtra, el detalle no",
/// así que ambas pantallas exponen los 3.
class DetalleAlumnoController extends ChangeNotifier {
  DetalleAlumnoController({
    required this.token,
    required this.idAlumno,
    AdminAlumnosService? adminAlumnosService,
    NivelesService? nivelesService,
  }) : _service = adminAlumnosService ?? AdminAlumnosService(),
       _nivelesService = nivelesService ?? NivelesService();

  static const _limitePorPagina = 20;

  final String token;
  final int idAlumno;
  final AdminAlumnosService _service;
  final NivelesService _nivelesService;

  List<IntentoPractica> _intentos = [];
  List<IntentoPractica> get intentos => List.unmodifiable(_intentos);

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

  // T-070 (RNF-12): mismo mecanismo que SeguimientoAlumnosController — una
  // respuesta que llega después de un reinicio de la lista (cargarInicial()
  // / aplicarFiltros()) pertenece a los filtros viejos y se descarta.
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
    // Una cargarMas() en vuelo quedó obsoleta con este reinicio.
    _cargandoMas = false;
    _error = null;
    notifyListeners();
    try {
      final niveles = await _nivelesService.listar();
      final detalle = await _service.detalle(
        token: token,
        idAlumno: idAlumno,
        pagina: 1,
        limite: _limitePorPagina,
        nivel: _filtroNivel,
        carrera: _filtroCarrera,
        semestre: _filtroSemestre,
      );
      if (generacion != _generacion) return;
      _niveles = niveles;
      _intentos = detalle.intentos;
      _pagina = detalle.pagina;
      _totalPaginas = detalle.totalPaginas;
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
      final detalle = await _service.detalle(
        token: token,
        idAlumno: idAlumno,
        pagina: _pagina + 1,
        limite: _limitePorPagina,
        nivel: _filtroNivel,
        carrera: _filtroCarrera,
        semestre: _filtroSemestre,
      );
      if (generacion != _generacion) return;
      _intentos = [..._intentos, ...detalle.intentos];
      _pagina = detalle.pagina;
      _totalPaginas = detalle.totalPaginas;
    } catch (_) {
      // Un fallo de una página ya obsoleta no se propaga (ver
      // SeguimientoAlumnosController.cargarMas()).
      if (generacion == _generacion) rethrow;
    } finally {
      if (generacion == _generacion) {
        _cargandoMas = false;
        notifyListeners();
      }
    }
  }

  // RF-30: los 3 filtros se aplican juntos, de una sola vez — cambiar
  // cualquiera reinicia la paginación y vuelve a cargar desde la página 1.
  Future<void> aplicarFiltros({int? nivel, String? carrera, int? semestre}) {
    _filtroNivel = nivel;
    _filtroCarrera = carrera;
    _filtroSemestre = semestre;
    return cargarInicial();
  }
}
