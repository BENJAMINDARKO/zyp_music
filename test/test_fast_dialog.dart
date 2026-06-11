import 'package:flutter/material.dart';

void main() {
  print('Run this mentally:');
  print('1. showDialog(...)');
  print('2. await Future.delayed(50ms)');
  print('3. Navigator.pop(context)');
  print('If 3 happens before the dialog is fully pushed, the pop might pop the current route, then the dialog appears and stays.');
}
