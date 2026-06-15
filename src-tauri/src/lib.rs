use serde::Serialize;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use tauri::menu::{MenuBuilder, MenuItem, SubmenuBuilder};
use tauri::{AppHandle, LogicalPosition, Manager, State, WebviewUrl, WebviewWindowBuilder};

/// 新規ウィンドウへ「起動時に開くファイル」を引き渡すための保管庫（label → path）。
#[derive(Default)]
struct PendingFiles(Mutex<HashMap<String, String>>);

/// データを読み込んだ（＝空でない）ウィンドウの label 集合。
#[derive(Default)]
struct LoadedWindows(Mutex<HashSet<String>>);

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

#[derive(Serialize)]
struct Dataset {
    name: String,
    columns: Vec<String>,
    rows: Vec<Vec<f64>>,
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
fn read_meta_defaults(path: &str) -> (Option<String>, Option<String>) {
    let Some(dir) = Path::new(path).parent() else {
        return (None, None);
    };
    let Ok(txt) = fs::read_to_string(dir.join("metadata.json")) else {
        return (None, None);
    };
    let Ok(v) = serde_json::from_str::<serde_json::Value>(&txt) else {
        return (None, None);
    };
    let get = |k: &str| v.get(k).and_then(|x| x.as_str()).map(|s| s.to_string());
    (get("default_x"), get("default_y"))
}

/// 列・行を Dataset にまとめ、metadata の既定軸が実在する場合のみ採用する。
fn finalize(name: String, columns: Vec<String>, rows: Vec<Vec<f64>>, path: &str) -> Result<Dataset, String> {
    if columns.is_empty() {
        return Err("列が見つかりません".into());
    }
    if rows.is_empty() {
        return Err("数値データが見つかりません".into());
    }
    let (dx, dy) = read_meta_defaults(path);
    let exists = |c: &Option<String>| c.as_ref().is_some_and(|n| columns.iter().any(|col| col == n));
    let default_x = if exists(&dx) { dx } else { None };
    let default_y = if exists(&dy) { dy } else { None };
    Ok(Dataset {
        name,
        columns,
        rows,
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

const MENU_NEW_WINDOW: &str = "new-window";
const MENU_NEXT_WINDOW: &str = "next-window";
const MENU_PREV_WINDOW: &str = "prev-window";
const MENU_ARRANGE: &str = "arrange-windows";

/// 開いているウィンドウを画面左上から行詰めでタイル配置する。
fn arrange_windows(app: &AppHandle) {
    let mut wins: Vec<_> = app.webview_windows().into_iter().collect();
    if wins.is_empty() {
        return;
    }
    wins.sort_by(|a, b| a.0.cmp(&b.0));

    // 配置領域（プライマリモニタ）。取得できなければ既定値。
    let (area_x, area_y, area_w) = wins[0]
        .1
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

    let gap = 12.0;
    let margin_top = 28.0; // メニューバー分
    let mut x = area_x + gap;
    let mut y = area_y + margin_top;
    let mut row_h: f64 = 0.0;
    for (_, w) in &wins {
        let s = w.scale_factor().unwrap_or(1.0);
        let size = w
            .outer_size()
            .map(|sz| sz.to_logical::<f64>(s))
            .unwrap_or_else(|_| tauri::LogicalSize::new(360.0, 320.0));
        // 行末で折り返し
        if x > area_x + gap && x + size.width > area_x + area_w - gap {
            x = area_x + gap;
            y += row_h + gap;
            row_h = 0.0;
        }
        let _ = w.set_position(LogicalPosition::new(x, y));
        x += size.width + gap;
        if size.height > row_h {
            row_h = size.height;
        }
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
        .title("Raw-Plot")
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
        .invoke_handler(tauri::generate_handler![
            read_dataset,
            take_pending_file,
            mark_window_loaded
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
            // 標準のアプリメニュー（Hide ⌘H / Hide Others / Quit ⌘Q など）を復活
            let app_menu = SubmenuBuilder::new(handle, "Raw-Plot")
                .hide()
                .hide_others()
                .show_all()
                .separator()
                .quit()
                .build()?;
            let file_menu = SubmenuBuilder::new(handle, "File")
                .item(&new_window)
                .build()?;
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
            let menu = MenuBuilder::new(handle)
                .item(&app_menu)
                .item(&file_menu)
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
                }
            }
        });
}
