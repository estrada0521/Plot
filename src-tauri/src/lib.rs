use serde::Serialize;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tauri::menu::{MenuBuilder, MenuItem, SubmenuBuilder};
use tauri::{
    AppHandle, Emitter, LogicalPosition, Manager, State, WebviewUrl, WebviewWindowBuilder,
};

/// 新規ウィンドウへ「起動時に開くファイル」を引き渡すための保管庫（label → path）。
#[derive(Default)]
struct PendingFiles(Mutex<HashMap<String, String>>);

/// データを読み込んだ（＝空でない）ウィンドウの label 集合。
#[derive(Default)]
struct LoadedWindows(Mutex<HashSet<String>>);

/// 各ウィンドウの plot パネル実寸（論理px, label → (幅, 高さ)）。タイル配置で使用。
#[derive(Default)]
struct WindowMetrics(Mutex<HashMap<String, (f64, f64)>>);

/// フィルタウィンドウの初期データ（対象ウィンドウ label と列一覧）。
#[derive(Clone, Serialize)]
struct FilterInit {
    source_label: String,
    name: String,
    columns: Vec<String>,
}
#[derive(Default)]
struct FilterInits(Mutex<HashMap<String, FilterInit>>);

/// フロントが plot パネルのサイズを報告する（リサイズ毎）。
#[tauri::command]
fn report_panel_size(window: tauri::Window, width: f64, height: f64, metrics: State<WindowMetrics>) {
    if let Ok(mut m) = metrics.0.lock() {
        m.insert(window.label().to_string(), (width, height));
    }
}

static WIN_SEQ: AtomicU64 = AtomicU64::new(0);

/// フロントが起動直後に呼び、自ウィンドウに割り当てられたファイルパスを受け取る。
#[tauri::command]
fn take_pending_file(window: tauri::Window, pending: State<PendingFiles>) -> Option<String> {
    pending.0.lock().ok()?.remove(window.label())
}

/// フロントがデータ読み込み成功時に呼び、自ウィンドウを「空でない」と記録する。
#[tauri::command]
fn mark_window_loaded(window: tauri::Window, loaded: State<LoadedWindows>) {
    if let Ok(mut s) = loaded.0.lock() {
        s.insert(window.label().to_string());
    }
}

/// フィルタウィンドウが起動直後に呼び、対象ウィンドウ label と列一覧を受け取る。
#[tauri::command]
fn take_filter_init(window: tauri::Window, inits: State<FilterInits>) -> Option<FilterInit> {
    inits.0.lock().ok()?.get(window.label()).cloned()
}

/// テキスト（CSV）を指定パスへ新規保存する。元データには触れない。
#[tauri::command]
fn write_text_file(path: String, content: String) -> Result<(), String> {
    fs::write(&path, content).map_err(|e| e.to_string())
}

fn close_empty_main_window(app: &AppHandle) {
    let Some(main) = app.get_webview_window("main") else {
        return;
    };
    let loaded = app
        .try_state::<LoadedWindows>()
        .and_then(|state| state.0.lock().ok().map(|s| s.contains("main")))
        .unwrap_or(false);
    if !loaded {
        let _ = main.close();
    }
}

fn schedule_close_empty_main_window(app: &AppHandle) {
    let app = app.clone();
    std::thread::spawn(move || {
        for delay in [100_u64, 400, 900] {
            std::thread::sleep(Duration::from_millis(delay));
            close_empty_main_window(&app);
        }
    });
}

#[derive(Serialize)]
struct Dataset {
    name: String,
    columns: Vec<String>,
    rows: Vec<Vec<f64>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    default_x: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    default_y: Option<String>,
}

/// 1セルを数値へ。空欄・非数値は NaN（JSON では null）として保持し、行は捨てない。
fn cell(t: &str) -> f64 {
    let t = t.trim();
    if t.is_empty() {
        f64::NAN
    } else {
        t.parse::<f64>().unwrap_or(f64::NAN)
    }
}

