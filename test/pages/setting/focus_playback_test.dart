import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/pages/setting/common_setting.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GStorage.setting = await Hive.openBox('setting', bytes: Uint8List(0));
    GStorage.video = await Hive.openBox('video', bytes: Uint8List(0));
    GStorage.localCache = await Hive.openBox('localCache', bytes: Uint8List(0));
    await GStorage.localCache.put('buvid', 'test-buvid');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
  });

  setUp(() async {
    await GStorage.setting.clear();
    await GStorage.video.clear();
  });

  tearDown(() {
    PlPlayerController.instance?.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  tearDownAll(() async {
    await Hive.close();
  });

  test(
    'focus keeps sequential default and maps legacy related autoplay',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(Pref.playRepeat, PlayRepeat.listOrder);
      await GStorage.video.put(
        VideoBoxKey.playRepeat,
        PlayRepeat.autoPlayRelated.index,
      );
      expect(Pref.playRepeat, PlayRepeat.listOrder);
      expect(Pref.showRelatedVideo, isFalse);

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(Pref.playRepeat, PlayRepeat.autoPlayRelated);
      expect(Pref.playRepeatOptions, contains(PlayRepeat.autoPlayRelated));
      await GStorage.video.delete(VideoBoxKey.playRepeat);
      expect(Pref.playRepeat, PlayRepeat.pause);
    },
  );

  testWidgets('focus settings exposes and saves all four playback modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CommonSetting(settingType: SettingType.playSetting),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('播放顺序'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    for (final mode in const [
      PlayRepeat.pause,
      PlayRepeat.singleCycle,
      PlayRepeat.listCycle,
      PlayRepeat.listOrder,
    ]) {
      await tester.tap(find.text('播放顺序'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<PlayRepeat>), findsNWidgets(4));
      expect(find.text('自动连播'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<PlayRepeat>),
          matching: find.text(mode.label),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(mode.label), findsOneWidget);
      expect(GStorage.video.get(VideoBoxKey.playRepeat), mode.index);
      expect(Pref.playRepeat, mode);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  test(
    'player changes apply immediately and persist unless temporary',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final player = PlPlayerController.getInstance();
      expect(player.playRepeat, PlayRepeat.listOrder);
      for (final mode in Pref.playRepeatOptions) {
        player.setPlayRepeat(mode);
        expect(player.playRepeat, mode);
        await GStorage.video.flush();
        expect(Pref.playRepeat, mode);
      }
      player.dispose();

      await GStorage.video.put(
        VideoBoxKey.playRepeat,
        PlayRepeat.listOrder.index,
      );
      await GStorage.setting.put(SettingBoxKey.tempPlayerConf, true);
      final temporaryPlayer = PlPlayerController.getInstance()
        ..setPlayRepeat(PlayRepeat.pause);
      expect(temporaryPlayer.playRepeat, PlayRepeat.pause);
      expect(Pref.playRepeat, PlayRepeat.listOrder);
      temporaryPlayer.dispose();
      expect(PlPlayerController.getInstance().playRepeat, PlayRepeat.listOrder);
    },
  );
}
