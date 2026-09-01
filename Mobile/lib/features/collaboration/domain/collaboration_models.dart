final class OaTodo {
  const OaTodo({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.dueAt,
    required this.createdById,
    this.conversationId = '',
    this.createdAt,
    this.updatedAt,
  });

  factory OaTodo.fromJson(Map<String, Object?> json) => OaTodo(
    id: _text(json, 'id'),
    title: _text(json, 'title'),
    description: _text(json, 'description'),
    status: _text(json, 'status'),
    priority: _text(json, 'priority'),
    dueAt: _date(json['dueAt']),
    createdById: _text(json, 'createdById'),
    conversationId: _text(json, 'conversationId'),
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
  );

  final String id;
  final String title;
  final String description;
  final String status;
  final String priority;
  final DateTime? dueAt;
  final String createdById;
  final String conversationId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

bool isTerminalTodoStatus(String status) => const {
  'approved',
  'rejected',
  'withdrawn',
  'terminated',
  'completed',
  'canceled',
  'cancelled',
}.contains(status.trim().toLowerCase());

final class OaAnnouncement {
  const OaAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    this.conversationId = '',
  });

  factory OaAnnouncement.fromJson(Map<String, Object?> json) => OaAnnouncement(
    id: _text(json, 'id'),
    title: _text(json, 'title'),
    content: _text(json, 'content'),
    conversationId: _text(json, 'conversationId'),
  );

  final String id;
  final String title;
  final String content;
  final String conversationId;
}

final class OaApplicationCatalogItem {
  const OaApplicationCatalogItem({
    required this.applicationKey,
    required this.name,
    required this.category,
    required this.iconKey,
    required this.iconDataUrl,
    required this.displayOrder,
    required this.configurationKind,
    required this.configurationId,
    required this.approvalTemplateId,
    required this.allowOfflineDraft,
    required this.availabilitySource,
    required this.sourceDepartmentId,
  });

  factory OaApplicationCatalogItem.fromJson(Map<String, Object?> json) =>
      OaApplicationCatalogItem(
        applicationKey: _text(json, 'applicationKey'),
        name: _text(json, 'name'),
        category: _text(json, 'category'),
        iconKey: _text(json, 'iconKey'),
        iconDataUrl: _text(json, 'iconDataUrl').isEmpty
            ? null
            : _text(json, 'iconDataUrl'),
        displayOrder: _integer(_value(json, 'displayOrder')),
        configurationKind: _text(json, 'configurationKind'),
        configurationId: _value(json, 'configurationId')?.toString(),
        approvalTemplateId: _value(json, 'approvalTemplateId')?.toString(),
        allowOfflineDraft: _boolean(_value(json, 'allowOfflineDraft')),
        availabilitySource: _text(json, 'availabilitySource'),
        sourceDepartmentId: _value(json, 'sourceDepartmentId')?.toString(),
      );

  final String applicationKey;
  final String name;
  final String category;
  final String iconKey;
  final String? iconDataUrl;
  final int displayOrder;
  final String configurationKind;
  final String? configurationId;
  final String? approvalTemplateId;
  final bool allowOfflineDraft;
  final String availabilitySource;
  final String? sourceDepartmentId;
}

final class OaApplicationCatalog {
  const OaApplicationCatalog({
    required this.catalogVersion,
    required this.items,
  });

  factory OaApplicationCatalog.fromJson(Map<String, Object?> json) =>
      OaApplicationCatalog(
        catalogVersion: _text(json, 'catalogVersion'),
        items: _list(_value(json, 'items'), OaApplicationCatalogItem.fromJson),
      );

  final String catalogVersion;
  final List<OaApplicationCatalogItem> items;
}

final class OaApprovalTemplate {
  const OaApprovalTemplate({
    required this.id,
    required this.name,
    required this.category,
    this.iconKey = 'approval',
    this.workflowKey = '',
    this.version = 0,
    this.formSchemaJson = '{}',
  });

  factory OaApprovalTemplate.fromJson(Map<String, Object?> json) =>
      OaApprovalTemplate(
        id: _text(json, 'id'),
        name: _text(json, 'name'),
        category: _text(json, 'category'),
        iconKey: _text(json, 'iconKey').isEmpty
            ? 'approval'
            : _text(json, 'iconKey'),
        workflowKey: _text(json, 'workflowKey'),
        version: _integer(_value(json, 'version')),
        formSchemaJson: _text(json, 'formSchemaJson').isEmpty
            ? '{}'
            : _text(json, 'formSchemaJson'),
      );

  final String id;
  final String name;
  final String category;
  final String iconKey;
  final String workflowKey;
  final int version;
  final String formSchemaJson;
}

final class OaApprovalTask {
  const OaApprovalTask({
    required this.id,
    required this.nodeName,
    required this.assigneeId,
    required this.assigneeName,
    required this.status,
    required this.version,
    required this.decision,
    required this.comment,
    required this.canOperate,
    required this.createdAt,
    required this.completedAt,
    this.nodeId = '',
    this.stage = 0,
    this.completedById = '',
    this.completedByName = '',
    this.dueAt,
    this.timeoutAction = '',
    this.timeoutHandledAt,
    this.timeoutLastError = '',
  });

  factory OaApprovalTask.fromJson(Map<String, Object?> json) => OaApprovalTask(
    id: _text(json, 'id'),
    nodeId: _text(json, 'nodeId'),
    nodeName: _text(json, 'nodeName'),
    stage: _integer(_value(json, 'stage')),
    assigneeId: _text(json, 'assigneeId'),
    assigneeName: _text(json, 'assigneeName'),
    status: _text(json, 'status'),
    version: _integer(_value(json, 'version')),
    decision: _text(json, 'decision'),
    comment: _text(json, 'comment'),
    canOperate: _boolean(_value(json, 'canOperate')),
    completedById: _text(json, 'completedById'),
    completedByName: _text(json, 'completedByName'),
    dueAt: _date(_value(json, 'dueAt')),
    timeoutAction: _text(json, 'timeoutAction'),
    timeoutHandledAt: _date(_value(json, 'timeoutHandledAt')),
    timeoutLastError: _text(json, 'timeoutLastError'),
    createdAt: _date(_value(json, 'createdAt')),
    completedAt: _date(_value(json, 'completedAt')),
  );

  final String id;
  final String nodeId;
  final String nodeName;
  final int stage;
  final String assigneeId;
  final String assigneeName;
  final String status;
  final int version;
  final String decision;
  final String comment;
  final bool canOperate;
  final String completedById;
  final String completedByName;
  final DateTime? dueAt;
  final String timeoutAction;
  final DateTime? timeoutHandledAt;
  final String timeoutLastError;
  final DateTime? createdAt;
  final DateTime? completedAt;
}

final class OaApprovalAction {
  const OaApprovalAction({
    required this.actorName,
    required this.action,
    required this.comment,
    required this.occurredAt,
  });

  factory OaApprovalAction.fromJson(Map<String, Object?> json) =>
      OaApprovalAction(
        actorName: _text(json, 'actorName'),
        action: _text(json, 'action'),
        comment: _text(json, 'comment'),
        occurredAt: _date(_value(json, 'occurredAt')),
      );

  final String actorName;
  final String action;
  final String comment;
  final DateTime? occurredAt;
}

final class OaApprovalAttachment {
  const OaApprovalAttachment({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.size,
    required this.sha256,
    required this.isPreviewableImage,
  });

  factory OaApprovalAttachment.fromJson(Map<String, Object?> json) =>
      OaApprovalAttachment(
        id: _text(json, 'id'),
        fileName: _text(json, 'fileName'),
        contentType: _text(json, 'contentType'),
        size: _integer(_value(json, 'size')),
        sha256: _text(json, 'sha256'),
        isPreviewableImage: _boolean(_value(json, 'isPreviewableImage')),
      );

