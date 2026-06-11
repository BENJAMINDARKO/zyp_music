import 'dart:mirrors';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:dart_ytmusic_api/types.dart';
void main() async {
  final yt = YTMusic();
  try {
    final p = await yt.getPlaylist("PLFgquLnL59alCl_2epm10C2SWAZ-xUJb5");
    var im = reflect(p);
    for (var d in im.type.declarations.values) {
      if (d is VariableMirror) {
        print(MirrorSystem.getName(d.simpleName));
      }
    }
  } catch (e) {
    print(e);
  }
}
