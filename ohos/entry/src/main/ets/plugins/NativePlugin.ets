import { UIAbility, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { audio } from '@kit.AudioKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { connection } from '@kit.NetworkKit';
import { vibrator } from '@kit.SensorServiceKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { webview } from '@kit.ArkWeb';
import { window } from '@kit.ArkUI';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

const TAG = 'NativePlugin';
const DEFAULT_URL = 'https://m.weibo.cn/';

/** Session cookies to expire on sign-out, by host and the parent domain they may be set on. */
const AUTH_HOSTS: string[][] = [
  ['m.weibo.cn', '.weibo.cn'],
  ['weibo.com', '.weibo.com'],
  ['passport.weibo.com', '.weibo.com'],
  ['login.sina.com.cn', '.sina.com.cn'],
  ['passport.sina.cn', '.sina.cn'],
];
const AUTH_NAMES: string[] = ['SUB', 'SUBP', 'ALF', 'SSOLoginState', 'MLOGIN', 'SCF'];

/**
 * HarmonyOS side of `app.inf.flutter/native`, mirroring MainActivity.kt. Picture-in-picture,
 * setting the media volume and Motion Photo files have no public equivalent here, so those
 * report failure or fall back (a live photo is saved as its still image).
 */
export default class NativePlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private ability: UIAbility | null = null;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'app.inf.flutter/native');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.ability = binding.getAbility();
  }

  onDetachedFromAbility(): void {
    this.ability = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.handle(call, result).catch((error: BusinessError) => {
      Log.e(TAG, `${call.method} failed: ${error?.code} ${error?.message}`);
      result.error('native_error', error?.message ?? `${error}`, null);
    });
  }

  private async handle(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'getCookies':
        result.success(webview.WebCookieManager.fetchCookieSync(this.url(call)) ?? '');
        break;
      case 'setCookie':
        webview.WebCookieManager.configCookieSync(this.url(call), this.str(call, 'value') ?? '');
        await webview.WebCookieManager.saveCookieAsync();
        result.success(true);
        break;
      case 'clearCookies':
        webview.WebCookieManager.clearAllCookiesSync();
        await webview.WebCookieManager.saveCookieAsync();
        result.success(true);
        break;
      case 'clearAuthCookies':
        // Like Android, a cookie's Domain is not reported, so expire each name both host-only
        // and on the parent domain.
        for (const host of AUTH_HOSTS) {
          const url = `https://${host[0]}/`;
          for (const name of AUTH_NAMES) {
            webview.WebCookieManager.configCookieSync(url, `${name}=; Max-Age=0; Path=/; Secure`);
            webview.WebCookieManager.configCookieSync(url, `${name}=; Max-Age=0; Path=/; Domain=${host[1]}; Secure`);
          }
        }
        await webview.WebCookieManager.saveCookieAsync();
        result.success(true);
        break;
      case 'userAgent':
        result.success(webview.WebviewController.getDefaultUserAgent());
        break;
      case 'openUrl':
        result.success(await this.openUrl(this.str(call, 'url')));
        break;
      case 'isMetered':
        result.success(this.isMetered());
        break;
      case 'isPipAvailable':
      case 'enterPip':
      case 'setVolume':
        result.success(false);
        break;
      case 'peakRefreshRate':
        result.success(null);
        break;
      case 'saveImage':
        result.success(await this.saveToGallery(this.str(call, 'path'), this.str(call, 'name') ?? 'INF-image.jpg',
          photoAccessHelper.PhotoType.IMAGE));
        break;
      case 'saveMotionPhoto':
        result.success(await this.saveToGallery(this.str(call, 'image'), this.str(call, 'name') ?? 'INF-live.jpg',
          photoAccessHelper.PhotoType.IMAGE));
        break;
      case 'saveVideo':
        result.success(await this.saveToGallery(this.str(call, 'path'), this.str(call, 'name') ?? 'INF-video.mp4',
          photoAccessHelper.PhotoType.VIDEO));
        break;
      case 'brightness': {
        const own = (await this.window()).getWindowProperties().brightness;
        result.success(own >= 0 ? own : null);
        break;
      }
      case 'setBrightness': {
        const value = this.num(call, 'value') ?? -1;
        await (await this.window()).setWindowBrightness(value < 0 ? -1 : Math.min(Math.max(value, 0.01), 1));
        result.success(true);
        break;
      }
      case 'volume': {
        const manager = audio.getAudioManager().getVolumeManager().getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID);
        const max = Math.max(manager.getMaxVolumeSync(audio.AudioVolumeType.MEDIA), 1);
        result.success(manager.getVolumeSync(audio.AudioVolumeType.MEDIA) / max);
        break;
      }
      case 'keepScreenOn':
        await (await this.window()).setWindowKeepScreenOn(call.argument('on') === true);
        result.success(true);
        break;
      case 'haptic':
        result.success(await this.haptic(this.str(call, 'kind')));
        break;
      case 'share':
        await this.share(this.str(call, 'text'), this.str(call, 'path'), this.str(call, 'mime'));
        result.success(true);
        break;
      default:
        result.notImplemented();
    }
  }

  private url(call: MethodCall): string {
    return this.str(call, 'url') ?? DEFAULT_URL;
  }

  private str(call: MethodCall, key: string): string | null {
    const value: Object | null = call.argument(key);
    return typeof value === 'string' && value.length > 0 ? value : null;
  }

  private num(call: MethodCall, key: string): number | null {
    const value: Object | null = call.argument(key);
    return typeof value === 'number' ? value : null;
  }

  private context(): common.UIAbilityContext {
    if (this.ability == null) throw new Error('no ability');
    return this.ability.context;
  }

  private window(): Promise<window.Window> {
    return window.getLastWindow(this.context());
  }

  private async openUrl(url: string | null): Promise<boolean> {
    if (url == null) return false;
    try {
      await this.context().startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url,
      });
      return true;
    } catch (error) {
      return false;
    }
  }

  private isMetered(): boolean {
    try {
      const net = connection.getDefaultNetSync();
      if (net.netId === 0) return true;
      const caps = connection.getNetCapabilitiesSync(net).networkCap ?? [];
      return !caps.includes(connection.NetCap.NET_CAPABILITY_NOT_METERED);
    } catch (error) {
      return true;
    }
  }

  /**
   * The system save dialog writes into the gallery without the restricted WRITE_IMAGEVIDEO
   * permission; the user confirms each save. Null when they decline.
   */
  private async saveToGallery(path: string | null, name: string, type: photoAccessHelper.PhotoType): Promise<string | null> {
    if (path == null || !fs.accessSync(path)) throw new Error('missing file');
    const dot = name.lastIndexOf('.');
    const config: photoAccessHelper.PhotoCreationConfig = {
      title: dot > 0 ? name.substring(0, dot) : name,
      fileNameExtension: dot > 0 ? name.substring(dot + 1) : (type === photoAccessHelper.PhotoType.VIDEO ? 'mp4' : 'jpg'),
      photoType: type,
    };
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context());
    try {
      const targets = await helper.showAssetsCreationDialog([fileUri.getUriFromPath(path)], [config]);
      if (targets.length === 0) return null;
      const source = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const target = fs.openSync(targets[0], fs.OpenMode.WRITE_ONLY);
      try {
        fs.copyFileSync(source.fd, target.fd);
      } finally {
        fs.closeSync(source);
        fs.closeSync(target);
      }
      return type === photoAccessHelper.PhotoType.VIDEO ? `Movies/${name}` : `Pictures/${name}`;
    } finally {
      helper.release();
    }
  }

  /** System presets, tuned per motor; the touch usage honours the system haptics switch. */
  private async haptic(kind: string | null): Promise<boolean> {
    const preferred: string[] = kind === 'longPress' || kind === 'error' ? ['haptic.effect.hard', 'haptic.clock.timer']
      : kind === 'success' || kind === 'toggleOn' || kind === 'threshold' ? ['haptic.effect.sharp', 'haptic.clock.timer']
        : ['haptic.effect.soft', 'haptic.clock.timer'];
    for (const effectId of preferred) {
      try {
        if (!vibrator.isSupportEffectSync(effectId)) continue;
        await vibrator.startVibration({ type: 'preset', effectId: effectId, count: 1 }, { usage: 'touch' });
        return true;
      } catch (error) {
        continue;
      }
    }
    return false;
  }

  private async share(text: string | null, path: string | null, mime: string | null): Promise<void> {
    let data: systemShare.SharedData;
    if (path != null) {
      const type = mime != null ? utd.getUniformDataTypeByMIMEType(mime) : utd.UniformDataType.FILE;
      data = new systemShare.SharedData({ utd: type, uri: fileUri.getUriFromPath(path) });
    } else {
      data = new systemShare.SharedData({ utd: utd.UniformDataType.PLAIN_TEXT, content: text ?? '' });
    }
    await new systemShare.ShareController(data).show(this.context(), {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT,
    });
  }
}
