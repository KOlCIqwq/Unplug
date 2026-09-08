class FocusTask {
  final String id;
  String title;
  int estimatedMinutes;
  int spentMinutes;
  bool isCompleted;
  final DateTime createdAt;

  FocusTask({
    required this.id,
    required this.title,
    required this.estimatedMinutes,
    this.spentMinutes = 0,
    this.isCompleted = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  int get remainingMinutes => (estimatedMinutes - spentMinutes).clamp(0, estimatedMinutes);

  double get progress {
    if (estimatedMinutes <= 0) return 1.0;
    return (spentMinutes / estimatedMinutes).clamp(0.0, 1.0);
  }

  int get percentage => (progress * 100).round();

  bool get isFulfilled => spentMinutes >= estimatedMinutes;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'estimatedMinutes': estimatedMinutes,
      'spentMinutes': spentMinutes,
      'isCompleted': isCompleted,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory FocusTask.fromJson(Map<String, dynamic> json) {
    return FocusTask(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled Task',
      estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt() ?? 25,
      spentMinutes: (json['spentMinutes'] as num?)?.toInt() ?? 0,
      isCompleted: json['isCompleted'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  FocusTask copyWith({
    String? id,
    String? title,
    int? estimatedMinutes,
    int? spentMinutes,
    bool? isCompleted,
    DateTime? createdAt,
  }) {
    return FocusTask(
      id: id ?? this.id,
      title: title ?? this.title,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      spentMinutes: spentMinutes ?? this.spentMinutes,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
