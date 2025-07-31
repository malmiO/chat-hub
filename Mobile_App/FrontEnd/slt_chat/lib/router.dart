import 'package:flutter/material.dart';
import 'home_screen.dart';

Route<dynamic> generateRoute(RouteSettings settings) {
  switch (settings.name) {
    case '/home':
      return MaterialPageRoute(builder: (_) => HomeScreen());
    default:
      return MaterialPageRoute(builder: (_) => HomeScreen());
  }
}
