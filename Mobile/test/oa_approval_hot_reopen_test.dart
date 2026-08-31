import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';

void main() {
  test(
    'approval detail reuses loader on hot reopen and refreshes on invalidation',
    () async {
      final request = PreviewData.oaBootstrap.approvalRequests.first;
      var loads = 0;
      final container = ProviderContainer.test(
        overrides: [
          oaApprovalRequestLoaderProvider.overrideWithValue((id) async {
            loads += 1;
            return request;
          }),
        ],
      );
      final provider = oaApprovalRequestProvider(request.id);

      final first = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      expect(await container.read(provider.future), same(request));
      first.close();
      await container.pump();

      final reopened = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      expect(await container.read(provider.future), same(request));
      expect(loads, 1);

      container.invalidate(provider);
      await container.pump();
      expect(await container.read(provider.future), same(request));
      expect(loads, 2);

      reopened.close();
      container.dispose();
    },
  );
}
