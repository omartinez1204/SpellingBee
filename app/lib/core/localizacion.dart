import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// RNF-01 (T-071): la interfaz completa va en español, incluidos los textos
/// que pone el propio Flutter — el tooltip del botón "Atrás", la barra de
/// Cortar/Copiar/Pegar, la etiqueta de las barreras de menús y diálogos...
/// Esos no salen de ningún literal del código: sin esta configuración Flutter
/// los dibuja en inglés en CUALQUIER dispositivo, incluso uno configurado en
/// español.
///
/// El idioma se FIJA en español en vez de seguir el del dispositivo: un
/// teléfono con el sistema en inglés no debe mostrar ni un texto de interfaz
/// en inglés. Lo único que queda fuera del control de la app es lo que dibuja
/// Android por su cuenta (el diálogo del permiso de micrófono y el selector de
/// archivos), que sigue el idioma del dispositivo.
const localeDeLaInterfaz = Locale('es');

const localesSoportados = <Locale>[localeDeLaInterfaz];

const delegadosDeLocalizacion = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
