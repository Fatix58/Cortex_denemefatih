import 'package:cortex/l10n/app_localizations.dart';
import 'package:cortex/notifications/extrovert/service.dart';
import 'package:cortex/tasks/service.dart';
import 'package:cortex/tasks/task.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Offers a reminder when a message mentions a concrete future commitment.
class ExamReminderSuggestion {
  ExamReminderSuggestion._();

  static final RegExp _futureCommitment = RegExp(
    r'(\b(yarın|yarin|bugün|bugun|haftaya|gelecek hafta|sonra|daha sonra|'
    r'toplantı|toplanti|randevu|teslim tarihi|son tarih|sunum|mülakat|'
    r'mulakat|seyahat|uçuş|ucus|başvuru|basvuru|görüşme|gorusme|'
    r'sınav|sinav|hatırlat|hatirlat|unutma)\b|'
    r'\b(tomorrow|today|next week|later|meeting|appointment|deadline|'
    r'presentation|interview|trip|flight|application|follow up|remind me|'
    r'exam|test)\b)',
    caseSensitive: false,
  );

  static bool matches(String message) => _futureCommitment.hasMatch(message);

  static void offer(BuildContext context, String message) {
    if (!context.mounted || !matches(message)) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.examReminderSuggestion),
          action: SnackBarAction(
            label: l10n.examReminderAction,
            onPressed: () => _chooseTime(context, message),
          ),
        ),
      );
  }

  static Future<void> _chooseTime(BuildContext context, String message) async {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !context.mounted) return;
    final reminder = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!reminder.isAfter(DateTime.now())) return;

    final title = _taskTitle(message);
    final notifications = context.read<ExtrovertNotificationService>();
    int? notificationId;
    var reminderMayBeDelayed = false;
    try {
      if (await notifications.requestTaskReminderPermission()) {
        notificationId = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
        await notifications.scheduleTaskReminder(
          notificationId: notificationId,
          title: title,
          scheduledAt: reminder,
        );
        reminderMayBeDelayed = !await notifications
            .canScheduleTaskReminderExactly();
      }
    } catch (_) {
      notificationId = null;
    }

    final taskService = TaskService();
    final tasks = await taskService.load();
    tasks.insert(
      0,
      CortexTask(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        dueAt: reminder,
        notificationId: notificationId,
      ),
    );
    await taskService.save(tasks);
    if (context.mounted && notificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.taskReminderPermissionNeeded)),
      );
    } else if (context.mounted && reminderMayBeDelayed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.taskReminderMayBeDelayed)));
    }
  }

  static String _taskTitle(String message) {
    final compact = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 100) return compact;
    return '${compact.substring(0, 97).trimRight()}…';
  }
}
