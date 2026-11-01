import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { webview } from '@kit.ArkWeb';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import NativePlugin from '../plugins/NativePlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // The Sina login chain hops across weibo.com, weibo.cn and sina.com.cn.
    webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true)
    flutterEngine.getPlugins()?.add(new NativePlugin())
  }
}
