import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../finance/finance_data.dart';

/// Um lembrete a agendar. O texto nunca leva valores.
class Reminder {
  const Reminder(this.when, this.body);
  final DateTime when;
  final String body;
}

/// Lembretes a partir dos dados: véspera e dia de cada compromisso pendente
/// e o dia de cada contribuição da Kixikila, sempre às 9:00.
List<Reminder> plannedReminders(FinanceData data, {required DateTime now, int max = 60}) {
  final out = <Reminder>[];
  DateTime at9(DateTime d) => DateTime(d.year, d.month, d.day, 9);
  void add(DateTime when, String body) {
    if (when.isAfter(now)) out.add(Reminder(when, body));
  }

  for (final c in data.ledger.pending()) {
    add(at9(c.dueDate.subtract(const Duration(days: 1))), '${c.description} vence amanhã.');
    add(at9(c.dueDate), '${c.description} vence hoje.');
  }
  for (final g in data.kixikilas) {
    if (g.archived) continue;
    final s = KixikilaEngine.status(data.ledger, g, data.kixikilaRecords);
    final next = s.nextContribution;
    if (next != null) add(at9(g.roundDate(next)), 'Contribuição da Kixikila "${g.name}" é hoje.');
    if (!s.received) add(at9(s.myPayoutDate), 'Hoje é a sua vez de receber na Kixikila "${g.name}".');
  }
  out.sort((a, b) => a.when.compareTo(b.when));
  return out.take(max).toList();
}

abstract interface class Reminders {
  /// Pede a autorização do sistema. `true` se pode notificar.
  Future<bool> requestPermission();
  Future<void> reschedule(FinanceData data);
  Future<void> cancelAll();
}

class DeviceReminders implements Reminders {
  DeviceReminders();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'fintrack_lembretes',
      'Lembretes',
      channelDescription: 'Compromissos a vencer e contribuições da Kixikila',
      importance: Importance.defaultImportance,
      // No ecrã bloqueado aparece só "FINTRACK", sem o texto.
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    return false;
  }

  @override
  Future<void> reschedule(FinanceData data) async {
    await _init();
    await _plugin.cancelAll();
    final reminders = plannedReminders(data, now: DateTime.now());
    for (final (i, r) in reminders.indexed) {
      await _plugin.zonedSchedule(
        id: i + 1,
        // Hora local convertida num instante absoluto.
        scheduledDate: tz.TZDateTime.from(r.when, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'FINTRACK',
        body: r.body,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancelAll();
  }
}

/// Implementação vazia, para testes.
@visibleForTesting
class MemoryReminders implements Reminders {
  bool allow = true;
  List<Reminder> scheduled = [];
  int reschedules = 0;

  @override
  Future<bool> requestPermission() async => allow;

  @override
  Future<void> reschedule(FinanceData data) async {
    reschedules++;
    scheduled = plannedReminders(data, now: DateTime.now());
  }

  @override
  Future<void> cancelAll() async => scheduled = [];
}

final remindersProvider = Provider<Reminders>((ref) => DeviceReminders());
