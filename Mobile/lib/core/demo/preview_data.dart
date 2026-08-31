import '../../features/collaboration/domain/collaboration_models.dart';

abstract final class PreviewData {
  static const demoDeviceId = '00000000-0000-0000-0000-000000000001';

  static final demoDeviceAuthorizations = <ImDeviceAuthorization>[
    ImDeviceAuthorization(
      deviceId: demoDeviceId,
      deviceName: 'Android 模拟器',
      platform: 'android',
      isAuthorized: true,
      authorizedAt: DateTime(2026, 8, 31, 8, 50),
      lastSeenAt: DateTime(2026, 8, 31, 9),
      revokedAt: null,
    ),
    ImDeviceAuthorization(
      deviceId: '00000000-0000-0000-0000-000000000003',
      deviceName: 'Windows 桌面终端',
      platform: 'windows',
      isAuthorized: true,
      authorizedAt: DateTime(2026, 8, 24, 19),
      lastSeenAt: DateTime(2026, 8, 31, 8, 45),
      revokedAt: null,
    ),
  ];

  static ImPushDevice? demoPushDevice = ImPushDevice(
    deviceId: demoDeviceId,
    platform: 'android',
    provider: 'fcm',
    privacyMode: 'summary',
    isEnabled: true,
    lastPushEventSequence: 18,
    updatedAt: DateTime(2026, 8, 31, 9),
  );

  static void resetDemoDeviceSettings() {
    demoDeviceAuthorizations
      ..clear()
      ..addAll([
        ImDeviceAuthorization(
          deviceId: demoDeviceId,
          deviceName: 'Android 模拟器',
          platform: 'android',
          isAuthorized: true,
          authorizedAt: DateTime(2026, 8, 31, 8, 50),
          lastSeenAt: DateTime(2026, 8, 31, 9),
          revokedAt: null,
        ),
        ImDeviceAuthorization(
          deviceId: '00000000-0000-0000-0000-000000000003',
          deviceName: 'Windows 桌面终端',
          platform: 'windows',
          isAuthorized: true,
          authorizedAt: DateTime(2026, 8, 24, 19),
          lastSeenAt: DateTime(2026, 8, 31, 8, 45),
          revokedAt: null,
        ),
      ]);
    demoPushDevice = ImPushDevice(
      deviceId: demoDeviceId,
      platform: 'android',
      provider: 'fcm',
      privacyMode: 'summary',
      isEnabled: true,
      lastPushEventSequence: 18,
      updatedAt: DateTime(2026, 8, 31, 9),
    );
  }

  static final demoFriendRemarks = <String, String>{};

  static OaWorkflowPreview workflowPreview(OaApprovalTemplate template) =>
      OaWorkflowPreview(
        templateId: template.id,
        templateName: template.name,
        workflowKey: template.workflowKey,
        templateVersion: template.version,
        requesterDepartmentName: '上海运营部',
        nodes: const [
          OaWorkflowPreviewNode(
            stage: 1,
            nodeId: 'demo-department-owner',
            nodeName: '部门负责人审批',
            nodeType: 'approval',
            actors: [
              OaWorkflowPreviewActor(
                memberId: '1',
                displayName: '冯逸',
                userName: 'term.sz02',
                departmentName: '深圳运营部',
              ),
              OaWorkflowPreviewActor(
                memberId: '4',
                displayName: '江敏',
                userName: 'term.sz04',
                departmentName: '深圳运营部',
              ),
            ],
            isResolved: true,
            completionMode: 'all',
          ),
          OaWorkflowPreviewNode(
            stage: 2,
            nodeId: 'demo-hr-review',
            nodeName: '人事复核',
            nodeType: 'approval',
            actors: [
              OaWorkflowPreviewActor(
                memberId: '2',
                displayName: '叶青',
                userName: 'term.sh03',
                departmentName: '人事部',
              ),
              OaWorkflowPreviewActor(
                memberId: '5',
                displayName: '周宁',
                userName: 'term.sh05',
                departmentName: '人事部',
              ),
            ],
            isResolved: true,
            completionMode: 'any',
          ),
        ],
        isResolved: true,
      );

