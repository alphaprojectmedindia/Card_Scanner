import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

/// Computes cryptographic and perceptual hashes for business-card images.
class ImageHashService {
  const ImageHashService();

  /// Computes a canonical SHA-256 hex string from raw image bytes or file.
  String computeSha256(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Computes SHA-256 from a file path.
  Future<String> computeFileSha256(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return '';
    final bytes = await file.readAsBytes();
    return computeSha256(bytes);
  }

  /// Computes a 64-bit difference hash (dHash) hex string (16 hex chars).
  ///
  /// Algorithm:
  /// 1. Decode image and downscale to 9 columns by 8 rows (72 pixels).
  /// 2. Convert to grayscale luminance.
  /// 3. For each of the 8 rows, compare pixel[col] > pixel[col+1] (8 comparisons * 8 rows = 64 bits).
  /// 4. Pack 64 bits into a 16-character hex string.
  String computeDHash(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return '';

      // Resize to 9x8 for dHash
      final resized = img.copyResize(decoded, width: 9, height: 8);
      final grayscale = img.grayscale(resized);

      BigInt hash = BigInt.zero;
      for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
          final leftLum = grayscale.getPixel(x, y).luminance;
          final rightLum = grayscale.getPixel(x + 1, y).luminance;

          hash = hash << 1;
          if (leftLum > rightLum) {
            hash = hash | BigInt.one;
          }
        }
      }

      return hash.toRadixString(16).padLeft(16, '0');
    } catch (_) {
      return '';
    }
  }

  /// Computes dHash from a file path.
  Future<String> computeFileDHash(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return '';
    final bytes = await file.readAsBytes();
    return computeDHash(bytes);
  }

  /// Computes the Hamming distance (number of differing bits) between two 16-char dHash hex strings.
  /// Returns a value between 0 (identical) and 64 (completely inverted).
  /// A distance <= 8 indicates very high perceptual visual similarity.
  int hammingDistance(String hashA, String hashB) {
    if (hashA.isEmpty || hashB.isEmpty || hashA.length != 16 || hashB.length != 16) {
      return 64;
    }

    try {
      final bigA = BigInt.parse(hashA, radix: 16);
      final bigB = BigInt.parse(hashB, radix: 16);
      BigInt xorVal = bigA ^ bigB;

      int dist = 0;
      while (xorVal > BigInt.zero) {
        if ((xorVal & BigInt.one) == BigInt.one) {
          dist++;
        }
        xorVal = xorVal >> 1;
      }
      return dist;
    } catch (_) {
      return 64;
    }
  }
}

