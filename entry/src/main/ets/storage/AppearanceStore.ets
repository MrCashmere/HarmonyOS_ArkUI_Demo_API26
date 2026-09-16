/**
 * 外观设置持久化（preferences）—— 教学版
 * 对应 `CLink/entry/src/main/ets/storage/AppSettingsStore.ets`。
 *
 * 教学要点｜**「通知」和「持久化」是两件事，都要做。**
 *   写进 preferences 只保证「重启后还在」，**不会**让界面刷新；
 *   让界面刷新的是 `AppStorage` 广播（见 DesignTokens.reloadAppTheme）。
 *   所以设置页的标准写法是「三连」：
 *
 *     AppSettingsStore.setBoolean(KEY, v);        // ① 落盘
 *     AppStorage.setOrCreate(KEY, v);             // ② 建/更新订阅键（供 @StorageLink 双向绑定）
 *     reloadAppTheme();                           // ③ 重算 token 并广播 accentColor
 *
 *   漏掉 ①：重启后设置丢失。
 *   漏掉 ②：@StorageLink 拿不到初值，开关会「点一下弹回去」。
 *   漏掉 ③：token 是旧值，界面不刷新。
 *
 * 这里用**同步** preferences（`getPreferencesSync`），与参考工程一致：
 * 外观设置量小、又要在首屏渲染前读完，同步读最省事也最不容易出错。
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME = 'ui_teach_appearance';

export class AppearanceStore {
  private static prefs: preferences.Preferences | null = null;

  static init(context: common.UIAbilityContext): void {
    if (AppearanceStore.prefs === null) {
      AppearanceStore.prefs = preferences.getPreferencesSync(context, {
        name: STORE_NAME
      });
    }
  }

  private static store(): preferences.Preferences {
    if (AppearanceStore.prefs === null) {
      throw new Error('AppearanceStore not initialized: 请先在 EntryAbility.onCreate 里调 init()');
    }
    return AppearanceStore.prefs;
  }

  static has(key: string): boolean {
    return AppearanceStore.store().hasSync(key);
  }

  static getBoolean(key: string, defaultValue: boolean): boolean {
    const value = AppearanceStore.store().getSync(key, defaultValue);
    return typeof value === 'boolean' ? value : defaultValue;
  }

  static getString(key: string, defaultValue: string): string {
    const value = AppearanceStore.store().getSync(key, defaultValue);
    return typeof value === 'string' ? value : defaultValue;
  }

  static getNumber(key: string, defaultValue: number): number {
    const value = AppearanceStore.store().getSync(key, defaultValue);
    return typeof value === 'number' ? value : defaultValue;
  }

  /**
   * 字符串数组。
   *
   * ⚠️ ArkTS 的 preferences **不直接支持数组**，所以这里统一存成 JSON 字符串。
   *    读入时解析失败一律回落到默认值——**存储内容可能被外部改坏或残留旧版本数据**。
   */
  static getStringArray(key: string, defaultValue: string[]): string[] {
    const raw = AppearanceStore.getString(key, '');
    if (raw.length === 0) {
      return defaultValue.slice();
    }
    try {
      const parsed = JSON.parse(raw) as Object;
      if (parsed instanceof Array) {
        return parsed.map((item: Object) => String(item));
      }
    } catch (err) {
    }
    return defaultValue.slice();
  }

  static setBoolean(key: string, value: boolean): void {
    AppearanceStore.store().putSync(key, value);
    AppearanceStore.store().flushSync();
  }

  static setString(key: string, value: string): void {
    AppearanceStore.store().putSync(key, value);
    AppearanceStore.store().flushSync();
  }

  static setNumber(key: string, value: number): void {
    AppearanceStore.store().putSync(key, value);
    AppearanceStore.store().flushSync();
  }

  static setStringArray(key: string, value: string[]): void {
    AppearanceStore.setString(key, JSON.stringify(value));
  }

  static delete(key: string): void {
    AppearanceStore.store().deleteSync(key);
    AppearanceStore.store().flushSync();
  }
}
