// =============================================================================
// COMPONENTES VISUALES de la lista de vehículos — extraídos para mantener
// navegable el screen principal. Comparten privacidad y los imports via
// `part of`. Si necesitás reusar alguno desde otra pantalla, hacelo público
// y movelo a `lib/features/vehicles/widgets/`.
// =============================================================================

part of 'admin_vehiculos_lista_screen.dart';

// =============================================================================
// LISTA POR TIPO (un AppListPage por tab)
// =============================================================================

class _ListaPorTipo extends StatelessWidget {
  final String tipo;
  const _ListaPorTipo({required this.tipo});

  @override
  Widget build(BuildContext context) {
    return Consumer<VehiculoProvider>(
      builder: (ctx, provider, _) => AppListPage(
        stream: provider.getVehiculosPorTipo(tipo),
        searchHint: 'Buscar patente, marca, modelo o VIN...',
        emptyTitle: 'Sin ${_pluralPretty(tipo)} cargados',
        emptySubtitle: 'Tocá el botón + para agregar uno',
        emptyIcon: Icons.local_shipping_outlined,
        filter: (doc, q) {
          final data = doc.data() as Map<String, dynamic>;
          final hay = '${doc.id} ${data['MARCA'] ?? ''} '
                  '${data['MODELO'] ?? ''} ${data['VIN'] ?? ''}'
              .toUpperCase();
          return hay.contains(q);
        },
        itemBuilder: (ctx, doc) => _VehiculoCard(doc: doc),
      ),
    );
  }

  String _pluralPretty(String tipo) {
    return AppTiposVehiculo.pluralMinusculas[tipo] ?? tipo.toLowerCase();
  }
}

// =============================================================================
// TARJETA DE VEHÍCULO (vista colapsada)
// =============================================================================

