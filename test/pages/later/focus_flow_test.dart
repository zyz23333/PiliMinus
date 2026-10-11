import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/later/data.dart';
import 'package:PiliPlus/models_new/later/list.dart';
import 'package:PiliPlus/pages/later/focus_queue.dart';
import 'package:PiliPlus/pages/later/focus_view.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/router/app_pages.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

LoginAccount _account(String mid) => LoginAccount(
  BiliCookieJar.fromJson({'DedeUserID': mid, 'bili_jct': 'test-csrf'}),
  null,
  null,
);

class _Queue extends LaterQueueSource {
  _Queue(this.items);

  final List<LaterItemModel> items;
  final reads = <({Account account, int page, bool asc, int viewed})>[];
  final removals = <({Account account, int aid})>[];
  Future<LoadingState<LaterData>> Function()? nextRead;
  Future<LoadingState<void>> Function()? nextRemoval;

  @override
  Future<LoadingState<LaterData>> read({
    required Account account,
    required int page,
    required bool asc,
    required int viewed,
  }) async {
    reads.add((account: account, page: page, asc: asc, viewed: viewed));
    if (nextRead case final callback?) {
      nextRead = null;
      return callback();
    }
    final ordered = asc ? items : items.reversed;
    final filtered = ordered.where(
      (item) => viewed == 0 || item.progress != -1,
    );
    return Success(
      LaterData(
        count: filtered.length,
        list: filtered.skip((page - 1) * 20).take(20).toList(),
      ),
    );
  }

  @override
  Future<LoadingState<void>> remove({
    required Account account,
    required int aid,
  }) async {
    removals.add((account: account, aid: aid));
    final callback = nextRemoval;
    nextRemoval = null;
    final result =
        await (callback?.call() ?? Future.value(const Success<void>(null)));
    if (result.isSuccess) items.removeWhere((item) => item.aid == aid);
    return result;
  }
}

Future<void> _show(
  WidgetTester tester,
  LaterFocusController controller, {
  Future<void> Function(LaterItemModel)? openVideo,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LaterFocusView(
        controller: controller,
        openVideo: openVideo ?? (_) async {},
        onLogin: () {},
        onLogout: controller.clearSession,
        onSettings: () {},
      ),
    ),
  );
  await controller.refresh();
  await tester.pumpAndSettle();
}

