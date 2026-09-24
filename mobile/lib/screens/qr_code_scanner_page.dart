import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrCodeScannerPage extends StatefulWidget {
  final bool galleryOnly;

  const QrCodeScannerPage({super.key, this.galleryOnly = false});

  @override
  State<QrCodeScannerPage> createState() => _QrCodeScannerPageState();
}

class _QrCodeScannerPageState extends State<QrCodeScannerPage> {
  final _picker = ImagePicker();
  late final MobileScannerController _scannerController;
  bool _handlingCode = false;
  bool _readingImage = false;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      autoStart: !widget.galleryOnly,
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _restorePickedImage());
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _restorePickedImage() async {
    try {
      final lost = await _picker.retrieveLostData();
      if (lost.isEmpty || lost.files == null || lost.files!.isEmpty) return;
      await _decodeImage(lost.files!.first);
    } catch (_) {
      // No lost image is the normal startup case. Never log image contents.
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handlingCode || _readingImage) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (value.isEmpty) return;
    _returnPayload(value);
  }

  Future<void> _returnPayload(String value) async {
    if (_handlingCode) return;
    _handlingCode = true;
    if (!widget.galleryOnly) await _scannerController.stop();
    if (!mounted) return;
    Navigator.of(context).pop(value);
  }

  Future<void> _pickImage() async {
    if (_readingImage || _handlingCode) return;
    setState(() => _readingImage = true);
    if (!widget.galleryOnly) await _scannerController.stop();
    try {
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) await _decodeImage(image);
    } catch (_) {
      if (mounted) _showMessage('无法读取图片，请换一张清晰的二维码图片。');
    } finally {
      if (mounted && !_handlingCode) {
        setState(() => _readingImage = false);
        if (!widget.galleryOnly) {
          try {
            await _scannerController.start();
          } catch (_) {
            // MobileScanner's errorBuilder explains camera recovery options.
          }
        }
      }
    }
  }

  Future<void> _retryCamera() async {
    try {
      await _scannerController.start();
    } catch (_) {
      if (mounted) {
        _showMessage('仍无法使用相机。请到系统设置中允许 TapLens 使用相机后重试。');
      }
    }
  }

  Future<void> _decodeImage(XFile image) async {
    try {
      final capture = await _scannerController.analyzeImage(
        image.path,
        formats: const [BarcodeFormat.qrCode],
      );
      final value = capture?.barcodes
          .map((barcode) => barcode.rawValue)
          .whereType<String>()
          .map((value) => value.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      if (value == null || value.isEmpty) {
        if (mounted) _showMessage('这张图片中没有识别到二维码，请换一张清晰图片。');
        return;
      }
      await _returnPayload(value);
    } catch (_) {
      if (mounted) _showMessage('图片二维码解析失败，请换一张清晰图片。');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.galleryOnly ? '从图片识别二维码' : '扫码检查'),
        actions: [
          IconButton(
            tooltip: '从相册选择图片',
            onPressed: _readingImage ? null : _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: widget.galleryOnly
                  ? _GalleryOnlyPanel(
                      onPick: _pickImage, loading: _readingImage)
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: _scannerController,
                          onDetect: _onDetect,
                          errorBuilder: (context, error) => _CameraErrorPanel(
                            onPick: _pickImage,
                            onRetry: _retryCamera,
                          ),
                        ),
                        IgnorePointer(
                          child: Center(
                            child: Container(
                              width: 264,
                              height: 264,
                              decoration: BoxDecoration(
                                border:
                                    Border.all(color: colors.primary, width: 3),
                                borderRadius: BorderRadius.circular(24),
                                color: colors.surface.withValues(alpha: 0.04),
                              ),
                            ),
                          ),
                        ),
                        if (_readingImage)
                          ColoredBox(
                            color: colors.scrim.withValues(alpha: 0.5),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                children: [
                  Text(
                    widget.galleryOnly
                        ? '选择一张包含二维码的图片，内容只在本机解码。'
                        : '将二维码放入框内。TapLens 只读取内容，不会打开或执行它。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _readingImage ? null : _pickImage,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(_readingImage ? '正在读取图片…' : '从相册选择二维码图片'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraErrorPanel extends StatelessWidget {
  final VoidCallback onPick;
  final VoidCallback onRetry;

  const _CameraErrorPanel({required this.onPick, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _ScannerMessage(
      icon: Icons.no_photography_outlined,
      title: '无法使用相机',
      message: '请到系统设置中允许 TapLens 使用相机，然后重试；也可以改用相册图片。',
      actionLabel: '重新打开相机',
      actionIcon: Icons.refresh_rounded,
      onAction: onRetry,
      secondaryLabel: '从相册选择',
      onSecondaryAction: onPick,
    );
  }
}

class _GalleryOnlyPanel extends StatelessWidget {
  final VoidCallback onPick;
  final bool loading;

  const _GalleryOnlyPanel({required this.onPick, required this.loading});

  @override
  Widget build(BuildContext context) {
    return _ScannerMessage(
      icon: Icons.qr_code_2_rounded,
      title: '识别海报中的二维码',
      message: '选择图片后在手机本地解码；整张海报不会上传。',
      actionLabel: loading ? '正在读取…' : '选择图片',
      onAction: loading ? null : onPick,
    );
  }
}

class _ScannerMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryAction;

  const _ScannerMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    this.actionIcon = Icons.photo_library_outlined,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colors.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon),
              label: Text(actionLabel),
            ),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onSecondaryAction,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
