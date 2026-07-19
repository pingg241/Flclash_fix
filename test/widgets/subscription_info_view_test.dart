import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/widgets/subscription_info_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subscription progress clamps malformed counters', () {
    expect(
      subscriptionProgress(
        const SubscriptionInfo(upload: -1, download: 5, total: 10),
      ),
      0.5,
    );
    expect(
      subscriptionProgress(
        const SubscriptionInfo(upload: 8, download: 8, total: 10),
      ),
      1,
    );
    expect(
      subscriptionProgress(
        const SubscriptionInfo(upload: 1, download: 1, total: -1),
      ),
      0,
    );
  });

  test('subscription expiry rejects values outside DateTime range', () {
    expect(subscriptionExpiryDate(null), isNull);
    expect(subscriptionExpiryDate(-1), isNull);
    expect(subscriptionExpiryDate(999999999999999999), isNull);
    expect(subscriptionExpiryDate(1), isNotNull);
  });
}