Future<void> _complete(WidgetTester tester) async {
  await tester.ensureVisible(find.text('完成'));
  await tester.tap(find.text('完成'));
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliminus-focus-test-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.video = await Hive.openBox('video');
    GStorage.localCache = await Hive.openBox('localCache');
    await GStorage.localCache.put('buvid', 'test-buvid');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets(
    'oldest watched item is the only item, including scrolling and landscape',
    (tester) async {
      final account = _account('1');
      final source = _Queue([
        LaterItemModel(aid: 10, title: '最早加入的已看完视频', progress: -1),
        LaterItemModel(aid: 20, title: '较新视频'),
      ]);
      final controller = LaterFocusController(
        source: source,
        activeAccount: () => account,
      );
      addTearDown(controller.dispose);
      await _show(tester, controller);
      expect(find.text('最早加入的已看完视频'), findsOneWidget);
      expect(find.text('较新视频'), findsNothing);
      expect(find.text('已看完 · 仍需手动完成'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('较新视频'), findsNothing);
      tester.view.physicalSize = const Size(1200, 500);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(find.text('较新视频'), findsNothing);
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(
        source.reads.every(
          (read) => read.asc && read.viewed == 0 && read.page == 1,
        ),
        isTrue,
      );
      expect(source.removals, isEmpty);
    },
  );

  testWidgets(
    'play, change collection episode, return, then complete the original item',
    (tester) async {
      final account = _account('1');
      final source = _Queue([
        LaterItemModel(aid: 10, title: '原始队列项目'),
        LaterItemModel(aid: 20, title: '下一个项目'),
      ]);
      final controller = LaterFocusController(
        source: source,
        activeAccount: () => account,
      );
      addTearDown(controller.dispose);
      await _show(
        tester,
        controller,
        openVideo: (item) async {
          expect(item.aid, 10);
          await Navigator.of(tester.element(find.text('播放'))).push(
            MaterialPageRoute<void>(
              builder: (context) {
                String title = '原始视频';
                return StatefulBuilder(
                  builder: (context, setState) => Scaffold(
                    appBar: AppBar(title: Text(title)),
                    body: Column(
                      children: [
                        TextButton(
                          onPressed: () => setState(() => title = '合集中的另一集已播完'),
                          child: const Text('切换合集选集'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('返回首页'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
      await tester.tap(find.text('播放'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('切换合集选集'));
      await tester.pumpAndSettle();
      expect(find.text('合集中的另一集已播完'), findsOneWidget);
      expect(source.removals, isEmpty);
      await tester.tap(find.text('返回首页'));
      await tester.pumpAndSettle();
      expect(find.text('原始队列项目'), findsOneWidget);
      await _complete(tester);
      expect(source.removals.single.aid, 10);
      expect(find.text('原始队列项目'), findsNothing);
      expect(find.text('下一个项目'), findsOneWidget);
    },
  );

  testWidgets(
    'failed removal keeps the head and pending repeated taps send one request',
    (tester) async {
      final account = _account('1');
      final source = _Queue([
        LaterItemModel(aid: 10, title: '无法播放也能移除'),
        LaterItemModel(aid: 20, title: '下一项'),
      ]);
      final controller = LaterFocusController(
        source: source,
        activeAccount: () => account,
      );
      addTearDown(controller.dispose);
      await _show(tester, controller);
      final gate = Completer<LoadingState<void>>();
      source.nextRemoval = () => gate.future;
      await tester.ensureVisible(find.text('完成'));
      await tester.tap(find.text('完成'));
      await tester.pump();
      await tester.tap(find.text('正在完成…'));
      await tester.pump();
      expect(source.removals, hasLength(1));
      expect(find.text('无法播放也能移除'), findsOneWidget);
      gate.complete(const Error('网络中断'));
      await tester.pumpAndSettle();
      expect(find.textContaining('移除失败'), findsOneWidget);
      expect(find.text('下一项'), findsNothing);
      await _complete(tester);
      expect(source.removals.map((request) => request.aid), [10, 10]);
      expect(find.text('下一项'), findsOneWidget);
    },
  );

  testWidgets(
    'successful removal followed by read failure retries reading without deleting again',
    (tester) async {
      final account = _account('1');
      final source = _Queue([
        LaterItemModel(aid: 10, title: '已删除项目'),
        LaterItemModel(aid: 20, title: '新队首'),
      ]);
      final controller = LaterFocusController(
        source: source,
        activeAccount: () => account,
      );
      addTearDown(controller.dispose);
      await _show(tester, controller);
      source.nextRead = () async => const Error('读取网络中断');
      await _complete(tester);
      expect(find.text('已删除项目'), findsNothing);
      expect(find.text('读取稍后再看失败'), findsOneWidget);
      expect(find.text('完成'), findsNothing);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('新队首'), findsOneWidget);
      expect(source.removals, hasLength(1));
    },
  );

  testWidgets(
    'more than one page completes in order and reaches a distinct empty state',
    (tester) async {
      final account = _account('1');
      final source = _Queue(
        List.generate(
          25,
          (index) => LaterItemModel(aid: index + 1, title: '视频 ${index + 1}'),
        ),
      );
      final controller = LaterFocusController(
        source: source,
        activeAccount: () => account,
      );
      addTearDown(controller.dispose);
      await _show(tester, controller);
      for (int aid = 1; aid <= 25; aid++) {
        expect(find.text('视频 $aid'), findsOneWidget);
        await _complete(tester);
      }
      expect(
        source.removals.map((request) => request.aid),
        List.generate(25, (index) => index + 1),
      );
      expect(find.text('稍后再看已全部处理完'), findsOneWidget);
      expect(find.text('读取稍后再看失败'), findsNothing);
      expect(find.text('刷新队列'), findsOneWidget);
    },
  );

  testWidgets(
    'logout and account switching discard late reads and late removals',
    (tester) async {
      Account session = _account('1');
      final source = _Queue([LaterItemModel(aid: 10, title: '旧账号队首')]);
      final controller = LaterFocusController(
        source: source,
        activeAccount: () => session,
      );
      addTearDown(controller.dispose);
      await _show(tester, controller);
      final readGate = Completer<LoadingState<LaterData>>();
      source.nextRead = () => readGate.future;
      final oldRead = controller.refresh();
      session = AnonymousAccount();
      await controller.synchronizeAccount();
      readGate.complete(
        Success(LaterData(list: [LaterItemModel(aid: 10, title: '迟到的旧数据')])),
      );
      await oldRead;
      await tester.pumpAndSettle();
      expect(find.text('登录后观看稍后再看'), findsOneWidget);
      expect(find.text('迟到的旧数据'), findsNothing);

      session = _account('2');
      await controller.synchronizeAccount();
      await tester.pumpAndSettle();
      final removalGate = Completer<LoadingState<void>>();
      source.nextRemoval = () => removalGate.future;
      final oldAccount = session;
      final oldRemoval = controller.complete();
      session = _account('3');
      source.items
        ..clear()
        ..add(LaterItemModel(aid: 30, title: '新账号队首'));
      await controller.synchronizeAccount();
      removalGate.complete(const Success(null));
      await oldRemoval;
      await tester.pumpAndSettle();
      expect(source.removals.single.account, same(oldAccount));
      expect(find.text('新账号队首'), findsOneWidget);
      expect(find.text('旧账号队首'), findsNothing);
    },
  );

  test(
    'Android ignores old comment and repeat preferences and rejects content links',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await GStorage.setting.putAll({
        SettingBoxKey.showVideoReply: true,
        SettingBoxKey.showBangumiReply: true,
        SettingBoxKey.showRelatedVideo: true,
        SettingBoxKey.defaultShowComment: true,
        SettingBoxKey.showFSActionItem: true,
      });
      await GStorage.video.put(
        VideoBoxKey.playRepeat,
        PlayRepeat.autoPlayRelated.index,
      );
      expect(
        Pref.showVideoReply ||
            Pref.showBangumiReply ||
            Pref.showRelatedVideo ||
            Pref.defaultShowComment ||
            Pref.showFSActionItem,
        isFalse,
      );
      expect(Pref.playRepeat, PlayRepeat.listOrder);
      final routes = Routes.getPages.map((page) => page.name).toSet();
      expect(routes.contains('/'), isTrue);
      expect(
        routes.intersection({
          '/home',
          '/search',
          '/fav',
          '/member',
          '/history',
          '/settingsSearch',
        }),
        isEmpty,
      );
      expect(
        await PiliScheme.routePush(Uri.parse('bilibili://video/123')),
        isFalse,
      );
      expect(
        await PiliScheme.routePushFromUrl(
          'https://www.bilibili.com/video/BV1xx411c7mD',
        ),
        isFalse,
      );
    },
  );
}
