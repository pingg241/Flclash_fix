import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common.dart';

const _okStatus = 'ok';
const _silentServerStatuses = {'', 'group', 'unsupported'};

class ProxyGeoSection extends ConsumerWidget {
  final Proxy proxy;

  const ProxyGeoSection({super.key, required this.proxy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberId = proxy.runtimeId;
    if (memberId.isEmpty) {
      return const _GeoSlots();
    }
    final runtimeGroup = ref.watch(
      runtimeProxiesProvider.select((state) => state.groupById(memberId)),
    );
    if (runtimeGroup != null) {
      final leafId = ref.watch(resolvedCurrentLeafIdProvider(memberId));
      final leaf = ref.watch(
        runtimeProxiesProvider.select(
          (state) => leafId == null ? null : state.nodesById[leafId],
        ),
      );
      final serverState = leafId == null
          ? const ProxyServerGeoEntryState()
          : ref.watch(proxyServerGeoEntryProvider(leafId));
      return _GeoSlots(
        first: _CurrentLeafLine(leafName: leaf?.name),
        second: _ServerGeoLine(state: serverState),
      );
    }

    final serverState = ref.watch(proxyServerGeoEntryProvider(memberId));
    final exitState = ref.watch(proxyExitGeoEntryProvider(memberId));
    return _GeoSlots(
      first: _ServerGeoLine(state: serverState),
      second: _ExitGeoLine(state: exitState),
    );
  }
}

class _GeoSlots extends StatelessWidget {
  final Widget? first;
  final Widget? second;

  const _GeoSlots({this.first, this.second});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: proxyGeoLineHeight * 2 + 4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: proxyGeoLineHeight, child: first),
          const SizedBox(height: 4),
          SizedBox(height: proxyGeoLineHeight, child: second),
        ],
      ),
    );
  }
}

class _CurrentLeafLine extends StatelessWidget {
  final String? leafName;

