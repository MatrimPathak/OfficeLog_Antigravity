import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/office_location.dart';
import '../../../services/admin_service.dart';

class AddOfficeLocationDialog extends StatefulWidget {
  final WidgetRef ref;
  final OfficeLocation? location;

  const AddOfficeLocationDialog({super.key, required this.ref, this.location});

  @override
  State<AddOfficeLocationDialog> createState() =>
      _AddOfficeLocationDialogState();
}

class _AddOfficeLocationDialogState extends State<AddOfficeLocationDialog> {
  final nameController = TextEditingController();
  final addressController = TextEditingController();
  final latController = TextEditingController();
  final lngController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.location != null) {
      nameController.text = widget.location!.name;
      addressController.text = widget.location!.address;
      latController.text = widget.location!.latitude.toString();
      lngController.text = widget.location!.longitude.toString();
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    addressController.dispose();
    latController.dispose();
    lngController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.location == null
                    ? 'Add Office Location'
                    : 'Edit Office Location',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              _buildTextField(
                controller: nameController,
                label: 'Name',
                hint: 'e.g. Hyderabad Office',
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: addressController,
                label: 'Address',
                hint: 'e.g. Hitech City, Hyderabad',
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: latController,
                label: 'Latitude',
                hint: 'e.g. 17.437',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: lngController,
                label: 'Longitude',
                hint: 'e.g. 78.383',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 32),
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
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (nameController.text.isNotEmpty) {
                          final loc = OfficeLocation(
                            id:
                                widget.location?.id ??
                                DateTime.now().millisecondsSinceEpoch
                                    .toString(),
                            name: nameController.text,
                            address: addressController.text,
                            latitude: double.tryParse(latController.text) ?? 0,
                            longitude: double.tryParse(lngController.text) ?? 0,
                          );
                          if (widget.location == null) {
                            widget.ref
                                .read(adminServiceProvider)
                                .addOfficeLocation(loc);
                          } else {
                            widget.ref
                                .read(adminServiceProvider)
                                .updateOfficeLocation(loc);
                          }
                          Navigator.pop(context);
                        }
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
                      child: Text(widget.location == null ? 'Add' : 'Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1A2230)
                : Colors.grey[200],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
