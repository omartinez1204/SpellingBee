import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_exception.dart';

/// RF-38 (T-065): manejo uniforme de "backend no disponible" (falla de red,
/// tiempo de espera agotado, o un 5xx del servidor — ver
/// ApiException.esBackendNoDisponible) en cualquier pantalla que dependa de
/// la API.
///
/// Un MaterialBanner, no un SnackBar: el criterio de RF-38 exige que la
/// persona "vea un mensaje de error y un botón de reintentar" de forma
/// confiable — un SnackBar se cierra solo pasado su `duration`, con el
/// riesgo de desaparecer antes de que alcance a leerlo o a tocar el botón
/// (a diferencia de la confirmación transitoria de RF-34/T-064, que SÍ debe
/// desaparecer sola: ahí no hay ninguna acción que tomar). Un MaterialBanner
/// se queda visible hasta que se descarta explícitamente.
///
/// Se muestra ENCIMA del contenido actual, sin desmontarlo ni navegar a
/// otra pantalla — así el texto/datos que la persona ya había capturado
/// (RF-38: "sin perder los datos que el usuario ya había capturado en
/// pantalla") simplemente siguen ahí, visibles debajo del banner, listos
/// para que [onReintentar] vuelva a intentar la MISMA operación sin que
/// nadie tenga que volver a escribir nada.
///
/// [context] debe ser el de la pantalla (o widget) que lanzó la operación:
/// el banner vive en el ScaffoldMessenger de toda la app, por ENCIMA de las
/// rutas, así que no desaparece solo al salir de esa pantalla. Por eso, sin
/// salvaguardas, tocar "Reintentar" desde otra pantalla ejecutaría el
/// callback de una pantalla ya destruida (con sus controllers y llaves de
/// formulario liberados — en el peor caso, mandando datos vacíos en vez de
/// los que la persona había capturado). Dos salvaguardas lo evitan: el
/// banner se cierra solo cuando la ruta de [context] sale de la pila, y
/// "Reintentar" solo llama a [onReintentar] si [context] sigue montado.
///
/// [nota] (opcional) se muestra bajo el mensaje del error: para cuando el
/// dato ya está a salvo aunque el envío falló (p. ej. una práctica que quedó
/// en la cola local), de modo que el aviso no parezca "se perdió".
void mostrarErrorBackend(
  BuildContext context,
  ApiException error, {
  required VoidCallback onReintentar,
  String? nota,
}) {
  final mensajeria = ScaffoldMessenger.of(context);
  mensajeria
    ..clearMaterialBanners()
    ..showMaterialBanner(
      MaterialBanner(
        content: Text(nota == null ? error.message : '${error.message}\n$nota'),
        leading: Icon(
          Icons.cloud_off,
          color: Theme.of(context).colorScheme.error,
        ),
        actions: [
          TextButton(
            onPressed: () {
              mensajeria.clearMaterialBanners();
              if (context.mounted) onReintentar();
            },
            child: const Text('Reintentar'),
          ),
          TextButton(
            onPressed: mensajeria.clearMaterialBanners,
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );

  final ruta = ModalRoute.of(context);
  if (ruta != null) {
    unawaited(
      ruta.popped.then((_) {
        if (mensajeria.mounted) mensajeria.clearMaterialBanners();
      }),
    );
  }
}
