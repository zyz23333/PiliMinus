import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:PiliPlus/utils/watch_later_focus.dart';

class CommonSetting extends StatefulWidget {
  const CommonSetting({
    super.key,
    required this.settingType,
    this.showAppBar = true,
  });

  final bool showAppBar;
  final SettingType settingType;

  @override
  State<CommonSetting> createState() => _CommonSettingState();
}

class _CommonSettingState extends State<CommonSetting> {
  late EdgeInsets padding;
  late List<SettingsModel> settings;

  void _initSetting() {
    settings = widget.settingType.settings;
    if (WatchLaterFocus.enabled) {
      settings = settings
          .where(
            (item) => switch (widget.settingType) {
              SettingType.styleSetting => const {
                '横屏适配',
                'App字体设置',
                '界面缩放',
                '页面过渡动画',
                '播放页移除安全边距',
                '视频播放页使用深色主题',
                '图片质量',
                '深色下图片颜色叠加',
                '气泡提示不透明度',
                '主题模式',
                '纯黑主题',
                '应用主题',
                '屏幕帧率',
              }.contains(item.title),
              SettingType.playSetting => !const {
                '播放顺序',
                '全屏展示点赞/投币/收藏等操作按钮',
                'SuperChat (醒目留言) 显示类型',
                '全屏 SC 大小',
              }.contains(item.title),
              SettingType.videoSetting =>
                !(item.title?.contains('直播') ?? false),
              _ => false,
            },
          )
          .toList();
    }
  }

  @override
  void initState() {
    super.initState();
    _initSetting();
  }

  @override
  void didUpdateWidget(CommonSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.settingType != oldWidget.settingType) {
      _initSetting();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    padding = MediaQuery.viewPaddingOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = widget.showAppBar;
    return SimpleScaffold(
      appBar: showAppBar ? AppBar(title: Text(widget.settingType.title)) : null,
      body: ListView.builder(
        key: ValueKey(widget.settingType),
        padding: EdgeInsets.only(
          left: showAppBar ? padding.left : 0,
          right: showAppBar ? padding.right : 0,
          bottom: padding.bottom + 100,
        ),
        itemCount: settings.length,
        itemBuilder: (context, index) => settings[index].widget,
      ),
    );
  }
}
