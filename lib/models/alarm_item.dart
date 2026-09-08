class AlarmItem {
  final String id;
  String title;
  int hour;
  int minute;
  bool isEnabled;
  List<int> daysOfWeek; // 1 = Monday, 7 = Sunday; empty = one-time
  bool vibrate;
  bool sound;
  DateTime createdAt;
  DateTime? lastTriggered;

  AlarmItem({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    this.isEnabled = true,
    List<int>? daysOfWeek,
    this.vibrate = true,
    this.sound = true,
    DateTime? createdAt,
    this.lastTriggered,
  })  : daysOfWeek = daysOfWeek ?? [],
        createdAt = createdAt ?? DateTime.now();

  String get formattedTime {
    final String hStr = hour.toString().padLeft(2, '0');
    final String mStr = minute.toString().padLeft(2, '0');
    return '$hStr:$mStr';
  }

  String get formattedTimeAmPm {
    final int h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final String amPm = hour >= 12 ? 'PM' : 'AM';
    final String mStr = minute.toString().padLeft(2, '0');
    return '$h12:$mStr $amPm';
  }

  String get repeatSummary {
    if (daysOfWeek.isEmpty) return 'Once';
    if (daysOfWeek.length == 7) return 'Every day';
    final sorted = List<int>.from(daysOfWeek)..sort();
    if (sorted.length == 5 && listEquals(sorted, [1, 2, 3, 4, 5])) {
      return 'Weekdays';
    }
    if (sorted.length == 2 && listEquals(sorted, [6, 7])) {
      return 'Weekends';
    }

    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return sorted.map((d) => dayNames[(d - 1).clamp(0, 6)]).join(', ');
  }

  static bool listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  DateTime get nextTriggerDateTime {
    final now = DateTime.now();
    if (daysOfWeek.isEmpty) {
      DateTime candidate = DateTime(now.year, now.month, now.day, hour, minute);
      if (candidate.isBefore(now) || candidate.isAtSameMomentAs(now)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      return candidate;
    } else {
      for (int i = 0; i < 8; i++) {
        final day = now.add(Duration(days: i));
        if (daysOfWeek.contains(day.weekday)) {
          final candidate = DateTime(day.year, day.month, day.day, hour, minute);
          if (candidate.isAfter(now)) {
            return candidate;
          }
        }
      }
      // Fallback
      return DateTime(now.year, now.month, now.day, hour, minute).add(const Duration(days: 1));
    }
  }

  String get timeUntilNext {
    final now = DateTime.now();
    final next = nextTriggerDateTime;
    final diff = next.difference(now);

    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;

    if (hours == 0 && minutes <= 1) {
      return 'in less than a minute';
    }
    if (hours == 0) {
      return 'in ${minutes}m';
    }
    if (minutes == 0) {
      return 'in ${hours}h';
    }
    return 'in ${hours}h ${minutes}m';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'hour': hour,
      'minute': minute,
      'isEnabled': isEnabled,
      'daysOfWeek': daysOfWeek,
      'vibrate': vibrate,
      'sound': sound,
      'createdAt': createdAt.toIso8601String(),
      'lastTriggered': lastTriggered?.toIso8601String(),
    };
  }

  factory AlarmItem.fromJson(Map<String, dynamic> json) {
    return AlarmItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Alarm',
      hour: (json['hour'] as num?)?.toInt() ?? 8,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      isEnabled: json['isEnabled'] as bool? ?? true,
      daysOfWeek: (json['daysOfWeek'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      vibrate: json['vibrate'] as bool? ?? true,
      sound: json['sound'] as bool? ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastTriggered: json['lastTriggered'] != null
          ? DateTime.tryParse(json['lastTriggered'] as String)
          : null,
    );
  }

  AlarmItem copyWith({
    String? id,
    String? title,
    int? hour,
    int? minute,
    bool? isEnabled,
    List<int>? daysOfWeek,
    bool? vibrate,
    bool? sound,
    DateTime? createdAt,
    DateTime? lastTriggered,
  }) {
    return AlarmItem(
      id: id ?? this.id,
      title: title ?? this.title,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      isEnabled: isEnabled ?? this.isEnabled,
      daysOfWeek: daysOfWeek ?? List<int>.from(this.daysOfWeek),
      vibrate: vibrate ?? this.vibrate,
      sound: sound ?? this.sound,
      createdAt: createdAt ?? this.createdAt,
      lastTriggered: lastTriggered ?? this.lastTriggered,
    );
  }
}
