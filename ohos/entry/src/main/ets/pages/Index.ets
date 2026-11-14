import common from '@ohos.app.ability.common';
import { FlutterPage } from '@ohos/flutter_ohos'
import NativePlugin from '../plugins/NativePlugin'

let storage = LocalStorage.getShared()
const EVENT_BACK_PRESS = 'EVENT_BACK_PRESS'

/** How often one drag may vote, so a swipe does not ask the engine on every move event. */
const VOTE_INTERVAL_MS = 120

@Entry(storage)
@Component
struct Index {
  private context = getContext(this) as common.UIAbilityContext
  @LocalStorageLink('viewId') viewId: string = "";
  private lastVote = 0;

  /**
   * The engine votes 60 fps on every vsync and never learns that a finger is down, so the whole app
   * sits at 60 on a 120 Hz panel — see `NativePlugin.voteFrameRate`. A finger on the page is exactly
   * the case that vote is for, so it is sent while one is down. The vote reports a lift, which holds
   * 120 for a moment and then falls back to 60 by itself, so a still page costs nothing.
   */
  private vote(): void {
    const now = Date.now();
    if (now - this.lastVote < VOTE_INTERVAL_MS) return;
    this.lastVote = now;
    NativePlugin.voteFrameRate();
  }

  build() {
    Column() {
      FlutterPage({ viewId: this.viewId })
    }
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down || event.type === TouchType.Move) this.vote();
    })
  }

  onBackPress(): boolean {
    this.context.eventHub.emit(EVENT_BACK_PRESS)
    return true
  }
}
