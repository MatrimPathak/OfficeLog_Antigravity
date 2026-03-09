import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../providers/providers.dart';
import '../../services/admin_service.dart';
import '../../data/models/holiday.dart';
import '../../data/models/user_profile.dart';
import '../admin/widgets/add_holiday_dialog.dart';

class PersonalHolidaysScreen extends ConsumerStatefulWidget {
  const PersonalHolidaysScreen({super.key});

  @override
  ConsumerState<PersonalHolidaysScreen> createState() =>
      _PersonalHolidaysScreenState();
}

class _PersonalHolidaysScreenState
    extends ConsumerState<PersonalHolidaysScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Set<String>? _selectedHolidays;
  int? _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _savePreferences({bool popOnSuccess = true}) async {
    if (_selectedHolidays == null) return;

    final user = ref.read(currentUserProvider);
    if (user != null) {
      if (popOnSuccess) {
        // Show loading only for explicit saves
        FocusScope.of(context).unfocus();
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        );
      }

      try {
        await ref
            .read(authServiceProvider)
            .updateUserSelectedHolidays(user.uid, _selectedHolidays!.toList());

        if (mounted) {
          if (popOnSuccess) {
            Navigator.pop(context); // Dismiss loading
            Navigator.pop(context); // Go back
            AppTheme.showSuccessSnackBar(context, 'Holiday preferences saved');
          }
        }
      } catch (e) {
        if (mounted) {
          if (popOnSuccess) {
            Navigator.pop(context); // Dismiss loading
          }
          AppTheme.showErrorSnackBar(context, 'Failed to save preferences: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProfileAsync = ref.watch(userProfileProvider);
    final holidaysAsync = ref.watch(sortedHolidaysProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text('Personal Holidays'),
        centerTitle: true,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (userProfileAsync.value != null && holidaysAsync.value != null)
            TextButton(
              onPressed: _savePreferences,
              child: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
        ],
      ),
      body: userProfileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('User profile not found.'));
          }

          return holidaysAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Error: $error')),
            data: (allHolidays) {
              if (allHolidays.isEmpty) {
                return const Center(child: Text('No holidays available.'));
              }

              // Extract unique years from all holidays
              final Set<int> availableYears = {DateTime.now().year};
              for (final holiday in allHolidays) {
                availableYears.add(holiday.date.year);
              }
              final List<int> sortedYears = availableYears.toList()
                ..sort((a, b) => b.compareTo(a));

              // Initialize selection on first load
              if (_selectedHolidays == null) {
                if (profile.selectedHolidays != null) {
                  _selectedHolidays = profile.selectedHolidays!.toSet();
                } else {
                  // If null, user hasn't saved preferences so select NO holidays by default
                  _selectedHolidays = {};
                }
              }

              final filteredHolidays = allHolidays.where((holiday) {
                // Year filter
                final matchesYear =
                    _selectedYear == null ||
                    holiday.date.year == _selectedYear ||
                    holiday.isRecurring;
                if (!matchesYear) return false;

                // Search query filter
                if (_searchQuery.isEmpty) return true;

                final matchesName = holiday.name.toLowerCase().contains(
                  _searchQuery,
                );
                final formattedDate = DateFormat.yMMMd()
                    .format(holiday.date)
                    .toLowerCase();
                final matchesDate = formattedDate.contains(_searchQuery);
                return matchesName || matchesDate;
              }).toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search holidays...',
                              hintStyle: TextStyle(
                                color: Colors.grey.withValues(alpha: 0.6),
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Theme.of(context).cardTheme.color,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 0,
                                horizontal: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 100,
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: DropdownButtonFormField<int?>(
                            value: _selectedYear,
                            isExpanded: true,
                            dropdownColor: Theme.of(context).cardTheme.color,
                            icon: const Icon(Icons.filter_list, size: 20),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text(
                                  'All',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                              ...sortedYears.map((year) {
                                return DropdownMenuItem<int?>(
                                  value: year,
                                  child: Text(
                                    year.toString(),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                );
                              }),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedYear = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filteredHolidays.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 64,
                                  color: Colors.grey.withValues(alpha: 0.3),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No holidays found',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredHolidays.length,
                            itemBuilder: (context, index) {
                              final holiday = filteredHolidays[index];
                              final isSelected = _selectedHolidays!.contains(
                                holiday.id,
                              );

                              final dateString = DateFormat.yMMMd().format(
                                holiday.date,
                              );

                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardTheme.color,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: CheckboxListTile(
                                  value: isSelected,
                                  onChanged: (bool? value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedHolidays!.add(holiday.id);
                                      } else {
                                        _selectedHolidays!.remove(holiday.id);
                                      }
                                    });
                                  },
                                  title: Text(
                                    holiday.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '$dateString${holiday.isRecurring ? ' • Recurring' : ''}',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                  secondary: holiday.id.startsWith('custom_')
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () => _deleteCustomHoliday(
                                            context,
                                            profile,
                                            holiday,
                                          ),
                                        )
                                      : null,
                                  activeColor: AppTheme.primaryColor,
                                  checkColor: Colors.white,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: userProfileAsync.value != null
          ? FloatingActionButton.extended(
              onPressed: () =>
                  _showAddCustomHolidayDialog(context, userProfileAsync.value!),
              backgroundColor: AppTheme.primaryColor,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Custom',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  void _showAddCustomHolidayDialog(BuildContext context, UserProfile profile) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AddHolidayDialog(
          ref: ref,
          isCustomHoliday: true,
          onSave: (name, date, isRecurring, offices) async {
            final newHoliday = Holiday(
              id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
              name: name.trim(),
              date: date,
              isRecurring: isRecurring,
              officeLocations:
                  [], // Custom holidays apply globally for the user
            );

            try {
              await ref
                  .read(authServiceProvider)
                  .addCustomHoliday(profile.id, newHoliday);
              if (!context.mounted) return;
              AppTheme.showSuccessSnackBar(context, 'Custom holiday added');
              // Automatically select the new holiday locally
              setState(() {
                _selectedHolidays?.add(newHoliday.id);
              });
              // No auto-save here, user must click AppBar Save button
            } catch (e) {
              if (!context.mounted) return;
              AppTheme.showErrorSnackBar(context, 'Error adding holiday: $e');
            }
          },
        );
      },
    );
  }

  Future<void> _deleteCustomHoliday(
    BuildContext context,
    UserProfile profile,
    Holiday holiday,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardTheme.color,
        title: Text(
          'Delete Holiday',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Text(
          'Remove "${holiday.name}" from your custom holidays?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref
          .read(authServiceProvider)
          .deleteCustomHoliday(profile.id, holiday);
      if (!context.mounted) return;
      setState(() {
        _selectedHolidays?.remove(holiday.id);
      });
      // No auto-save here, user hit delete but needs to save preference if they want it reflected in calendar
      AppTheme.showSuccessSnackBar(context, 'Holiday deleted.');
    } catch (e) {
      if (context.mounted) {
        AppTheme.showErrorSnackBar(context, 'Error deleting holiday: $e');
      }
    }
  }
}
