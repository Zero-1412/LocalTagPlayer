import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

part 'src/app.dart';
part 'src/core/app_paths.dart';
part 'src/core/layout_size.dart';
part 'src/core/playback_settings.dart';
part 'src/core/platform_interfaces.dart';
part 'src/core/tag_rules.dart';
part 'src/models/video_item.dart';
part 'src/models/media_details.dart';
part 'src/models/platform_models.dart';
part 'src/repositories/repository_interfaces.dart';
part 'src/services/library_store.dart';
part 'src/services/tag_query_service.dart';
part 'src/services/external_media_tools.dart';
part 'src/services/thumbnail_service.dart';
part 'src/services/media_details_service.dart';
part 'src/pages/library_page.dart';
part 'src/pages/tag_manager_page.dart';
part 'src/pages/player_page.dart';
part 'src/widgets/library_widgets.dart';