  static final oaBootstrap = OaBootstrap(
    currentMemberId: 'me',
    displayName: '林晨',
    todos: [
      OaTodo(
        id: '1',
        title: '终端绑定申请',
        description: '深圳运营站终端绑定',
        status: 'pending',
        priority: 'urgent',
        dueAt: DateTime(2026, 8, 13, 9, 18),
        createdById: '1',
        conversationId: 'tang',
      ),
      OaTodo(
        id: '2',
        title: '数据导出申请',
        description: '运营数据看板',
        status: 'pending',
        priority: 'high',
        dueAt: DateTime(2026, 8, 13, 9, 30),
        createdById: '2',
      ),
      OaTodo(
        id: '3',
        title: '审计报告确认',
        description: '本月审计报告',
        status: 'pending',
        priority: 'normal',
        dueAt: DateTime(2026, 8, 13, 12),
        createdById: '3',
      ),
    ],
    announcements: const [
      OaAnnouncement(
        id: '1',
        title: '安全提示',
        content: '请及时完成本周终端安全检查',
        conversationId: 'ops',
      ),
    ],
    templates: const [
      OaApprovalTemplate(
        id: '1',
        name: '请假申请',
        category: '考勤',
        iconKey: 'leave',
        workflowKey: 'attendance.leave',
        version: 1,
        formSchemaJson: '{"fields":[{"id":"leaveType","label":"请假类型","type":"select","required":true,"options":["年假","事假","病假"]},{"id":"startAt","label":"开始时间","type":"datetime","required":true},{"id":"endAt","label":"结束时间","type":"datetime","required":true},{"id":"reason","label":"请假事由","type":"textarea","required":true}]}',
      ),
      OaApprovalTemplate(
        id: '2',
        name: '报销申请',
        category: '费用',
        iconKey: 'expense',
        workflowKey: 'expense.reimbursement',
        version: 1,
        formSchemaJson: '{"fields":[{"id":"amount","label":"报销金额","type":"amount","required":true},{"id":"reason","label":"费用说明","type":"textarea","required":true}]}',
      ),
      OaApprovalTemplate(
        id: '3',
        name: '分级请款审批',
        category: '财务',
        iconKey: 'payment',
        workflowKey: 'finance.tiered-payment',
        version: 4,
        formSchemaJson: '{"fields":[{"id":"amount","label":"请款金额","type":"amount","required":true},{"id":"reason","label":"请款事由","type":"textarea","required":true},{"id":"proof","label":"附件","type":"attachment"}]}',
      ),
    ],
    approvalRequests: [
      OaApprovalRequest(
        id: '1',
        requesterId: 'employee-1',
        title: '林晨的请假申请',
        formDataJson: '{"leaveType":"年假","startAt":"2026-08-14 09:00","endAt":"2026-08-14 18:00","duration":"1 天","reason":"办理个人事务，工作已交接给顾宁。","proof":[{"id":"attachment-1","fileName":"工作交接清单.pdf","contentType":"application/pdf"}]}',
        formSchemaSnapshotJson: '{"fields":[{"id":"leaveType","label":"请假类型"},{"id":"startAt","label":"开始时间"},{"id":"endAt","label":"结束时间"},{"id":"duration","label":"请假时长"},{"id":"reason","label":"请假事由"},{"id":"proof","label":"证明附件","type":"attachment"}]}',
        status: 'submitted',
        createdAt: DateTime(2026, 8, 13, 9, 18),
        updatedAt: DateTime(2026, 8, 13, 9, 26),
        requesterName: '林晨',
        requesterDepartmentName: '深圳运营部',
        templateName: '请假审批',
        templateCategory: '考勤',
        conversationId: 'tang',
        allowedActions: const ['approve', 'reject', 'transfer'],
        tasks: [
          OaApprovalTask(
            id: 'task-1',
            nodeName: '直属负责人审批',
            assigneeId: '1',
            assigneeName: '冯逸',
            status: 'approved',
            version: 2,
            decision: 'approved',
            comment: '工作已安排，同意。',
            canOperate: false,
            createdAt: DateTime(2026, 8, 13, 9, 18),
            completedAt: DateTime(2026, 8, 13, 9, 26),
          ),
          OaApprovalTask(
            id: 'task-2',
            nodeName: '部门负责人审批',
            assigneeId: 'me',
            assigneeName: '当前用户',
            status: 'pending',
            version: 1,
            decision: '',
            comment: '',
            canOperate: true,
            createdAt: DateTime(2026, 8, 13, 9, 26),
            completedAt: null,
            dueAt: DateTime(2026, 8, 14, 18),
            timeoutAction: 'remind',
          ),
          OaApprovalTask(
            id: 'task-3',
            nodeName: '财务复核',
            assigneeId: 'me',
            assigneeName: '当前用户',
            status: 'waiting',
            version: 1,
            decision: '',
            comment: '',
            canOperate: false,
            createdAt: DateTime(2026, 8, 13, 9, 26),
            completedAt: null,
            dueAt: DateTime(2026, 8, 15, 18),
            timeoutAction: 'remind',
          ),
        ],
        actions: [
          OaApprovalAction(
            actorName: '林晨',
            action: 'submitted',
            comment: '提交申请',
            occurredAt: DateTime(2026, 8, 13, 9, 18),
          ),
          OaApprovalAction(
            actorName: '顾宁',
            action: 'approved',
            comment: '工作已安排，同意。',
            occurredAt: DateTime(2026, 8, 13, 9, 26),
          ),
        ],
        attachments: const [
          OaApprovalAttachment(
            id: 'attachment-1',
            fileName: '工作交接清单.pdf',
            contentType: 'application/pdf',
            size: 292864,
            sha256: '',
            isPreviewableImage: false,
          ),
        ],
        ccs: [
          OaApprovalCc(
            id: 'cc-1',
            memberId: 'employee-2',
            memberName: '冯逸',
            isRead: true,
            createdAt: DateTime(2026, 8, 13, 9, 26),
            readAt: DateTime(2026, 8, 13, 10, 2),
          ),
          OaApprovalCc(
            id: 'cc-2',
            memberId: 'employee-3',
            memberName: '江敏',
            isRead: false,
            createdAt: DateTime(2026, 8, 13, 9, 26),
            readAt: null,
          ),
        ],
      ),
      OaApprovalRequest(
        id: '20260824-withdrawn-payment',
        requesterId: 'me',
        title: '分级请款审批',
        formDataJson: '{"amount":4999,"reason":"测试环境请款","proof":[{"id":"payment-proof","fileName":"请款凭证.pdf","contentType":"application/pdf"}]}',
        formSchemaSnapshotJson: '{"fields":[{"id":"amount","label":"请款金额","type":"amount"},{"id":"reason","label":"请款事由","type":"textarea"},{"id":"proof","label":"附件","type":"attachment"}]}',
        status: 'withdrawn',
        createdAt: DateTime(2026, 8, 24, 13, 46),
        updatedAt: DateTime(2026, 8, 24, 13, 54),
        requesterName: '林晨',
        requesterDepartmentName: '上海运营部',
        templateName: '分级请款审批',
        templateCategory: '财务',
        applicationKey: 'finance.tiered-payment',
        allowedActions: const [],
        tasks: const [],
        actions: [
          OaApprovalAction(
            actorName: '林晨',
            action: 'withdrawn',
            comment: '申请人已撤回',
            occurredAt: DateTime(2026, 8, 24, 13, 54),
          ),
        ],
        attachments: const [
          OaApprovalAttachment(
            id: 'payment-proof',
            fileName: '请款凭证.pdf',
            contentType: 'application/pdf',
            size: 184320,
            sha256: '',
            isPreviewableImage: false,
          ),
        ],
      ),
    ],
    notifications: [
      OaNotification(
        id: 'notification-1',
        requestId: '1',
        category: 'approval',
        type: 'approval.task.created',
        title: '请假审批待处理',
        body: '林晨提交的请假申请等待你处理',
        importance: 'high',
        action: 'review',
        isRead: false,
        readAt: null,
        createdAt: DateTime(2026, 8, 13, 9, 26),
      ),
    ],
  );