  final String id;
  final String fileName;
  final String contentType;
  final int size;
  final String sha256;
  final bool isPreviewableImage;

  Map<String, Object?> toJson() => {
    'id': id,
    'fileName': fileName,
    'contentType': contentType,
    'size': size,
    'sha256': sha256,
    'isPreviewableImage': isPreviewableImage,
  };
}

final class OaApprovalCc {
  const OaApprovalCc({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.isRead,
    required this.createdAt,
    required this.readAt,
  });

  factory OaApprovalCc.fromJson(Map<String, Object?> json) => OaApprovalCc(
    id: _text(json, 'id'),
    memberId: _text(json, 'memberId'),
    memberName: _text(json, 'memberName'),
    isRead: _boolean(_value(json, 'isRead')),
    createdAt: _date(_value(json, 'createdAt')),
    readAt: _date(_value(json, 'readAt')),
  );

  final String id;
  final String memberId;
  final String memberName;
  final bool isRead;
  final DateTime? createdAt;
  final DateTime? readAt;
}

final class OaWorkflowPreviewActor {
  const OaWorkflowPreviewActor({
    required this.memberId,
    required this.displayName,
    required this.userName,
    required this.departmentName,
  });

  factory OaWorkflowPreviewActor.fromJson(Map<String, Object?> json) =>
      OaWorkflowPreviewActor(
        memberId: _text(json, 'memberId'),
        displayName: _text(json, 'displayName'),
        userName: _text(json, 'userName'),
        departmentName: _text(json, 'departmentName'),
      );

  final String memberId;
  final String displayName;
  final String userName;
  final String departmentName;
}

final class OaWorkflowPreviewNode {
  const OaWorkflowPreviewNode({
    required this.stage,
    required this.nodeId,
    required this.nodeName,
    required this.nodeType,
    required this.actors,
    required this.isResolved,
    required this.completionMode,
  });

  factory OaWorkflowPreviewNode.fromJson(Map<String, Object?> json) =>
      OaWorkflowPreviewNode(
        stage: _integer(_value(json, 'stage')),
        nodeId: _text(json, 'nodeId'),
        nodeName: _text(json, 'nodeName'),
        nodeType: _text(json, 'nodeType'),
        actors: _list(_value(json, 'actors'), OaWorkflowPreviewActor.fromJson),
        isResolved: _boolean(_value(json, 'isResolved')),
        completionMode: _text(json, 'completionMode'),
      );

  final int stage;
  final String nodeId;
  final String nodeName;
  final String nodeType;
  final List<OaWorkflowPreviewActor> actors;
  final bool isResolved;
  final String completionMode;
}

final class OaWorkflowPreview {
  const OaWorkflowPreview({
    required this.templateId,
    required this.templateName,
    required this.workflowKey,
    required this.templateVersion,
    required this.requesterDepartmentName,
    required this.nodes,
    required this.isResolved,
  });

  factory OaWorkflowPreview.fromJson(Map<String, Object?> json) =>
      OaWorkflowPreview(
        templateId: _text(json, 'templateId'),
        templateName: _text(json, 'templateName'),
        workflowKey: _text(json, 'workflowKey'),
        templateVersion: _integer(_value(json, 'templateVersion')),
        requesterDepartmentName: _text(json, 'requesterDepartmentName'),
        nodes: _list(_value(json, 'nodes'), OaWorkflowPreviewNode.fromJson),
        isResolved: _boolean(_value(json, 'isResolved')),
      );

  final String templateId;
  final String templateName;
  final String workflowKey;
  final int templateVersion;
  final String requesterDepartmentName;
  final List<OaWorkflowPreviewNode> nodes;
  final bool isResolved;
}

final class OaApprovalRequestPage {
  const OaApprovalRequestPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  factory OaApprovalRequestPage.fromJson(Map<String, Object?> json) =>
      OaApprovalRequestPage(
        items: _list(_value(json, 'items'), OaApprovalRequest.fromJson),
        nextCursor: _value(json, 'nextCursor')?.toString(),
        hasMore: _boolean(_value(json, 'hasMore')),
      );

  final List<OaApprovalRequest> items;
  final String? nextCursor;
  final bool hasMore;
}

final class OaApprovalRequest {
  const OaApprovalRequest({
    required this.id,
    required this.requesterId,
    required this.title,
    required this.formDataJson,
    required this.formSchemaSnapshotJson,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.requesterName,
    required this.requesterDepartmentName,
    required this.templateName,
    required this.templateCategory,
    required this.allowedActions,
    required this.tasks,
    required this.actions,
    required this.attachments,
    this.applicationKey = '',
    this.conversationId = '',
    this.ccs = const [],
  });

  factory OaApprovalRequest.fromJson(Map<String, Object?> json) =>
      OaApprovalRequest(
        id: _text(json, 'id'),
        requesterId: _text(json, 'requesterId'),
        title: _text(json, 'title'),
        formDataJson: _text(json, 'formDataJson'),
        formSchemaSnapshotJson: _text(json, 'formSchemaSnapshotJson'),
        status: _text(json, 'status'),
        createdAt: _date(_value(json, 'createdAt')),
        updatedAt: _date(_value(json, 'updatedAt')),
        requesterName: _text(json, 'requesterName'),
        requesterDepartmentName: _text(json, 'requesterDepartmentName'),
        templateName: _text(json, 'templateName'),
        templateCategory: _text(json, 'templateCategory'),
        applicationKey: _text(json, 'applicationKey'),
        conversationId: _text(json, 'conversationId'),
        allowedActions: _strings(_value(json, 'allowedActions')),
        tasks: _list(_value(json, 'tasks'), OaApprovalTask.fromJson),
        actions: _list(_value(json, 'actions'), OaApprovalAction.fromJson),
        attachments: _list(
          _value(json, 'attachments'),
          OaApprovalAttachment.fromJson,
        ),
        ccs: _list(_value(json, 'ccs'), OaApprovalCc.fromJson),
      );

  final String id;
  final String requesterId;
  final String title;
  final String formDataJson;
  final String formSchemaSnapshotJson;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String requesterName;
  final String requesterDepartmentName;
  final String templateName;
  final String templateCategory;
  final String applicationKey;
  final String conversationId;
  final List<String> allowedActions;
  final List<OaApprovalTask> tasks;
  final List<OaApprovalAction> actions;
  final List<OaApprovalAttachment> attachments;
  final List<OaApprovalCc> ccs;

  OaApprovalTask? get operableTask {
    for (final task in tasks) {
      if (task.canOperate) return task;
    }
    return null;
  }
}

final class OaNotification {
  const OaNotification({
    required this.id,
    required this.requestId,
    required this.category,
    required this.type,
    required this.title,
    required this.body,
    required this.importance,
    required this.action,
    required this.isRead,
    required this.readAt,
    required this.createdAt,
    this.targetKind = '',
    this.targetId = '',
  });

  factory OaNotification.fromJson(Map<String, Object?> json) => OaNotification(
    id: _text(json, 'id'),
    requestId: _text(json, 'requestId'),
    category: _text(json, 'category'),
    type: _text(json, 'type'),
    title: _text(json, 'title'),
    body: _text(json, 'body'),
    importance: _text(json, 'importance'),
    action: _text(json, 'action'),
    isRead: _boolean(_value(json, 'isRead')),
    readAt: _date(_value(json, 'readAt')),
    createdAt: _date(_value(json, 'createdAt')),
    targetKind: _text(json, 'targetKind'),
    targetId: _text(json, 'targetId'),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'requestId': requestId,
    'category': category,
    'type': type,
    'title': title,
    'body': body,
    'importance': importance,
    'action': action,
    'isRead': isRead,
    'readAt': readAt?.toIso8601String(),
    'createdAt': createdAt?.toIso8601String(),
    'targetKind': targetKind,
    'targetId': targetId,
  };

