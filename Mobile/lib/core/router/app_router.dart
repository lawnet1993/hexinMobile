import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/attendance/presentation/attendance_page.dart';
import '../../features/contacts/presentation/contacts_page.dart';
import '../../features/messages/presentation/chat_page.dart';
import '../../features/messages/presentation/messages_page.dart';
import '../../features/messages/presentation/message_assistant_page.dart';
import '../../features/messages/presentation/message_favorites_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/profile/presentation/network_security_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/profile/presentation/profile_edit_page.dart';
import '../../features/profile/presentation/settings_pages.dart';
import '../../features/shell/presentation/mobile_shell.dart';
import '../../features/todos/presentation/approval_detail_page.dart';
import '../../features/todos/presentation/approval_request_page.dart';
import '../../features/todos/presentation/todos_page.dart';
import '../../features/workbench/presentation/all_apps_page.dart';
import '../../features/workbench/presentation/workbench_page.dart';
import '../../features/workbench/presentation/schedule_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier();
  ref.listen(authControllerProvider, (_, _) => refresh.notify());
  ref.onDispose(refresh.dispose);
  final router = GoRouter(
    initialLocation: '/workbench',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      if (auth.isLoading) return null;
      final signedIn = auth.value != null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn && !atLogin) return '/login';
      if (signedIn && atLogin) return '/workbench';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MobileShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/workbench',
                builder: (context, state) => const WorkbenchPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/messages',
                builder: (context, state) => const MessagesPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/todos',
                builder: (context, state) => const TodosPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/contacts',
                builder: (context, state) => ContactsPage(
                  initialMode: state.uri.queryParameters['mode'] == 'requests'
                      ? 2
                      : 0,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/apps', builder: (context, state) => const AllAppsPage()),
      GoRoute(
        path: '/sites',
        builder: (context, state) => const ManagedSitesPage(),
      ),
      GoRoute(
        path: '/schedule',
        builder: (context, state) => const SchedulePage(),
      ),
      GoRoute(
        path: '/punch',
        builder: (context, state) => AttendancePage(
          openInspectionOnStart:
              state.uri.queryParameters['inspection'] == 'active',
        ),
      ),
      GoRoute(
        path: '/attendance',
        builder: (context, state) => AttendancePage(
          correctionMode: true,
          initialExceptionId: state.uri.queryParameters['exceptionId'],
        ),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => NotificationsPage(
          initialSection: switch (state.uri.queryParameters['tab']) {
            'announcements' => 1,
            'friends' => 2,
            _ => 0,
          },
        ),
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) => ChatPage(
          conversationId: state.pathParameters['id']!,
          initialResourceTab: switch (state.uri.queryParameters['tab']) {
            'files' => 1,
            'tasks' => 2,
            _ => 0,
          },
        ),
      ),
      GoRoute(
        path: '/message-assistant',
        builder: (context, state) => const MessageAssistantPage(),
      ),
      GoRoute(
        path: '/message-favorites',
        builder: (context, state) => const MessageFavoritesPage(),
      ),
      GoRoute(
        path: '/approval/:id',
        builder: (context, state) =>
            ApprovalDetailPage(approvalId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/apply/:applicationKey',
        builder: (context, state) => ApprovalRequestPage(
          applicationKey: state.pathParameters['applicationKey']!,
          templateId: state.uri.queryParameters['templateId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const ProfileEditPage(),
      ),
      GoRoute(
        path: '/network-security',
        builder: (context, state) => const NetworkSecurityPage(),
      ),
      GoRoute(
        path: '/account-security',
        builder: (context, state) => const AccountSecurityPage(),
      ),
      GoRoute(
        path: '/notification-settings',
        builder: (context, state) => const NotificationSettingsPage(),
      ),
      GoRoute(
        path: '/login-devices',
        builder: (context, state) => const LoginDevicesPage(),
      ),
      GoRoute(
        path: '/appearance-language',
        builder: (context, state) => const AppearanceLanguagePage(),
      ),
      GoRoute(
        path: '/help-feedback',
        builder: (context, state) => const HelpFeedbackPage(),
      ),
      GoRoute(path: '/about', builder: (context, state) => const AboutPage()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

final class _RouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