  static const oaCatalog = OaApplicationCatalog(
    catalogVersion: 'demo-1',
    items: [
      OaApplicationCatalogItem(
        applicationKey: 'attendance.leave',
        name: '请假申请',
        category: '考勤',
        iconKey: 'leave',
        iconDataUrl: null,
        displayOrder: 10,
        configurationKind: 'approval',
        configurationId: 'configuration-1',
        approvalTemplateId: '1',
        allowOfflineDraft: true,
        availabilitySource: 'department',
        sourceDepartmentId: 'department-1',
      ),
      OaApplicationCatalogItem(
        applicationKey: 'expense.reimbursement',
        name: '报销申请',
        category: '费用',
        iconKey: 'expense',
        iconDataUrl: null,
        displayOrder: 20,
        configurationKind: 'approval',
        configurationId: 'configuration-2',
        approvalTemplateId: '2',
        allowOfflineDraft: true,
        availabilitySource: 'department',
        sourceDepartmentId: 'department-1',
      ),
    ],
  );

  static final imBootstrap = ImBootstrap(
    currentMember: const ImMember(
      id: 'me',
      username: 'term.sh01',
      displayName: '林晨',
      isOnline: true,
      departmentId: 'department-shanghai',
      departmentName: '上海运营部',
      groupRole: 'owner',
    ),
    conversations: [
      ImConversation(
        id: 'ops',
        type: 'group',
        title: '华南运营协作',
        preview: '6 月运营数据看板已更新',
        updatedAt: DateTime(2026, 8, 13, 9, 42),
        unreadCount: 2,
        lastMessageSequence: 42,
      ),
      ImConversation(
        id: 'data',
        type: 'group',
        title: '数据对接项目组',
        preview: '接口联调已完成',
        updatedAt: DateTime(2026, 8, 13, 9, 35),
        unreadCount: 1,
        lastMessageSequence: 35,
      ),
      ImConversation(
        id: 'tang',
        type: 'direct',
        title: '唐泽',
        preview: '请确认接口文档',
        updatedAt: DateTime(2026, 8, 13, 9, 41),
        unreadCount: 0,
        lastMessageSequence: 41,
      ),
    ],
    contacts: [
      ImMember(
        id: '1',
        username: 'term.sz02',
        displayName: '冯逸',
        isOnline: true,
        departmentId: 'department-shenzhen',
        departmentName: '深圳运营部',
        isFriend: true,
        canStartDirect: true,
      ),
      ImMember(
        id: '2',
        username: 'term.hk01',
        displayName: '叶青',
        isOnline: false,
        lastSeenAt: DateTime(2026, 8, 13, 9, 22),
        departmentId: 'department-east-data',
        departmentName: '华东数据部',
        canStartDirect: true,
      ),
      ImMember(
        id: '3',
        username: 'term.gz01',
        displayName: '唐泽',
        isOnline: true,
        departmentId: 'department-shanghai',
        departmentName: '上海运营部',
        isFriend: true,
        canStartDirect: true,
      ),
    ],
    permissions: const ImPermissionSnapshot(
      createGroup: true,
      invite: true,
      batchSend: true,
    ),
  );

