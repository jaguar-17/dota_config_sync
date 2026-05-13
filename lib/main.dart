import 'dart:io';
import 'package:flutter/material.dart';
import 'package:win32_registry/win32_registry.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(600, 600),
    // tamaño inicial
    minimumSize: Size(500, 500),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const DotaConfigApp());
}

// --- MODELO DE DATOS ---
class CuentaSteam {
  final String id;
  final String nombre;

  CuentaSteam({required this.id, required this.nombre});
}

class DotaConfigApp extends StatelessWidget {
  const DotaConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sincronizador Dota 2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD32F2F),
          surface: Color(0xFF1E1E1E),
        ),
        fontFamily: 'Segoe UI',
      ),
      home: const SyncScreen(),
    );
  }
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  String estadoTexto = "Buscando Steam...";
  Color estadoColor = Colors.grey;

  String rutaUserData = "";
  List<CuentaSteam> cuentas = [];
  CuentaSteam? cuentaOrigenSeleccionada;
  CuentaSteam? cuentaDestinoSeleccionada;

  @override
  void initState() {
    super.initState();
    // Ejecutamos la búsqueda de Steam en cuanto se abre la app
    _cargarRutaSteam();
  }

  // --- LÓGICA DE DETECCIÓN Y LECTURA ---
  void _cargarRutaSteam() {
    try {
      if (Platform.isWindows) {
        // Lógica para Windows
        final registryKey = CURRENT_USER.open(r'Software\Valve\Steam');
        final steamPathValue = registryKey.getString('SteamPath');
        registryKey.close();

        if (steamPathValue != null) {
          String steamPath = steamPathValue.replaceAll(
            '/',
            Platform.pathSeparator,
          );
          rutaUserData = '$steamPath${Platform.pathSeparator}userdata';
          String rutaLoginUsers =
              '$steamPath${Platform.pathSeparator}config${Platform.pathSeparator}loginusers.vdf';
          _verificarCarpeta(rutaUserData, rutaLoginUsers);
        }
      } else if (Platform.isLinux) {
        // Lógica para Arch Linux
        String? home = Platform.environment['HOME'];
        if (home != null) {
          // Intentamos la ruta habitual de Steam en Linux
          rutaUserData = '$home/.local/share/Steam/userdata';
          String rutaLoginUsers =
              '$home/.local/share/Steam/config/loginusers.vdf';

          // Si no está ahí, probamos la ruta alternativa
          if (!Directory(rutaUserData).existsSync()) {
            rutaUserData = '$home/.steam/steam/userdata';
            rutaLoginUsers = '$home/.steam/steam/config/loginusers.vdf';
          }
          _verificarCarpeta(rutaUserData, rutaLoginUsers);
        }
      }
    } catch (e) {
      setState(() {
        estadoTexto = "Error al buscar Steam: $e";
        estadoColor = Colors.red;
      });
    }
  }

  void _verificarCarpeta(String userPath, String loginPath) {
    if (Directory(userPath).existsSync()) {
      _obtenerCuentas(loginPath);
    } else {
      setState(() {
        estadoTexto = "No se encontró la carpeta userdata.";
        estadoColor = Colors.red;
      });
    }
  }

  Map<String, String> _obtenerMapeoCuentas(String rutaLoginUsers) {
    Map<String, String> mapeo = {};
    final file = File(rutaLoginUsers);

    if (!file.existsSync()) return mapeo;

    final lineas = file.readAsLinesSync();
    String id64Actual = "";

    for (var linea in lineas) {
      if (linea.contains('"7656')) {
        var partes = linea.split('"');
        if (partes.length >= 2) id64Actual = partes[1];
      }
      if (linea.contains('"PersonaName"') && id64Actual.isNotEmpty) {
        var partes = linea.split('"');
        if (partes.length >= 4) {
          String nombreCuenta = partes[3];
          int? id64 = int.tryParse(id64Actual);
          if (id64 != null) {
            int id32 = id64 - 76561197960265728;
            mapeo[id32.toString()] = nombreCuenta;
          }
        }
        id64Actual = "";
      }
    }
    return mapeo;
  }

  void _obtenerCuentas(String rutaLoginUsers) {
    Map<String, String> nombresCuentas = _obtenerMapeoCuentas(rutaLoginUsers);
    List<CuentaSteam> cuentasEncontradas = [];

    final carpetas = Directory(rutaUserData).listSync();

    for (var entidad in carpetas) {
      if (entidad is Directory) {
        String idCuenta = entidad.path.split(Platform.pathSeparator).last;

        if (int.tryParse(idCuenta) != null) {
          String nombreMostrar = nombresCuentas.containsKey(idCuenta)
              ? "Cuenta: ${nombresCuentas[idCuenta]} - ($idCuenta)"
              : "ID: $idCuenta";

          cuentasEncontradas.add(
            CuentaSteam(id: idCuenta, nombre: nombreMostrar),
          );
        }
      }
    }

    setState(() {
      cuentas = cuentasEncontradas;
      if (cuentas.isNotEmpty) {
        estadoTexto =
            "Se encontraron ${cuentas.length} cuentas. Selecciona y sincroniza.";
        estadoColor = Colors.grey;
      } else {
        estadoTexto = "La carpeta userdata está vacía.";
        estadoColor = Colors.red;
      }
    });
  }

  // --- LÓGICA DE SINCRONIZACIÓN ---
  // Verificación de procesos activos usando el terminal de Windows en segundo plano
  Future<bool> _estanProcesosAbiertos() async {
    try {
      if (Platform.isWindows) {
        var result = await Process.run('tasklist', []);
        return result.stdout.toString().toLowerCase().contains('dota2.exe');
      } else if (Platform.isLinux) {
        // pgrep busca procesos por nombre en Linux. Devuelve código de salida 0 si lo encuentra.
        var result = await Process.run('pgrep', ['-f', 'dota2']);
        return result.exitCode == 0;
      }
    } catch (e) {
      print("Error leyendo procesos: $e");
    }
    return false;
  }

  // Copia recursiva de directorios
  void _copiarDirectorio(Directory origen, Directory destino) {
    destino.createSync(recursive: true);

    for (var entidad in origen.listSync(recursive: false)) {
      String nombreItem = entidad.path.split(Platform.pathSeparator).last;
      String nuevaRuta = '${destino.path}${Platform.pathSeparator}$nombreItem';

      if (entidad is Directory) {
        Directory nuevoDirectorio = Directory(nuevaRuta);
        nuevoDirectorio.createSync();
        _copiarDirectorio(entidad, nuevoDirectorio);
      } else if (entidad is File) {
        entidad.copySync(nuevaRuta);
      }
    }
  }

  void _ejecutarSincronizacion() async {
    if (cuentaOrigenSeleccionada == null || cuentaDestinoSeleccionada == null) {
      setState(() {
        estadoTexto = "Por favor selecciona ambas cuentas.";
        estadoColor = Colors.red;
      });
      return;
    }

    if (cuentaOrigenSeleccionada!.id == cuentaDestinoSeleccionada!.id) {
      setState(() {
        estadoTexto = "La cuenta de origen y destino no pueden ser la misma.";
        estadoColor = Colors.red;
      });
      return;
    }

    setState(() {
      estadoTexto = "Verificando Steam...";
      estadoColor = Colors.orange;
    });

    // Verificamos si Dota están abiertos
    bool procesosAbiertos = await _estanProcesosAbiertos();
    if (procesosAbiertos) {
      setState(() {
        estadoTexto = "¡Error! Por favor cierra Dota 2 antes de sincronizar.";
        estadoColor = Colors.red;
      });
      return;
    }

    // Armamos las rutas (570 es el ID de Dota 2)
    String rutaOrigen = p.join(
      rutaUserData,
      cuentaOrigenSeleccionada!.id,
      '570',
    );
    String rutaDestino = p.join(
      rutaUserData,
      cuentaDestinoSeleccionada!.id,
      '570',
    );
    String rutaBackup = p.join(
      rutaUserData,
      cuentaDestinoSeleccionada!.id,
      '570_backup',
    );

    try {
      final dirOrigen = Directory(rutaOrigen);
      if (!dirOrigen.existsSync()) {
        setState(() {
          estadoTexto =
              "La cuenta origen no tiene datos de Dota 2 (carpeta 570).";
          estadoColor = Colors.red;
        });
        return;
      }

      final dirDestino = Directory(rutaDestino);
      final dirBackup = Directory(rutaBackup);

      // Sistema de Backup Automático
      if (dirDestino.existsSync()) {
        if (dirBackup.existsSync()) {
          dirBackup.deleteSync(recursive: true); // Borramos el backup viejo
        }
        dirDestino.renameSync(rutaBackup); // Renombramos el actual a backup
      }

      // Copiamos los archivos
      _copiarDirectorio(dirOrigen, Directory(rutaDestino));

      setState(() {
        estadoTexto = "¡Éxito! Configuración sincronizada y backup creado.";
        estadoColor = Colors.green;
      });
    } catch (e) {
      setState(() {
        estadoTexto = "Error al sincronizar: $e";
        estadoColor = Colors.red;
      });
    }
  }

  // --- MODAL DE AYUDA ---
  void _mostrarAyuda() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          // Fondo oscuro
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            "BIENVENIDO",
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "⚠️ IMPORTANTE:",
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "Para que tus cuentas aparezcan en la lista, debes haber iniciado sesión y abierto Dota 2 al menos una vez en esta PC con cada cuenta.",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              SizedBox(height: 16),
              Text(
                "Instrucciones de uso:",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "1. Cierra completamente Dota 2.\n2. Selecciona tu cuenta principal (Origen).\n3. Selecciona tu cuenta secundaria (Destino).\n4. Presiona Sincronizar.",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 16),
              Center(
                child: Text(
                  "Se creará un backup automático de tu configuración anterior.",
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50), // Verde
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 15,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(), // Cierra el modal
                child: const Text(
                  "Entendido",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barra Superior
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Text(
                        "DOTA 2 ",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFD32F2F),
                        ),
                      ),
                      Text(
                        "CONFIG SYNC",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D2D30),
                      foregroundColor: Colors.white70,
                      elevation: 0,
                    ),
                    onPressed: _mostrarAyuda,
                    child: const Text("Ayuda"),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              // Cuentas
              const Text(
                "Cuenta Origen (Tu configuración ideal):",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<CuentaSteam>(
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                hint: const Text("Selecciona una cuenta..."),
                initialValue: cuentaOrigenSeleccionada,
                items: cuentas.map((cuenta) {
                  return DropdownMenuItem<CuentaSteam>(
                    value: cuenta,
                    child: Text(cuenta.nombre, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (valor) =>
                    setState(() => cuentaOrigenSeleccionada = valor),
              ),
              const SizedBox(height: 20),

              const Text(
                "Cuenta Destino (La que se actualizará):",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<CuentaSteam>(
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                hint: const Text("Selecciona una cuenta..."),
                initialValue: cuentaDestinoSeleccionada,
                items: cuentas.map((cuenta) {
                  return DropdownMenuItem<CuentaSteam>(
                    value: cuenta,
                    child: Text(cuenta.nombre, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (valor) =>
                    setState(() => cuentaDestinoSeleccionada = valor),
              ),
              const SizedBox(height: 40),

              // Botón de Acción
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _ejecutarSincronizacion,
                child: const Text(
                  "SINCRONIZAR CONFIGURACIÓN",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // Estado
              Text(
                estadoTexto,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: estadoColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
