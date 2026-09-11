import 'package:flutter/material.dart';

import '../core/api_exception.dart';
import '../core/insignia.dart';
import '../core/insignias_service.dart';
import '../core/nivel.dart';
import '../core/niveles_service.dart';

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
  });

  final String token;

  /// Inyectables solo para pruebas — mismo motivo que en las demás
  /// pantallas: sin esto, siempre construirían un ApiClient real.
  final NivelesService? nivelesService;
  final InsigniasService? insigniasService;

  @override
  State<PerfilProgresoScreen> createState() => _PerfilProgresoScreenState();
}

class _PerfilProgresoScreenState extends State<PerfilProgresoScreen> {
  late final NivelesService _nivelesService;
  late final InsigniasService _insigniasService;
  late final Future<(List<Nivel>, List<Insignia>)> _futuroProgreso;

  @override
  void initState() {
    super.initState();
    _nivelesService = widget.nivelesService ?? NivelesService();
    _insigniasService = widget.insigniasService ?? InsigniasService();
    _futuroProgreso = _cargarProgreso();
  }

  Future<(List<Nivel>, List<Insignia>)> _cargarProgreso() async {
    final niveles = await _nivelesService.listar();
    final insignias = await _insigniasService.obtenerInsignias(widget.token);
    return (niveles, insignias);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi progreso')),
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
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(mensaje, textAlign: TextAlign.center),
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