  static const imDepartments = <ImDepartment>[
    ImDepartment(
      id: 'department-hq',
      name: '集团总部',
      code: 'HQ',
      parentId: '',
      sortOrder: 0,
    ),
    ImDepartment(
      id: 'department-shanghai',
      name: '上海运营部',
      code: 'SH',
      parentId: 'department-hq',
      sortOrder: 10,
    ),
    ImDepartment(
      id: 'department-shenzhen',
      name: '深圳运营部',
      code: 'SZ',
      parentId: 'department-hq',
      sortOrder: 20,
    ),
    ImDepartment(
      id: 'department-east-data',
      name: '华东数据部',
      code: 'EAST-DATA',
      parentId: 'department-hq',
      sortOrder: 30,
    ),
  ];

  static final imFavorites = <ImFavoriteMessage>[
    ImFavoriteMessage(
      messageId: 'favorite-message-1',
      note: '运营周报',
      createdAt: DateTime(2026, 8, 13, 9, 45),
      message: ImMessage(
        id: 'favorite-message-1',
        conversationId: 'ops',
        sequence: 1,
        senderId: '1',
        content: '6 月运营数据看板已更新，请大家查收。',
        kind: 'text',
        createdAt: DateTime(2026, 8, 13, 9, 41),
      ),
    ),
    ImFavoriteMessage(
      messageId: 'favorite-message-2',
      note: '',
      createdAt: DateTime(2026, 8, 13, 9, 46),
      message: ImMessage(
        id: 'favorite-message-2',
        conversationId: 'tang',
        sequence: 3,
        senderId: '3',
        content: '',
        kind: 'file',
        attachmentName: '接口联调清单.pdf',
        attachmentSize: 286720,
        createdAt: DateTime(2026, 8, 13, 9, 42),
      ),
    ),
  ];

