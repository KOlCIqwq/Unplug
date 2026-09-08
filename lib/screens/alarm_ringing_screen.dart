import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/alarm_item.dart';
import '../services/alarm_service.dart';

class AlarmRingingScreen extends StatefulWidget {
  final AlarmItem alarm;

  const AlarmRingingScreen({
    super.key,
    required this.alarm,
  });

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _pulseAnimation;
  Timer? _vibrateTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    // Periodic haptics
    _vibrateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _vibrateTimer?.cancel();
    super.dispose();
  }

  void _dismiss() async {
    _vibrateTimer?.cancel();
    await AlarmService.dismissAlarm(widget.alarm.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _snooze() async {
    _vibrateTimer?.cancel();
    await AlarmService.snoozeAlarm(widget.alarm.id, snoozeMinutes: 5);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final hStr = now.hour.toString().padLeft(2, '0');
    final mStr = now.minute.toString().padLeft(2, '0');

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top header
                Column(
                  children: [
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.alarm, color: colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'ALARM RINGING',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '$hStr:$mStr',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.0,
                            color: colorScheme.primary,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.alarm.title.isNotEmpty ? widget.alarm.title : 'Alarm',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                    ),
                  ],
                ),

                // Center animated bell
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primaryContainer,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.35),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.alarm_on_rounded,
                      size: 72,
                      color: colorScheme.primary,
                    ),
                  ),
                ),

                // Bottom action buttons
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Snooze button
                    OutlinedButton.icon(
                      onPressed: _snooze,
                      icon: const Icon(Icons.snooze_rounded),
                      label: const Text(
                        'Snooze (+5 min)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5), width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Dismiss button
                    ElevatedButton.icon(
                      onPressed: _dismiss,
                      icon: const Icon(Icons.stop_rounded, size: 28),
                      label: const Text(
                        'Dismiss Alarm',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
