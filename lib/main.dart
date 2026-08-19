import 'src/composition/local_tag_player_bootstrap.dart' as bootstrap;
import 'src/qa/player_desktop_pixel_qa_app.dart' as desktop_pixel_qa;
import 'src/qa/player_real_page_pixel_qa_app.dart' as real_page_pixel_qa;
export 'src/app/local_tag_player_app.dart' show LocalTagPlayerApp;

Future<void> main() => real_page_pixel_qa.shouldRunPlayerRealPagePixelQa()
    ? real_page_pixel_qa.runPlayerRealPagePixelQa()
    : desktop_pixel_qa.shouldRunPlayerDesktopPixelQa()
        ? desktop_pixel_qa.runPlayerDesktopPixelQa()
        : bootstrap.bootstrapLocalTagPlayer();
