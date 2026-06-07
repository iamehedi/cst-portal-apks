import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/theme_provider.dart';

class UpdateService {
  /// Automatic check on startup — fails silently if anything goes wrong.
  static Future<void> checkForUpdate(BuildContext context) async {
    // Firebase Remote Config is not available on web — skip silently
    if (kIsWeb) return;
    try {
      final updateUrl = await _fetchAndCompare();
      if (updateUrl != null && context.mounted) {
        _showUpdateDialog(context, updateUrl);
      }
    } catch (e) {
      debugPrint('[UpdateService] Skipped: $e');
    }
  }

  /// Manual check from profile screen — shows a snackbar for both cases.
  static Future<void> checkForUpdateManually(BuildContext context) async {
    if (kIsWeb) {
      if (context.mounted) {
        _showSnackBar(context, 'Updates are not available on web.', isError: false);
      }
      return;
    }
    try {
      final updateUrl = await _fetchAndCompare();
      if (!context.mounted) return;

      if (updateUrl != null) {
        _showUpdateDialog(context, updateUrl);
      } else {
        _showSnackBar(context, 'You are on the latest version!');
      }
    } catch (e) {
      if (context.mounted) {
        _showSnackBar(context, 'Could not check for updates. Try again later.', isError: true);
      }
    }
  }

  /// Returns the update URL if a newer version is available, null otherwise.
  static Future<String?> _fetchAndCompare() async {
    final results = await Future.wait([
      _fetchRemoteConfig(),
      PackageInfo.fromPlatform(),
      _deviceAbi(),
    ]);

    final remoteConfig = results[0] as Map<String, dynamic>;
    final packageInfo = results[1] as PackageInfo;
    final abi = results[2] as String;

    final latestVersion = remoteConfig['latest_version'] as int;
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

    if (latestVersion <= currentBuild) return null;

    // Pick the best URL for this device's ABI, fallback to universal
    final updateUrl = _pickUrl(remoteConfig, abi);
    return updateUrl.isNotEmpty ? updateUrl : null;
  }

  /// Picks the architecture-specific URL, falling back to universal.
  static String _pickUrl(Map<String, dynamic> config, String abi) {
    switch (abi) {
      case 'arm64-v8a':
        return (config['update_url_arm64_v8a'] as String).isNotEmpty
            ? config['update_url_arm64_v8a'] as String
            : config['update_url'] as String;
      case 'armeabi-v7a':
        return (config['update_url_armeabi_v7a'] as String).isNotEmpty
            ? config['update_url_armeabi_v7a'] as String
            : config['update_url'] as String;
      case 'x86_64':
        return (config['update_url_x86_64'] as String).isNotEmpty
            ? config['update_url_x86_64'] as String
            : config['update_url'] as String;
      default:
        return config['update_url'] as String;
    }
  }

  /// Detects the device's primary ABI using device_info_plus.
  static Future<String> _deviceAbi() async {
    if (kIsWeb) return 'unknown';
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      // supportedAbis is ordered by preference (most preferred first)
      final abis = androidInfo.supportedAbis;
      if (abis != null && abis.isNotEmpty) {
        final abi = abis.first;
        debugPrint('[UpdateService] Device ABIs: $abis, selected: $abi');
        return abi;
      }
    } catch (e) {
      debugPrint('[UpdateService] ABI detection failed: $e');
    }
    return 'unknown';
  }

  /// Fetches and activates Remote Config, returning all required values.
  static Future<Map<String, dynamic>> _fetchRemoteConfig() async {
    final remoteConfig = FirebaseRemoteConfig.instance;

    await remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: Duration.zero,
    ));

    await remoteConfig.setDefaults(const {
      'latest_version': 0,
      'update_url': '',
      'update_url_arm64_v8a': '',
      'update_url_armeabi_v7a': '',
      'update_url_x86_64': '',
    });

    await remoteConfig.fetchAndActivate();

    return {
      'latest_version': remoteConfig.getInt('latest_version'),
      'update_url': remoteConfig.getString('update_url'),
      'update_url_arm64_v8a': remoteConfig.getString('update_url_arm64_v8a'),
      'update_url_armeabi_v7a': remoteConfig.getString('update_url_armeabi_v7a'),
      'update_url_x86_64': remoteConfig.getString('update_url_x86_64'),
    };
  }

  static void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    final c = context.colorsOf;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: c.white)),
      backgroundColor: isError ? c.danger : c.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  static void _showUpdateDialog(BuildContext context, String updateUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.system_update_rounded,
              color: Theme.of(ctx).colorScheme.primary,
              size: 28,
            ),
          ),
          title: const Text('Update Available!', style: TextStyle(color: Colors.white)),
          content: const Text(
            'A newer version of CST Portal is available with improvements and bug fixes. '
            'Please update to the latest version for the best experience.',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                launchUrl(
                  Uri.parse(updateUrl),
                  mode: LaunchMode.externalApplication,
                );
              },
              child: const Text('Update Now'),
            ),
          ],
        );
      },
    );
  }
}
