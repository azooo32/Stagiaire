import 'dart:typed_data';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

class SlideImageCropScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const SlideImageCropScreen({super.key, required this.imageBytes});

  static Future<Uint8List?> show(BuildContext context, Uint8List imageBytes) {
    return Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(
        builder: (_) => SlideImageCropScreen(imageBytes: imageBytes),
      ),
    );
  }

  @override
  State<SlideImageCropScreen> createState() => _SlideImageCropScreenState();
}

class _SlideImageCropScreenState extends State<SlideImageCropScreen> {
  final _cropController = CropController();
  bool _isCropping = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF171428),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F1B35),
        elevation: 0,
        title: const Text(
          'Crop Image',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isCropping)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: () {
                setState(() {
                  _isCropping = true;
                });
                _cropController.crop();
              },
              child: const Text(
                'Done',
                style: TextStyle(
                  color: Color(0xFFC7B8EA),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Crop(
                image: widget.imageBytes,
                controller: _cropController,
                onCropped: (result) {
                  if (result is CropSuccess) {
                    Navigator.pop(context, result.croppedImage);
                  } else {
                    Navigator.pop(context, null);
                  }
                },
                interactive: true,
                maskColor: Colors.black.withValues(alpha: 0.5),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Drag the corners to adjust crop area, then press Done.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
