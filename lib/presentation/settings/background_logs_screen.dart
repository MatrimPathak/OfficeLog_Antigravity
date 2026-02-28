import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class BackgroundLogsScreen extends StatelessWidget {
  const BackgroundLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Background Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              final box = await Hive.openBox<String>('background_logs');
              await box.clear();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Logs cleared')));
              }
            },
          ),
        ],
      ),
      body: FutureBuilder(
        future: Hive.openBox<String>('background_logs'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final box = snapshot.data as Box<String>;

          return ValueListenableBuilder(
            valueListenable: box.listenable(),
            builder: (context, Box<String> box, _) {
              if (box.isEmpty) {
                return const Center(child: Text('No background logs found.'));
              }

              final logs = box.values.toList().reversed.toList();

              return ListView.separated(
                itemCount: logs.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final log = logs[index];
                  final isError = log.contains('ERROR');

                  return ListTile(
                    leading: Icon(
                      isError ? Icons.error_outline : Icons.info_outline,
                      color: isError ? Colors.red : Colors.blue,
                    ),
                    title: Text(
                      log,
                      style: TextStyle(
                        fontSize: 12,
                        color: isError ? Colors.red[700] : null,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
