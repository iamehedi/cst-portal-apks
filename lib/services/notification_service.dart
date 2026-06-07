import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'supabase_service.dart';

// Firebase-এর ব্যাকগ্রাউন্ড নোটিফিকেশন হ্যান্ডেলার (টপ-লেভেল ফাংশন)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Already initialized in background isolate
  }
  // ব্যাকগ্রাউন্ড মেমোরিতে লোকাল নোটিফিকেশন চ্যানেল পুনরায় তৈরি করা
  final localNotifications = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await localNotifications.initialize(const InitializationSettings(android: androidInit));

  NotificationService._showLocalNotification(message, localNotifications);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // নোটিফিকেশনের জন্য কাস্টম চ্যানেল তৈরি (গাইডের স্টেপ ১ অনুযায়ী)
  static const AndroidNotificationChannel _kNoticeChannel = AndroidNotificationChannel(
    'notice_channel',
    'Important Notices',
    description: 'This channel is used for institute notice boards.',
    importance: Importance.max,
    playSound: true,
  );

  static const AndroidNotificationChannel _kReminderChannel = AndroidNotificationChannel(
    'reminder_channel',
    'Exam & Class Reminders',
    description: 'This channel is used for exam routine alerts.',
    importance: Importance.high,
    playSound: true,
  );

  /// নোটিফিকেশন সার্ভিসের মেইন ইনিশিয়ালাইজেশন
  Future<void> initialize(BuildContext context) async {
    // টাইমজোন ডাটা ইনিশিয়ালাইজ করা (শিডিউল নোটিফিকেশনের জন্য বাধ্যতামূলক)
    tz.initializeTimeZones();

    // ইউজার থেকে নোটিফিকেশনের পারমিশন চাওয়া (Android 13+)
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // লোকাল নোটিফিকেশন সেটআপ
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          // নোটিফিকেশনে ট্যাপ করলে কোন স্ক্রিনে যাবে তা ঠিক করা (Background state tap)
          _routeFromMessage(context, {'type': response.payload});
        }
      },
    );

    // অ্যান্ড্রয়েডের জন্য চ্যানেলগুলো ডাটাবেজে রেজিস্টার করা
    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(_kNoticeChannel);
      await androidPlugin.createNotificationChannel(_kReminderChannel);
    }

    // ১. Foreground State: অ্যাপ চোখের সামনে খোলা থাকলে এই লিসেনার কাজ করবে
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message, _localNotifications);
    });

    // ২. Background State: ব্যাকগ্রাউন্ড থেকে নোটিফিকেশনে ট্যাপ করলে অ্যাপ সচল হবে
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _routeFromMessage(context, message.data);
    });

    // ৩. Terminated State: অ্যাপ একদম বন্ধ থাকা অবস্থায় নোটিফিকেশন ট্যাপ করলে যেভাবে হ্যান্ডেল হবে
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null && context.mounted) {
      // একটু সময় নিয়ে নেভিগেশন কল করা যাতে রুটগুলো লোড হওয়ার সময় পায়
      Future.delayed(const Duration(milliseconds: 500), () {
        _routeFromMessage(context, initialMessage.data);
      });
    }

    // ডিভাইস টোকেন ডাটাবেজে সেভ করা (non-blocking — won't crash profile load)
    saveDeviceToken().catchError((e) {
      debugPrint('[FCM] saveDeviceToken failed (non-blocking): $e');
    });
  }

  /// লোকাল নোটিফিকেশন পপ-আপ স্ক্রিনে দেখানোর মেথড
  static void _showLocalNotification(RemoteMessage message, FlutterLocalNotificationsPlugin plugin) {
    final notification = message.notification;
    if (notification == null) return;

    // মেসেজের ডাটা অনুযায়ী সঠিক চ্যানেল সিলেক্ট করা
    final type = message.data['type'] ?? 'notice';
    final channel = (type == 'exam' || type == 'reminder') ? _kReminderChannel : _kNoticeChannel;

    plugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          icon: '@mipmap/ic_launcher',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      payload: type,
    );
  }

  /// নোটিফিকেশন ক্লিক করলে অ্যাপের কোন পেজে যাবে (Centralised Navigation Logic)
  void _routeFromMessage(BuildContext context, Map<String, dynamic> data) {
    final String type = data['type'] ?? 'notice';
    
    if (type == 'notice') {
      Navigator.of(context).pushNamed('/notices');
    } else if (type == 'note') {
      Navigator.of(context).pushNamed('/notes');
    } else if (type == 'exam') {
      Navigator.of(context).pushNamed('/exams');
    }
  }

  /// ইউজারের FCM Token সুপাবেজ ডাটাবেজে সেভ করে রাখার মেথড
  Future<void> saveDeviceToken() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    String? token;
    try {
      token = await _fcm.getToken().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[FCM] getToken() timed out in release build');
          return null;
        },
      );
    } catch (e) {
      debugPrint('[FCM] getToken() failed: $e');
      token = null;
    }

    // Guard: skip DB write entirely if token is null or empty
    if (token == null || token.trim().isEmpty) {
      debugPrint('[FCM] Token is null/empty — skipping device_tokens upsert');
      return;
    }

    try {
      await SupabaseService.upsertDeviceToken({
        'user_id': user.id,
        'token': token.trim(),
        'device_token': token.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      debugPrint('[FCM] Device token saved successfully');
    } catch (e) {
      debugPrint('[FCM] Unexpected error during token save: $e');
    }
  }

  /// ⏰ নির্দিষ্ট সময়ে রিমাইন্ডার শিডিউল করার মেথড
  Future<void> scheduleNotification(
    int id,
    String title,
    String body,
    DateTime scheduledDate, {
    bool repeatWeekly = false,
  }) async {
    try {
      await _localNotifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledDate, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _kReminderChannel.id,
            _kReminderChannel.name,
            channelDescription: _kReminderChannel.description,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents:
            repeatWeekly ? DateTimeComponents.dayOfWeekAndTime : null,
      );
    } catch (e) {
      // Fallback: if exact alarms are denied, use inexact scheduling
      debugPrint('[Notif] Exact alarm failed, trying inexact: $e');
      await _localNotifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledDate, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _kReminderChannel.id,
            _kReminderChannel.name,
            channelDescription: _kReminderChannel.description,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents:
            repeatWeekly ? DateTimeComponents.dayOfWeekAndTime : null,
      );
    }
  }

  /// ❌ আইডি অনুযায়ী শিডিউল করা নোটিফিকেশন বাতিল করার মেথড
  Future<void> cancelNotification(int id) async {
    await _localNotifications.cancel(id);
  }

  /// 🎓 বিগিনারের নোটিফিকেশন টেস্ট করার জন্য সবচেয়ে প্রয়োজনীয় হেল্পার
  /// ভিএস কোডের ডিবাগ কনসোলে টোকেন প্রিন্ট করার জন্য এটি কল করবেন
  Future<void> printToken() async {
    try {
      final token = await _fcm.getToken();
      debugPrint('====================================================');
      debugPrint('FCM Token: $token');
      debugPrint('====================================================');
    } catch (e) {
      debugPrint('[FCM] printToken failed: $e');
    }
  }
}