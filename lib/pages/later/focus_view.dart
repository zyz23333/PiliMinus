import 'dart:async';

import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models_new/later/list.dart';
import 'package:PiliPlus/pages/later/focus_queue.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class LaterFocusPage extends StatefulWidget {
  const LaterFocusPage({super.key});

  @override
  State<LaterFocusPage> createState() => _LaterFocusPageState();
}

class _LaterFocusPageState extends State<LaterFocusPage> {
  late final LaterFocusController _controller;
  StreamSubscription? _loginListener;
  StreamSubscription? _accountListener;
  bool _opening = false;
  String? _playError;
  int? _playErrorAid;

  @override
  void initState() {
    super.initState();
    _controller = LaterFocusController(
      source: const BiliLaterQueueSource(),
      activeAccount: () => Accounts.main,
    );
    _loginListener = Get.find<AccountService>().isLogin.listen(
      (_) => _controller.synchronizeAccount(),
    );
    _accountListener = Accounts.account.watch().listen(
      (_) => _controller.synchronizeAccount(),
    );
    _controller.refresh();
  }

  Future<void> _openVideo(LaterItemModel item) async {
    if (_opening) return;
    final account = Accounts.main;
    setState(() {
      _opening = true;
      _playError = null;
      _playErrorAid = item.aid;
    });
    try {
      if (item.isPugv == true) {
        await PageUtils.viewPugv(
          seasonId: item.aid,
          canNavigate: () => mounted && identical(account, Accounts.main),
        );
        return;
      }
      if (item.isPgc == true) {
        if (item.bangumi?.epId case final epId?) {
          await PageUtils.viewPgc(
            epId: epId,
            canNavigate: () => mounted && identical(account, Accounts.main),
          );
        } else if (item.redirectUrl?.isNotEmpty == true) {
          if (!PageUtils.viewPgcFromUri(
            item.redirectUrl!,
            canNavigate: () => mounted && identical(account, Accounts.main),
          )) {
            throw StateError('该视频暂不支持播放，可在首页点击完成移除');
          }
        } else {
          throw StateError('该视频暂不支持播放，可在首页点击完成移除');
        }
        return;
      }
      final cid =
          item.cid ?? await SearchHttp.ab2c(aid: item.aid, bvid: item.bvid);
      if (!mounted || !identical(account, Accounts.main)) return;
      if (cid == null || cid <= 0 || (item.aid == null && item.bvid == null)) {
        throw StateError('视频已失效或暂时无法播放，可重试或点击完成移除');
      }
      await PageUtils.toVideoPage(
        aid: item.aid,
        bvid: item.bvid,
        cid: cid,
        cover: item.pic,
        title: item.title,
        dimension: item.dimension,
      );
    } catch (e) {
      if (mounted && identical(account, Accounts.main)) {
        setState(() => _playError = e.toString());
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _logout() async {
    final account = Accounts.main;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出账号'),
        content: const Text('退出当前账号登录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _controller.clearSession();
    await Accounts.deleteAll({account});
  }

  @override
  void dispose() {
    _loginListener?.cancel();
    _accountListener?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LaterFocusView(
    controller: _controller,
    openVideo: _openVideo,
    onLogin: () => Get.toNamed('/loginPage'),
    onLogout: _logout,
    onSettings: () => Get.toNamed('/setting'),
    opening: _opening,
    playError: _playError,
    playErrorAid: _playErrorAid,
  );
}

/// The same queue screen is used in production and in flow tests without a media engine.
class LaterFocusView extends StatelessWidget {
  const LaterFocusView({
    super.key,
    required this.controller,
    required this.openVideo,
    required this.onLogin,
    required this.onLogout,
    required this.onSettings,
    this.opening = false,
    this.playError,
    this.playErrorAid,
  });

  final LaterFocusController controller;
  final Future<void> Function(LaterItemModel) openVideo;
  final VoidCallback onLogin;
  final VoidCallback onLogout;
  final VoidCallback onSettings;
  final bool opening;
  final String? playError;
  final int? playErrorAid;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final busy =
          controller.completing ||
          opening ||
          controller.status == LaterQueueStatus.loading;
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 20,
          title: const Text('稍后再看'),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: busy ? null : controller.refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '设置',
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
            if (controller.status != LaterQueueStatus.signedOut)
              IconButton(
                tooltip: '退出账号',
                onPressed: onLogout,
                icon: const Icon(Icons.logout),
              ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: busy ? () async {} : controller.refresh,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: _content(context, busy),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  List<Widget> _content(BuildContext context, bool busy) {
    switch (controller.status) {
      case LaterQueueStatus.signedOut:
        return [
          const SizedBox(height: 60),
          const Icon(Icons.playlist_play, size: 56),
          const SizedBox(height: 20),
          const Text('登录后观看稍后再看', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onLogin, child: const Text('登录')),
        ];
      case LaterQueueStatus.loading:
        return [
          const Padding(
            padding: EdgeInsets.all(60),
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      case LaterQueueStatus.empty:
        return [
          const SizedBox(height: 60),
          const Icon(Icons.check_circle_outline, size: 56),
          const SizedBox(height: 20),
          const Text('稍后再看已全部处理完', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Text('在 B 站官方客户端或网页加入视频后，回到这里刷新。', textAlign: TextAlign.center),
          TextButton(onPressed: controller.refresh, child: const Text('刷新队列')),
        ];
      case LaterQueueStatus.error:
        return [
          const SizedBox(height: 60),
          const Text('读取稍后再看失败', textAlign: TextAlign.center),
          Text(controller.error ?? '请稍后重试', textAlign: TextAlign.center),
          TextButton(onPressed: controller.refresh, child: const Text('重试')),
        ];
      case LaterQueueStatus.ready:
        final item = controller.current!;
        return [
          const Text('当前视频 · 最早添加'),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: item.pic?.isNotEmpty == true
                  ? LayoutBuilder(
                      builder: (context, constraints) => NetworkImgLayer(
                        src: item.pic,
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                      ),
                    )
                  : const ColoredBox(
                      color: Color(0xFFE8E8E8),
                      child: Icon(Icons.ondemand_video, size: 56),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            item.title ?? '失效视频',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (item.owner?.name case final name?) ...[
            const SizedBox(height: 8),
            Text('UP 主：$name'),
          ],
          if (item.progress == -1)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('已看完 · 仍需手动完成'),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: busy ? null : () => openVideo(item),
            icon: const Icon(Icons.play_arrow),
            label: Text(opening ? '正在打开…' : '播放'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy || item.aid == null ? null : controller.complete,
            icon: const Icon(Icons.check),
            label: Text(controller.completing ? '正在完成…' : '完成'),
          ),
          const SizedBox(height: 12),
          const Text('完成后会从 B 站稍后再看移除当前视频。', textAlign: TextAlign.center),
          if (playError != null && playErrorAid == item.aid)
            Text(
              playError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (controller.completionError != null)
            Text(
              '移除失败，请重试：${controller.completionError}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ];
    }
  }
}
