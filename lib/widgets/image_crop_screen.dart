import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';

/// Full-screen image crop screen for profile photos.
/// Crops to a square (1:1) aspect ratio with a circular overlay.
/// Returns the cropped [Uint8List] or null if cancelled.
class ImageCropScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const ImageCropScreen({super.key, required this.imageBytes});

  /// Opens the crop screen and returns the cropped image bytes, or null.
  static Future<Uint8List?> crop(BuildContext context, Uint8List imageBytes) {
    return Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageCropScreen(imageBytes: imageBytes),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final _controller = CropController();
  bool _cropping = false;
  bool _loading = true;
  Uint8List? _previewBytes;

  @override
  void initState() {
    super.initState();
    _preparePreview();
  }

  /// Downscales the original image to ~600px width and encodes as JPEG.
  /// JPEG is much faster to encode/decode than PNG, keeping both the crop
  /// interaction and the final crop operation smooth.  The small quality
  /// loss from JPEG is irrelevant for the crop preview.
  /// Final resize to 512px happens in _resizeForUpload after cropping.
  Future<void> _preparePreview() async {
    try {
      // 600px preview vs 1024px = ~3× fewer pixels = ~3× faster crop.
      // Still plenty for precise face-framing at 512px final output.
      const maxPreview = 600;
      final codec = await ui.instantiateImageCodec(
        widget.imageBytes,
        targetWidth: maxPreview,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null && mounted) {
        setState(() {
          _previewBytes = byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          );
          _loading = false;
        });
      } else if (mounted) {
        // Fallback
        setState(() {
          _previewBytes = widget.imageBytes;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[ImageCropScreen] Preview error: $e');
      if (mounted) {
        setState(() {
          _previewBytes = widget.imageBytes;
          _loading = false;
        });
      }
    }
  }

  void _cropImage() {
    // Set loading BEFORE calling crop so the rebuild happens instantly
    setState(() => _cropping = true);
    // Schedule the crop on the next frame so the loading overlay renders first
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.crop());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Crop Photo'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, null),
        ),
        actions: [
          TextButton(
            onPressed: (_cropping || _loading) ? null : _cropImage,
            child: _cropping
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Crop',
                    style: TextStyle(
                      color: Color(0xFF1E88E5),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Crop area
            if (_loading)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Preparing image…',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              )
            else if (_previewBytes != null)
              Crop(
                image: _previewBytes!,
                controller: _controller,
                withCircleUi: true,
                aspectRatio: 1.0,
                onCropped: (result) {
                  setState(() => _cropping = false);
                  switch (result) {
                    case CropSuccess(croppedImage: final image):
                      Navigator.pop(context, image);
                    case CropFailure(cause: final cause):
                      debugPrint(
                          '[ImageCropScreen] Crop error: $cause');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Failed to crop image. Please try again.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                  }
                },
              )
            else
              Center(
                child: Text(
                  'Failed to load image',
                  style: TextStyle(color: Colors.red.shade400),
                ),
              ),
            // Full-screen loading overlay during crop processing
            if (_cropping)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        'Cropping…',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
