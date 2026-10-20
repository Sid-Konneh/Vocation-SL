import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/errors.dart';

/// A resized image ready to upload or store.
typedef ResizedImage = ({Uint8List bytes, String extension, String contentType});

/// Shrinks photos and logos before they are saved, so uploads are small and
/// fast on mobile data and always fit the 2 MB storage limit.
class ImageResize {
  /// Scales [bytes] down so its longest side is at most [maxSide] pixels.
  /// Images with transparency stay PNG (so logos keep their background);
  /// everything else becomes JPEG.
  static ResizedImage shrink(Uint8List bytes, {int maxSide = 512, int quality = 85}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const ValidationException('That image couldn\'t be read. Choose a PNG or JPG file.');
    var image = img.bakeOrientation(decoded);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
    }
    if (image.hasAlpha && _usesTransparency(image)) {
      return (bytes: Uint8List.fromList(img.encodePng(image, level: 6)), extension: 'png', contentType: 'image/png');
    }
    return (bytes: Uint8List.fromList(img.encodeJpg(image, quality: quality)), extension: 'jpg', contentType: 'image/jpeg');
  }

  static bool _usesTransparency(img.Image image) {
    // Sample a grid rather than every pixel; enough to spot a transparent background.
    final stepX = (image.width / 24).ceil().clamp(1, image.width);
    final stepY = (image.height / 24).ceil().clamp(1, image.height);
    for (var y = 0; y < image.height; y += stepY) {
      for (var x = 0; x < image.width; x += stepX) {
        if (image.getPixel(x, y).a < image.maxChannelValue) return true;
      }
    }
    return false;
  }
}