  final String id;
  final String requestId;
  final String category;
  final String type;
  final String title;
  final String body;
  final String importance;
  final String action;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? createdAt;
  final String targetKind;
  final String targetId;
}

final class OaNotificationPage {
  const OaNotificationPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  factory OaNotificationPage.fromJson(Map<String, Object?> json) =>
      OaNotificationPage(
        items: _list(_value(json, 'items'), OaNotification.fromJson),
        nextCursor: _value(json, 'nextCursor')?.toString(),
        hasMore: _boolean(_value(json, 'hasMore')),
      );

  Map<String, Object?> toJson() => {
    'items': items.map((item) => item.toJson()).toList(),
    'nextCursor': nextCursor,
    'hasMore': hasMore,
  };

  final List<OaNotification> items;
  final String? nextCursor;
  final bool hasMore;
}

final class OaBootstrap {
  const OaBootstrap({
    required this.displayName,
    required this.todos,
    required this.announcements,
    required this.templates,
    this.currentMemberId = '',
    this.approvalRequests = const [],
    this.approvalRequestsNextCursor,
    this.approvalRequestsHasMore = false,
    this.notifications = const [],
  });

  factory OaBootstrap.fromJson(Map<String, Object?> json) {
    final member = _map(json['currentMember']);
    return OaBootstrap(
      currentMemberId: _text(member, 'id'),
      displayName: _text(member, 'displayName'),
      todos: _list(json['todos'], OaTodo.fromJson),
      announcements: _list(json['announcements'], OaAnnouncement.fromJson),
      templates: _list(json['approvalTemplates'], OaApprovalTemplate.fromJson),
      approvalRequests: _list(
        json['approvalRequests'],
        OaApprovalRequest.fromJson,
      ),
      approvalRequestsNextCursor: _value(
        json,
        'approvalRequestsNextCursor',
      )?.toString(),
      approvalRequestsHasMore: _boolean(
        _value(json, 'approvalRequestsHasMore'),
      ),
      notifications: _list(json['notifications'], OaNotification.fromJson),
    );
  }

  final String currentMemberId;
  final String displayName;
  final List<OaTodo> todos;
  final List<OaAnnouncement> announcements;
  final List<OaApprovalTemplate> templates;
  final List<OaApprovalRequest> approvalRequests;
  final String? approvalRequestsNextCursor;
  final bool approvalRequestsHasMore;
  final List<OaNotification> notifications;
}

final class OaAttendanceRecord {
  const OaAttendanceRecord({
    required this.id,
    required this.type,
    required this.occurredAt,
    required this.source,
    required this.periodIndex,
  });

  factory OaAttendanceRecord.fromJson(Map<String, Object?> json) =>
      OaAttendanceRecord(
        id: _text(json, 'id'),
        type: _text(json, 'type'),
        occurredAt: _date(_value(json, 'occurredAt')),
        source: _text(json, 'source'),
        periodIndex: _integer(_value(json, 'periodIndex')),
      );

  final String id;
  final String type;
  final DateTime? occurredAt;
  final String source;
  final int periodIndex;
}

final class OaAttendanceException {
  const OaAttendanceException({
    required this.id,
    required this.workDate,
    required this.type,
    required this.status,
    required this.resolutionApprovalRequestId,
  });

  factory OaAttendanceException.fromJson(Map<String, Object?> json) =>
      OaAttendanceException(
        id: _text(json, 'id'),
        workDate: _text(json, 'workDate'),
        type: _text(json, 'type'),
        status: _text(json, 'status'),
        resolutionApprovalRequestId: _value(
          json,
          'resolutionApprovalRequestId',
        )?.toString(),
      );

  final String id;
  final String workDate;
  final String type;
  final String status;
  final String? resolutionApprovalRequestId;
}

final class OaPersonalScheduleDay {
  const OaPersonalScheduleDay({
    required this.workDate,
    required this.isRestDay,
    required this.shiftName,
    required this.expectedCheckInAt,
    required this.expectedCheckOutAt,
    required this.status,
  });

  factory OaPersonalScheduleDay.fromJson(Map<String, Object?> json) {
    final result = _map(_value(json, 'result'));
    return OaPersonalScheduleDay(
      workDate: _text(json, 'workDate'),
      isRestDay: _boolean(_value(json, 'isRestDay')),
      shiftName: _text(json, 'shiftName'),
      expectedCheckInAt: _date(_value(json, 'expectedCheckInAt')),
      expectedCheckOutAt: _date(_value(json, 'expectedCheckOutAt')),
      status: _text(result, 'status'),
    );
  }

  final String workDate;
  final bool isRestDay;
  final String shiftName;
  final DateTime? expectedCheckInAt;
  final DateTime? expectedCheckOutAt;
  final String status;
}

final class OaAttendanceOverview {
  const OaAttendanceOverview({
    required this.today,
    required this.nextPunchType,
    required this.canPunch,
    required this.punchMessage,
    required this.monthExceptionCount,
    required this.requirePunchCorrectionApproval,
    required this.monthlyPunchCorrectionLimit,
    required this.monthPunchCorrectionCount,
    required this.exceptions,
    required this.recentRecords,
  });

  factory OaAttendanceOverview.fromJson(Map<String, Object?> json) =>
      OaAttendanceOverview(
        today: _scheduleDay(_value(json, 'today')),
        nextPunchType: _text(json, 'nextPunchType'),
        canPunch: _boolean(_value(json, 'canPunch')),
        punchMessage: _text(json, 'punchMessage'),
        monthExceptionCount: _integer(_value(json, 'monthExceptionCount')),
        requirePunchCorrectionApproval: _boolean(
          _value(json, 'requirePunchCorrectionApproval'),
        ),
        monthlyPunchCorrectionLimit: _integer(
          _value(json, 'monthlyPunchCorrectionLimit'),
        ),
        monthPunchCorrectionCount: _integer(
          _value(json, 'monthPunchCorrectionCount'),
        ),
        exceptions: _list(
          _value(json, 'exceptions'),
          OaAttendanceException.fromJson,
        ),
        recentRecords: _list(
          _value(json, 'recentRecords'),
          OaAttendanceRecord.fromJson,
        ),
      );

  final OaPersonalScheduleDay? today;
  final String nextPunchType;
  final bool canPunch;
  final String punchMessage;
  final int monthExceptionCount;
  final bool requirePunchCorrectionApproval;
  final int monthlyPunchCorrectionLimit;
  final int monthPunchCorrectionCount;
  final List<OaAttendanceException> exceptions;
  final List<OaAttendanceRecord> recentRecords;
}

final class OaBehaviorDefinition {
  const OaBehaviorDefinition({
    required this.id,
    required this.name,
    required this.timeoutMinutes,
    required this.maxOccurrencesPerShift,
    required this.allowParallel,
    required this.isEnabled,
    required this.sortOrder,
  });

  factory OaBehaviorDefinition.fromJson(Map<String, Object?> json) =>
      OaBehaviorDefinition(
        id: _text(json, 'id'),
        name: _text(json, 'name'),
        timeoutMinutes: _nullableInteger(_value(json, 'timeoutMinutes')),
        maxOccurrencesPerShift: _nullableInteger(
          _value(json, 'maxOccurrencesPerShift'),
        ),
        allowParallel: _boolean(_value(json, 'allowParallel')),
        isEnabled: _boolean(_value(json, 'isEnabled')),
        sortOrder: _integer(_value(json, 'sortOrder')),
      );

  final String id;
  final String name;
  final int? timeoutMinutes;
  final int? maxOccurrencesPerShift;
  final bool allowParallel;
  final bool isEnabled;
  final int sortOrder;
}

final class OaBehaviorSession {
  const OaBehaviorSession({
    required this.id,
    required this.behaviorDefinitionId,
    required this.behaviorName,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.workDate,
    required this.endReason,
    required this.isOvertime,
  });