  static final imAssistantTasks = <ImAssistantTask>[
    ImAssistantTask(
      id: 'assistant-task-1',
      messageKind: 'text',
      content: '请各位在今天 18:00 前提交本周工作小结。',
      attachmentJson: '',
      status: 'completed',
      receiverCount: 3,
      successCount: 3,
      failureCount: 0,
      createdAt: DateTime(2026, 8, 13, 9, 10),
      updatedAt: DateTime(2026, 8, 13, 9, 11),
    ),
  ];

  static ImGroupManagementCapabilities groupManagementCapabilities(
    String conversationId,
  ) => conversationId == 'ops' || conversationId == 'data'
      ? const ImGroupManagementCapabilities(
          canReviewJoinRequests: true,
          canMuteMembers: true,
          canManageAdministrators: true,
          canTransferOwnership: true,
          canDeleteAllHistory: true,
          canDissolveGroup: true,
        )
      : const ImGroupManagementCapabilities();

  static final demoGroupMutedMembers = <ImMutedGroupMember>[
    ImMutedGroupMember(
      member: imBootstrap.contacts[1],
      mutedUntil: DateTime(2026, 8, 31, 23),
    ),
  ];

  static final demoGroupJoinRequests = <ImGroupJoinRequest>[
    ImGroupJoinRequest(
      id: 'join-request-1',
      applicantMemberId: '2',
      applicantName: '叶青',
      status: 'pending',
      createdAt: DateTime(2026, 8, 13, 9, 50),
    ),
  ];

  static ImGroupManagementPage<ImMutedGroupMember> groupMutedMembers(
    String conversationId,
  ) {
    final items = conversationId == 'ops'
        ? List<ImMutedGroupMember>.of(demoGroupMutedMembers)
        : <ImMutedGroupMember>[];
    return ImGroupManagementPage(
      items: items,
      page: 1,
      pageSize: 50,
      total: items.length,
    );
  }

  static ImGroupManagementPage<ImMember> groupManagersPage(
    String conversationId,
  ) {
    final items = conversationId == 'ops' || conversationId == 'data'
        ? <ImMember>[
            imBootstrap.currentMember,
            const ImMember(
              id: '1',
              username: 'term.sz02',
              displayName: '冯逸',
              isOnline: true,
              departmentName: '深圳运营部',
              groupRole: 'manager',
            ),
          ]
        : <ImMember>[];
    return ImGroupManagementPage(
      items: items,
      page: 1,
      pageSize: 50,
      total: items.length,
    );
  }

  static ImGroupManagementPage<ImGroupJoinRequest> groupJoinRequests(
    String conversationId,
  ) {
    final items = conversationId == 'ops'
        ? List<ImGroupJoinRequest>.of(demoGroupJoinRequests)
        : <ImGroupJoinRequest>[];
    return ImGroupManagementPage(
      items: items,
      page: 1,
      pageSize: 50,
      total: items.length,
    );
  }

  static ImGroupManagementPage<ImGroupNotice> groupNotices(
    String conversationId,
  ) {
    final items = conversationId == 'ops'
        ? <ImGroupNotice>[
            ImGroupNotice(
              id: 'group-notice-1',
              type: 'group.notice.updated',
              actorName: '林晨',
              createdAt: DateTime(2026, 8, 13, 9, 30),
            ),
            ImGroupNotice(
              id: 'group-notice-2',
              type: 'group.member.muted',
              actorName: '冯逸',
              createdAt: DateTime(2026, 8, 13, 9, 38),
            ),
          ]
        : <ImGroupNotice>[];
    return ImGroupManagementPage(
      items: items,
      page: 1,
      pageSize: 50,
      total: items.length,
    );
  }

  static List<ImMember> groupManagers(String conversationId) =>
      conversationId == 'ops' || conversationId == 'data'
      ? [imBootstrap.currentMember]
      : const <ImMember>[];

  static final messages = <ImMessage>[
    ImMessage(
      id: '1',
      sequence: 1,
      senderId: '1',
      content: '6 月运营数据看板已更新，请大家查收。',
      kind: 'text',
      createdAt: DateTime(2026, 8, 13, 9, 41),
    ),
    ImMessage(
      id: '2',
      sequence: 2,
      senderId: 'me',
      content: '收到，数据整体稳定。',
      kind: 'text',
      createdAt: DateTime(2026, 8, 13, 9, 42),
    ),
  ];