/// 同フォルダの metadata.json から default_x / default_y を読む（無ければ None）。
fn read_meta_defaults(path: &str) -> (Option<String>, Option<String>, Option<String>) {
    let Some(dir) = Path::new(path).parent() else {
        return (None, None, None);
    };
    let Ok(txt) = fs::read_to_string(dir.join("metadata.json")) else {
        return (None, None, None);
    };
    let Ok(v) = serde_json::from_str::<serde_json::Value>(&txt) else {
        return (None, None, None);
    };
    let get = |k: &str| {
        v.get(k)
            .and_then(|x| x.as_str())
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
    };
    (get("default_x"), get("default_y"), get("display_name"))
}

/// 列・行を Dataset にまとめ、metadata の既定軸が実在する場合のみ採用する。
fn finalize(name: String, columns: Vec<String>, rows: Vec<Vec<f64>>, path: &str) -> Result<Dataset, String> {
    if columns.is_empty() {
        return Err("列が見つかりません".into());
    }
    if rows.is_empty() {
        return Err("数値データが見つかりません".into());
    }
    let (dx, dy, display_name) = read_meta_defaults(path);
    let exists = |c: &Option<String>| c.as_ref().is_some_and(|n| columns.iter().any(|col| col == n));
    let default_x = if exists(&dx) { dx } else { None };
    let default_y = if exists(&dy) { dy } else { None };
    Ok(Dataset {
        name,
        columns,
        rows,
        display_name,
        default_x,
        default_y,
    })
}

/// 区切り文字でデータ行をパース（ncol に合わせて NaN 埋め、全 NaN 行は除外）。
fn parse_rows<'a>(lines: impl Iterator<Item = &'a str>, ncol: usize, comma: bool) -> Vec<Vec<f64>> {
    let mut rows = Vec::new();
    for line in lines {
        let cells: Vec<f64> = if comma {
            line.split(',').map(cell).collect()
        } else {
            line.split_whitespace().map(cell).collect()
        };
        if cells.is_empty() {
            continue;
        }
        let row: Vec<f64> = (0..ncol).map(|i| *cells.get(i).unwrap_or(&f64::NAN)).collect();
        if row.iter().all(|v| v.is_nan()) {
            continue;
        }
        rows.push(row);
    }
    rows
}

/// 形式を自動判別してパースする。
/// - `[Data]` セクション付き（MPMS / Quantum Design）→ カンマ区切り
/// - SPEC 形式（`#L` 列名 + 空白区切り）→ 放射光ビームライン txt
/// - Rigaku `.ras`（`*RAS_INT_START`〜`*RAS_INT_END`）
/// - それ以外の csv / dat → 単純な表
fn parse_file(path: &str) -> Result<Dataset, String> {
    let ext = Path::new(path)
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase();
    let name = Path::new(path)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("data")
        .to_string();

    // .ras 等は非 UTF-8 ヘッダを含むのでロスレスに読めない場合は lossy 変換。
    let content = match fs::read_to_string(path) {
        Ok(s) => s,
        Err(_) => {
            let bytes = fs::read(path).map_err(|e| format!("読み込み失敗: {e}"))?;
            String::from_utf8_lossy(&bytes).into_owned()
        }
    };

    if ext == "ras" {
        return parse_ras(&content, name, path);
    }
    if let Some(idx) = content
        .lines()
        .position(|l| l.trim().eq_ignore_ascii_case("[data]"))
    {
        return parse_sectioned(&content, idx, name, path);
    }
    if content.lines().any(|l| l.starts_with("#L")) {
        return parse_spec(&content, name, path);
    }
    parse_table(&content, ext == "csv", name, path)
}