  factory OaBehaviorSession.fromJson(Map<String, Object?> json) =>
      OaBehaviorSession(
        id: _text(json, 'id'),
        behaviorDefinitionId: _text(json, 'behaviorDefinitionId'),
        behaviorName: _text(json, 'behaviorName'),
        startedAt: _date(_value(json, 'startedAt')),
        endedAt: _date(_value(json, 'endedAt')),
        durationSeconds: _nullableInteger(_value(json, 'durationSeconds')),
        workDate: _text(json, 'workDate'),
        endReason: _text(json, 'endReason'),
        isOvertime: _boolean(_value(json, 'isOvertime')),
      );

  final String id;
  final String behaviorDefinitionId;
  final String behaviorName;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final String workDate;
  final String endReason;
  final bool isOvertime;
}

final class OaActiveInspection {
  const OaActiveInspection({
    required this.inspectionId,
    required this.title,
    required this.message,
    required this.openedAt,
    required this.responseStatus,
  });

  factory OaActiveInspection.fromJson(Map<String, Object?> json) =>
      OaActiveInspection(
        inspectionId: _text(json, 'inspectionId'),
        title: _text(json, 'title'),
        message: _text(json, 'message'),
        openedAt: _date(_value(json, 'openedAt')),
        responseStatus: _text(json, 'responseStatus'),
      );

  final String inspectionId;
  final String title;
  final String message;
  final DateTime? openedAt;
  final String responseStatus;
}

final class ImMember {
  const ImMember({
    required this.id,
    required this.username,
    required this.displayName,
    required this.isOnline,
    this.avatarKey = '',
    this.avatarDataUrl = '',
    this.departmentId = '',
    this.departmentName = '',
    this.isOrganizationManager = false,
    this.isFriend = false,
    this.canStartDirect = false,
    this.groupRole = '',
    this.lastSeenAt,
  });

  factory ImMember.fromJson(Map<String, Object?> json) => ImMember(
    id: _text(json, 'id'),
    username: _text(json, 'userName'),
    displayName: _text(json, 'displayName'),
    isOnline: _boolean(_value(json, 'isOnline')),
    avatarKey: _text(json, 'avatarKey'),
    avatarDataUrl: _text(json, 'avatarDataUrl'),
    departmentId: _text(json, 'departmentId'),
    departmentName: _text(json, 'departmentName'),
    isOrganizationManager: _boolean(_value(json, 'isOrganizationManager')),
    isFriend: _boolean(_value(json, 'isFriend')),
    canStartDirect: _boolean(_value(json, 'canStartDirect')),
    groupRole: _text(json, 'groupRole'),
    lastSeenAt: _date(_value(json, 'lastSeenAt')),
  );

  final String id;
  final String username;
  final String displayName;
  final bool isOnline;
  final String avatarKey;
  final String avatarDataUrl;
  final String departmentId;
  final String departmentName;
  final bool isOrganizationManager;
  final bool isFriend;
  final bool canStartDirect;
  final String groupRole;
  final DateTime? lastSeenAt;
}

final class ImDepartment {
  const ImDepartment({
    required this.id,
    required this.name,
    required this.code,
    required this.parentId,
    required this.sortOrder,
  });

  factory ImDepartment.fromJson(Map<String, Object?> json) => ImDepartment(
    id: _text(json, 'id'),
    name: _text(json, 'name'),
    code: _text(json, 'code'),
    parentId: _text(json, 'parentId'),
    sortOrder: _integer(_value(json, 'sortOrder')),
  );

  final String id;
  final String name;
  final String code;
  final String parentId;
  final int sortOrder;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'parentId': parentId,
    'sortOrder': sortOrder,
  };
}

final class ImMemberProfile {
  const ImMemberProfile({
    required this.id,
    required this.displayName,
    this.nickname = '',
    this.signature = '',
    this.username = '',
    this.departmentName = '',
    this.remark = '',
    this.avatarKey = '',
    this.avatarDataUrl = '',
  });

  factory ImMemberProfile.fromJson(Map<String, Object?> json) =>
      ImMemberProfile(
        id: _text(json, 'id'),
        displayName: _text(json, 'displayName'),
        nickname: _text(json, 'nickname'),
        signature: _text(json, 'signature'),
        username: _text(json, 'userName'),
        departmentName: _text(json, 'departmentName'),
        remark: _text(json, 'remark'),
        avatarKey: _text(json, 'avatarKey'),
        avatarDataUrl: _text(json, 'avatarDataUrl'),
      );

  final String id;
  final String displayName;
  final String nickname;
  final String signature;
  final String username;
  final String departmentName;
  final String remark;
  final String avatarKey;
  final String avatarDataUrl;
}

final class ImGroupProfile {
  const ImGroupProfile({
    required this.conversationId,
    required this.title,
    required this.notice,
    this.groupNo = '',
    this.avatarUrl = '',
    this.introduction = '',
    this.maxMemberCount = 0,
    this.reviewEnabled = false,
    this.viewMembersEnabled = true,
    this.screenshotEnabled = true,
    this.atEnabled = true,
    this.identityEnabled = false,
    this.muted = false,
    this.status = '',
    this.currentUserRole = '',
    this.updatedAt,
  });

  factory ImGroupProfile.fromJson(Map<String, Object?> json) => ImGroupProfile(
    conversationId: _text(json, 'conversationId'),
    title: _text(json, 'title'),
    notice: _text(json, 'notice'),
    groupNo: _text(json, 'groupNo'),
    avatarUrl: _text(json, 'avatarUrl'),
    introduction: _text(json, 'introduction'),
    maxMemberCount: _integer(_value(json, 'maxMemberCount')),
    reviewEnabled: _boolean(_value(json, 'reviewEnabled')),
    viewMembersEnabled: _boolean(_value(json, 'viewMembersEnabled')),
    screenshotEnabled: _boolean(_value(json, 'screenshotEnabled')),
    atEnabled: _boolean(_value(json, 'atEnabled')),
    identityEnabled: _boolean(_value(json, 'identityEnabled')),
    muted: _boolean(_value(json, 'muted')),
    status: _text(json, 'status'),
    currentUserRole: _text(json, 'currentUserRole'),
    updatedAt: _date(_value(json, 'updatedAt')),
  );

  final String conversationId;
  final String title;
  final String groupNo;
  final String avatarUrl;
  final String introduction;
  final String notice;
  final int maxMemberCount;
  final bool reviewEnabled;
  final bool viewMembersEnabled;
  final bool screenshotEnabled;
  final bool atEnabled;
  final bool identityEnabled;
  final bool muted;
  final String status;
  final String currentUserRole;
  final DateTime? updatedAt;
}

final class ImGroupManagementCapabilities {
  const ImGroupManagementCapabilities({
    this.canReviewJoinRequests = false,
    this.canMuteMembers = false,
    this.canManageAdministrators = false,
    this.canTransferOwnership = false,
    this.canDeleteAllHistory = false,
    this.canDissolveGroup = false,
  });

  factory ImGroupManagementCapabilities.fromJson(Map<String, Object?> json) =>
      ImGroupManagementCapabilities(
        canReviewJoinRequests: _boolean(_value(json, 'canReviewJoinRequests')),
        canMuteMembers: _boolean(_value(json, 'canMuteMembers')),
        canManageAdministrators: _boolean(
          _value(json, 'canManageAdministrators'),
        ),
        canTransferOwnership: _boolean(_value(json, 'canTransferOwnership')),
        canDeleteAllHistory: _boolean(_value(json, 'canDeleteAllHistory')),
        canDissolveGroup: _boolean(_value(json, 'canDissolveGroup')),
      );

  final bool canReviewJoinRequests;
  final bool canMuteMembers;
  final bool canManageAdministrators;
  final bool canTransferOwnership;
  final bool canDeleteAllHistory;
  final bool canDissolveGroup;
}