  static List<ImMessage> conversationMessages(String conversationId) {
    if (conversationId == 'tang' || conversationId.startsWith('demo-direct-')) {
      final memberId = conversationId == 'tang'
          ? '3'
          : conversationId.substring('demo-direct-'.length);
      final peer = imBootstrap.contacts
          .where((item) => item.id == memberId)
          .firstOrNull;
      final incoming = switch (memberId) {
        '1' => '周报数据已更新，请帮忙确认。',
        '2' => '风控清单已更新，请查收。',
        _ => '接口文档已经更新，请帮忙确认。',
      };
      return [
        ImMessage(
          id: 'direct-1',
          sequence: 1,
          senderId: peer?.id ?? memberId,
          content: incoming,
          kind: 'text',
          createdAt: DateTime(2026, 8, 13, 9, 40),
        ),
        ImMessage(
          id: 'direct-2',
          sequence: 2,
          senderId: 'me',
          content: '收到，我现在查看。',
          kind: 'text',
          createdAt: DateTime(2026, 8, 13, 9, 41),
        ),
        ImMessage(
          id: 'direct-file-1',
          sequence: 3,
          senderId: peer?.id ?? memberId,
          content: '附件：接口联调清单.pdf',
          kind: 'file',
          attachmentName: '接口联调清单.pdf',
          attachmentSize: 286720,
          createdAt: DateTime(2026, 8, 13, 9, 42),
        ),
        ImMessage(
          id: 'direct-image-1',
          sequence: 4,
          senderId: peer?.id ?? memberId,
          content: '',
          kind: 'image',
          images: const [
            ImMessageImage(
              id: 'demo-image-1',
              fileName: '接口流程图.png',
              size: 184320,
              contentType: 'image/png',
            ),
          ],
          createdAt: DateTime(2026, 8, 13, 9, 43),
        ),
        ImMessage(
          id: 'direct-video-1',
          sequence: 5,
          senderId: 'me',
          content: '操作录屏',
          kind: 'video',
          attachments: const [
            ImMessageAttachment(
              id: 'demo-video-1',
              type: 'video',
              fileName: '终端绑定演示.mp4',
              contentType: 'video/mp4',
              size: 1572864,
              sha256: '',
              durationSeconds: 18,
            ),
          ],
          createdAt: DateTime(2026, 8, 13, 9, 44),
        ),
        ImMessage(
          id: 'direct-link-1',
          sequence: 6,
          senderId: peer?.id ?? memberId,
          content: '接口说明：https://docs.example.com/im/mobile',
          kind: 'text',
          createdAt: DateTime(2026, 8, 13, 9, 45),
        ),
      ];
    }
    return messages;
  }

  static List<ImMember> conversationMembers(String conversationId) {
    if (conversationId == 'ops') {
      return [
        imBootstrap.currentMember,
        ...imBootstrap.contacts.where(
          (item) => item.id == '1' || item.id == '3',
        ),
      ];
    }
    if (conversationId == 'data') {
      return [imBootstrap.currentMember, ...imBootstrap.contacts];
    }
    final directMemberId = conversationId == 'tang'
        ? '3'
        : conversationId.startsWith('demo-direct-')
        ? conversationId.substring('demo-direct-'.length)
        : '';
    return [
      imBootstrap.currentMember,
      ...imBootstrap.contacts.where((item) => item.id == directMemberId),
    ];
  }

  static ImGroupProfile? groupProfile(String conversationId) {
    if (conversationId == 'ops') {
      return const ImGroupProfile(
        conversationId: 'ops',
        title: '华南运营协作',
        notice: '周报请在每周一 10:00 前提交',
        introduction: '华南运营跨部门协作群',
        groupNo: 'OPS-SOUTH',
        maxMemberCount: 500,
      );
    }
    if (conversationId == 'data') {
      return const ImGroupProfile(
        conversationId: 'data',
        title: '数据对接项目组',
        notice: '',
        introduction: '数据平台联调与发布协作',
        groupNo: 'DATA-PROJECT',
        maxMemberCount: 200,
      );
    }
    return null;
  }
}
