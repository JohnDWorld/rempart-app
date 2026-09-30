import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/analyse_video.dart';

void main() {
  test('une vidéo portrait annoncée paysage est redressée par la vignette', () {
    expect(orienter(video: (1920, 1080), vignette: (450, 800)), (1080, 1920));
  });

  test('déjà dans le bon sens, rien ne change', () {
    expect(orienter(video: (1080, 1920), vignette: (450, 800)), (1080, 1920));
    expect(orienter(video: (1920, 1080), vignette: (800, 450)), (1920, 1080));
  });

  test('sans vignette, les dimensions de la vidéo', () {
    expect(orienter(video: (1280, 720)), (1280, 720));
  });

  test('sans la vidéo, les proportions de la vignette', () {
    expect(orienter(vignette: (450, 800)), (450, 800));
    expect(orienter(), (null, null));
  });
}
