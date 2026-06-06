// Patchfly CLI entrypoint.
//
// Copyright (c) 2024 Shorebird Labs, Inc. and Patchfly contributors
// Licensed under MIT and Apache License, Version 2.0
//
// Derived from Shorebird (https://github.com/shorebirdtech/shorebird),
// Copyright Shorebird Labs, Inc. Distributed under the same dual
// MIT + Apache 2.0 license. See ../../LICENSE-MIT and
// ../../LICENSE-APACHE for the full license texts.

import 'package:patchfly/src/cli.dart';

Future<void> main(List<String> args) async {
  await runCli(args);
}
