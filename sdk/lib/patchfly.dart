/// Patchfly SDK public API.
///
/// Copyright (c) 2024 Shorebird Labs, Inc. and Patchfly contributors
/// Licensed under MIT and Apache License, Version 2.0
///
/// Derived from Shorebird (https://github.com/shorebirdtech/shorebird),
/// Copyright Shorebird Labs, Inc. Distributed under the same dual
/// MIT + Apache 2.0 license. See ../LICENSE-MIT and
/// ../LICENSE-APACHE for the full license texts.
///
/// This is a thin re-export so consumers can write:
///   import 'package:patchfly/patchfly.dart';
/// instead of the longer `package:patchfly/src/patchfly.dart`.
library patchfly;

export 'src/patchfly.dart';
export 'src/asset_manager.dart';
export 'src/logger.dart';
export 'src/models.dart';
export 'src/sha256_util.dart';
