import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/cuenta_steam.dart';

class SteamSyncService {
  String _rutaUserData = "";
  List<CuentaSteam> cuentasEncontradas = [];

  // Inicializa las rutas buscando en el sistema operativo
  Future<void> inicializarRutas() async {
    if (Platform.isWindows) {
      try {
        var result = await Process.run('reg', [
          'query',
          r'HKCU\Software\Valve\Steam',
          '/v',
          'SteamPath',
        ]);
        if (result.exitCode == 0) {
          final output = result.stdout.toString();
          final exp = RegExp(r'REG_SZ\s+(.+)');
          final match = exp.firstMatch(output);

          if (match != null) {
            String steamPath = match
                .group(1)!
                .trim()
                .replaceAll('/', Platform.pathSeparator);
            _rutaUserData = p.join(steamPath, 'userdata');
          }
        }
      } catch (e) {
        throw Exception("Error leyendo el registro de Windows: $e");
      }
    } else if (Platform.isLinux) {
      String? home = Platform.environment['HOME'];
      if (home != null) {
        _rutaUserData = p.join(home, '.local', 'share', 'Steam', 'userdata');
        if (!await Directory(_rutaUserData).exists()) {
          _rutaUserData = p.join(home, '.steam', 'steam', 'userdata');
        }
      }
    }

    if (_rutaUserData.isEmpty || !await Directory(_rutaUserData).exists()) {
      throw Exception(
        "No se encontró la carpeta userdata de Steam en este sistema.",
      );
    }
  }

  // Carga y mapeo de las cuentas
  Future<void> cargarCuentas() async {
    cuentasEncontradas.clear();

    String rutaLoginUsers = p.join(
      Directory(_rutaUserData).parent.path,
      'config',
      'loginusers.vdf',
    );
    Map<String, String> nombresCuentas = await _obtenerMapeoCuentas(
      rutaLoginUsers,
    );

    final dir = Directory(_rutaUserData);
    await for (var entidad in dir.list()) {
      if (entidad is Directory) {
        String idCuenta = p.basename(entidad.path);

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

    if (cuentasEncontradas.isEmpty) {
      throw Exception("La carpeta userdata existe, pero está vacía.");
    }
  }

  Future<Map<String, String>> _obtenerMapeoCuentas(
      String rutaLoginUsers,
      ) async {
    Map<String, String> mapeo = {};
    final file = File(rutaLoginUsers);

    if (!await file.exists()) return mapeo;

    final lineas = await file.readAsLines();
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

  Future<bool> estanProcesosAbiertos() async {
    try {
      if (Platform.isWindows) {
        var result = await Process.run('tasklist', []);
        return result.stdout.toString().toLowerCase().contains('dota2.exe');
      } else if (Platform.isLinux) {
        var result = await Process.run('pgrep', ['-f', 'dota2']);
        return result.exitCode == 0;
      }
    } catch (e) {
      debugPrint("Error leyendo procesos: $e");
    }
    return false;
  }

  Future<void> ejecutarSincronizacion(
      CuentaSteam origen,
      CuentaSteam destino,
      ) async {
    if (origen.id == destino.id) {
      throw Exception("La cuenta de origen y destino no pueden ser la misma.");
    }

    if (await estanProcesosAbiertos()) {
      throw Exception("¡Error! Por favor cierra Dota 2 antes de sincronizar.");
    }

    String rutaOrigen = p.join(_rutaUserData, origen.id, '570');
    String rutaDestino = p.join(_rutaUserData, destino.id, '570');
    String rutaBackup = p.join(_rutaUserData, destino.id, '570_backup');

    final dirOrigen = Directory(rutaOrigen);
    if (!await dirOrigen.exists()) {
      throw Exception(
        "La cuenta origen no tiene datos de Dota 2 (carpeta 570).",
      );
    }

    final dirDestino = Directory(rutaDestino);
    final dirBackup = Directory(rutaBackup);

    // Sistema de Backup Automático
    if (await dirDestino.exists()) {
      if (await dirBackup.exists()) {
        await dirBackup.delete(recursive: true);
      }
      await dirDestino.rename(rutaBackup);
    }

    await _copiarDirectorio(dirOrigen, Directory(rutaDestino));
  }

  Future<void> _copiarDirectorio(Directory origen, Directory destino) async {
    await destino.create(recursive: true);

    await for (var entidad in origen.list(recursive: false)) {
      String nombreItem = p.basename(entidad.path);
      String nuevaRuta = p.join(destino.path, nombreItem);

      if (entidad is Directory) {
        Directory nuevoDirectorio = Directory(nuevaRuta);
        await nuevoDirectorio.create();
        await _copiarDirectorio(entidad, nuevoDirectorio);
      } else if (entidad is File) {
        await entidad.copy(nuevaRuta);
      }
    }
  }
}