/// 単純な csv/dat。先頭行が全数値ならヘッダなし(col1…)、そうでなければヘッダ行。
fn parse_table(content: &str, comma: bool, name: String, path: &str) -> Result<Dataset, String> {
    let lines: Vec<&str> = content.lines().filter(|l| !l.trim().is_empty()).collect();
    if lines.is_empty() {
        return Err("空ファイルです".into());
    }
    let split = |l: &str| -> Vec<String> {
        if comma {
            l.split(',').map(|s| s.trim().to_string()).collect()
        } else {
            l.split_whitespace().map(|s| s.to_string()).collect()
        }
    };
    let first = split(lines[0]);
    let first_numeric = !first.is_empty() && first.iter().all(|t| t.parse::<f64>().is_ok());
    let (columns, start) = if first_numeric {
        ((0..first.len()).map(|i| format!("col{}", i + 1)).collect::<Vec<_>>(), 0)
    } else {
        (first.clone(), 1)
    };
    let ncol = columns.len();
    let rows = parse_rows(lines[start..].iter().copied(), ncol, comma);
    finalize(name, columns, rows, path)
}

/// `[Data]` セクション形式（MPMS 等）。直後の行を列名、以降をカンマ区切りデータ。
fn parse_sectioned(content: &str, data_idx: usize, name: String, path: &str) -> Result<Dataset, String> {
    let lines: Vec<&str> = content.lines().collect();
    let mut i = data_idx + 1;
    while i < lines.len() && lines[i].trim().is_empty() {
        i += 1;
    }
    if i >= lines.len() {
        return Err("[Data] 以降にデータがありません".into());
    }
    let columns: Vec<String> = lines[i].split(',').map(|s| s.trim().to_string()).collect();
    let ncol = columns.len();
    let rows = parse_rows(lines[i + 1..].iter().copied(), ncol, true);
    finalize(name, columns, rows, path)
}

/// SPEC 形式（放射光 txt）。最初の `#L` 行を列名、`#` 以外の行を空白区切りデータ。
fn parse_spec(content: &str, name: String, path: &str) -> Result<Dataset, String> {
    let lcol = content
        .lines()
        .find(|l| l.starts_with("#L"))
        .ok_or("SPEC ヘッダ(#L)が見つかりません")?;
    let columns: Vec<String> = lcol[2..].split_whitespace().map(|s| s.to_string()).collect();
    let ncol = columns.len();
    let data = content
        .lines()
        .filter(|l| !l.trim().is_empty() && !l.starts_with('#'));
    let rows = parse_rows(data, ncol, false);
    finalize(name, columns, rows, path)
}

/// Rigaku `.ras`。`*RAS_INT_START`〜`*RAS_INT_END` の空白区切り（2theta, intensity, …）。
fn parse_ras(content: &str, name: String, path: &str) -> Result<Dataset, String> {
    let mut data: Vec<&str> = Vec::new();
    let mut in_data = false;
    for line in content.lines() {
        let t = line.trim();
        if t.starts_with("*RAS_INT_START") {
            in_data = true;
            continue;
        }
        if t.starts_with("*RAS_INT_END") {
            in_data = false;
            continue;
        }
        if in_data && !t.is_empty() && !t.starts_with('*') {
            data.push(t);
        }
    }
    let ncol = data
        .iter()
        .map(|l| l.split_whitespace().count())
        .max()
        .unwrap_or(0);
    let columns: Vec<String> = match ncol {
        0 => return Err("RAS データが見つかりません".into()),
        2 => vec!["2theta".into(), "intensity".into()],
        3 => vec!["2theta".into(), "intensity".into(), "attenuation".into()],
        n => (0..n).map(|i| format!("col{}", i + 1)).collect(),
    };
    let rows = parse_rows(data.into_iter(), ncol, false);
    finalize(name, columns, rows, path)
}

#[tauri::command]
fn read_dataset(path: String) -> Result<Dataset, String> {
    parse_file(&path)
}

/// Finder で対象ファイルを表示（選択状態で開く）。
#[tauri::command]
fn reveal_in_finder(path: String) -> Result<(), String> {
    Command::new("open")
        .arg("-R")
        .arg(&path)
        .spawn()
        .map(|_| ())
        .map_err(|e| e.to_string())
}

