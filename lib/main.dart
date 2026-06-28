import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const GodotLauncherApp());
}

class GodotLauncherApp extends StatelessWidget {
  const GodotLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Godot Launchpad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff1f8a70),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff6f7f2),
        textTheme: ThemeData.light().textTheme.apply(
              fontFamily: 'Arial',
              bodyColor: const Color(0xff17201c),
              displayColor: const Color(0xff17201c),
            ),
      ),
      home: const GodotLauncherScreen(),
    );
  }
}

class GodotLauncherScreen extends StatefulWidget {
  const GodotLauncherScreen({super.key});

  @override
  State<GodotLauncherScreen> createState() => _GodotLauncherScreenState();
}

class _GodotLauncherScreenState extends State<GodotLauncherScreen> {
  final GodotReleaseService _releaseService = GodotReleaseService();
  final TextEditingController _executableController = TextEditingController();
  final TextEditingController _argumentsController = TextEditingController();
  final TextEditingController _installPathController = TextEditingController();

  List<GodotRelease> _releases = const [];
  Map<String, String> _installedExecutables = const {};
  GodotRelease? _selectedRelease;
  bool _loading = true;
  bool _launching = false;
  bool _installing = false;
  double? _installProgress;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _installPathController.text = _defaultInstallPath;
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _executableController.dispose();
    _argumentsController.dispose();
    _installPathController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadSettings();
    await _loadReleases(autoInstallLatest: true);
  }

  Future<void> _loadSettings() async {
    try {
      final file = _settingsFile;
      if (!await file.exists()) return;

      final settings = jsonDecode(await file.readAsString());
      if (settings is! Map<String, dynamic>) return;

      final installPath = settings['installPath'];
      final executablePath = settings['executablePath'];
      final launchArguments = settings['launchArguments'];
      final installedExecutables = settings['installedExecutables'];

      if (!mounted) return;
      setState(() {
        if (installPath is String && installPath.trim().isNotEmpty) {
          _installPathController.text = installPath;
        }
        if (executablePath is String) {
          _executableController.text = executablePath;
        }
        if (launchArguments is String) {
          _argumentsController.text = launchArguments;
        }
        if (installedExecutables is Map) {
          _installedExecutables = installedExecutables.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          );
        }
      });
    } catch (_) {
      // Broken settings should not stop the launcher from opening.
    }
  }

  Future<void> _loadReleases({bool autoInstallLatest = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _status = 'Checking Godot releases...';
    });

    try {
      final releases = await _releaseService.fetchStableReleases();
      if (!mounted) return;

      setState(() {
        _releases = releases;
        _selectedRelease = releases.isEmpty ? null : releases.first;
        _loading = false;
        _status = releases.isEmpty
            ? 'No stable releases were returned by GitHub.'
            : 'Latest stable release: ${releases.first.version}';
      });
      _useInstalledExecutableForSelectedRelease();
      if (autoInstallLatest && releases.isNotEmpty) {
        unawaited(_ensureSelectedReleaseInstalled());
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Could not refresh releases: $error';
        _status = 'Release check failed.';
      });
    }
  }

  Future<void> _launchGodot() async {
    var executablePath = _executableController.text.trim();
    if (executablePath.isEmpty) {
      executablePath = await _ensureSelectedReleaseInstalled() ?? '';
      if (executablePath.isEmpty) {
        setState(() {
          _error = 'Godot could not be installed for this platform.';
        });
        return;
      }
    }

    setState(() {
      _launching = true;
      _error = null;
      _status = 'Launching Godot...';
    });

    try {
      final executable = _normalizeExecutablePath(executablePath);
      final args = _splitArguments(_argumentsController.text);
      await Process.start(executable, args, mode: ProcessStartMode.detached);
      await _saveSettings();
      if (!mounted) return;

      setState(() {
        _launching = false;
        _status =
            'Godot launched with ${_selectedRelease?.version ?? 'your selected install'}.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _launching = false;
        _error = 'Launch failed: $error';
        _status = 'Godot did not start.';
      });
    }
  }

  Future<String?> _ensureSelectedReleaseInstalled() async {
    final release = _selectedRelease;
    if (release == null) return null;

    final installedExecutable = _installedExecutables[release.version];
    if (installedExecutable != null && installedExecutable.trim().isNotEmpty) {
      _executableController.text = installedExecutable;
      return installedExecutable;
    }

    return _installSelectedRelease();
  }

  Future<String?> _installSelectedRelease() async {
    if (_installing) return null;

    final release = _selectedRelease;
    final asset = release?.assetForCurrentPlatform;
    if (release == null || asset == null || asset.downloadUrl.isEmpty) {
      setState(() {
        _error = 'No installable Godot download was found for this platform.';
      });
      return null;
    }

    final installRootPath = _installPathController.text.trim().isEmpty
        ? _defaultInstallPath
        : _installPathController.text.trim();
    _installPathController.text = installRootPath;

    setState(() {
      _installing = true;
      _installProgress = null;
      _error = null;
      _status = 'Preparing ${release.version} install...';
    });

    try {
      final installRoot = Directory(installRootPath);
      final releaseDirectory = Directory(
        _joinPaths(installRoot.path, _safePathSegment(release.version)),
      );
      await releaseDirectory.create(recursive: true);

      final existingExecutable =
          await _findGodotExecutable(releaseDirectory.path);
      if (existingExecutable != null) {
        await _rememberInstalledRelease(release.version, existingExecutable);
        if (!mounted) return existingExecutable;
        setState(() {
          _installing = false;
          _installProgress = 1;
          _status = '${release.version} is already installed.';
        });
        return existingExecutable;
      }

      final archivePath = await _downloadAsset(asset);
      if (!mounted) return null;
      setState(() {
        _installProgress = null;
        _status = 'Extracting ${release.version}...';
      });

      await _extractArchive(archivePath, releaseDirectory.path);

      final executablePath = await _findGodotExecutable(releaseDirectory.path);
      if (executablePath == null) {
        throw FileSystemException(
          'Godot executable was not found after extraction',
          releaseDirectory.path,
        );
      }

      await _rememberInstalledRelease(release.version, executablePath);
      if (!mounted) return executablePath;

      setState(() {
        _installing = false;
        _installProgress = 1;
        _status = 'Installed and configured ${release.version}.';
      });
      return executablePath;
    } catch (error) {
      if (!mounted) return null;

      setState(() {
        _installing = false;
        _installProgress = null;
        _error = 'Install failed: $error';
        _status = '${release.version} was not installed.';
      });
      return null;
    }
  }

  Future<void> _saveDefaultInstallPath() async {
    if (_installPathController.text.trim().isEmpty) {
      _installPathController.text = _defaultInstallPath;
    }
    await _saveSettings();
    if (!mounted) return;

    setState(() {
      _error = null;
      _status = 'Default install folder saved.';
    });
  }

  Future<void> _rememberInstalledRelease(
    String version,
    String executablePath,
  ) async {
    setState(() {
      _installedExecutables = {
        ..._installedExecutables,
        version: executablePath,
      };
      _executableController.text = executablePath;
    });
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    final file = _settingsFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'installPath': _installPathController.text.trim().isEmpty
            ? _defaultInstallPath
            : _installPathController.text.trim(),
        'executablePath': _executableController.text.trim(),
        'launchArguments': _argumentsController.text.trim(),
        'installedExecutables': _installedExecutables,
      }),
    );
  }

  String _normalizeExecutablePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (Platform.isMacOS && trimmed.endsWith('.app')) {
      final appName = trimmed
          .split(Platform.pathSeparator)
          .last
          .replaceFirst(RegExp(r'\.app$'), '');
      return '$trimmed/Contents/MacOS/$appName';
    }
    return trimmed;
  }

  Future<String> _downloadAsset(GodotAsset asset) async {
    final downloadsDirectory = Directory(
      _joinPaths(Directory.systemTemp.path, 'godot_launchpad_downloads'),
    );
    await downloadsDirectory.create(recursive: true);

    final archivePath =
        _joinPaths(downloadsDirectory.path, _safePathSegment(asset.name));
    final request = http.Request('GET', Uri.parse(asset.downloadUrl));
    final response = await request.send().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Download returned ${response.statusCode}');
    }

    final file = File(archivePath);
    final sink = file.openWrite();
    final totalBytes = response.contentLength;
    var receivedBytes = 0;

    try {
      await for (final chunk in response.stream) {
        receivedBytes += chunk.length;
        sink.add(chunk);

        if (mounted && totalBytes != null && totalBytes > 0) {
          setState(() {
            _installProgress = receivedBytes / totalBytes;
            _status =
                'Downloading ${asset.name} (${(_installProgress! * 100).round()}%)...';
          });
        }
      }
    } finally {
      await sink.close();
    }

    return archivePath;
  }

  Future<void> _extractArchive(
      String archivePath, String destinationPath) async {
    late ProcessResult result;

    if (Platform.isMacOS) {
      result = await Process.run(
          'ditto', ['-x', '-k', archivePath, destinationPath]);
    } else if (Platform.isWindows) {
      result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Expand-Archive -Force -LiteralPath "$archivePath" -DestinationPath "$destinationPath"',
      ]);
    } else {
      result = await Process.run(
          'unzip', ['-o', archivePath, '-d', destinationPath]);
    }

    if (result.exitCode != 0) {
      throw ProcessException(
        'extract',
        [archivePath],
        '${result.stderr}${result.stdout}',
        result.exitCode,
      );
    }
  }

  Future<String?> _findGodotExecutable(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return null;

    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      final path = entity.path;
      final name = path.split(Platform.pathSeparator).last.toLowerCase();

      if (Platform.isMacOS && entity is Directory && name.endsWith('.app')) {
        return path;
      }

      if (entity is File && name.startsWith('godot')) {
        if (Platform.isWindows && name.endsWith('.exe')) return path;
        if (Platform.isLinux && !name.endsWith('.zip')) return path;
      }
    }

    return null;
  }

  String get _defaultInstallPath {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return _joinPaths(home, 'GodotVersions');
  }

  File get _settingsFile {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return File(_joinPaths(home, '.godot_launchpad', 'settings.json'));
  }

  String _safePathSegment(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _joinPaths(String first, String second, [String? third]) {
    final separator = Platform.pathSeparator;
    final firstPart = first.endsWith(separator)
        ? first.substring(0, first.length - 1)
        : first;
    final secondPart =
        second.startsWith(separator) ? second.substring(1) : second;
    if (third == null) return '$firstPart$separator$secondPart';
    return _joinPaths('$firstPart$separator$secondPart', third);
  }

  void _useInstalledExecutableForSelectedRelease() {
    final version = _selectedRelease?.version;
    if (version == null) return;

    final executablePath = _installedExecutables[version];
    if (executablePath == null || executablePath.trim().isEmpty) return;

    setState(() {
      _executableController.text = executablePath;
      _status = 'Selected installed ${_selectedRelease!.version}.';
    });
  }

  List<String> _splitArguments(String rawArguments) {
    final arguments = <String>[];
    final current = StringBuffer();
    var insideQuotes = false;

    for (var index = 0; index < rawArguments.length; index += 1) {
      final character = rawArguments[index];
      if (character == '"') {
        insideQuotes = !insideQuotes;
        continue;
      }

      if (character == ' ' && !insideQuotes) {
        if (current.isNotEmpty) {
          arguments.add(current.toString());
          current.clear();
        }
        continue;
      }

      current.write(character);
    }

    if (current.isNotEmpty) {
      arguments.add(current.toString());
    }

    return arguments;
  }

  @override
  Widget build(BuildContext context) {
    final latestRelease = _releases.isEmpty ? null : _releases.first;
    final selectedAsset = _selectedRelease?.assetForCurrentPlatform;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    latestVersion: latestRelease?.version,
                    status: _status,
                    loading: _loading,
                    onRefresh: () => _loadReleases(autoInstallLatest: true),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 9,
                          child: _VersionPanel(
                            loading: _loading,
                            releases: _releases,
                            selectedRelease: _selectedRelease,
                            onSelectRelease: (release) {
                              setState(() {
                                _selectedRelease = release;
                                _status = 'Selected ${release.version}.';
                              });
                              _useInstalledExecutableForSelectedRelease();
                              unawaited(_ensureSelectedReleaseInstalled());
                            },
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          flex: 7,
                          child: _LaunchPanel(
                            selectedRelease: _selectedRelease,
                            selectedAsset: selectedAsset,
                            executableController: _executableController,
                            argumentsController: _argumentsController,
                            installPathController: _installPathController,
                            launching: _launching,
                            installing: _installing,
                            installProgress: _installProgress,
                            error: _error,
                            onLaunch: _launchGodot,
                            onInstall: _installSelectedRelease,
                            onSaveInstallPath: _saveDefaultInstallPath,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.latestVersion,
    required this.status,
    required this.loading,
    required this.onRefresh,
  });

  final String? latestVersion;
  final String? status;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xff1f8a70),
            borderRadius: BorderRadius.circular(8),
          ),
          child:
              const Icon(Icons.gamepad_outlined, color: Colors.white, size: 30),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Godot Launchpad',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                status ?? 'Ready',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xff58645e),
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _LatestBadge(version: latestVersion),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          tooltip: 'Refresh releases',
          onPressed: loading ? null : onRefresh,
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _LatestBadge extends StatelessWidget {
  const _LatestBadge({required this.version});

  final String? version;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xffffd166),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        version == null ? 'Latest: checking' : 'Latest: $version',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xff2c2611),
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _VersionPanel extends StatelessWidget {
  const _VersionPanel({
    required this.loading,
    required this.releases,
    required this.selectedRelease,
    required this.onSelectRelease,
  });

  final bool loading;
  final List<GodotRelease> releases;
  final GodotRelease? selectedRelease;
  final ValueChanged<GodotRelease> onSelectRelease;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffdce3dd)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    color: Color(0xff1f8a70)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Version Selector',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : releases.isEmpty
                      ? const Center(child: Text('No releases found.'))
                      : ListView.separated(
                          itemCount: releases.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final release = releases[index];
                            final selected = release == selectedRelease;
                            return _ReleaseTile(
                              release: release,
                              selected: selected,
                              newest: index == 0,
                              onTap: () => onSelectRelease(release),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({
    required this.release,
    required this.selected,
    required this.newest,
    required this.onTap,
  });

  final GodotRelease release;
  final bool selected;
  final bool newest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xffe7f4ee) : const Color(0xfff8faf8),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  selected ? const Color(0xff1f8a70) : const Color(0xffe4e9e5),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? const Color(0xff1f8a70)
                    : const Color(0xff79847e),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      release.version,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      release.publishedLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xff65716b),
                          ),
                    ),
                  ],
                ),
              ),
              if (newest)
                const _Pill(
                  icon: Icons.auto_awesome,
                  label: 'Current',
                  color: Color(0xffffd166),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaunchPanel extends StatelessWidget {
  const _LaunchPanel({
    required this.selectedRelease,
    required this.selectedAsset,
    required this.executableController,
    required this.argumentsController,
    required this.installPathController,
    required this.launching,
    required this.installing,
    required this.installProgress,
    required this.error,
    required this.onLaunch,
    required this.onInstall,
    required this.onSaveInstallPath,
  });

  final GodotRelease? selectedRelease;
  final GodotAsset? selectedAsset;
  final TextEditingController executableController;
  final TextEditingController argumentsController;
  final TextEditingController installPathController;
  final bool launching;
  final bool installing;
  final double? installProgress;
  final String? error;
  final VoidCallback onLaunch;
  final Future<String?> Function() onInstall;
  final VoidCallback onSaveInstallPath;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffdce3dd)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: ListView(
          children: [
            Row(
              children: [
                const Icon(Icons.rocket_launch_outlined,
                    color: Color(0xff1f8a70)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Launcher',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SelectedVersionSummary(
                release: selectedRelease, asset: selectedAsset),
            const SizedBox(height: 18),
            TextField(
              controller: installPathController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Default install folder',
                hintText: '~/GodotVersions',
                prefixIcon: const Icon(Icons.storage),
                suffixIcon: IconButton(
                  tooltip: 'Save default install folder',
                  onPressed: onSaveInstallPath,
                  icon: const Icon(Icons.save),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: executableController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Godot executable path',
                hintText: '/Applications/Godot.app or /usr/local/bin/godot',
                prefixIcon: Icon(Icons.folder_open),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: argumentsController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Launch arguments',
                hintText: '--editor /path/to/project',
                prefixIcon: Icon(Icons.terminal),
              ),
            ),
            const SizedBox(height: 16),
            if (installing || installProgress != null) ...[
              LinearProgressIndicator(value: installProgress),
              const SizedBox(height: 12),
            ],
            if (error != null) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xffffece8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xffffb3a5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    error!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xff8b2e1d),
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: installing || selectedAsset == null
                        ? null
                        : () => unawaited(onInstall()),
                    icon: installing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.install_desktop),
                    label: Text(installing ? 'Installing' : 'Install selected'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: launching || installing ? null : onLaunch,
                    icon: launching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(launching ? 'Launching' : 'Launch Godot'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedVersionSummary extends StatelessWidget {
  const _SelectedVersionSummary({required this.release, required this.asset});

  final GodotRelease? release;
  final GodotAsset? asset;

  @override
  Widget build(BuildContext context) {
    final assetText = asset == null
        ? 'No matching download asset detected for this platform.'
        : asset!.name;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff17201c),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _Pill(
                  icon: Icons.check_circle_outline,
                  label: 'Selected',
                  color: Color(0xff7bd389),
                ),
                const Spacer(),
                Text(
                  release?.version ?? 'None',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              assetText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xffd9e4dc),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xff17201c)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xff17201c),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class GodotReleaseService {
  static final Uri _releasesUri = Uri.parse(
      'https://api.github.com/repos/godotengine/godot/releases?per_page=20');

  Future<List<GodotRelease>> fetchStableReleases() async {
    final response = await http.get(
      _releasesUri,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'GodotLaunchpad',
      },
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('GitHub returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Unexpected release response');
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(GodotRelease.fromJson)
        .where(
            (release) => !release.prerelease && !release.version.contains('rc'))
        .take(8)
        .toList(growable: false);
  }
}

class GodotRelease {
  const GodotRelease({
    required this.version,
    required this.publishedAt,
    required this.prerelease,
    required this.assets,
  });

  factory GodotRelease.fromJson(Map<String, dynamic> json) {
    final assets = (json['assets'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(GodotAsset.fromJson)
        .toList(growable: false);

    return GodotRelease(
      version: (json['tag_name'] ?? json['name'] ?? 'Unknown').toString(),
      publishedAt: DateTime.tryParse((json['published_at'] ?? '').toString()),
      prerelease: json['prerelease'] == true,
      assets: assets,
    );
  }

  final String version;
  final DateTime? publishedAt;
  final bool prerelease;
  final List<GodotAsset> assets;

  String get publishedLabel {
    final date = publishedAt;
    if (date == null) return 'Release date unavailable';
    return 'Published ${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)}';
  }

  GodotAsset? get assetForCurrentPlatform {
    final platformNeedles = <String>[
      if (Platform.isMacOS) 'macos',
      if (Platform.isWindows) 'win64',
      if (Platform.isLinux) 'linux',
    ];

    for (final needle in platformNeedles) {
      final matches = assets.where((asset) {
        final name = asset.name.toLowerCase();
        return name.contains(needle) && !name.contains('export_templates');
      });
      if (matches.isNotEmpty) return matches.first;
    }
    return null;
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class GodotAsset {
  const GodotAsset({
    required this.name,
    required this.downloadUrl,
  });

  factory GodotAsset.fromJson(Map<String, dynamic> json) {
    return GodotAsset(
      name: (json['name'] ?? 'Download').toString(),
      downloadUrl: (json['browser_download_url'] ?? '').toString(),
    );
  }

  final String name;
  final String downloadUrl;
}