final class ImMutedGroupMember {
  const ImMutedGroupMember({required this.member, this.mutedUntil});

  factory ImMutedGroupMember.fromJson(Map<String, Object?> json) =>
      ImMutedGroupMember(
        member: ImMember.fromJson(
          (_value(json, 'member') is Map
                  ? _value(json, 'member') as Map
                  : const <String, Object?>{})
              .cast<String, Object?>(),
        ),
        mutedUntil: _date(_value(json, 'mutedUntil')),
      );

  final ImMember member;
  final DateTime? mutedUntil;
}

final class ImGroupJoinRequest {
  const ImGroupJoinRequest({
    required this.id,
    required this.applicantMemberId,
    required this.applicantName,
    required this.status,
    this.createdAt,
  });

  factory ImGroupJoinRequest.fromJson(Map<String, Object?> json) =>
      ImGroupJoinRequest(
        id: _text(json, 'id'),
        applicantMemberId: _text(json, 'applicantMemberId'),
        applicantName: _text(json, 'applicantName'),
        status: _text(json, 'status'),
        createdAt: _date(_value(json, 'createdAt')),
      );

  final String id;
  final String applicantMemberId;
  final String applicantName;
  final String status;
  final DateTime? createdAt;
}

final class ImGroupNotice {
  const ImGroupNotice({
    required this.id,
    required this.type,
    required this.actorName,
    this.createdAt,
  });

  factory ImGroupNotice.fromJson(Map<String, Object?> json) => ImGroupNotice(
    id: _text(json, 'id'),
    type: _text(json, 'type'),
    actorName: _text(json, 'actorName'),
    createdAt: _date(_value(json, 'createdAt')),
  );

  final String id;
  final String type;
  final String actorName;
  final DateTime? createdAt;
}

enum ImConversationKind { direct, group, unsupported }

final class ImConversation {
  const ImConversation({
    required this.id,
    required this.type,
    required this.title,
    required this.preview,
    required this.updatedAt,
    required this.unreadCount,
    this.lastMessageSequence = 0,
    this.lastReadSequence = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.unreadMentionSequences = const [],
  });

  factory ImConversation.fromJson(Map<String, Object?> json) => ImConversation(
    id: _text(json, 'id'),
    type: _text(json, 'type'),
    title: _text(json, 'title'),
    preview: _text(json, 'lastMessagePreview'),
    updatedAt: _date(_value(json, 'updatedAt')),
    unreadCount: _integer(_value(json, 'unreadCount')),
    lastMessageSequence: _integer(_value(json, 'lastMessageSequence')),
    lastReadSequence: _integer(_value(json, 'lastReadSequence')),
    isPinned: _boolean(_value(json, 'isPinned')),
    isMuted: _boolean(_value(json, 'isMuted')),
    unreadMentionSequences:
        (_value(json, 'unreadMentionSequences') is List
                ? _value(json, 'unreadMentionSequences') as List
                : const <Object?>[])
            .map(_integer)
            .where((value) => value > 0)
            .toList(),
  );

  final String id;
  final String type;
  final String title;
  final String preview;
  final DateTime? updatedAt;
  final int unreadCount;
  final int lastMessageSequence;
  final int lastReadSequence;
  final bool isPinned;
  final bool isMuted;
  final List<int> unreadMentionSequences;
  bool get hasUnreadMention => unreadMentionSequences.isNotEmpty;
  int? get firstUnreadSequence => unreadCount > 0 ? lastReadSequence + 1 : null;
  ImConversationKind get kind => switch (type.trim().toLowerCase()) {
    'direct' => ImConversationKind.direct,
    'group' => ImConversationKind.group,
    _ => ImConversationKind.unsupported,
  };

  bool get isDirect => kind == ImConversationKind.direct;
  bool get isGroup => kind == ImConversationKind.group;
  bool get isSupported => kind != ImConversationKind.unsupported;
}

final class ImPermissionSnapshot {
  const ImPermissionSnapshot({
    this.createGroup = false,
    this.editMessage = false,
    this.revokeMessage = false,
    this.deleteMessage = false,
    this.batchSend = false,
    this.readReceipt = true,
    this.viewIp = false,
    this.deleteFriend = false,
    this.invite = false,
  });

  factory ImPermissionSnapshot.fromJson(Map<String, Object?> json) =>
      ImPermissionSnapshot(
        createGroup: _boolean(_value(json, 'createGroup')),
        editMessage: _boolean(_value(json, 'editMessage')),
        revokeMessage: _boolean(_value(json, 'revokeMessage')),
        deleteMessage: _boolean(_value(json, 'deleteMessage')),
        batchSend: _boolean(_value(json, 'batchSend')),
        readReceipt: _boolean(_value(json, 'readReceipt')),
        viewIp: _boolean(_value(json, 'viewIp')),
        deleteFriend: _boolean(_value(json, 'deleteFriend')),
        invite: _boolean(_value(json, 'invite')),
      );

  Map<String, Object?> toJson() => {
    'createGroup': createGroup,
    'editMessage': editMessage,
    'revokeMessage': revokeMessage,
    'deleteMessage': deleteMessage,
    'batchSend': batchSend,
    'readReceipt': readReceipt,
    'viewIp': viewIp,
    'deleteFriend': deleteFriend,
    'invite': invite,
  };

  final bool createGroup;
  final bool editMessage;
  final bool revokeMessage;
  final bool deleteMessage;
  final bool batchSend;
  final bool readReceipt;
  final bool viewIp;
  final bool deleteFriend;
  final bool invite;
}

final class ImFriendApplicationBatchResult {
  const ImFriendApplicationBatchResult({
    required this.processed,
    required this.remaining,
  });

  factory ImFriendApplicationBatchResult.fromJson(Map<String, Object?> json) =>
      ImFriendApplicationBatchResult(
        processed: _integer(_value(json, 'processed')),
        remaining: _integer(_value(json, 'remaining')),
      );

  final int processed;
  final int remaining;
}

final class ImMemberPage {
  const ImMemberPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  factory ImMemberPage.fromJson(Map<String, Object?> json) => ImMemberPage(
    items: _list(_value(json, 'items'), ImMember.fromJson),
    page: _integer(_value(json, 'page')),
    pageSize: _integer(_value(json, 'pageSize')),
    total: _integer(_value(json, 'total')),
  );

  final List<ImMember> items;
  final int page;
  final int pageSize;
  final int total;
}

final class ImListPage<T> {
  const ImListPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  factory ImListPage.fromJson(
    Map<String, Object?> json,
    T Function(Map<String, Object?>) itemFactory, {
    int fallbackPage = 1,
    int fallbackPageSize = 50,
  }) {
    final items = _list(_value(json, 'items'), itemFactory);
    final parsedPage = _integer(_value(json, 'page'));
    final parsedPageSize = _integer(_value(json, 'pageSize'));
    final page = parsedPage > 0 ? parsedPage : fallbackPage;
    final pageSize = parsedPageSize > 0 ? parsedPageSize : fallbackPageSize;
    final parsedTotal = _integer(_value(json, 'total'));
    final total = parsedTotal > 0
        ? parsedTotal
        : ((page - 1) * pageSize) + items.length;
    return ImListPage<T>(
      items: items,
      page: page,
      pageSize: pageSize,
      total: total,
    );
  }

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;

  bool get hasMore => page * pageSize < total;
}

final class ImGroupManagementPage<T> {
  const ImGroupManagementPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  factory ImGroupManagementPage.fromJson(
    Map<String, Object?> json,
    T Function(Map<String, Object?>) itemFactory,
  ) => ImGroupManagementPage<T>(
    items: _list(_value(json, 'items'), itemFactory),
    page: _integer(_value(json, 'page')),
    pageSize: _integer(_value(json, 'pageSize')),
    total: _integer(_value(json, 'total')),
  );

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;

  bool get hasMore => page * pageSize < total;
}

