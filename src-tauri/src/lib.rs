use serde::Serialize;
use std::fs;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::menu::{MenuBuilder, MenuItem, SubmenuBuilder};
use tauri::{AppHandle, WebviewUrl, WebviewWindowBuilder};

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

fn create_plot_window(app: &AppHandle) -> tauri::Result<()> {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default();
    let label = format!("plot-{suffix}");

    WebviewWindowBuilder::new(app, label, WebviewUrl::App("index.html".into()))
        .title("Raw-Plot")
        .inner_size(360.0, 320.0)
        .resizable(false)
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .focused(true)
        .build()?;

    Ok(())
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
        .invoke_handler(tauri::generate_handler![read_dataset])
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
            let window_menu = SubmenuBuilder::new(handle, "Window")
                .minimize()
                .build()?;
            let menu = MenuBuilder::new(handle)
                .item(&app_menu)
                .item(&file_menu)
                .item(&window_menu)
                .build()?;
            app.set_menu(menu)?;
            Ok(())
        })
        .on_menu_event(|app, event| {
            if event.id().as_ref() == MENU_NEW_WINDOW {
                if let Err(err) = create_plot_window(app) {
                    eprintln!("failed to create plot window: {err}");
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
