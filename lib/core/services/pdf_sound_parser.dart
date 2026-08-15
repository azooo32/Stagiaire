import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class PdfSoundAnnotation {
  final int pageNumber;
  final List<double> rect; // [left, bottom, right, top] in PDF coordinates
  final String tempAudioPath;
  final int sampleRate;
  final int bitsPerSample;
  final int channels;

  const PdfSoundAnnotation({
    required this.pageNumber,
    required this.rect,
    required this.tempAudioPath,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.channels,
  });

  Map<String, dynamic> toJson() => {
        'pageNumber': pageNumber,
        'rect': rect,
        'tempAudioPath': tempAudioPath,
        'sampleRate': sampleRate,
        'bitsPerSample': bitsPerSample,
        'channels': channels,
      };

  factory PdfSoundAnnotation.fromJson(Map<String, dynamic> json) {
    return PdfSoundAnnotation(
      pageNumber: json['pageNumber'] as int? ?? 1,
      rect: (json['rect'] as List? ?? []).map((e) => (e as num).toDouble()).toList(),
      tempAudioPath: json['tempAudioPath'] as String? ?? '',
      sampleRate: json['sampleRate'] as int? ?? 44100,
      bitsPerSample: json['bitsPerSample'] as int? ?? 16,
      channels: json['channels'] as int? ?? 1,
    );
  }
}

class PdfSoundParser {
  /// Parses the PDF file at [pdfPath] and extracts all /Sound annotations.
  /// Saves extracted audio streams as temporary WAV files and returns a list of annotations.
  static Future<List<PdfSoundAnnotation>> parseAndExtract(
    String pdfPath,
    String tempDir,
  ) async {
    final file = File(pdfPath);
    if (!await file.exists()) return const [];

    final bytes = await file.readAsBytes();
    final results = <PdfSoundAnnotation>[];

    try {
      // Step 1: Scan all PDF objects ("X Y obj" ... "endobj")
      final objects = _parsePdfObjects(bytes);
      final objectsMap = <String, _PdfObject>{};
      for (final obj in objects) {
        objectsMap[obj.id] = obj;
      }

      // Step 2: Map page objects and their index
      // Map pageObjId -> 1-based pageIndex
      final pageIdToIndex = <String, int>{};
      // Map 1-based pageIndex -> List of annotation object IDs
      final pageAnnotsMap = <int, List<String>>{};
      int pageIndex = 1;

      for (final obj in objects) {
        final dict = obj.dictionaryText;
        if (dict.contains('/Type') && _getDictValue(dict, '/Type') == '/Page') {
          pageIdToIndex[obj.id] = pageIndex;

          final annotsVal = _getDictValue(dict, '/Annots');
          if (annotsVal != null) {
            final refs = _resolveAnnotationRefs(annotsVal, objectsMap);
            pageAnnotsMap[pageIndex] = refs;
          }
          pageIndex++;
        }
      }

      // Step 3: Find all Sound Annotations
      // Subtype: /Sound
      // Rect: [ left bottom right top ]
      // Sound: Ref pointing to the Sound stream object (e.g. 40 0 R)
      final soundAnnots = <String, _SoundAnnotData>{};
      for (final obj in objects) {
        final dict = obj.dictionaryText;
        if (dict.contains('/Subtype') && _getDictValue(dict, '/Subtype') == '/Sound') {
          final rectVal = _getDictValue(dict, '/Rect');
          final soundVal = _getDictValue(dict, '/Sound');
          final pageVal = _getDictValue(dict, '/P');

          if (rectVal != null && soundVal != null) {
            final rect = _parseRect(rectVal);
            final soundRef = _cleanRef(soundVal);
            final pageRef = pageVal != null ? _cleanRef(pageVal) : null;
            soundAnnots[obj.id] = _SoundAnnotData(
              annotId: obj.id,
              rect: rect,
              soundRef: soundRef,
              pageRef: pageRef,
            );
          }
        }
      }

      // Step 4: Extract audio for each sound annotation and associate with its page
      for (final annotEntry in soundAnnots.entries) {
        final soundData = annotEntry.value;

        // Determine which page this annotation belongs to
        int? targetPage;

        // Try direct /P reference first
        if (soundData.pageRef != null && pageIdToIndex.containsKey(soundData.pageRef)) {
          targetPage = pageIdToIndex[soundData.pageRef];
        }

        // If not found from /P, check pageAnnotsMap
        if (targetPage == null) {
          for (final pEntry in pageAnnotsMap.entries) {
            if (pEntry.value.contains(soundData.annotId)) {
              targetPage = pEntry.key;
              break;
            }
          }
        }

        // Default to page 1 if unknown
        targetPage ??= 1;

        // Find the sound stream object
        final streamObj = objectsMap[soundData.soundRef];
        if (streamObj == null || streamObj.streamBytes == null) continue;

        // Parse sound stream parameters (Support standard short PDF keys and full names)
        final dict = streamObj.dictionaryText;
        final rate = int.tryParse(_getDictValue(dict, '/R') ?? _getDictValue(dict, '/Rate') ?? '22050') ?? 22050;
        final bits = int.tryParse(_getDictValue(dict, '/B') ?? _getDictValue(dict, '/Bits') ?? '16') ?? 16;
        final channels = int.tryParse(_getDictValue(dict, '/C') ?? _getDictValue(dict, '/Channels') ?? '1') ?? 1;
        final encoding = _getDictValue(dict, '/E') ?? _getDictValue(dict, '/Encoding') ?? '/Signed';

        // Decompress stream if FlateDecode/ZLib filtered
        Uint8List pcmAudio = streamObj.streamBytes!;
        final filter = _getDictValue(dict, '/Filter');
        if (filter == '/FlateDecode' || filter == '/Fl') {
          try {
            pcmAudio = Uint8List.fromList(zlib.decode(pcmAudio));
          } catch (e) {
            // Keep raw if decompress fails
          }
        }

        // Build standard WAV file with 44-byte RIFF header
        final wavBytes = _createWavFileBytes(
          pcmAudio,
          rate,
          bits,
          channels,
          encoding,
        );

        final tempFile = File(
          '$tempDir/pdf_sound_${soundData.annotId}_p$targetPage.wav',
        );
        await tempFile.writeAsBytes(wavBytes);

        results.add(
          PdfSoundAnnotation(
            pageNumber: targetPage,
            rect: soundData.rect,
            tempAudioPath: tempFile.path,
            sampleRate: rate,
            bitsPerSample: bits,
            channels: channels,
          ),
        );
      }
    } catch (e) {
      // ignore
    }

    return results;
  }

