import 'package:flutter/foundation.dart';

import 'admin_palabras_service.dart';
import 'api_exception.dart';
import 'nivel.dart';
import 'niveles_service.dart';
import 'palabra_admin.dart';

/// Estado del panel de administración del catálogo (T-027, RF-39). Un solo
/// ChangeNotifier alcanza aquí igual que en AuthController — no hay
/// necesidad de un paquete de manejo de estado para el alcance de esta
/// pantalla.
///
/// Convención de errores: cargarInicial() atrapa sus propios errores porque
/// una falla ahí necesita convertirse en estado persistente de UI ("no se
/// pudo cargar, reintentar"). El resto de los métodos (cargarMas, crear,
/// editar, alternarOculta, subirAudio) NO atrapan sus errores — los dejan
/// propagarse a quien los llama, igual que AuthController.iniciarSesion(),
/// para que la pantalla decida cómo mostrarlos (normalmente un SnackBar)
/// sin destruir la lista ya cargada.
class AdminCatalogoController extends ChangeNotifier {
  AdminCatalogoController({
    required this.token,
    AdminPalabrasService? palabrasService,
    NivelesService? nivelesService,
  }) : _palabrasService = palabrasService ?? AdminPalabrasService(),
       _nivelesService = nivelesService ?? NivelesService();

  static const _limitePorPagina = 20;

  final String token;
  final AdminPalabrasService _palabrasService;
  final NivelesService _nivelesService;

  List<PalabraAdmin> _palabras = [];
  List<PalabraAdmin> get palabras => List.unmodifiable(_palabras);

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

  Future<void> cargarInicial() async {
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      final niveles = await _nivelesService.listar();
      final lista = await _palabrasService.listar(
        token: token,
        pagina: 1,
        limite: _limitePorPagina,
      );
      _niveles = niveles;
      _palabras = lista.palabras;
      _pagina = lista.pagina;
      _totalPaginas = lista.totalPaginas;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  Future<void> cargarMas() async {
    if (!hayMasPaginas || _cargandoMas) return;
    _cargandoMas = true;
    notifyListeners();
    try {
      final lista = await _palabrasService.listar(
        token: token,
        pagina: _pagina + 1,
        limite: _limitePorPagina,
      );
      _palabras = [..._palabras, ...lista.palabras];
      _pagina = lista.pagina;
      _totalPaginas = lista.totalPaginas;
    } finally {
      _cargandoMas = false;
      notifyListeners();
    }
  }

  // RF-08. Se agrega al principio de la lista ya cargada para que el
  // profesor la vea de inmediato — no es el orden "verdadero" (id
  // ascendente) que tendría una recarga completa, pero es lo que se espera
  // al acabar de crear algo en un panel de administración.
  Future<PalabraAdmin> crear({
    required String texto,
    required int idNivel,
    String? significadoEs,
    String? oracionEjemplo,
  }) async {
    final creada = await _palabrasService.crear(
      token: token,
      texto: texto,
      idNivel: idNivel,
      significadoEs: significadoEs,
      oracionEjemplo: oracionEjemplo,
    );
    _palabras = [creada, ..._palabras];
    notifyListeners();
    return creada;
  }

  // RF-09.
  Future<PalabraAdmin> editar({
    required int id,
    required String texto,
    required int idNivel,
    required String significadoEs,
    required String oracionEjemplo,
  }) async {
    final editada = await _palabrasService.editar(
      token: token,
      id: id,
      texto: texto,
      idNivel: idNivel,
      significadoEs: significadoEs,
      oracionEjemplo: oracionEjemplo,
    );
    _reemplazar(editada);
    return editada;
  }

  // RF-10. Recibe la palabra completa (no solo el id) para poder mandar lo
  // contrario de su oculta actual sin que la pantalla tenga que llevar ese
  // dato aparte.
  Future<PalabraAdmin> alternarOculta(PalabraAdmin palabra) async {
    final actualizada = await _palabrasService.ocultar(
      token: token,
      id: palabra.id,
      oculta: !palabra.oculta,
    );
    _reemplazar(actualizada);
    return actualizada;
  }

  // RF-11.
  Future<PalabraAdmin> subirAudio({
    required int id,
    required List<int> bytes,
    required String nombreArchivo,
  }) async {
    final actualizada = await _palabrasService.subirAudio(
      token: token,
      id: id,
      bytes: bytes,
      nombreArchivo: nombreArchivo,
    );
    _reemplazar(actualizada);
    return actualizada;
  }

  void _reemplazar(PalabraAdmin actualizada) {
    _palabras = [
      for (final p in _palabras)
        if (p.id == actualizada.id) actualizada else p,
    ];
    notifyListeners();
  }
}
