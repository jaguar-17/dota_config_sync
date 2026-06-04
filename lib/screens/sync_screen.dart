import 'package:flutter/material.dart';

import '../models/cuenta_steam.dart';
import '../services/steam_sync_service.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final SteamSyncService _syncService = SteamSyncService();

  String estadoTexto = "Inicializando...";
  Color estadoColor = Colors.grey;
  bool isCargando = true;

  CuentaSteam? cuentaOrigenSeleccionada;
  CuentaSteam? cuentaDestinoSeleccionada;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      isCargando = true;
      estadoTexto = "Buscando instalación de Steam...";
      estadoColor = Colors.grey;
    });

    try {
      await _syncService.inicializarRutas();
      await _syncService.cargarCuentas();

      setState(() {
        estadoTexto =
        "Se encontraron ${_syncService.cuentasEncontradas.length} cuentas. Selecciona y sincroniza.";
        estadoColor = Colors.grey;
        isCargando = false;
      });
    } catch (e) {
      setState(() {
        estadoTexto = e.toString().replaceAll("Exception: ", "");
        estadoColor = Colors.red;
        isCargando = false;
      });
    }
  }

  Future<void> _iniciarSincronizacion() async {
    if (cuentaOrigenSeleccionada == null || cuentaDestinoSeleccionada == null) {
      setState(() {
        estadoTexto = "Por favor selecciona ambas cuentas.";
        estadoColor = Colors.red;
      });
      return;
    }

    setState(() {
      isCargando = true;
      estadoTexto = "Verificando estado de Steam y sincronizando...";
      estadoColor = Colors.orange;
    });

    try {
      await _syncService.ejecutarSincronizacion(
        cuentaOrigenSeleccionada!,
        cuentaDestinoSeleccionada!,
      );

      setState(() {
        estadoTexto = "¡Éxito! Configuración sincronizada y backup creado.";
        estadoColor = Colors.green;
      });
    } catch (e) {
      setState(() {
        estadoTexto = e.toString().replaceAll("Exception: ", "");
        estadoColor = Colors.red;
      });
    } finally {
      setState(() => isCargando = false);
    }
  }

  void _mostrarAyuda() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
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
                  backgroundColor: const Color(0xFF4CAF50),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 15,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
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
                items: _syncService.cuentasEncontradas.map((cuenta) {
                  return DropdownMenuItem<CuentaSteam>(
                    value: cuenta,
                    child: Text(cuenta.nombre, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: isCargando
                    ? null
                    : (valor) =>
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
                items: _syncService.cuentasEncontradas.map((cuenta) {
                  return DropdownMenuItem<CuentaSteam>(
                    value: cuenta,
                    child: Text(cuenta.nombre, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: isCargando
                    ? null
                    : (valor) =>
                    setState(() => cuentaDestinoSeleccionada = valor),
              ),
              const SizedBox(height: 40),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[800],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: isCargando ? null : _iniciarSincronizacion,
                child: isCargando
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text(
                  "SINCRONIZAR CONFIGURACIÓN",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 15),

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