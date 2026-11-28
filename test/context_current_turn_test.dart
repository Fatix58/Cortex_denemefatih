import 'dart:io';

import 'package:cortex/chat/messages/messages.dart';
import 'package:cortex/chat/providers/conversation.dart';
import 'package:cortex/chat/services/context.dart';
import 'package:cortex/library/backend/data/entity.dart';
import 'package:cortex/library/backend/data/service.dart';
import 'package:flutter_test/flutter_test.dart';

class _ModelService implements ModelService {
  @override
  ModelEntity getPreciseModelData(String modelId, {required String langCode}) =>
      ModelEntity.fromMap(
        {'id': modelId, 'isServerSide': true, 'name': 'Test'},
        langCode,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('excluding the current user turn prevents attachment duplication',
      () async {
    final directory = await Directory.systemTemp.createTemp('cortex_context');
    final image = File('${directory.path}/photo.jpg');
    await image.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

    final conversation = ConversationProvider();
    addTearDown(() async {
      conversation.dispose();
      await directory.delete(recursive: true);
    });
    conversation.loadMessages([
      Message(text: 'Earlier answer', isUserMessage: false),
      Message(
        text: 'What is in this picture?',
        isUserMessage: true,
        attachmentPaths: [image.path],
      ),
    ]);

    final context = await ContextService(
      conversationProvider: conversation,
      modelService: _ModelService(),
    ).buildContextMessages(
      includeLastUser: false,
      targetModelId: 'cortex/auto',
      langCode: 'en',
    );

    expect(context, hasLength(1));
    expect(context.single['role'], 'assistant');
    expect(context.single['content'], 'Earlier answer');
  });
}