  static List<_PdfObject> _parsePdfObjects(Uint8List bytes) {
    final list = <_PdfObject>[];
    final latin1Str = latin1.decode(bytes, allowInvalid: true);
    final len = bytes.length;

    final objHeaderRegex = RegExp(r'(\d+)\s+(\d+)\s+obj');
    final matches = objHeaderRegex.allMatches(latin1Str);

    for (final match in matches) {
      final objId = '${match.group(1)}_${match.group(2)}';
      final headerEnd = match.end;

      // Find endobj
      final endobjIdx = latin1Str.indexOf('endobj', headerEnd);
      if (endobjIdx == -1) continue;

      final objContentStr = latin1Str.substring(headerEnd, endobjIdx);

      // Extract dictionary << ... >>
      final dictStart = objContentStr.indexOf('<<');
      if (dictStart == -1) {
        list.add(_PdfObject(id: objId, dictionaryText: objContentStr.trim()));
        continue;
      }

      var dictEnd = -1;
      var braceCount = 0;
      for (var k = dictStart; k + 1 < objContentStr.length; k++) {
        if (objContentStr[k] == '<' && objContentStr[k + 1] == '<') {
          braceCount++;
          k++;
        } else if (objContentStr[k] == '>' && objContentStr[k + 1] == '>') {
          braceCount--;
          if (braceCount == 0) {
            dictEnd = k + 2;
            break;
          }
          k++;
        }
      }

      final dictText = dictEnd != -1 ? objContentStr.substring(dictStart, dictEnd) : '';

      // Check if there is a stream
      Uint8List? streamBytes;
      final streamKeywordIdx = objContentStr.indexOf('stream', dictEnd != -1 ? dictEnd : dictStart);
      if (streamKeywordIdx != -1) {
        var byteStart = headerEnd + streamKeywordIdx + 6;
        if (byteStart < len && bytes[byteStart] == 13) byteStart++;
        if (byteStart < len && bytes[byteStart] == 10) byteStart++;

        var byteEnd = headerEnd + endobjIdx;
        final endstreamIdx = latin1Str.indexOf('endstream', byteStart);
        if (endstreamIdx != -1) {
          byteEnd = endstreamIdx;
        }

        while (byteEnd > byteStart && (bytes[byteEnd - 1] == 10 || bytes[byteEnd - 1] == 13)) {
          byteEnd--;
        }

        if (byteEnd >= byteStart && byteEnd <= len) {
          streamBytes = bytes.sublist(byteStart, byteEnd);
        }
      }

      list.add(
        _PdfObject(
          id: objId,
          dictionaryText: dictText.isNotEmpty ? dictText : objContentStr.trim(),
          streamBytes: streamBytes,
        ),
      );
    }

    return list;
  }

  static String? _getDictValue(String dictText, String key) {
    final regex = RegExp(key + r'(?:\s+|\b)(\d+\s+\d+\s+R|/[^\s/\[\]<>\(\)]+|\[[^\]]*\]|\([^\)]*\)|<<[^>]*>>|[^\s/\[\]<>\(\)]+)');
    final match = regex.firstMatch(dictText);
    if (match != null) {
      return match.group(1)?.trim();
    }
    return null;
  }

