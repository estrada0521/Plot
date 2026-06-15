use serde::Serialize;
use std::fs;
use std::path::Path;

#[derive(Serialize)]
struct Dataset {
    name: String,
    columns: Vec<String>,
    rows: Vec<Vec<f64>>,
}

/// csv / dat を数値テーブルにパースする。
/// - csv: カンマ区切り / dat: 空白区切り
/// - 先頭行が全て数値ならヘッダなし(col1, col2…)、そうでなければヘッダ行とみなす
fn parse_file(path: &str) -> Result<Dataset, String> {
    let content = fs::read_to_string(path).map_err(|e| format!("読み込み失敗: {e}"))?;
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

    let is_csv = ext == "csv";
    let split = |line: &str| -> Vec<String> {
        if is_csv {
            line.split(',').map(|s| s.trim().to_string()).collect()
        } else {
            line.split_whitespace().map(|s| s.to_string()).collect()
        }
    };

    let lines: Vec<&str> = content.lines().filter(|l| !l.trim().is_empty()).collect();
    if lines.is_empty() {
        return Err("空ファイルです".into());
    }

    let first = split(lines[0]);
    let first_is_numeric =
        !first.is_empty() && first.iter().all(|t| t.parse::<f64>().is_ok());

    let (columns, data_start): (Vec<String>, usize) = if first_is_numeric {
        ((0..first.len()).map(|i| format!("col{}", i + 1)).collect(), 0)
    } else {
        (first.clone(), 1)
    };

    let ncol = columns.len();
    let mut rows: Vec<Vec<f64>> = Vec::new();
    for line in &lines[data_start..] {
        let toks = split(line);
        if toks.len() < ncol {
            continue;
        }
        let mut row = Vec::with_capacity(ncol);
        let mut ok = true;
        for t in toks.iter().take(ncol) {
            match t.parse::<f64>() {
                Ok(v) => row.push(v),
                Err(_) => {
                    ok = false;
                    break;
                }
            }
        }
        if ok {
            rows.push(row);
        }
    }
    if rows.is_empty() {
        return Err("数値データが見つかりません".into());
    }

    Ok(Dataset { name, columns, rows })
}

#[tauri::command]
fn read_dataset(path: String) -> Result<Dataset, String> {
    parse_file(&path)
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
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![read_dataset])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