  const _CurrentLeafLine({required this.leafName});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final currentName = leafName?.trim().isNotEmpty == true
        ? leafName!.trim()
        : appLocalizations.unknown;
    final text = '${appLocalizations.dynamicNode} · $currentName';
    final description = '${appLocalizations.currentNode}: $currentName';
    return Tooltip(
      message: description,
      triggerMode: TooltipTriggerMode.manual,
      child: Semantics(
        label: description,
        child: Row(
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 14,
              color: context.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerGeoLine extends StatelessWidget {
  final ProxyServerGeoEntryState state;

  const _ServerGeoLine({required this.state});

  @override
  Widget build(BuildContext context) {
    final value = state.value;
    final address = value?.primaryAddress;
    final status = value?.status ?? '';
    if (address != null && status == _okStatus) {
      return _GeoAddressLine(
        sourceLabel: context.appLocalizations.serverAddress,
        sourceIcon: Icons.dns_outlined,
        address: address,
        multiRegion: value?.multiRegion ?? false,
        loading: state.loading,
        stale: state.stale,
      );
    }
    if (state.loading) {
      return _GeoStatusLine(
        sourceLabel: context.appLocalizations.serverAddress,
        sourceIcon: Icons.dns_outlined,
        loading: true,
      );
    }
    if (state.error != null || !_silentServerStatuses.contains(status)) {
      return _GeoStatusLine(
        sourceLabel: context.appLocalizations.serverAddress,
        sourceIcon: Icons.dns_outlined,
        error: true,
      );
    }
    return const SizedBox.shrink();
  }
}

class _ExitGeoLine extends StatelessWidget {
  final ProxyExitGeoEntryState state;

  const _ExitGeoLine({required this.state});

  @override
  Widget build(BuildContext context) {
    if (!state.connected || !state.active) {
      return const SizedBox.shrink();
    }
    final value = state.value;
    if (value != null && value.ip.trim().isNotEmpty) {
      return _GeoAddressLine(
        sourceLabel: context.appLocalizations.exitAddress,
        sourceIcon: Icons.output_rounded,
        address: ProxyGeoAddress(
          ip: value.ip,
          countryCode: value.countryCode,
          asn: value.asn,
          aso: value.aso,
        ),
        loading: state.loading,
        stale: state.stale || value.stale,
        cached: value.cached,
        accent: true,
      );
    }
    if (state.loading) {
      return _GeoStatusLine(
        sourceLabel: context.appLocalizations.exitAddress,
        sourceIcon: Icons.output_rounded,
        loading: true,
        accent: true,
      );
    }
    if (state.error != null) {
      return _GeoStatusLine(
        sourceLabel: context.appLocalizations.exitAddress,
        sourceIcon: Icons.output_rounded,
        error: true,
        accent: true,
      );
    }
    return const SizedBox.shrink();
  }
}

class _GeoStatusLine extends StatelessWidget {
  final String sourceLabel;
  final IconData sourceIcon;
  final bool loading;
  final bool error;
  final bool accent;

  const _GeoStatusLine({
    required this.sourceLabel,
    required this.sourceIcon,
    this.loading = false,
    this.error = false,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? context.colorScheme.primary
        : context.colorScheme.onSurfaceVariant;
    final status = loading
        ? context.appLocalizations.loading
        : context.appLocalizations.locationUnavailable;
    return Semantics(
      label: '$sourceLabel: $status',
      child: Row(
        children: [
          Icon(sourceIcon, size: 14, color: color),
          const SizedBox(width: 4),
          if (loading)
            SizedBox.square(
              dimension: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else if (error)
            Icon(
              Icons.warning_amber_rounded,
              size: 12,
              color: context.colorScheme.error,
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _GeoAddressLine extends StatelessWidget {
  final String sourceLabel;
  final IconData sourceIcon;
  final ProxyGeoAddress address;
  final bool multiRegion;
  final bool loading;
  final bool stale;
  final bool cached;
  final bool accent;

  const _GeoAddressLine({
    required this.sourceLabel,
    required this.sourceIcon,
    required this.address,
    this.multiRegion = false,
    this.loading = false,
    this.stale = false,
    this.cached = false,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? context.colorScheme.primary
        : context.colorScheme.onSurfaceVariant;
    final countryCode = address.countryCode.trim().toUpperCase();
    final region = multiRegion
        ? context.appLocalizations.multipleRegions
        : countryCode;
    final flag = multiRegion ? '' : countryCodeToFlag(countryCode);
    final description = _addressDescription(
      context,
      sourceLabel: sourceLabel,
      address: address,
      multiRegion: multiRegion,
      cached: cached,
      stale: stale,
    );
    return Tooltip(
      message: description,
      triggerMode: TooltipTriggerMode.manual,
      child: Semantics(
        label: description,
        child: Row(
          children: [
            Icon(sourceIcon, size: 14, color: color),
            const SizedBox(width: 4),
            if (multiRegion)
              Icon(Icons.public, size: 14, color: color)
            else if (flag.isNotEmpty)
              Text(
                flag,
                style: context.textTheme.labelSmall?.copyWith(
                  fontFamily: FontFamily.twEmoji.value,
                  color: null,
                ),
              )
            else
              Icon(Icons.public_outlined, size: 14, color: color),
            if (region.isNotEmpty) ...[
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  region,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.labelSmall?.copyWith(color: color),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '·',
                style: context.textTheme.labelSmall?.copyWith(color: color),
              ),
              const SizedBox(width: 4),
            ] else
              const SizedBox(width: 4),
            Expanded(
              flex: 2,
              child: Text(
                address.ip,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.labelSmall?.copyWith(color: color),
              ),
            ),
            if (loading || stale || cached) ...[
              const SizedBox(width: 3),
              if (loading)
                SizedBox.square(
                  dimension: 9,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: color,
                  ),
                )
              else
                Icon(
                  stale ? Icons.history_toggle_off : Icons.history,
                  size: 11,
                  color: color,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String countryCodeToFlag(String countryCode) {
  final code = countryCode.trim().toUpperCase();
  if (code.length != 2) return '';
  final first = code.codeUnitAt(0);
  final second = code.codeUnitAt(1);
  if (first < 0x41 || first > 0x5A || second < 0x41 || second > 0x5A) {
    return '';
  }
  return String.fromCharCode(first - 0x41 + 0x1F1E6) +
      String.fromCharCode(second - 0x41 + 0x1F1E6);
}

String _addressDescription(
  BuildContext context, {
  required String sourceLabel,
  required ProxyGeoAddress address,
  required bool multiRegion,
  required bool cached,
  required bool stale,
}) {
  final appLocalizations = context.appLocalizations;
  final parts = <String>['$sourceLabel: ${address.ip}'];
  if (multiRegion) {
    parts.add(appLocalizations.multipleRegions);
  } else if (address.countryCode.isNotEmpty) {
    parts.add(
      '${appLocalizations.country}: ${address.countryCode.toUpperCase()}',
    );
  }
  if (address.asn.isNotEmpty) parts.add('ASN: AS${address.asn}');
  if (cached) parts.add(appLocalizations.cachedResult);
  if (stale) parts.add(appLocalizations.staleResult);
  return parts.join('\n');
}

void showProxyGeoDetails(BuildContext context, Proxy proxy) {
  showSheet<void>(
    context: context,
    props: const SheetProps(isScrollControlled: true),
    builder: (_) => _ProxyGeoDetailsSheet(proxy: proxy),
  );
}

class _ProxyGeoDetailsSheet extends ConsumerWidget {
  final Proxy proxy;

  const _ProxyGeoDetailsSheet({required this.proxy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberId = proxy.runtimeId;
    final runtimeGroup = memberId.isEmpty
        ? null
        : ref.watch(
            runtimeProxiesProvider.select((state) => state.groupById(memberId)),
          );
    final leafId = runtimeGroup == null
        ? memberId
        : ref.watch(resolvedCurrentLeafIdProvider(memberId));
    final leaf = ref.watch(
      runtimeProxiesProvider.select(
        (state) => leafId == null ? null : state.nodesById[leafId],
      ),
    );
    final serverState = leafId == null || leafId.isEmpty
        ? const ProxyServerGeoEntryState()
        : ref.watch(proxyServerGeoEntryProvider(leafId));
    final exitState = runtimeGroup != null || memberId.isEmpty
        ? const ProxyExitGeoEntryState()
        : ref.watch(proxyExitGeoEntryProvider(memberId));
    final appLocalizations = context.appLocalizations;
    return AdaptiveSheetScaffold(
      title: appLocalizations.detailsTitle,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmojiText(
              proxy.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            if (runtimeGroup != null) ...[
              _DetailValue(
                label: appLocalizations.currentNode,
                value: leaf?.name ?? appLocalizations.unknown,
              ),
              const SizedBox(height: 20),
            ],
            _ServerDetails(state: serverState),
            if (runtimeGroup == null &&
                exitState.active &&
                exitState.connected) ...[
              const SizedBox(height: 24),
              _ExitDetails(state: exitState),
            ],
          ],
        ),
      ),
    );
  }
}

class _ServerDetails extends StatelessWidget {
  final ProxyServerGeoEntryState state;

  const _ServerDetails({required this.state});

  @override
  Widget build(BuildContext context) {
    final value = state.value;
    final addresses = value?.addresses ?? const <ProxyGeoAddress>[];
    return _GeoDetailsSection(
      title: context.appLocalizations.serverAddress,
      icon: Icons.dns_outlined,
      addresses: addresses,
      loading: state.loading,
      error:
          state.error != null ||
          (value != null &&
              !_silentServerStatuses.contains(value.status) &&
              value.status != _okStatus),
      stale: state.stale,
      multiRegion: value?.multiRegion ?? false,
      source: switch (value?.source) {
        'literal' => 'IP',
        'dns' => 'DNS',
        _ => null,
      },
    );
  }
}

class _ExitDetails extends StatelessWidget {
  final ProxyExitGeoEntryState state;

  const _ExitDetails({required this.state});

  @override
  Widget build(BuildContext context) {
    final value = state.value;
    final addresses = value == null || value.ip.trim().isEmpty
        ? const <ProxyGeoAddress>[]
        : [
            ProxyGeoAddress(
              ip: value.ip,
              countryCode: value.countryCode,
              asn: value.asn,
              aso: value.aso,
            ),
          ];
    final metadata = <String>[
      if (value?.routeSample == true) context.appLocalizations.routeSample,
      if (value?.cached == true) context.appLocalizations.cachedResult,
    ].join(' · ');
    return _GeoDetailsSection(
      title: context.appLocalizations.exitAddress,
      icon: Icons.output_rounded,
      addresses: addresses,
      loading: state.loading,
      error: state.error != null,
      stale: state.stale || (value?.stale ?? false),
      source: metadata.isEmpty ? null : metadata,
    );
  }
}

class _GeoDetailsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<ProxyGeoAddress> addresses;
  final bool loading;
  final bool error;
  final bool stale;
  final bool multiRegion;
  final String? source;

  const _GeoDetailsSection({
    required this.title,
    required this.icon,
    required this.addresses,
    required this.loading,
    required this.error,
    required this.stale,
    this.multiRegion = false,
    this.source,
  });

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final metadata = <String>[
      if (source != null) '${appLocalizations.source}: $source',
      if (multiRegion) appLocalizations.multipleRegions,
      if (stale) appLocalizations.staleResult,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: context.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (loading)
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
          ],
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            metadata.join(' · '),
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (addresses.isEmpty)
          Row(
            children: [
              Icon(
                error ? Icons.warning_amber_rounded : Icons.public_off_outlined,
                size: 16,
                color: error
                    ? context.colorScheme.error
                    : context.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                loading
                    ? appLocalizations.loading
                    : appLocalizations.locationUnavailable,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          )
        else
          for (var index = 0; index < addresses.length; index++) ...[
            if (index > 0) const Divider(height: 24),
            _AddressDetails(address: addresses[index]),
          ],
      ],
    );
  }
}

class _AddressDetails extends StatelessWidget {
  final ProxyGeoAddress address;

  const _AddressDetails({required this.address});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: address.ip));
    if (context.mounted) {
      context.showNotifier(context.appLocalizations.copySuccess);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final countryCode = address.countryCode.trim().toUpperCase();
    final flag = countryCodeToFlag(countryCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                address.ip,
                style: context.textTheme.bodyMedium?.toJetBrainsMono,
              ),
            ),
            IconButton(
              tooltip: appLocalizations.copy,
              visualDensity: VisualDensity.compact,
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
          ],
        ),
        if (countryCode.isNotEmpty)
          _DetailValue(
            label: appLocalizations.country,
            value: '${flag.isEmpty ? '' : '$flag '}$countryCode',
          ),
        if (address.asn.isNotEmpty)
          _DetailValue(label: 'ASN', value: 'AS${address.asn}'),
        if (address.aso.trim().isNotEmpty)
          _DetailValue(
            label: appLocalizations.organization,
            value: address.aso.trim(),
          ),
      ],
    );
  }
}

class _DetailValue extends StatelessWidget {
  final String label;
  final String value;

  const _DetailValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: context.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
