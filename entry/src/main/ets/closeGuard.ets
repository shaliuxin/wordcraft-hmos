// 关闭守卫：与兄弟工程（DeckCraft/PhotoCraft/GridCraft）同一套机制。
// 系统关窗（窗口关闭按钮 / 2in1 任务关闭）默认会直接销毁窗口，绕过宿主；
// 这里把关闭拦截下来交给 Rust 检查未保存文档，确认后再放行。
// 选中/活动的编辑页把关闭请求注册为 native.close()；Rust 侧经 close_requested()
// 决定是否有未保存改动，有则弹出「是否保存」提示并暂缓，确认后通知宿主放行。
let requestPageClose: (() => void) | null = null;
let confirmedClose: boolean = false;

export function resetCloseGuard(): void {
  confirmedClose = false;
  requestPageClose = null;
}

export function setCloseRequest(handler: (() => void) | null): void {
  requestPageClose = handler;
}

// 系统发起关闭时调用：返回 true 拦截本次关闭，交给 Rust 检查未保存文档；
// 已确认放行（confirmedClose）或没有注册处理器时返回 false，放行后续关闭。
export function requestWindowClose(): boolean {
  if (confirmedClose || requestPageClose === null) {
    return false;
  }
  requestPageClose();
  return true;
}

// Rust 侧确认可以关闭（无未保存改动，或用户已选保存/丢弃）后调用，放行后续关闭。
export function allowConfirmedClose(): void {
  confirmedClose = true;
}

export function restoreCloseGuard(): void {
  confirmedClose = false;
}