final class ImBadgeSummary {
  const ImBadgeSummary({
    required this.unreadMessages,
    required this.pendingFriendRequests,
  });

  factory ImBadgeSummary.fromJson(Map<String, Object?> json) => ImBadgeSummary(
    unreadMessages: _integer(_value(json, 'unreadMessages')),
    pendingFriendRequests: _integer(_value(json, 'pendingFriendRequests')),
  );

  final int unreadMessages;
  final int pendingFriendRequests;
}

final class ImContactCard {
  const ImContactCard({
    required this.memberId,
    required this.username,
    required this.displayName,
    this.avatarKey = '',
    this.avatarDataUrl = '',
    this.departmentId = '',
    this.departmentName = '',
    this.isOrganizationManager = false,
  });

  factory ImContactCard.fromJson(Map<String, Object?> json) => ImContactCard(
    memberId: _text(json, 'memberId'),
    username: _text(json, 'userName'),
    displayName: _text(json, 'displayName'),
    avatarKey: _text(json, 'avatarKey'),
    avatarDataUrl: _text(json, 'avatarDataUrl'),
    departmentId: _text(json, 'departmentId'),
    departmentName: _text(json, 'departmentName'),
    isOrganizationManager: _boolean(_value(json, 'isOrganizationManager')),
  );

  final String memberId;
  final String username;
  final String displayName;
  final String avatarKey;
  final String avatarDataUrl;
  final String departmentId;
  final String departmentName;
  final bool isOrganizationManager;

  Map<String, Object?> toJson() => {
    'memberId': memberId,
    'userName': username,
    'displayName': displayName,
    'avatarKey': avatarKey,
    'avatarDataUrl': avatarDataUrl,
    'departmentId': departmentId,
    'departmentName': departmentName,
    'isOrganizationManager': isOrganizationManager,
  };
}

enum ImLocalMessageStatus { pending, sent, failed }

final class ImFavoriteMessage {
  const ImFavoriteMessage({
    required this.messageId,
    required this.note,
    required this.createdAt,
    required this.message,
  });

  factory ImFavoriteMessage.fromJson(Map<String, Object?> json) {
    final rawMessage = _value(json, 'message');
    return ImFavoriteMessage(
      messageId: _text(json, 'messageId'),
      note: _text(json, 'note'),
      createdAt: _date(_value(json, 'createdAt')),
      message: ImMessage.fromJson(
        rawMessage is Map
            ? rawMessage.cast<String, Object?>()
            : const <String, Object?>{},
      ),
    );
  }

  final String messageId;
  final String note;
  final DateTime? createdAt;
  final ImMessage message;
}

final class ImAssistantTask {
  const ImAssistantTask({
    required this.id,
    required this.messageKind,
    required this.content,
    required this.attachmentJson,
    required this.status,
    required this.receiverCount,
    required this.successCount,
    required this.failureCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ImAssistantTask.fromJson(Map<String, Object?> json) =>
      ImAssistantTask(
        id: _text(json, 'id'),
        messageKind: _text(json, 'messageKind'),
        content: _text(json, 'content'),
        attachmentJson: _text(json, 'attachmentJson'),
        status: _text(json, 'status'),
        receiverCount: _integer(_value(json, 'receiverCount')),
        successCount: _integer(_value(json, 'successCount')),
        failureCount: _integer(_value(json, 'failureCount')),
        createdAt: _date(_value(json, 'createdAt')),
        updatedAt: _date(_value(json, 'updatedAt')),
      );

  final String id;
  final String messageKind;
  final String content;
  final String attachmentJson;
  final String status;
  final int receiverCount;
  final int successCount;
  final int failureCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get canCancel => const {
    'pending',
    'queued',
    'running',
  }.contains(status.trim().toLowerCase());
}

final class ImGroupHistoryDeletionJob {
  const ImGroupHistoryDeletionJob({
    required this.id,
    required this.conversationId,
    required this.status,
    required this.deletedMessageCount,
    required this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
  });

  factory ImGroupHistoryDeletionJob.fromJson(Map<String, Object?> json) =>
      ImGroupHistoryDeletionJob(
        id: _text(json, 'id'),
        conversationId: _text(json, 'conversationId'),
        status: _text(json, 'status'),
        deletedMessageCount: _integer(_value(json, 'deletedMessageCount')),
        errorMessage: _text(json, 'errorMessage'),
        createdAt: _date(_value(json, 'createdAt')),
        updatedAt: _date(_value(json, 'updatedAt')),
        completedAt: _date(_value(json, 'completedAt')),
      );

  final String id;
  final String conversationId;
  final String status;
  final int deletedMessageCount;
  final String errorMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  bool get isCompleted => status.trim().toLowerCase() == 'completed';
  bool get isFailed => status.trim().toLowerCase() == 'failed';
}

final class ImDeviceAuthorization {
  const ImDeviceAuthorization({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.isAuthorized,
    required this.authorizedAt,
    required this.lastSeenAt,
    required this.revokedAt,
  });

  factory ImDeviceAuthorization.fromJson(Map<String, Object?> json) =>
      ImDeviceAuthorization(
        deviceId: _text(json, 'deviceId'),
        deviceName: _text(json, 'deviceName'),
        platform: _text(json, 'platform'),
        isAuthorized: _boolean(_value(json, 'isAuthorized')),
        authorizedAt: _date(_value(json, 'authorizedAt')),
        lastSeenAt: _date(_value(json, 'lastSeenAt')),
        revokedAt: _date(_value(json, 'revokedAt')),
      );

  final String deviceId;
  final String deviceName;
  final String platform;
  final bool isAuthorized;
  final DateTime? authorizedAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;
}

final class ImPushDevice {
  const ImPushDevice({
    required this.deviceId,
    required this.platform,
    required this.provider,
    required this.privacyMode,
    required this.isEnabled,
    required this.lastPushEventSequence,
    required this.updatedAt,
  });

  factory ImPushDevice.fromJson(Map<String, Object?> json) => ImPushDevice(
    deviceId: _text(json, 'deviceId'),
    platform: _text(json, 'platform'),
    provider: _text(json, 'provider'),
    privacyMode: _text(json, 'privacyMode'),
    isEnabled: _boolean(_value(json, 'isEnabled')),
    lastPushEventSequence: _integer(_value(json, 'lastPushEventSequence')),
    updatedAt: _date(_value(json, 'updatedAt')),
  );

  final String deviceId;
  final String platform;
  final String provider;
  final String privacyMode;
  final bool isEnabled;
  final int lastPushEventSequence;
  final DateTime? updatedAt;
}

final class ImLanguagePreference {
  const ImLanguagePreference({required this.language, required this.updatedAt});

  factory ImLanguagePreference.fromJson(Map<String, Object?> json) =>
      ImLanguagePreference(
        language: _text(json, 'language'),
        updatedAt: _date(_value(json, 'updatedAt')),
      );

  final String language;
  final DateTime? updatedAt;
}

final class ImMessage {
  const ImMessage({
    required this.id,
    required this.sequence,
    required this.senderId,
    required this.content,
    required this.kind,
    required this.createdAt,
    this.conversationId = '',
    this.clientMessageId = '',
    this.attachmentName = '',
    this.attachmentSize,
    this.attachmentContentType = '',
    this.attachmentSha256 = '',
    this.contactCard,
    this.images = const [],
    this.attachments = const [],
    this.mentions = const [],
    this.replyTo,
    this.recalledAt,
    this.localStatus = ImLocalMessageStatus.sent,
    this.lastError = '',
  });

  factory ImMessage.fromJson(Map<String, Object?> json) => ImMessage(
    id: _text(json, 'id'),
    sequence: _integer(_value(json, 'sequence')),
    senderId: _text(json, 'senderId'),
    conversationId: _text(json, 'conversationId'),
    clientMessageId: _text(json, 'clientMessageId'),
    content: _text(json, 'content'),
    kind: _text(json, 'kind'),
    attachmentName: _text(json, 'attachmentName'),
    attachmentSize: _nullableInteger(_value(json, 'attachmentSize')),
    attachmentContentType: _text(json, 'attachmentContentType'),
    attachmentSha256: _text(json, 'attachmentSha256'),
    contactCard: _contactCard(_value(json, 'contactCard')),
    images: _list(_value(json, 'images'), ImMessageImage.fromJson),
    attachments: _list(
      _value(json, 'attachments'),
      ImMessageAttachment.fromJson,
    ),
    mentions: _list(_value(json, 'mentions'), ImMessageMention.fromJson),
    replyTo: _replyTo(_value(json, 'replyTo')),
    createdAt: _date(_value(json, 'createdAt')),
    recalledAt: _date(_value(json, 'recalledAt')),
  );

  final String id;
  final String conversationId;
  final int sequence;
  final String senderId;
  final String clientMessageId;
  final String content;
  final String kind;
  final String attachmentName;
  final int? attachmentSize;
  final String attachmentContentType;
  final String attachmentSha256;
  final ImContactCard? contactCard;
  final List<ImMessageImage> images;
  final List<ImMessageAttachment> attachments;
  final List<ImMessageMention> mentions;
  final ImMessageReply? replyTo;
  final DateTime? createdAt;
  final DateTime? recalledAt;
  final ImLocalMessageStatus localStatus;
  final String lastError;

  ImMessage copyWith({
    String? id,
    int? sequence,
    String? content,
    DateTime? recalledAt,
    List<ImMessageMention>? mentions,
    ImMessageReply? replyTo,
    ImLocalMessageStatus? localStatus,
    String? lastError,
  }) => ImMessage(
    id: id ?? this.id,
    conversationId: conversationId,
    sequence: sequence ?? this.sequence,
    senderId: senderId,
    clientMessageId: clientMessageId,
    content: content ?? this.content,
    kind: kind,
    attachmentName: attachmentName,
    attachmentSize: attachmentSize,
    attachmentContentType: attachmentContentType,
    attachmentSha256: attachmentSha256,
    contactCard: contactCard,
    images: images,
    attachments: attachments,
    mentions: mentions ?? this.mentions,
    replyTo: replyTo ?? this.replyTo,
    createdAt: createdAt,
    recalledAt: recalledAt ?? this.recalledAt,
    localStatus: localStatus ?? this.localStatus,
    lastError: lastError ?? this.lastError,
  );
}

final class ImMessageAttachment {
  const ImMessageAttachment({
    required this.id,
    required this.type,
    required this.fileName,
    required this.contentType,
    required this.size,
    required this.sha256,
    this.width,
    this.height,
    this.coverObjectId = '',
    this.coverWidth,
    this.coverHeight,
    this.durationSeconds,
  });

  factory ImMessageAttachment.fromJson(Map<String, Object?> json) =>
      ImMessageAttachment(
        id: _text(json, 'id'),
        type: _text(json, 'type'),
        fileName: _text(json, 'fileName'),
        contentType: _text(json, 'contentType'),
        size: _integer(_value(json, 'size')),
        sha256: _text(json, 'sha256'),
        width: _nullableInteger(_value(json, 'width')),
        height: _nullableInteger(_value(json, 'height')),
        coverObjectId: _text(json, 'coverObjectId'),
        coverWidth: _nullableInteger(_value(json, 'coverWidth')),
        coverHeight: _nullableInteger(_value(json, 'coverHeight')),
        durationSeconds: _nullableDouble(_value(json, 'durationSeconds')),
      );

  final String id;
  final String type;
  final String fileName;
  final String contentType;
  final int size;
  final String sha256;
  final int? width;
  final int? height;
  final String coverObjectId;
  final int? coverWidth;
  final int? coverHeight;
  final double? durationSeconds;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'fileName': fileName,
    'contentType': contentType,
    'size': size,
    'sha256': sha256,
    'width': width,
    'height': height,
    'coverObjectId': coverObjectId,
    'coverWidth': coverWidth,
    'coverHeight': coverHeight,
    'durationSeconds': durationSeconds,
  };
}

final class ImMessageImage {
  const ImMessageImage({
    required this.id,
    required this.fileName,
    required this.size,
    this.contentType = '',
    this.sha256 = '',
  });

