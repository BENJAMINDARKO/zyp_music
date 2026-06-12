import 'package:flutter/material.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'dart:io';

void test(BuildContext context) async {
  String? path = await FilesystemPicker.open(
    title: 'Save to folder',
    context: context,
    rootDirectory: Directory('/storage/emulated/0'),
    fsType: FilesystemType.folder,
    pickText: 'Save here',
  );
}
