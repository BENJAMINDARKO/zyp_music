import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dbPath = 'ytmusix.db'; // Wait, getDatabasesPath() on Mac might be different
  print('done');
}
