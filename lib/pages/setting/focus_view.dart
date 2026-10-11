import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/pages/setting/common_setting.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class FocusSettingPage extends StatelessWidget {
  const FocusSettingPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: SafeArea(
      child: ListView(
        children: [
          for (final (type, icon) in const [
            (SettingType.videoSetting, Icons.video_settings_outlined),
            (SettingType.playSetting, Icons.touch_app_outlined),
            (SettingType.styleSetting, Icons.style_outlined),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(type.title),
              onTap: () => Get.to(() => CommonSetting(settingType: type)),
            ),
        ],
      ),
    ),
  );
}