  factory ImMessageImage.fromJson(Map<String, Object?> json) => ImMessageImage(
    id: _text(json, 'id'),
    fileName: _text(json, 'fileName'),
    size: _integer(_value(json, 'size')),
    contentType: _text(json, 'contentType'),
    sha256: _text(json, 'sha256'),
  );

  final String id;
  final String fileName;
  final int size;
  final String contentType;
  final String sha256;

  Map<String, Object?> toJson() => {
    'id': id,
    'fileName': fileName,
    'size': size,
    'contentType': contentType,
    'sha256': sha256,
  };
}

final class ImMessageMention {
  const ImMessageMention({
    required this.mentionedMemberId,
    required this.displayName,
    this.isMentionAll = false,
  });

  factory ImMessageMention.fromJson(Map<String, Object?> json) =>
      ImMessageMention(
        mentionedMemberId: _text(json, 'mentionedMemberId'),
        displayName: _text(json, 'displayName'),
        isMentionAll: _boolean(_value(json, 'isMentionAll')),
      );

  final String mentionedMemberId;
  final String displayName;
  final bool isMentionAll;
}

final class ImMessageReply {
  const ImMessageReply({
    required this.messageId,
    required this.senderId,
    required this.content,
    required this.kind,
    required this.createdAt,
    this.recalledAt,
  });

  factory ImMessageReply.fromJson(Map<String, Object?> json) => ImMessageReply(
    messageId: _text(json, 'messageId'),
    senderId: _text(json, 'senderId'),
    content: _text(json, 'content'),
    kind: _text(json, 'kind'),
    createdAt: _date(_value(json, 'createdAt')),
    recalledAt: _date(_value(json, 'recalledAt')),
  );

  final String messageId;
  final String senderId;
  final String content;
  final String kind;
  final DateTime? createdAt;
  final DateTime? recalledAt;
}

final class ImMessageReadMember {
  const ImMessageReadMember({
    required this.memberId,
    required this.username,
    required this.displayName,
    required this.role,
    required this.readAt,
    this.avatarKey = '',
    this.avatarDataUrl = '',
  });

  factory ImMessageReadMember.fromJson(Map<String, Object?> json) =>
      ImMessageReadMember(
        memberId: _text(json, 'memberId'),
        username: _text(json, 'userName'),
        displayName: _text(json, 'displayName'),
        role: _text(json, 'role'),
        readAt: _date(_value(json, 'readAt')),
        avatarKey: _text(json, 'avatarKey'),
        avatarDataUrl: _text(json, 'avatarDataUrl'),
      );

  final String memberId;
  final String username;
  final String displayName;
  final String role;
  final DateTime? readAt;
  final String avatarKey;
  final String avatarDataUrl;
}

final class ImMessageReadReceipt {
  const ImMessageReadReceipt({
    required this.conversationId,
    required this.messageId,
    required this.sequence,
    required this.readCount,
    required this.totalRecipientCount,
    required this.isReadByAll,
    required this.peerRead,
    required this.readers,
  });

  factory ImMessageReadReceipt.fromJson(Map<String, Object?> json) =>
      ImMessageReadReceipt(
        conversationId: _text(json, 'conversationId'),
        messageId: _text(json, 'messageId'),
        sequence: _integer(_value(json, 'sequence')),
        readCount: _integer(_value(json, 'readCount')),
        totalRecipientCount: _integer(_value(json, 'totalRecipientCount')),
        isReadByAll: _boolean(_value(json, 'isReadByAll')),
        peerRead: _boolean(_value(json, 'peerRead')),
        readers: _list(_value(json, 'readers'), ImMessageReadMember.fromJson),
      );