  static List<String> _resolveAnnotationRefs(
    String val,
    Map<String, _PdfObject> objectsMap,
  ) {
    final list = <String>[];
    if (val.startsWith('[') && val.endsWith(']')) {
      final inner = val.substring(1, val.length - 1).trim();
      final parts = inner.split(RegExp(r'\s+'));
      for (var k = 0; k + 2 < parts.length; k += 3) {
        if (parts[k + 2] == 'R') {
          list.add('${parts[k]}_${parts[k + 1]}');
        }
      }
    } else if (val.endsWith('R')) {
      final clean = _cleanRef(val);
      final targetObj = objectsMap[clean];
      if (targetObj != null) {
        // Resolve indirect array object e.g. "37 0 obj [38 0 R] endobj"
        return _resolveAnnotationRefs(targetObj.dictionaryText, objectsMap);
      }
      list.add(clean);
    }
    return list;
  }

  static String _cleanRef(String val) {
    final parts = val.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0]}_${parts[1]}';
    }
    return val.replaceAll('R', '').trim().replaceAll(' ', '_');
  }

  static List<double> _parseRect(String val) {
    final clean = val.replaceAll('[', '').replaceAll(']', '').trim();
    final parts = clean.split(RegExp(r'\s+'));
    final rect = <double>[];
    for (final p in parts) {
      rect.add(double.tryParse(p) ?? 0.0);
    }
    while (rect.length < 4) {
      rect.add(0.0);
    }
    return rect;
  }

  /// Wraps raw PCM audio bytes with a 44-byte standard WAV header
  static Uint8List _createWavFileBytes(
    Uint8List rawAudio,
    int sampleRate,
    int bitsPerSample,
    int channels,
    String encoding,
  ) {
    // 1. Process raw audio according to bits and encoding
    Uint8List pcmData;

    if (bitsPerSample == 16) {
      // PDF stores 16-bit audio in Big-Endian.
      // WAV files require Little-Endian PCM.
      // Convert Big-Endian to Little-Endian by swapping adjacent byte pairs:
      pcmData = Uint8List(rawAudio.length);
      for (var i = 0; i + 1 < rawAudio.length; i += 2) {
        pcmData[i] = rawAudio[i + 1]; // LSB
        pcmData[i + 1] = rawAudio[i]; // MSB
      }
      if (rawAudio.length % 2 != 0) {
        pcmData[rawAudio.length - 1] = rawAudio[rawAudio.length - 1];
      }
    } else if (bitsPerSample == 8 &&
        (encoding == '/Signed' || encoding.toLowerCase().contains('signed'))) {
      // PDF 8-bit signed is [-128..127], WAV 8-bit PCM is unsigned [0..255]
      pcmData = Uint8List(rawAudio.length);
      for (var i = 0; i < rawAudio.length; i++) {
        final signedVal = rawAudio[i].toSigned(8);
        pcmData[i] = (signedVal + 128) & 0xFF;
      }
    } else {
      pcmData = rawAudio;
    }

    final dataSize = pcmData.length;
    final totalSize = 36 + dataSize;
    final byteRate = (sampleRate * channels * bitsPerSample) ~/ 8;
    final blockAlign = (channels * bitsPerSample) ~/ 8;

    final header = ByteData(44);
    // ChunkID: "RIFF"
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);

    // ChunkSize: 36 + dataSize (Little Endian)
    header.setUint32(4, totalSize, Endian.little);

    // Format: "WAVE"
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);

    // Subchunk1ID: "fmt "
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6d);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);

    // Subchunk1Size: 16
    header.setUint32(16, 16, Endian.little);

    // AudioFormat:
    // 1 = Uncompressed PCM
    // 6 = A-Law
    // 7 = Mu-Law
    var audioFormat = 1;
    if (encoding.toLowerCase().contains('mulaw')) {
      audioFormat = 7;
    } else if (encoding.toLowerCase().contains('alaw')) {
      audioFormat = 6;
    }
    header.setUint16(20, audioFormat, Endian.little);

    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // Subchunk2ID: "data"
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);

    header.setUint32(40, dataSize, Endian.little);

    final wavBytes = Uint8List(44 + dataSize);
    wavBytes.setRange(0, 44, header.buffer.asUint8List());
    wavBytes.setRange(44, wavBytes.length, pcmData);

    return wavBytes;
  }
}

class _PdfObject {
  final String id;
  final String dictionaryText;
  final Uint8List? streamBytes;

  const _PdfObject({
    required this.id,
    required this.dictionaryText,
    this.streamBytes,
  });
}

class _SoundAnnotData {
  final String annotId;
  final List<double> rect;
  final String soundRef;
  final String? pageRef;

  const _SoundAnnotData({
    required this.annotId,
    required this.rect,
    required this.soundRef,
    this.pageRef,
  });
}
