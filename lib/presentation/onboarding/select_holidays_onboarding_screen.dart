import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../providers/providers.dart';
import '../../services/admin_service.dart';
import '../../data/models/holiday.dart';
import '../../data/models/user_profile.dart';
import '../admin/widgets/add_holiday_dialog.dart';

class SelectHolidaysOnboardingScreen extends ConsumerStatefulWidget {
  const SelectHolidaysOnboardingScreen({super.key});

  @override
  ConsumerState<SelectHolidaysOnboardingScreen> createState() =>
      _SelectHolidaysOnboardingScreenState();
}

class _SelectHolidaysOnboardingScreenState
    extends ConsumerState<SelectHolidaysOnboardingScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedHolidays = {}; // Start empty!
  final int _currentYear = DateTime.now().year;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
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

  Future<void> _saveAndContinue() async {
    final user = ref.read(currentUserProvider);
    if (user != null) {
      setState(() => _isLoading = true);
      try {
        await ref
            .read(authServiceProvider)
            .updateUserSelectedHolidays(user.uid, _selectedHolidays.toList());
        // main.dart will rebuild and navigate to the next step
      } catch (e) {
        if (mounted) {
          AppTheme.showErrorSnackBar(context, 'Failed to save holidays: $e');
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
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
        automaticallyImplyLeading: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text('Select Your Holidays'),
        centerTitle: true,
        scrolledUnderElevation: 0,
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
              final filteredHolidays = allHolidays.where((holiday) {
                // Year filter (Current year only for onboarding)
                final matchesYear =
                    holiday.date.year == _currentYear || holiday.isRecurring;
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select the holidays you observe for $_currentYear. You can add custom ones using the + button.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
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
                                const Text(
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
                              final isSelected = _selectedHolidays.contains(
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
                                        _selectedHolidays.add(holiday.id);
                                      } else {
                                        _selectedHolidays.remove(holiday.id);
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
                  // Bottom container for the confirm button
                  Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 15,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: _isLoading
                              ? null
                              : LinearGradient(
                                  colors: [
                                    AppTheme.primaryColor,
                                    AppTheme.logGradientStart,
                                  ],
                                ),
                          borderRadius: BorderRadius.circular(16),
                          color: _isLoading ? Colors.grey : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _isLoading ? null : _saveAndContinue,
                            borderRadius: BorderRadius.circular(16),
                            child: Center(
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : const Text(
                                      'Confirm & Continue',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0), // Above bottom bar
        child: FloatingActionButton(
          onPressed: () {
            if (userProfileAsync.value != null) {
              _showAddCustomHolidayDialog(context, userProfileAsync.value!);
            }
          },
          backgroundColor: AppTheme.primaryColor,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
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
              officeLocations: [],
            );

            try {
              await ref
                  .read(authServiceProvider)
                  .addCustomHoliday(profile.id, newHoliday);
              if (!context.mounted) return;
              AppTheme.showSuccessSnackBar(context, 'Custom holiday added');
              setState(() {
                _selectedHolidays.add(newHoliday.id);
              });
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
        _selectedHolidays.remove(holiday.id);
      });
      AppTheme.showSuccessSnackBar(context, 'Holiday deleted.');
    } catch (e) {
      if (context.mounted) {
        AppTheme.showErrorSnackBar(context, 'Error deleting holiday: $e');
      }
    }
  }
}