/// 指定エディタで開く。editor が空なら既定のテキストエディタ（open -t）で開く。
#[tauri::command]
fn open_with_editor(path: String, editor: String) -> Result<(), String> {
    let editor = editor.trim();
    let mut cmd = Command::new("open");
    if editor.is_empty() {
        cmd.arg("-t").arg(&path);
    } else {
        cmd.arg("-a").arg(editor).arg(&path);
    }
    cmd.spawn().map(|_| ()).map_err(|e| e.to_string())
}

/// パネル領域（ヘッダー＋プロット）を画面からキャプチャし Downloads に PNG 保存。
/// 引数は論理座標（左上原点, points）と寸法。
#[tauri::command]
fn save_panel_image(x: f64, y: f64, w: f64, h: f64, name: String) -> Result<String, String> {
    let home = std::env::var("HOME").map_err(|e| e.to_string())?;
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let safe: String = name
        .chars()
        .map(|c| if c == '/' || c == ':' { '_' } else { c })
        .collect();
    let file = format!("{home}/Downloads/{safe}-{ts}.png");
    let rect = format!(
        "{},{},{},{}",
        x.round() as i64,
        y.round() as i64,
        w.round() as i64,
        h.round() as i64
    );
    let status = Command::new("screencapture")
        .args(["-x", "-R", &rect, &file])
        .status()
        .map_err(|e| e.to_string())?;
    if !status.success() {
        return Err("screencapture に失敗しました".into());
    }
    Ok(file)
}

