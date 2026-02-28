import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/feedback_service.dart';

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({super.key});

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  int _rating = 0;
  final _messageController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      AppTheme.showWarningSnackBar(context, 'Please select a star rating');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      await FeedbackService().submitFeedback(
        userId: user.uid,
        userName: user.displayName ?? 'Anonymous',
        userEmail: user.email ?? 'No email',
        rating: _rating,
        message: _messageController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context);
      AppTheme.showSuccessSnackBar(context, 'Thank you for your feedback!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      AppTheme.showErrorSnackBar(context, 'Failed to send feedback: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Send Feedback',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close,
                    color: isDark
                        ? AppTheme.textSecondaryDark
                        : AppTheme.textSecondaryLight,
                  ),
                ),
              ],
            ),

            Divider(color: Theme.of(context).dividerColor),
            const SizedBox(height: 16),

            // Star rating label
            Text(
              'How would you rate your experience?',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),

            // Star rating row
            Row(
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                return GestureDetector(
                  onTap: () => setState(() => _rating = starIndex),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      starIndex <= _rating ? Icons.star : Icons.star_border,
                      color: starIndex <= _rating
                          ? AppTheme.primaryColor
                          : (isDark
                                ? AppTheme.textSecondaryDark
                                : AppTheme.textSecondaryLight),
                      size: 36,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),

            // Message label
            Text(
              'Your Message',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),

            // Text field
            TextField(
              controller: _messageController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText:
                    'Tell us how we can improve your office attendance experience...',
                hintStyle: TextStyle(
                  color: isDark
                      ? AppTheme.disabledTextDark
                      : AppTheme.disabledTextLight,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: isDark
                    ? AppTheme.scaffoldBgDark
                    : AppTheme.scaffoldBgLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.primaryColor.withValues(
                    alpha: 0.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit Feedback',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),

            // Footer text
            Center(
              child: Text(
                'Your feedback helps us build a better workplace\nenvironment. Thank you for sharing!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppTheme.textSecondaryDark
                      : AppTheme.textSecondaryLight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
