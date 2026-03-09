import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';

class AppTimePicker extends StatefulWidget {
  final TimeOfDay initialTime;
  final String? title;

  const AppTimePicker({super.key, required this.initialTime, this.title});

  static Future<TimeOfDay?> show({
    required BuildContext context,
    required TimeOfDay initialTime,
    String? title,
  }) {
    return showDialog<TimeOfDay>(
      context: context,
      builder: (context) =>
          AppTimePicker(initialTime: initialTime, title: title),
    );
  }

  @override
  State<AppTimePicker> createState() => _AppTimePickerState();
}

class _AppTimePickerState extends State<AppTimePicker> {
  late int selectedHour;
  late int selectedMinute;
  late bool isPm;

  @override
  void initState() {
    super.initState();
    selectedHour = widget.initialTime.hourOfPeriod == 0
        ? 12
        : widget.initialTime.hourOfPeriod;
    selectedMinute = widget.initialTime.minute;
    isPm = widget.initialTime.period == DayPeriod.pm;
  }

  void _vibrate() {
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black.withOpacity(0.2)
                  : Colors.grey[100]!,
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.title != null) ...[
              Text(
                widget.title!,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Picker Wheels
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.2)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Selection Highlight
                  Container(
                    height: 45,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Hours
                      _buildPickerWheel(
                        count: 12,
                        initialValue: selectedHour - 1,
                        onChanged: (index) {
                          setState(() => selectedHour = index + 1);
                          _vibrate();
                        },
                        itemBuilder: (context, index) =>
                            _buildItem('${index + 1}'),
                      ),

                      const Text(
                        ':',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      // Minutes
                      _buildPickerWheel(
                        count: 60,
                        initialValue: selectedMinute,
                        onChanged: (index) {
                          setState(() => selectedMinute = index);
                          _vibrate();
                        },
                        itemBuilder: (context, index) =>
                            _buildItem(index.toString().padLeft(2, '0')),
                      ),

                      const SizedBox(width: 8),

                      // AM/PM
                      _buildPickerWheel(
                        count: 2,
                        initialValue: isPm ? 1 : 0,
                        onChanged: (index) {
                          setState(() => isPm = index == 1);
                          _vibrate();
                        },
                        itemBuilder: (context, index) =>
                            _buildItem(index == 0 ? 'AM' : 'PM'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Actions
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      int hour = selectedHour;
                      if (isPm && hour < 12) hour += 12;
                      if (!isPm && hour == 12) hour = 0;
                      Navigator.pop(
                        context,
                        TimeOfDay(hour: hour, minute: selectedMinute),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerWheel({
    required int count,
    required int initialValue,
    required ValueChanged<int> onChanged,
    required IndexedWidgetBuilder itemBuilder,
  }) {
    return SizedBox(
      width: 60,
      child: CupertinoPicker.builder(
        itemExtent: 45,
        scrollController: FixedExtentScrollController(
          initialItem: initialValue,
        ),
        onSelectedItemChanged: onChanged,
        childCount: count,
        itemBuilder: itemBuilder,
        selectionOverlay: const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildItem(String text) {
    return Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
