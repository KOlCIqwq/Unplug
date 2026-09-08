import 'package:flutter/material.dart';
import '../models/alarm_item.dart';
import '../services/alarm_service.dart';

class AlarmsScreen extends StatefulWidget {
  const AlarmsScreen({super.key});

  @override
  State<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends State<AlarmsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Alarms',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Test Alarm (Goes off immediately)',
            onPressed: () {
              AlarmService.testAlarmNow(title: 'Quick Test Alarm');
            },
          ),
        ],
        elevation: 0,
      ),
      body: ValueListenableBuilder<List<AlarmItem>>(
        valueListenable: AlarmService.alarmsNotifier,
        builder: (context, alarms, _) {
          final enabledAlarms = alarms.where((a) => a.isEnabled).toList();
          AlarmItem? nextAlarm;
          if (enabledAlarms.isNotEmpty) {
            enabledAlarms.sort((a, b) =>
                a.nextTriggerDateTime.compareTo(b.nextTriggerDateTime));
            nextAlarm = enabledAlarms.first;
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
            children: [
              // Next upcoming alarm card
              Card(
                color: nextAlarm != null
                    ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                    : colorScheme.surfaceContainerHighest,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: nextAlarm != null
                      ? BorderSide(color: colorScheme.primary.withValues(alpha: 0.3))
                      : BorderSide.none,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: nextAlarm != null
                              ? colorScheme.primary.withValues(alpha: 0.2)
                              : colorScheme.outline.withValues(alpha: 0.15),
                        ),
                        child: Icon(
                          nextAlarm != null
                              ? Icons.alarm_on_rounded
                              : Icons.alarm_off_rounded,
                          color: nextAlarm != null
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nextAlarm != null
                                  ? 'NEXT ALARM ${nextAlarm.timeUntilNext.toUpperCase()}'
                                  : 'NO ACTIVE ALARMS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                                color: nextAlarm != null
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              nextAlarm != null
                                  ? '${nextAlarm.formattedTimeAmPm} • ${nextAlarm.title}'
                                  : 'Tap + below to set an alarm',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Section title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your Alarms',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    '${alarms.length} ${alarms.length == 1 ? 'alarm' : 'alarms'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (alarms.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48.0),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.alarm_add_rounded,
                          size: 56,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No alarms configured yet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Set an alarm for focus sessions, waking up, or screen breaks.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () => _openAlarmEditor(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Create an Alarm'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...alarms.map((alarm) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Card(
                      color: colorScheme.surfaceContainerHighest,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: InkWell(
                        onTap: () => _openAlarmEditor(context, existing: alarm),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18.0, vertical: 14.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          alarm.formattedTimeAmPm.split(' ')[0],
                                          style: TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.w800,
                                            color: alarm.isEnabled
                                                ? colorScheme.onSurface
                                                : colorScheme.onSurfaceVariant
                                                    .withValues(alpha: 0.5),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          alarm.formattedTimeAmPm.split(' ').length > 1
                                              ? alarm.formattedTimeAmPm.split(' ')[1]
                                              : '',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: alarm.isEnabled
                                                ? colorScheme.primary
                                                : colorScheme.onSurfaceVariant
                                                    .withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          alarm.title,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: alarm.isEnabled
                                                ? colorScheme.onSurface
                                                : colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '•  ${alarm.repeatSummary}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (alarm.isEnabled) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Rings ${alarm.timeUntilNext}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                color: colorScheme.onSurfaceVariant,
                                tooltip: 'Delete Alarm',
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete Alarm'),
                                      content: Text(
                                          'Are you sure you want to delete "${alarm.title}"?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          style: TextButton.styleFrom(
                                              foregroundColor: Colors.redAccent),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await AlarmService.deleteAlarm(alarm.id);
                                  }
                                },
                              ),
                              Switch(
                                value: alarm.isEnabled,
                                activeTrackColor: colorScheme.primary,
                                onChanged: (val) {
                                  AlarmService.toggleAlarm(alarm.id, val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAlarmEditor(context),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('New Alarm'),
      ),
    );
  }

  void _openAlarmEditor(BuildContext context, {AlarmItem? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AlarmEditorSheet(existing: existing),
    );
  }
}

class _AlarmEditorSheet extends StatefulWidget {
  final AlarmItem? existing;

  const _AlarmEditorSheet({this.existing});

  @override
  State<_AlarmEditorSheet> createState() => _AlarmEditorSheetState();
}

class _AlarmEditorSheetState extends State<_AlarmEditorSheet> {
  late TextEditingController _titleController;
  late TimeOfDay _selectedTime;
  late List<int> _selectedDays;
  late bool _vibrate;
  late bool _sound;

  final List<String> _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _titleController = TextEditingController(text: ex?.title ?? '');
    _selectedTime = ex != null
        ? TimeOfDay(hour: ex.hour, minute: ex.minute)
        : TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 30)));
    _selectedDays = ex != null ? List<int>.from(ex.daysOfWeek) : [];
    _vibrate = ex?.vibrate ?? true;
    _sound = ex?.sound ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _setPreset(int minutesFromNow) {
    final target = DateTime.now().add(Duration(minutes: minutesFromNow));
    setState(() {
      _selectedTime = TimeOfDay(hour: target.hour, minute: target.minute);
      _selectedDays = [];
    });
  }

  void _save() async {
    final title = _titleController.text.trim().isEmpty
        ? 'Alarm'
        : _titleController.text.trim();

    if (widget.existing != null) {
      final updated = widget.existing!.copyWith(
        title: title,
        hour: _selectedTime.hour,
        minute: _selectedTime.minute,
        daysOfWeek: _selectedDays,
        vibrate: _vibrate,
        sound: _sound,
        isEnabled: true,
      );
      await AlarmService.updateAlarm(updated);
    } else {
      await AlarmService.addAlarm(
        title: title,
        hour: _selectedTime.hour,
        minute: _selectedTime.minute,
        daysOfWeek: _selectedDays,
        vibrate: _vibrate,
        sound: _sound,
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final String hStr = _selectedTime.hour.toString().padLeft(2, '0');
    final String mStr = _selectedTime.minute.toString().padLeft(2, '0');
    final int h12 = _selectedTime.hour == 0
        ? 12
        : (_selectedTime.hour > 12 ? _selectedTime.hour - 12 : _selectedTime.hour);
    final String amPm = _selectedTime.hour >= 12 ? 'PM' : 'AM';

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            widget.existing != null ? 'Edit Alarm' : 'Set New Alarm',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 18),

          // Time Picker Display
          InkWell(
            onTap: _pickTime,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$h12:$mStr',
                        style: TextStyle(
                          fontSize: 54,
                          fontWeight: FontWeight.w900,
                          color: colorScheme.primary,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        amPm,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit, size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        'Tap to change time ($hStr:$mStr)',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Quick presets
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(
                  label: const Text('+15 min'),
                  onPressed: () => _setPreset(15),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: const Text('+30 min'),
                  onPressed: () => _setPreset(30),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: const Text('+45 min'),
                  onPressed: () => _setPreset(45),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: const Text('+1 hour'),
                  onPressed: () => _setPreset(60),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Title / Label input
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Alarm Label / Purpose',
              hintText: 'e.g. Wake up, Break time, Deep work done',
              prefixIcon: const Icon(Icons.label_outline),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Days of week repeat
          Text(
            'Repeat Days',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final dayIndex = index + 1; // 1 = Mon, 7 = Sun
              final isSelected = _selectedDays.contains(dayIndex);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedDays.remove(dayIndex);
                    } else {
                      _selectedDays.add(dayIndex);
                    }
                  });
                },
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    _dayNames[index].substring(0, 1),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isSelected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            _selectedDays.isEmpty
                ? 'Rings once (today or tomorrow)'
                : _selectedDays.length == 7
                    ? 'Rings every day'
                    : 'Rings on selected days',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 18),

          // Sound & Vibrate options
          SwitchListTile(
            title: const Text('Sound', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Play alarm ringtone when it goes off'),
            value: _sound,
            activeTrackColor: colorScheme.primary,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _sound = v),
          ),
          SwitchListTile(
            title: const Text('Vibrate', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Vibrate phone when alarm fires'),
            value: _vibrate,
            activeTrackColor: colorScheme.primary,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _vibrate = v),
          ),

          const SizedBox(height: 18),

          // Save button
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              widget.existing != null ? 'Update Alarm' : 'Set Alarm',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
