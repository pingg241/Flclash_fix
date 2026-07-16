import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'geo.dart';

class ProxyCard extends StatelessWidget {
  final Group group;
  final Proxy proxy;
  final ProxyCardType type;

  const ProxyCard({
    super.key,
    required this.group,
    required this.proxy,
    required this.type,
  });

  String get groupName => group.name;

  GroupType get groupType => group.type;

  String? get testUrl => group.testUrl;

  Measure get measure => globalState.measure;

  void _handleTestCurrentDelay() {
    if (isDelayTestBusy) {
      return;
    }
    proxyDelayTest(proxy, testUrl);
  }

  Widget _buildDelayText() {
    return SizedBox(
      height: measure.labelSmallHeight,
      child: Consumer(
        builder: (context, ref, _) {
          final delay = ref.watch(
            delayProvider(proxyName: proxy.name, testUrl: testUrl),
          );
          return FadeThroughBox(
            alignment: type == ProxyCardType.expand
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: delay == 0 || delay == null
                ? SizedBox(
                    height: measure.labelSmallHeight,
                    width: measure.labelSmallHeight,
                    child: delay == 0
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : IconButton(
                            icon: const Icon(Icons.bolt),
                            iconSize: globalState.measure.labelSmallHeight,
                            padding: EdgeInsets.zero,
                            onPressed: _handleTestCurrentDelay,
                          ),
                  )
                : GestureDetector(
                    onTap: _handleTestCurrentDelay,
                    child: Text(
                      delay > 0
                          ? '$delay ms'
                          : context.appLocalizations.timeout,
                      style: context.textTheme.labelSmall?.copyWith(
                        overflow: TextOverflow.ellipsis,
                        color: utils.getDelayColor(delay),
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildProxyNameText(BuildContext context) {
    if (type == ProxyCardType.min) {
      return SizedBox(
        height: measure.bodyMediumHeight * 1,
        child: EmojiText(
          proxy.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyMedium,
        ),
      );
    } else {
      return SizedBox(
        height: measure.bodyMediumHeight * 2,
        child: EmojiText(
          proxy.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyMedium,
        ),
      );
    }
  }

  Future<void> _changeProxy(WidgetRef ref) async {
    final isComputedSelected = groupType.isComputedSelected;
    final isSelector = groupType == GroupType.Selector;
    if (isComputedSelected || isSelector) {
      final snapshot = ref.read(runtimeProxiesProvider);
      final useRuntimeIds =
          group.runtimeId.isNotEmpty &&
          proxy.runtimeId.isNotEmpty &&
          snapshot.generation > 0;
      if (!useRuntimeIds && !hasUniqueLegacyProxyName(group, proxy.name)) {
        return;
      }
      final isCurrent = useRuntimeIds
          ? ref.read(selectedProxyIdProvider(group.runtimeId)) ==
                proxy.runtimeId
          : ref.read(proxyNameProvider(groupName)) == proxy.name;
      final nextProxyName = switch (isComputedSelected) {
        true => isCurrent ? '' : proxy.name,
        false => proxy.name,
      };
      await globalState.safeRun<void>(
        () => ref
            .read(proxiesActionProvider.notifier)
            .changeProxyDebounce(
              groupName,
              nextProxyName,
              groupId: useRuntimeIds ? group.runtimeId : null,
              memberId: useRuntimeIds && nextProxyName.isNotEmpty
                  ? proxy.runtimeId
                  : null,
              generation: useRuntimeIds ? snapshot.generation : null,
            ),
      );
      return;
    }
    globalState.showNotifier(currentAppLocalizations.notSelectedTip);
  }

  @override
  Widget build(BuildContext context) {
    final measure = globalState.measure;
    final delayText = _buildDelayText();
    final proxyNameText = _buildProxyNameText(context);
    return Stack(
      children: [
        Consumer(
          builder: (_, ref, child) {
            final useRuntimeIds =
                group.runtimeId.isNotEmpty && proxy.runtimeId.isNotEmpty;
            final isSelected = useRuntimeIds
                ? ref.watch(selectedProxyIdProvider(group.runtimeId)) ==
                      proxy.runtimeId
                : ref.watch(selectedProxyNameProvider(groupName)) ==
                          proxy.name &&
                      hasUniqueLegacyProxyName(group, proxy.name);
            return CommonCard(
              key: key,
              onPressed: () {
                _changeProxy(ref);
              },
              onLongPress: () => showProxyGeoDetails(context, proxy),
              isSelected: isSelected,
              child: child!,
            );
          },
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                proxyNameText,
                const SizedBox(height: 8),
                if (type == ProxyCardType.expand) ...[
                  SizedBox(
                    height: measure.bodySmallHeight,
                    child: _ProxyDesc(proxy: proxy),
                  ),
                  const SizedBox(height: 6),
                  delayText,
                ] else
                  SizedBox(
                    height: measure.bodySmallHeight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          flex: 1,
                          child: TooltipText(
                            text: Text(
                              proxy.type,
                              style: context.textTheme.bodySmall?.copyWith(
                                overflow: TextOverflow.ellipsis,
                                color: context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        delayText,
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                ProxyGeoSection(proxy: proxy),
              ],
            ),
          ),
        ),
        if (groupType.isComputedSelected)
          Positioned(
            top: 0,
            right: 0,
            child: _ProxyComputedMark(group: group, proxy: proxy),
          ),
      ],
    );
  }
}

class _ProxyDesc extends ConsumerWidget {
  final Proxy proxy;

  const _ProxyDesc({required this.proxy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desc = ref.watch(proxyDescProvider(proxy));
    return EmojiText(
      desc,
      overflow: TextOverflow.ellipsis,
      style: context.textTheme.bodySmall?.copyWith(
        color: context.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ProxyComputedMark extends ConsumerWidget {
  final Group group;
  final Proxy proxy;

  const _ProxyComputedMark({required this.group, required this.proxy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useRuntimeIds =
        group.runtimeId.isNotEmpty && proxy.runtimeId.isNotEmpty;
    final selected = useRuntimeIds
        ? ref.watch(selectedProxyIdProvider(group.runtimeId)) == proxy.runtimeId
        : ref.watch(proxyNameProvider(group.name)) == proxy.name &&
              hasUniqueLegacyProxyName(group, proxy.name);
    if (!selected) {
      return const SizedBox();
    }
    return Container(
      alignment: Alignment.topRight,
      margin: const EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.secondaryContainer,
        ),
        child: const SelectIcon(),
      ),
    );
  }
}