class _VehiculoCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _VehiculoCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final patente = doc.id;
    final marca = (data['MARCA'] ?? 'S/D').toString();
    final modelo = (data['MODELO'] ?? 'S/D').toString();
    final estado = (data['ESTADO'] ?? 'LIBRE').toString().toUpperCase();
    final km = data['KM_ACTUAL'];
    // Avatar de la unidad: si tiene foto cargada, la mostramos circular.
    // Si no, fallback a un ícono según el tipo (tractor / enganche).
    final urlFoto = data['ARCHIVO_FOTO']?.toString();
    final tieneFoto =
        urlFoto != null && urlFoto.isNotEmpty && urlFoto != '-';
    final tipo = (data['TIPO'] ?? 'TRACTOR').toString().toUpperCase();
    final esTractor = tipo == 'TRACTOR';

    return Selector<VehiculoProvider,
        ({bool loading, bool success, String? error})>(
      selector: (_, p) => (
        loading: p.isLoading(patente),
        success: p.isSuccess(patente),
        error: p.getError(patente),
      ),
      builder: (ctx, state, _) {
        return AppCard(
          onTap: () => _abrirDetalle(context, patente, data),
          highlighted: state.success || state.error != null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar de la unidad — mismo patrón que _EmpleadoCard.
              // Foto si la cargó el admin; si no, ícono temático (camión
              // para tractor, enganche para acoplados).
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white12,
                backgroundImage: tieneFoto ? NetworkImage(urlFoto) : null,
                child: !tieneFoto
                    ? Icon(
                        esTractor ? Icons.local_shipping : Icons.rv_hookup,
                        color: Colors.white54,
                        size: 22,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: patente + badge estado + indicadores
                    Row(
                      children: [
                        Text(
                          patente.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _EstadoBadge(estado: estado),
                        const Spacer(),
                        if (state.loading)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                        if (state.success)
                          const Icon(Icons.check_circle,
                              color: AppColors.accentGreen, size: 16),
                        if (state.error != null)
                          const Icon(Icons.error_outline,
                              color: AppColors.accentRed, size: 16),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Subtítulo: marca/modelo + km
                    Row(
                      children: [
                        Icon(Icons.local_shipping,
                            size: 12, color: Colors.white.withAlpha(120)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$marca $modelo',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.speed,
                            size: 12, color: Colors.white.withAlpha(120)),
                        const SizedBox(width: 4),
                        Text(
                          '${AppFormatters.formatearKilometraje(km)} km',
                          style: const TextStyle(
                            color: AppColors.accentGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    // Telemetría compacta (combustible + autonomía). Solo
                    // se muestra si la unidad reporta esos datos vía
                    // Volvo. Para unidades sin telemetría, esta fila no
                    // aparece y el card queda como antes.
                    _TelemetriaCompacta(data: data),
                    const SizedBox(height: 10),
                    // Vista rápida de vencimientos (badges compactos)
                    Row(
                      children: [
                        _MiniVencimiento(
                            label: 'RTO', fecha: data['VENCIMIENTO_RTO']),
                        const SizedBox(width: 14),
                        _MiniVencimiento(
                            label: 'Seguro',
                            fecha: data['VENCIMIENTO_SEGURO']),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Dispara el sync con Volvo si corresponde y abre el bottom sheet de detalle.
  void _abrirDetalle(BuildContext context, String patente,
          Map<String, dynamic> data) =>
      abrirDetalleVehiculo(context, patente, data);
}

/// Abre el detalle (bottom sheet) de un vehículo desde cualquier parte
/// del código.
///
/// Si la unidad es Volvo y tiene VIN, dispara un sync de KM no bloqueante
/// en segundo plano antes de abrir — el stream del doc se refresca solo.
///
/// Pensado para que features externos (CommandPalette / búsqueda Ctrl+K,
/// links profundos, etc.) puedan abrir el detalle sin tener que crear
/// un `_VehiculoCard` artificial.
void abrirDetalleVehiculo(BuildContext context, String patente,
    Map<String, dynamic> data) {
  final marca = (data['MARCA'] ?? '').toString().toUpperCase();
  final vin = (data['VIN'] ?? '').toString();

  // Sync no bloqueante: si es Volvo y tiene VIN, refrescamos el KM en
  // segundo plano. El stream del documento se actualiza solo cuando termina.
  if (marca == 'VOLVO' && vin.isNotEmpty) {
    final p = context.read<VehiculoProvider>();
    if (!p.isLoading(patente) && p.debeSincronizar(patente)) {
      p.sync(patente, vin);
    }
  }

  AppDetailSheet.show(
    context: context,
    title: 'Ficha $patente',
    icon: Icons.local_shipping,
    actions: [
      IconButton(
        icon: const Icon(Icons.edit, color: AppColors.accentGreen, size: 20),
        tooltip: 'Editar ficha',
        onPressed: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminVehiculoFormScreen(
                vehiculoId: patente,
                datosIniciales: data,
              ),
            ),
          );
        },
      ),
    ],
    builder: (sheetCtx, scrollCtl) => _DetalleVehiculo(
      patente: patente,
      dataInicial: data,
      scrollController: scrollCtl,
    ),
  );
}

// =============================================================================
// DETALLE DEL VEHÍCULO (contenido del bottom sheet)
// =============================================================================

class _DetalleVehiculo extends StatelessWidget {
  final String patente;
  final Map<String, dynamic> dataInicial;
  final ScrollController scrollController;

  const _DetalleVehiculo({
    required this.patente,
    required this.dataInicial,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection(AppCollections.vehiculos)
          .doc(patente)
          .snapshots(),
      builder: (ctx, snap) {
        // Mientras llega el primer snapshot mostramos los datos que
        // teníamos del listado, así no parpadea el sheet.
        final data = snap.hasData && snap.data!.exists
            ? snap.data!.data() as Map<String, dynamic>
            : dataInicial;

        return _buildBody(data);
      },
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    final marca = (data['MARCA'] ?? 'S/D').toString();
    final modelo = (data['MODELO'] ?? 'S/D').toString();
    final anio = (data['ANIO'] ?? data['AÑO'] ?? '').toString();
    final estado = (data['ESTADO'] ?? 'LIBRE').toString().toUpperCase();
    final vin = (data['VIN'] ?? '').toString();
    // KM ahora se lee dentro de _PanelTelemetria; no hace falta tenerlo
    // como variable local acá.

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        // Header con marca + modelo + estado
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$marca $modelo'.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (anio.isNotEmpty && anio != '0')
                    Text(
                      'Año $anio',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                ],
              ),
            ),
            _EstadoBadge(estado: estado),
          ],
        ),
        const SizedBox(height: 16),

        // Panel de telemetría: KM + combustible + autonomía. Si la unidad
        // no tiene combustible/autonomía reportados, el panel cae a una
        // tarjeta simple de KM (compatibilidad con vehículos no-Volvo).
        _PanelTelemetria(data: data),

        const SizedBox(height: 18),
        const _SectionTitle(icon: Icons.fingerprint, label: 'Datos técnicos'),
        _InfoRow(
            label: 'VIN',
            valor: vin.isEmpty ? '—' : vin,
            monoespaciado: true),
        _InfoRow(
            label: 'Empresa', valor: (data['EMPRESA'] ?? '—').toString()),

        const SizedBox(height: 18),
        const _SectionTitle(icon: Icons.event_note, label: 'Vencimientos'),
        // Iteramos AppVencimientos.forTipo() para que sumar un vencimiento
        // nuevo a la config (ej. extintores en TRACTOR) aparezca automaticamente
        // en la ficha sin tocar este archivo. Antes estaba hardcoded a RTO+Seguro
        // y los extintores cargados en tractores no se veian aca aunque si en
        // la pantalla del chofer y en el form de edicion.
        for (final spec
            in AppVencimientos.forTipo(data['TIPO']?.toString()))
          _VencimientoRow(
            etiqueta: spec.etiqueta,
            fecha: data[spec.campoFecha],
            url: data[spec.campoArchivo],
            tituloVisor: '${spec.etiqueta} $patente',
          ),

        if (data['ULTIMA_SINCRO'] != null) ...[
          const SizedBox(height: 18),
          const _SectionTitle(icon: Icons.sync, label: 'Sincronización Volvo'),
          Row(
            children: [
              Text(
                _formatTimestamp(data['ULTIMA_SINCRO']),
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 8),
              if ((data['SINCRO_TIPO'] ?? '') != '')
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accentCyan.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (data['SINCRO_TIPO'] ?? '').toString(),
                    style: const TextStyle(
                      color: AppColors.accentCyan,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ],

        const SizedBox(height: 30),
      ],
    );
  }

  String _formatTimestamp(dynamic ts) {
    DateTime? d;
    if (ts is Timestamp) {
      d = ts.toDate();
    } else if (ts is DateTime) {
      d = ts;
    } else if (ts is String) {
      d = DateTime.tryParse(ts);
    }
    if (d == null) {
      return '—';
    }

    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) {
      return 'hace ${diff.inSeconds}s';
    }
    if (diff.inMinutes < 60) {
      return 'hace ${diff.inMinutes}min';
    }
    if (diff.inHours < 24) {
      return 'hace ${diff.inHours}h';
    }
    if (diff.inDays < 7) {
      return 'hace ${diff.inDays}d';
    }
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

// =============================================================================
// WIDGETS PRIVADOS DE ESTA PANTALLA (no se reutilizan en otras)
// =============================================================================

class _EstadoBadge extends StatelessWidget {
  final String estado;
  const _EstadoBadge({required this.estado});

  Color get _color {
    switch (estado.toUpperCase()) {
      case 'LIBRE':
        return AppColors.accentGreen;
      case 'OCUPADO':
      case 'ASIGNADO':
        return AppColors.accentBlue;
      case 'TALLER':
      case 'MANTENIMIENTO':
        return AppColors.accentOrange;
      case 'BAJA':
      case 'INACTIVO':
        return AppColors.accentRed;
      default:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withAlpha(80)),
      ),
      child: Text(
        estado,
        style: TextStyle(
          color: _color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _MiniVencimiento extends StatelessWidget {
  final String label;
  final dynamic fecha;
  const _MiniVencimiento({required this.label, required this.fecha});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.event_note, size: 12, color: Colors.white38),
        const SizedBox(width: 4),
        Text(label,
            style:
                const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(width: 6),
        VencimientoBadge(fecha: fecha, compact: true),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accentGreen, size: 16),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.accentGreen,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String valor;
  final bool monoespaciado;
  const _InfoRow({
    required this.label,
    required this.valor,
    this.monoespaciado = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: monoespaciado ? 'monospace' : null,
                letterSpacing: monoespaciado ? 0.5 : 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TELEMETRÍA (combustible + autonomía leídos de Volvo Connect)
// ─────────────────────────────────────────────────────────────────────────────

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// Color para la barrita de combustible: verde > 50, naranja 20-50, rojo < 20.
Color _colorCombustible(double pct) {
  if (pct >= 50) return AppColors.accentGreen;
  if (pct >= 20) return AppColors.accentOrange;
  return AppColors.accentRed;
}

/// Versión compacta de la telemetría para usar dentro del card de la lista.
/// Una sola fila con dos chips: combustible y autonomía. Si la unidad no
/// reporta ninguno de los dos, el widget devuelve un SizedBox vacío.
class _TelemetriaCompacta extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TelemetriaCompacta({required this.data});

  @override
  Widget build(BuildContext context) {
    final fuel = _toDouble(data['NIVEL_COMBUSTIBLE']);
    final auton = _toDouble(data['AUTONOMIA_KM']);

    if (fuel == null && auton == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          if (fuel != null) ...[
            _ChipTelemetria(
              icono: Icons.local_gas_station,
              color: _colorCombustible(fuel),
              texto: '${fuel.clamp(0, 100).toStringAsFixed(0)}%',
            ),
            const SizedBox(width: 8),
          ],
          if (auton != null)
            _ChipTelemetria(
              icono: Icons.route,
              color: AppColors.accentCyan,
              texto: '${auton.toStringAsFixed(0)} km',
            ),
        ],
      ),
    );
  }
}

class _ChipTelemetria extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String texto;

  const _ChipTelemetria({
    required this.icono,
    required this.color,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            texto,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel de telemetría grande que va en el bottom sheet del detalle.
/// Reemplaza la tarjeta de "Kilometraje" original. Si la unidad solo
/// tiene KM (no es Volvo o no reporta), se ve como antes.
class _PanelTelemetria extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PanelTelemetria({required this.data});

  @override
  Widget build(BuildContext context) {
    final km = _toDouble(data['KM_ACTUAL']);
    final fuel = _toDouble(data['NIVEL_COMBUSTIBLE']);
    final auton = _toDouble(data['AUTONOMIA_KM']);
    final hayTelemetria = fuel != null || auton != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.accentGreen.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentGreen.withAlpha(40)),
      ),
      child: hayTelemetria
          ? Row(
              children: [
                Expanded(
                  child: _CeldaTelemetria(
                    icono: Icons.speed,
                    color: AppColors.accentGreen,
                    valor: km != null
                        ? AppFormatters.formatearKilometraje(km)
                        : '—',
                    unidad: 'km',
                    etiqueta: 'ODÓMETRO',
                  ),
                ),
                if (fuel != null)
                  Expanded(
                    child: _CeldaCombustible(porcentaje: fuel),
                  ),
                if (auton != null)
                  Expanded(
                    child: _CeldaTelemetria(
                      icono: Icons.route,
                      color: AppColors.accentCyan,
                      valor: auton.toStringAsFixed(0),
                      unidad: 'km',
                      etiqueta: 'AUTONOMÍA',
                    ),
                  ),
              ],
            )
          // Fallback: igual que antes para unidades sin combustible/autonomía.
          : Row(
              children: [
                const Icon(Icons.speed, color: AppColors.accentGreen),
                const SizedBox(width: 10),
                const Text('Kilometraje',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
                const Spacer(),
                Text(
                  '${AppFormatters.formatearKilometraje(km)} km',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
    );
  }
}

class _CeldaTelemetria extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String valor;
  final String unidad;
  final String etiqueta;

  const _CeldaTelemetria({
    required this.icono,
    required this.color,
    required this.valor,
    required this.unidad,
    required this.etiqueta,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icono, color: color, size: 22),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: valor,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              TextSpan(
                text: ' $unidad',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          etiqueta,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _CeldaCombustible extends StatelessWidget {
  final double porcentaje;
  const _CeldaCombustible({required this.porcentaje});

  @override
  Widget build(BuildContext context) {
    final pct = porcentaje.clamp(0.0, 100.0);
    final color = _colorCombustible(pct);

    return Column(
      children: [
        Icon(Icons.local_gas_station, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          '${pct.toStringAsFixed(0)}%',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 60,
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct / 100,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'COMBUSTIBLE',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _VencimientoRow extends StatelessWidget {
  final String etiqueta;
  final dynamic fecha;
  final String? url;
  final String tituloVisor;

  const _VencimientoRow({
    required this.etiqueta,
    required this.fecha,
    required this.url,
    required this.tituloVisor,
  });

  @override
  Widget build(BuildContext context) {
    final tieneFecha = fecha != null && fecha.toString().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AppFileThumbnail(url: url, tituloVisor: tituloVisor),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(
              etiqueta,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              tieneFecha ? AppFormatters.formatearFecha(fecha) : '—',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          VencimientoBadge(fecha: fecha),
        ],
      ),
    );
  }
}
