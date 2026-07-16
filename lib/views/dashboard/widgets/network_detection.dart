import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkDetection extends ConsumerStatefulWidget {
  const NetworkDetection({super.key});

  @override
  ConsumerState<NetworkDetection> createState() => _NetworkDetectionState();
}

class _NetworkDetectionState extends ConsumerState<NetworkDetection> {
  String _countryCodeToEmoji(String countryCode) {
    final String code = countryCode.toUpperCase();
    if (code.length != 2) {
      return countryCode;
    }
    final int firstLetter = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int secondLetter = code.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(firstLetter) + String.fromCharCode(secondLetter);
  }

  /// Detect IP family from the address string (IPv6 contains ':').
  String _ipFamilyLabel(String ip) {
    final trimmed = ip.trim();
    if (trimmed.contains(':')) {
      return 'IPv6';
    }
    return 'IPv4';
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final networkDetection = ref.watch(networkDetectionProvider);
    final ipInfo = networkDetection.ipInfo;
    final isLoading = networkDetection.isLoading;
    final isRefreshing = ipInfo != null && isLoading;
    // Do not tint emoji with TextStyle.color — it becomes a solid brown blob.
    final emojiTextStyle = context.textTheme.titleMedium?.copyWith(
      fontFamily: FontFamily.twEmoji.value,
      color: null,
      height: 1.1,
    );
    final titleTextStyle = context.colorScheme.onSurfaceVariant;
    final descTextStyle = context.textTheme.titleSmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final titleLabel = ipInfo != null
        ? _ipFamilyLabel(ipInfo.ip)
        : appLocalizations.networkDetection;
    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        onPressed: () {},
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              height: globalState.measure.titleMediumHeight + 16,
              padding: baseInfoEdgeInsets.copyWith(bottom: 0),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  ipInfo != null
                      ? Text(
                          _countryCodeToEmoji(ipInfo.countryCode),
                          style: emojiTextStyle,
                        )
                      : Icon(Icons.network_check, color: titleTextStyle),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 1,
                    child: TooltipText(
                      text: Text(
                        titleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: descTextStyle,
                      ),
                    ),
                  ),
                  SizedBox(
                    key: const ValueKey('network-detection-refresh-slot'),
                    width: 18,
                    height: 12,
                    child: isRefreshing
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox.square(
                              dimension: 12,
                              child: CircularProgressIndicator(
                                key: const ValueKey(
                                  'network-detection-refreshing',
                                ),
                                strokeWidth: 1.5,
                                color: context.colorScheme.primary,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 2),
                  AspectRatio(
                    aspectRatio: 1,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        globalState.showMessage(
                          title: appLocalizations.tip,
                          message: TextSpan(
                            text: appLocalizations.detectionTip,
                          ),
                          cancelable: false,
                        );
                      },
                      icon: Icon(
                        size: 16.ap,
                        Icons.info_outline,
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: baseInfoEdgeInsets.copyWith(top: 0),
              child: SizedBox(
                height: globalState.measure.bodyMediumHeight + 2,
                child: FadeThroughBox(
                  child: ipInfo != null
                      ? TooltipText(
                          text: Text(
                            ipInfo.ip,
                            style: context.textTheme.bodyMedium?.toLight
                                .adjustSize(1),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : isLoading == false && ipInfo == null
                      ? Text(
                          appLocalizations.timeout,
                          style: context.textTheme.bodyMedium
                              ?.copyWith(color: Colors.red)
                              .adjustSize(1),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Container(
                          padding: const EdgeInsets.all(2),
                          child: const AspectRatio(
                            aspectRatio: 1,
                            child: CommonCircleLoading(),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
