import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/material.dart';

@visibleForTesting
double subscriptionProgress(SubscriptionInfo subscriptionInfo) {
  final total = subscriptionInfo.total;
  if (total <= 0) return 0;
  final upload = subscriptionInfo.upload < 0 ? 0 : subscriptionInfo.upload;
  final download = subscriptionInfo.download < 0
      ? 0
      : subscriptionInfo.download;
  final used = upload + download;
  if (used <= 0) return 0;
  if (used >= total) return 1;
  return (used * 1000000 ~/ total) / 1000000;
}

@visibleForTesting
DateTime? subscriptionExpiryDate(int? seconds) {
  if (seconds == null || seconds <= 0) return null;
  const maxEpochMilliseconds = 8640000000000000;
  if (seconds > maxEpochMilliseconds ~/ 1000) return null;
  try {
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  } on ArgumentError {
    return null;
  }
}

class SubscriptionInfoView extends StatelessWidget {
  final SubscriptionInfo? subscriptionInfo;

  const SubscriptionInfoView({super.key, this.subscriptionInfo});

  @override
  Widget build(BuildContext context) {
    if (subscriptionInfo == null) {
      return Container();
    }
    if (subscriptionInfo!.total <= 0) {
      return Container();
    }
    final upload = subscriptionInfo!.upload < 0 ? 0 : subscriptionInfo!.upload;
    final download = subscriptionInfo!.download < 0
        ? 0
        : subscriptionInfo!.download;
    final use = upload + download;
    final total = subscriptionInfo!.total;
    final progress = subscriptionProgress(subscriptionInfo!);

    final useShow = use.traffic.show;
    final totalShow = total.traffic.show;
    final expiry = subscriptionExpiryDate(subscriptionInfo!.expire);
    final expireShow = expiry != null
        ? expiry.show
        : context.appLocalizations.infiniteTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          minHeight: 6,
          value: progress,
          backgroundColor: context.colorScheme.primary.opacity15,
        ),
        const SizedBox(height: 8),
        Text(
          '$useShow / $totalShow · $expireShow',
          style: context.textTheme.labelMedium?.toLight,
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
