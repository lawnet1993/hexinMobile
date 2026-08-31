import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

void main() {
  test('OA attachment keeps desktop preview metadata', () {
    final attachment = OaApprovalAttachment.fromJson(const {
      'id': 'attachment-1',
      'fileName': 'evidence.png',
      'contentType': 'image/png',
      'size': 1024,
      'sha256': 'abc123',
      'isPreviewableImage': true,
    });

    expect(attachment.sha256, 'abc123');
    expect(attachment.isPreviewableImage, isTrue);
  });
}
