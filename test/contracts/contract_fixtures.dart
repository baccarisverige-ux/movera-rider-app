import 'dart:convert';
import 'dart:io';

/// Reads a file of the shipped contract copy (`contracts/`), as bytes so a
/// fixture is data, not source under test.
Object? contractJson(String path) =>
    jsonDecode(utf8.decode(File('contracts/$path').readAsBytesSync()));

Map<String, dynamic> get contract =>
    contractJson('contract.json')! as Map<String, dynamic>;
