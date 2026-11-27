import 'package:cortex/tasks/exam_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExamReminderSuggestion.matches', () {
    test('recognizes reminders for different future commitments', () {
      expect(ExamReminderSuggestion.matches('Akşam sınavım var'), isTrue);
      expect(ExamReminderSuggestion.matches('I have an exam tomorrow'), isTrue);
      expect(ExamReminderSuggestion.matches('Yarın dişçi randevum var'), isTrue);
      expect(ExamReminderSuggestion.matches('The project deadline is next week'), isTrue);
      expect(ExamReminderSuggestion.matches('Yarın toplantıyı konuşalım'), isTrue);
    });

    test('does not suggest reminders for unrelated messages', () {
      expect(
        ExamReminderSuggestion.matches('Let us review the notes'),
        isFalse,
      );
    });
  });
}
