import 'package:flutter/material.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF161C27),
        body: Center(
          child: Text(
            'PiFrame Showcase Window',
            style: TextStyle(color: Colors.white, fontSize: 24),
          ),
        ),
      ),
    ),
  );
}
