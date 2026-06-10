import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CustomSvgIcon extends StatelessWidget {
  final String assetPath;
  final double size;
  final Color? color;

  const CustomSvgIcon({
    super.key,
    required this.assetPath,
    this.size = 24.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tintColor = color ?? IconTheme.of(context).color ?? Colors.white;
    return SvgPicture.asset(
      assetPath,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tintColor, BlendMode.srcIn),
    );
  }
}

class CustomIconPaths {
  CustomIconPaths._();

  static const String similarSongs = 'assets/icons/similar_songs.svg';
  static const String sameGenre = 'assets/icons/same_genre.svg';
  static const String shuffleLibrary = 'assets/icons/shuffle_library.svg';
}