  final String conversationId;
  final String messageId;
  final int sequence;
  final int readCount;
  final int totalRecipientCount;
  final bool isReadByAll;
  final bool peerRead;
  final List<ImMessageReadMember> readers;
}

final class ImSyncEvent {
  const ImSyncEvent({
    required this.sequence,
    required this.id,
    required this.type,
    required this.payloadJson,
    required this.createdAt,
  });

  factory ImSyncEvent.fromJson(Map<String, Object?> json) => ImSyncEvent(
    sequence: _integer(_value(json, 'sequence')),
    id: _text(json, 'id'),
    type: _text(json, 'type'),
    payloadJson: _text(json, 'payloadJson'),
    createdAt: _date(_value(json, 'createdAt')),
  );

  final int sequence;
  final String id;
  final String type;
  final String payloadJson;
  final DateTime? createdAt;
}

final class ImBootstrap {
  const ImBootstrap({
    required this.currentMember,
    required this.conversations,
    required this.contacts,
    this.permissions = const ImPermissionSnapshot(),
    this.config = const ImClientConfig(),
  });

  factory ImBootstrap.fromJson(Map<String, Object?> json) => ImBootstrap(
    currentMember: ImMember.fromJson(_map(json['currentMember'])),
    conversations: _list(
      json['conversations'],
      ImConversation.fromJson,
    ).where((conversation) => conversation.isSupported).toList(),
    contacts: _list(json['contacts'], ImMember.fromJson),
    permissions: ImPermissionSnapshot.fromJson(_map(json['permissions'])),
    config: ImClientConfig.fromJson(_map(json['config'])),
  );

  final ImMember currentMember;
  final List<ImConversation> conversations;
  final List<ImMember> contacts;
  final ImPermissionSnapshot permissions;
  final ImClientConfig config;
}

final class ImClientConfig {
  const ImClientConfig({this.message = const ImMessageConfig()});

  factory ImClientConfig.fromJson(Map<String, Object?> json) =>
      ImClientConfig(message: ImMessageConfig.fromJson(_map(json['message'])));

  Map<String, Object?> toJson() => {'message': message.toJson()};

  final ImMessageConfig message;
}

final class ImMessageConfig {
  const ImMessageConfig({
    this.reply = true,
    this.forward = true,
    this.mentionMember = true,
    this.mentionAll = false,
  });

  factory ImMessageConfig.fromJson(Map<String, Object?> json) =>
      ImMessageConfig(
        reply: _value(json, 'reply') == null
            ? true
            : _boolean(_value(json, 'reply')),
        forward: _value(json, 'forward') == null
            ? true
            : _boolean(_value(json, 'forward')),
        mentionMember: _value(json, 'mentionMember') == null
            ? true
            : _boolean(_value(json, 'mentionMember')),
        mentionAll: _boolean(_value(json, 'mentionAll')),
      );

  Map<String, Object?> toJson() => {
    'reply': reply,
    'forward': forward,
    'mentionMember': mentionMember,
    'mentionAll': mentionAll,
  };

  final bool reply;
  final bool forward;
  final bool mentionMember;
  final bool mentionAll;
}

final class ImSearchResult {
  const ImSearchResult({
    required this.type,
    required this.id,
    required this.displayName,
    this.username = '',
    this.groupNo = '',
    this.avatarUrl = '',
    this.avatarKey = '',
    this.avatarDataUrl = '',
    this.departmentName = '',
    this.isOnline = false,
    this.isFriend = false,
    this.canStartDirect = false,
  });

  factory ImSearchResult.fromJson(Map<String, Object?> json) => ImSearchResult(
    type: _text(json, 'type'),
    id: _text(json, 'id'),
    displayName: _text(json, 'displayName'),
    username: _text(json, 'userName'),
    groupNo: _text(json, 'groupNo'),
    avatarUrl: _text(json, 'avatarUrl'),
    avatarKey: _text(json, 'avatarKey'),
    avatarDataUrl: _text(json, 'avatarDataUrl'),
    departmentName: _text(json, 'departmentName'),
    isOnline: _boolean(_value(json, 'isOnline')),
    isFriend: _boolean(_value(json, 'isFriend')),
    canStartDirect: _boolean(_value(json, 'canStartDirect')),
  );

  final String type;
  final String id;
  final String displayName;
  final String username;
  final String groupNo;
  final String avatarUrl;
  final String avatarKey;
  final String avatarDataUrl;
  final String departmentName;
  final bool isOnline;
  final bool isFriend;
  final bool canStartDirect;
}

final class ImConversationPresence {
  const ImConversationPresence({
    required this.conversationId,
    required this.type,
    required this.onlineMemberCount,
    required this.peerOnline,
    this.peerLastSeenAt,
    this.serverTime,
  });

  factory ImConversationPresence.fromJson(Map<String, Object?> json) =>
      ImConversationPresence(
        conversationId: _text(json, 'conversationId'),
        type: _text(json, 'type'),
        onlineMemberCount: _integer(_value(json, 'onlineMemberCount')),
        peerOnline: _boolean(_value(json, 'peerOnline')),
        peerLastSeenAt: _date(_value(json, 'peerLastSeenAt')),
        serverTime: _date(_value(json, 'serverTime')),
      );

  final String conversationId;
  final String type;
  final int onlineMemberCount;
  final bool peerOnline;
  final DateTime? peerLastSeenAt;
  final DateTime? serverTime;
}

final class ImFriendApplication {
  const ImFriendApplication({
    required this.id,
    required this.applicant,
    required this.target,
    required this.direction,
    required this.status,
    required this.greeting,
    this.createdAt,
  });

  factory ImFriendApplication.fromJson(Map<String, Object?> json) =>
      ImFriendApplication(
        id: _text(json, 'id'),
        applicant: ImMember.fromJson(_map(_value(json, 'applicant'))),
        target: ImMember.fromJson(_map(_value(json, 'target'))),
        direction: _text(json, 'direction'),
        status: _text(json, 'status'),
        greeting: _text(json, 'greeting'),
        createdAt: _date(_value(json, 'createdAt')),
      );

  final String id;
  final ImMember applicant;
  final ImMember target;
  final String direction;
  final String status;
  final String greeting;
  final DateTime? createdAt;
}

Object? _value(Map<String, Object?> json, String key) =>
    json[key] ?? json['${key[0].toUpperCase()}${key.substring(1)}'];

String _text(Map<String, Object?> json, String key) =>
    _value(json, key)?.toString() ?? '';

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

int _integer(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  _ => int.tryParse(value?.toString() ?? '') ?? 0,
};

int? _nullableInteger(Object? value) => value == null ? null : _integer(value);

double? _nullableDouble(Object? value) => switch (value) {
  null => null,
  num number => number.toDouble(),
  _ => double.tryParse(value.toString()),
};

Map<String, Object?>? _mapOrNull(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

OaPersonalScheduleDay? _scheduleDay(Object? value) {
  final json = _mapOrNull(value);
  return json == null ? null : OaPersonalScheduleDay.fromJson(json);
}

ImContactCard? _contactCard(Object? value) {
  final json = _mapOrNull(value);
  return json == null ? null : ImContactCard.fromJson(json);
}

ImMessageReply? _replyTo(Object? value) {
  final json = _mapOrNull(value);
  return json == null ? null : ImMessageReply.fromJson(json);
}

bool _boolean(Object? value) => switch (value) {
  bool result => result,
  String text => text.toLowerCase() == 'true' || text == '1',
  num number => number != 0,
  _ => false,
};

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};

List<T> _list<T>(Object? value, T Function(Map<String, Object?>) parse) =>
    value is List ? value.map((item) => parse(_map(item))).toList() : <T>[];

List<String> _strings(Object? value) =>
    value is List ? value.map((item) => item.toString()).toList() : <String>[];
