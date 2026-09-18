import 'package:flutter/material.dart';

import '../core/api_exception.dart';
import '../core/cola_practica_archivo.dart';
import '../core/insignia.dart';
import '../core/insignias_service.dart';
import '../core/nivel.dart';
import '../core/niveles_service.dart';
import '../core/sincronizador_practica.dart';
import '../widgets/indicador_sincronizacion.dart';

/// RF-24, punto 2 (T-047): insignias permanentes del alumno, una por nivel
/// completado al 100%. Combina GET /niveles (los 3 posibles, RF-05) con
/// GET /progreso/insignias (los ya ganados) para mostrar también los
/// niveles todavía sin completar como espacios bloqueados, no solo los ya
/// ganados [decisión de equipo, a confirmar]: el ERS solo exige que la
/// insignia "sea visible después" de ganarla, no exige mostrar los
/// pendientes — se decidió incluirlos por ser el patrón de gamificación
/// esperado (ERS, "Gamificación/incentivo" RF-22 a RF-24); GET
/// /progreso/insignias por sí solo ya expone solo las ganadas si se
/// prefiriera esa forma más literal.
class PerfilProgresoScreen extends StatefulWidget {
  const PerfilProgresoScreen({
    super.key,
    required this.token,
    this.nivelesService,
    this.insigniasService,
    this.sincronizador,
  });

  final String token;

  /// Inyectables solo para pruebas — mismo motivo que en las demás
  /// pantallas: sin esto, siempre construirían un ApiClient real.
  final NivelesService? nivelesService;
  final InsigniasService? insigniasService;

  /// RF-33 (T-062): compartido con la sesión completa del alumno (ver
  /// HomeScreen, dueño real del ciclo de vida de este objeto) — igual que en
  /// NivelesScreen/PracticaPalabraScreen, esta pantalla solo lo recibe para
  /// mostrar el indicador de RF-34 (T-064), nunca lo arranca con iniciar()
  /// ni lo cierra con dispose(). null (inyectable solo para pruebas, o
  /// cualquier navegación futura sin HomeScreen de por medio) hace que esta
  /// pantalla arme uno propio, sin arrancarlo.
  final SincronizadorPractica? sincronizador;

  @override
  State<PerfilProgresoScreen> createState() => _PerfilProgresoScreenState();
}

class _PerfilProgresoScreenState extends State<PerfilProgresoScreen> {
  late final NivelesService _nivelesService;
  late final InsigniasService _insigniasService;
  late final SincronizadorPractica _sincronizador;
  // RF-38 (T-065): no "late final" — _recargar() la reasigna para que el
  // botón "Reintentar" de abajo pueda volver a intentar la misma carga.
  late Future<(List<Nivel>, List<Insignia>)> _futuroProgreso;

  @override
  void initState() {
    super.initState();
    _nivelesService = widget.nivelesService ?? NivelesService();
    _insigniasService = widget.insigniasService ?? InsigniasService();
    _sincronizador =
        widget.sincronizador ??
        SincronizadorPractica(cola: ColaPracticaArchivo(), token: widget.token);
    _futuroProgreso = _cargarProgreso();
  }

  void _recargar() {
    // Cuerpo de bloque, NO "=> ...": una expresión de asignación evalúa al
    // valor asignado — aquí, el Future que regresa _cargarProgreso() — así
    // que una arrow function haría que este closure DEVOLVIERA ese Future,
    // y setState() rechaza en tiempo de ejecución cualquier callback que
    // regrese un Future (para atrapar justo este error: "¿esto es async por
    // accidente?").
    setState(() {
      _futuroProgreso = _cargarProgreso();
    });
  }

  Future<(List<Nivel>, List<Insignia>)> _cargarProgreso() async {
    final niveles = await _nivelesService.listar();
    final insignias = await _insigniasService.obtenerInsignias(widget.token);
    return (niveles, insignias);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi progreso'),
        actions: [IndicadorSincronizacion(sincronizador: _sincronizador)],
      ),
      body: SafeArea(
        child: FutureBuilder<(List<Nivel>, List<Insignia>)>(
          future: _futuroProgreso,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              final mensaje = error is ApiException
                  ? error.message
                  : 'No se pudo cargar tu progreso. Intenta de nuevo.';
              // RF-38 (T-065): antes esta pantalla no ofrecía ninguna forma
              // de reintentar la carga — la única opción era salir y volver
              // a entrar. Mismo patrón que NivelesScreen/AdminCatalogoScreen/
              // SeguimientoAlumnosScreen: mensaje + botón "Reintentar".
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(mensaje, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _recargar,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final (niveles, insignias) = snapshot.data!;
            final insigniaPorNivel = {
              for (final insignia in insignias) insignia.idNivel: insignia,
            };

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: niveles.length,
              itemBuilder: (context, index) {
                final nivel = niveles[index];
                final insignia = insigniaPorNivel[nivel.id];
                final ganada = insignia != null;

                return Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.emoji_events,
                      color: ganada ? Colors.amber : Colors.grey.shade300,
                      size: 36,
                    ),
                    title: Text(nivel.nombre),
                    subtitle: Text(
                      ganada
                          ? 'Insignia obtenida'
                          : 'Todavía no completas este nivel al 100%',
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