/// 対象ファイルのパスをクリップボードへコピー（pbcopy）。
#[tauri::command]
fn copy_path(text: String) -> Result<(), String> {
    let mut child = Command::new("pbcopy")
        .stdin(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    child
        .stdin
        .as_mut()
        .ok_or("pbcopy stdin unavailable")?
        .write_all(text.as_bytes())
        .map_err(|e| e.to_string())?;
    child.wait().map_err(|e| e.to_string())?;
    Ok(())
}

const MENU_NEW_WINDOW: &str = "new-window";
const MENU_SETTINGS: &str = "settings";

/// 設定ウィンドウを開く（既にあれば前面化＝シングルトン）。
fn open_settings_window(app: &AppHandle) -> tauri::Result<()> {
    if let Some(w) = app.get_webview_window("settings") {
        let _ = w.set_focus();
        return Ok(());
    }
    WebviewWindowBuilder::new(app, "settings", WebviewUrl::App("settings.html".into()))
        .title("Settings")
        .inner_size(360.0, 156.0)
        .resizable(false)
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .focused(true)
        .build()?;
    Ok(())
}

/// 対象ウィンドウ（source_label）に紐づくフィルタウィンドウを開く（既にあれば前面化）。
#[tauri::command]
fn open_filter_window(
    app: AppHandle,
    source_label: String,
    name: String,
    columns: Vec<String>,
    inits: State<FilterInits>,
) -> Result<(), String> {
    let label = format!("filter-{source_label}");
    if let Ok(mut m) = inits.0.lock() {
        m.insert(
            label.clone(),
            FilterInit {
                source_label: source_label.clone(),
                name,
                columns,
            },
        );
    }
    if let Some(w) = app.get_webview_window(&label) {
        let _ = w.set_focus();
        return Ok(());
    }
    // 対象（フォーカス中）ウィンドウの真下に、重ならないよう少し離して表示する。
    const GAP: f64 = 8.0;
    let near = app.get_webview_window(&source_label).and_then(|w| {
        let sf = w.scale_factor().ok()?;
        let pos = w.outer_position().ok()?.to_logical::<f64>(sf);
        let size = w.outer_size().ok()?.to_logical::<f64>(sf);
        Some((pos.x, pos.y + size.height + GAP))
    });
    let mut builder = WebviewWindowBuilder::new(&app, &label, WebviewUrl::App("filter.html".into()))
        .title("Filter")
        .inner_size(300.0, 360.0)
        .min_inner_size(220.0, 200.0)
        .resizable(true)
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .focused(true);
    if let Some((x, y)) = near {
        builder = builder.position(x, y);
    }
    let win = builder.build().map_err(|e| e.to_string())?;
    // フィルタウィンドウを閉じたら対象ウィンドウのフィルタを問答無用で解除する。
    let app_for_event = app.clone();
    win.on_window_event(move |event| {
        if let tauri::WindowEvent::Destroyed = event {
            let _ = app_for_event.emit_to(source_label.as_str(), "filter-reset", ());
        }
    });
    Ok(())
}
const MENU_NEXT_WINDOW: &str = "next-window";
const MENU_PREV_WINDOW: &str = "prev-window";
const MENU_ARRANGE: &str = "arrange-windows";
const MENU_OPEN: &str = "open-file";
const MENU_REVEAL: &str = "reveal-in-finder";
const MENU_OPEN_EDITOR: &str = "open-in-editor";
const MENU_COPY_PATH: &str = "copy-path";
const MENU_FILTER: &str = "filter-data";

/// File メニューの操作を、フォーカス中のウィンドウのフロントへ通知する
/// （対象ファイルはフロントが保持しているため）。
fn dispatch_menu_action(app: &AppHandle, action: &str) {
    if let Some(w) = app
        .webview_windows()
        .values()
        .find(|w| w.is_focused().unwrap_or(false))
    {
        // emit はブロードキャストのため、フォーカス中ウィンドウのみに届くよう emit_to を使う。
        let _ = app.emit_to(w.label(), "menu-action", action);
    }
}

/// 開いているウィンドウを画面左上から行詰めでタイル配置する。
/// plot とその filter ウィンドウは横並び（plot 左・filter 右）の1ユニットとして扱う。
fn arrange_windows(app: &AppHandle) {
    let all = app.webview_windows();
    if all.is_empty() {
        return;
    }
    let any = all.values().next().unwrap();

    // 配置領域（プライマリモニタ）。取得できなければ既定値。
    let (area_x, area_y, area_w) = any
        .primary_monitor()
        .ok()
        .flatten()
        .map(|m| {
            let s = m.scale_factor();
            let p = m.position().to_logical::<f64>(s);
            let sz = m.size().to_logical::<f64>(s);
            (p.x, p.y, sz.width)
        })
        .unwrap_or((0.0, 0.0, 1440.0));

    // plot パネル実寸スナップショット（無ければウィンドウ実寸で代用）。
    let metric_map: HashMap<String, (f64, f64)> = app
        .state::<WindowMetrics>()
        .0
        .lock()
        .map(|m| m.clone())
        .unwrap_or_default();
    let dims = |label: &str, w: &tauri::WebviewWindow| -> (f64, f64) {
        if let Some(d) = metric_map.get(label).copied() {
            return d;
        }
        let s = w.scale_factor().unwrap_or(1.0);
        w.outer_size()
            .map(|sz| {
                let l = sz.to_logical::<f64>(s);
                (l.width, l.height)
            })
            .unwrap_or((360.0, 320.0))
    };

    // ユニット構築: plot（main / plot-*）ごとに [plot, その filter] をまとめる。
    // 残り（settings や対応 plot の無い filter）は単独ユニット。
    let mut plot_labels: Vec<String> = all
        .keys()
        .filter(|l| l.as_str() == "main" || l.starts_with("plot-"))
        .cloned()
        .collect();
    plot_labels.sort();
    let mut units: Vec<Vec<String>> = Vec::new();
    let mut used: Vec<String> = Vec::new();
    for pl in &plot_labels {
        used.push(pl.clone());
        let mut unit = vec![pl.clone()];
        let fl = format!("filter-{pl}");
        if all.contains_key(&fl) {
            unit.push(fl.clone());
            used.push(fl);
        }
        units.push(unit);
    }
    let mut rest: Vec<String> = all.keys().filter(|l| !used.contains(l)).cloned().collect();
    rest.sort();
    for r in rest {
        units.push(vec![r]);
    }

    let gap = 12.0;
    let margin_top = 28.0; // メニューバー分
    let mut x = area_x + gap;
    let mut y = area_y + margin_top;
    let mut row_h: f64 = 0.0; // 行内パネル高さの最大
    for unit in &units {
        let sizes: Vec<(f64, f64)> = unit
            .iter()
            .filter_map(|l| all.get(l).map(|w| dims(l, w)))
            .collect();
        if sizes.is_empty() {
            continue;
        }
        let unit_w: f64 =
            sizes.iter().map(|d| d.0).sum::<f64>() + gap * (sizes.len() as f64 - 1.0);
        // ユニット単位で行末折り返し（plot と filter を分断しない）。
        if x > area_x + gap && x + unit_w > area_x + area_w - gap {
            x = area_x + gap;
            y += row_h + gap;
            row_h = 0.0;
        }
        let mut ux = x;
        for (i, l) in unit.iter().enumerate() {
            let (pw, ph) = sizes[i];
            if let Some(w) = all.get(l) {
                let _ = w.set_position(LogicalPosition::new(ux, y));
            }
            ux += pw + gap;
            if ph > row_h {
                row_h = ph;
            }
        }
        x += unit_w + gap;
    }
}

/// 開いているウィンドウのフォーカスを順に切り替える（label 順で巡回）。
fn cycle_windows(app: &AppHandle, forward: bool) {
    let mut wins: Vec<_> = app.webview_windows().into_iter().collect();
    if wins.len() < 2 {
        return;
    }
    wins.sort_by(|a, b| a.0.cmp(&b.0));
    let n = wins.len();
    let cur = wins
        .iter()
        .position(|(_, w)| w.is_focused().unwrap_or(false))
        .unwrap_or(0);
    let idx = if forward {
        (cur + 1) % n
    } else {
        (cur + n - 1) % n
    };
    let _ = wins[idx].1.set_focus();
}

/// 新規ウィンドウを生成する。pending_path があればそのファイルを開くよう保管する。
fn spawn_window(app: &AppHandle, pending_path: Option<&str>) -> tauri::Result<()> {
    let n = WIN_SEQ.fetch_add(1, Ordering::Relaxed);
    let label = format!("plot-{n}");

    if let Some(p) = pending_path {
        if let Some(state) = app.try_state::<PendingFiles>() {
            if let Ok(mut m) = state.0.lock() {
                m.insert(label.clone(), p.to_string());
            }
        }
    }

    // 現在フォーカス中のウィンドウから少し右下へずらして配置（カスケード）。
    const OFFSET: f64 = 28.0;
    let cascade = app
        .webview_windows()
        .values()
        .find(|w| w.is_focused().unwrap_or(false))
        .and_then(|w| {
            let sf = w.scale_factor().ok()?;
            let p = w.outer_position().ok()?.to_logical::<f64>(sf);
            Some((p.x + OFFSET, p.y + OFFSET))
        });

    let mut builder = WebviewWindowBuilder::new(app, &label, WebviewUrl::App("index.html".into()))
        .title("Plots")
        .inner_size(360.0, 320.0)
        .resizable(false)
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .focused(true);
    if let Some((x, y)) = cascade {
        builder = builder.position(x, y);
    }
    builder.build()?;

    Ok(())
}

fn create_plot_window(app: &AppHandle) -> tauri::Result<()> {
    spawn_window(app, None)
}

#[cfg(test)]
mod tests {
    use super::*;

    const BASE: &str = "/Users/okadaharuto/Library/CloudStorage/GoogleDrive-ryutan521@gmail.com/マイドライブ/Lab/okadaharuto-DB/rawdata";

    #[test]
    fn parses_csv_with_header() {
        let p = format!("{BASE}/000019/NiS2__250707__strain__exp-251206__raw.csv");
        let ds = parse_file(&p).unwrap();
        assert_eq!(ds.columns.len(), 13);
        assert_eq!(ds.columns[0], "Time_sec");
        assert!(ds.rows.len() > 100);
        assert_eq!(ds.rows[0].len(), 13);
    }

    #[test]
    fn parses_dat_without_header() {
        let p = format!("{BASE}/000178/ly-539.dat");
        let ds = parse_file(&p).unwrap();
        assert_eq!(ds.columns, vec!["col1", "col2"]);
        assert!(ds.rows.len() > 10);
        assert_eq!(ds.rows[0].len(), 2);
    }

    #[test]
    fn parses_mpms_dat() {
        let p = format!("{BASE}/000001/NiS2__250707-2__magnetization__exp-251217__mh-10k.dat");
        let ds = parse_file(&p).unwrap();
        assert!(ds.columns.iter().any(|c| c == "Magnetic Field (Oe)"));
        assert!(ds.columns.iter().any(|c| c == "DC Moment Fixed Ctr (emu)"));
        assert!(ds.rows.len() > 10);
        // metadata.json の既定軸が反映される
        assert_eq!(ds.default_x.as_deref(), Some("Magnetic Field (Oe)"));
        assert_eq!(ds.default_y.as_deref(), Some("DC Moment Fixed Ctr (emu)"));
    }

    #[test]
    fn parses_spec_txt() {
        let p = format!("{BASE}/000206/662_ascan_th_21.258_21.658_40_2.txt");
        let ds = parse_file(&p).unwrap();
        assert_eq!(ds.columns[0], "Theta");
        assert!(ds.columns.iter().any(|c| c == "Timepix1"));
        assert!(ds.rows.len() > 5);
    }

    #[test]
    fn parses_rigaku_ras() {
        let p = format!("{BASE}/000214/FePO4_#260421_2.ras");
        let ds = parse_file(&p).unwrap();
        assert_eq!(ds.columns[0], "2theta");
        assert_eq!(ds.columns[1], "intensity");
        assert!(ds.rows.len() > 100);
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(PendingFiles::default())
        .manage(LoadedWindows::default())
        .manage(WindowMetrics::default())
        .manage(FilterInits::default())
        .invoke_handler(tauri::generate_handler![
            read_dataset,
            take_pending_file,
            mark_window_loaded,
            report_panel_size,
            reveal_in_finder,
            open_with_editor,
            copy_path,
            save_panel_image,
            open_filter_window,
            take_filter_init,
            write_text_file
        ])
        .setup(|app| {
            let handle = app.handle();
            let new_window = MenuItem::with_id(
                handle,
                MENU_NEW_WINDOW,
                "New Window",
                true,
                Some("CmdOrCtrl+N"),
            )?;
            // 標準のアプリメニュー（Settings ⌘, / Hide ⌘H / Quit ⌘Q など）
            let settings_item = MenuItem::with_id(
                handle,
                MENU_SETTINGS,
                "Settings…",
                true,
                Some("CmdOrCtrl+,"),
            )?;
            let app_menu = SubmenuBuilder::new(handle, "Plots")
                .item(&settings_item)
                .separator()
                .hide()
                .hide_others()
                .show_all()
                .separator()
                .quit()
                .build()?;
            let open_file = MenuItem::with_id(handle, MENU_OPEN, "Open…", true, Some("CmdOrCtrl+O"))?;
            let reveal = MenuItem::with_id(
                handle,
                MENU_REVEAL,
                "Reveal in Finder",
                true,
                Some("CmdOrCtrl+F"),
            )?;
            let open_editor = MenuItem::with_id(
                handle,
                MENU_OPEN_EDITOR,
                "Open in Editor",
                true,
                Some("CmdOrCtrl+E"),
            )?;
            let copy_path_item = MenuItem::with_id(
                handle,
                MENU_COPY_PATH,
                "Copy Path",
                true,
                Some("CmdOrCtrl+P"),
            )?;
            let filter_item = MenuItem::with_id(
                handle,
                MENU_FILTER,
                "Filter…",
                true,
                Some("CmdOrCtrl+Alt+F"),
            )?;
            let file_menu = SubmenuBuilder::new(handle, "File")
                .item(&new_window)
                .item(&open_file)
                .separator()
                .item(&reveal)
                .item(&open_editor)
                .item(&copy_path_item)
                .build()?;
            // Tools メニュー（データ操作系。今後ここに追加していく）。
            let tools_menu = SubmenuBuilder::new(handle, "Tools").item(&filter_item).build()?;
            let next_window = MenuItem::with_id(
                handle,
                MENU_NEXT_WINDOW,
                "Next Window",
                true,
                Some("CmdOrCtrl+`"),
            )?;
            let prev_window = MenuItem::with_id(
                handle,
                MENU_PREV_WINDOW,
                "Previous Window",
                true,
                Some("CmdOrCtrl+Shift+`"),
            )?;
            let arrange = MenuItem::with_id(
                handle,
                MENU_ARRANGE,
                "Arrange Windows",
                true,
                Some("CmdOrCtrl+Alt+A"),
            )?;
            let window_menu = SubmenuBuilder::new(handle, "Window")
                .minimize()
                .separator()
                .item(&next_window)
                .item(&prev_window)
                .item(&arrange)
                .build()?;
            // 標準の Edit メニュー（⌘A 全選択 / ⌘C / ⌘V / ⌘Z / ⇧⌘Z）。
            // カスタムメニューが既定メニューを置き換えるため、これが無いと入力欄で
            // selectAll/copy/paste 等の標準ショートカットが効かなくなる。
            // Cut(⌘X) は plot の軸切替 ⌘X と衝突するため意図的に外している。
            let edit_menu = SubmenuBuilder::new(handle, "Edit")
                .undo()
                .redo()
                .separator()
                .copy()
                .paste()
                .select_all()
                .build()?;
            let menu = MenuBuilder::new(handle)
                .item(&app_menu)
                .item(&file_menu)
                .item(&edit_menu)
                .item(&tools_menu)
                .item(&window_menu)
                .build()?;
            app.set_menu(menu)?;
            Ok(())
        })
        .on_menu_event(|app, event| match event.id().as_ref() {
            MENU_NEW_WINDOW => {
                if let Err(err) = create_plot_window(app) {
                    eprintln!("failed to create plot window: {err}");
                }
            }
            MENU_NEXT_WINDOW => cycle_windows(app, true),
            MENU_PREV_WINDOW => cycle_windows(app, false),
            MENU_ARRANGE => arrange_windows(app),
            MENU_SETTINGS => {
                if let Err(err) = open_settings_window(app) {
                    eprintln!("failed to open settings window: {err}");
                }
            }
            MENU_OPEN => dispatch_menu_action(app, "open"),
            MENU_REVEAL => dispatch_menu_action(app, "reveal"),
            MENU_OPEN_EDITOR => dispatch_menu_action(app, "editor"),
            MENU_COPY_PATH => dispatch_menu_action(app, "copy-path"),
            MENU_FILTER => dispatch_menu_action(app, "filter"),
            _ => {}
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app, event| {
            // Finder で「このアプリで開く」/関連付けで開かれたファイルを受け取り、
            // 各ファイルを新規ウィンドウに展開する。
            if let tauri::RunEvent::Opened { urls } = event {
                let mut opened_any = false;
                for url in urls {
                    if let Ok(path) = url.to_file_path() {
                        if let Some(p) = path.to_str() {
                            if let Err(err) = spawn_window(app, Some(p)) {
                                eprintln!("failed to open file window: {err}");
                            } else {
                                opened_any = true;
                            }
                        }
                    }
                }
                if opened_any {
                    close_empty_main_window(app);
                    schedule_close_empty_main_window(app);
                }
            }
        });
}
