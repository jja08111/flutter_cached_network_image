import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:cached_network_image_platform_interface'
        '/cached_network_image_platform_interface.dart' as platform
    show ImageLoader;
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// ImageLoader class to load images on IO platforms.
class ImageLoader implements platform.ImageLoader {
  @override
  Stream<ui.Codec> loadAsync(
    String url,
    ImageDownloadCallBack onImageDownloaded,
    bool enableCompress,
    String? cacheKey,
    StreamController<ImageChunkEvent> chunkEvents,
    DecoderCallback decode,
    BaseCacheManager cacheManager,
    int? maxHeight,
    int? maxWidth,
    Map<String, String>? headers,
    Function()? errorListener,
    ImageRenderMethodForWeb imageRenderMethodForWeb,
    Function() evictImage,
  ) async* {
    try {
      assert(
          cacheManager is ImageCacheManager ||
              (maxWidth == null && maxHeight == null),
          'To resize the image with a CacheManager the '
          'CacheManager needs to be an ImageCacheManager. maxWidth and '
          'maxHeight will be ignored when a normal CacheManager is used.');

      var stream = cacheManager is ImageCacheManager
          ? cacheManager.getImageFile(url,
              maxHeight: maxHeight,
              maxWidth: maxWidth,
              withProgress: true,
              headers: headers,
              key: cacheKey)
          : cacheManager.getFileStream(url,
              withProgress: true, headers: headers, key: cacheKey);

      await for (var result in stream) {
        if (result is DownloadProgress) {
          chunkEvents.add(ImageChunkEvent(
            cumulativeBytesLoaded: result.downloaded,
            expectedTotalBytes: result.totalSize,
          ));
        }
        if (result is FileInfo) {
          final file = result.file;
          final fileKBSize = file.lengthSync() / 1024;
          var bytes = await file.readAsBytes();

          if (enableCompress && fileKBSize > 500) {
            bytes = await FlutterImageCompress.compressWithList(
              bytes,
              quality: 25,
              minWidth: 320,
              minHeight: 240,
            );
            await file.writeAsBytes(bytes);
          }
          try {
            bytes = await onImageDownloaded(bytes);
            yield await decode(bytes);
          } catch (e) {
            scheduleMicrotask(() {
              evictImage();
            });
          }
        }
      }
    } catch (e) {
      // Depending on where the exception was thrown, the image cache may not
      // have had a chance to track the key in the cache at all.
      // Schedule a microtask to give the cache a chance to add the key.
      scheduleMicrotask(() {
        evictImage();
      });

      errorListener?.call();
      rethrow;
    } finally {
      await chunkEvents.close();
    }
  }
}
