import 'dart:async';

import 'package:flutter/material.dart';

import '../core/sincronizador_practica.dart';

/// RF-34 (T-064): indicador visual PERSISTENTE de conectividad (en línea/sin
/// conexión) y de cuántos registros de práctica siguen pendientes de
/// sincronizar (SincronizadorPractica.estadoConexion/pendientes), más una
/// confirmación TRANSITORIA (SnackBar) apenas un lote se sincroniza con
/// éxito (SincronizadorPractica.sincronizacionesExitosas). Vive en el AppBar
/// de cada pantalla que ya recibe el SincronizadorPractica compartido de la
/// sesión del alumno (ver HomeScreen, dueño real de ese objeto) — este
/// widget solo lo escucha, nunca lo crea, arranca ni cierra.
class IndicadorSincronizacion extends StatefulWidget {
  const IndicadorSincronizacion({super.key, required this.sincronizador});

  final SincronizadorPractica sincronizador;

  @override
  State<IndicadorSincronizacion> createState() =>
      _IndicadorSincronizacionState();
}

class _IndicadorSincronizacionState extends State<IndicadorSincronizacion> {
  late final StreamSubscription<int> _suscripcionExitosa;

  @override
  void initState() {
    super.initState();
    _suscripcionExitosa = widget.sincronizador.sincronizacionesExitosas.listen(
      _mostrarConfirmacion,
    );
  }

  // RF-34: "una confirmación breve (p. ej. una notificación o mensaje
  // transitorio)" — un SnackBar es justo eso: visible un momento y se retira
  // solo, sin bloquear la pantalla ni exigir que el alumno lo cierre.
  void _mostrarConfirmacion(int cantidad) {
    if (!mounted) return;
    final mensaje = cantidad == 1
        ? 'Se sincronizó 1 práctica pendiente.'
        : 'Se sincronizaron $cantidad prácticas pendientes.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
    );
  }

  @override
  void dispose() {
    unawaited(_suscripcionExitosa.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.sincronizador,
      builder: (context, _) {
        final enLinea = widget.sincronizador.estadoConexion.hayConexion;
        final pendientes = widget.sincronizador.pendientes;
        final descripcion = _describir(enLinea, pendientes);

        return Semantics(
          label: descripcion,
          child: Tooltip(
            message: descripcion,
            child: Padding(
              key: const Key('indicador-sincronizacion'),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    enLinea ? Icons.wifi : Icons.wifi_off,
                    color: enLinea ? Colors.green : Colors.orange,
                  ),
                  if (pendientes > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$pendientes',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _describir(bool enLinea, int pendientes) {
    final estado = enLinea ? 'En línea' : 'Sin conexión';
    if (pendientes == 0) return estado;
    final registros = pendientes == 1
        ? '1 registro pendiente de sincronizar'
        : '$pendientes registros pendientes de sincronizar';
    return '$estado. $registros.';
  }
}
