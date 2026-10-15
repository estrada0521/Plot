use serde::Serialize;
use std::{fs, path::Path, ffi::{CStr, CString}, collections::HashSet, os::raw::c_char};

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


#[derive(Serialize)]
struct DatasetFile {
    path: String,
    dataset: Dataset,
}

#[derive(Serialize)]
struct DatasetGroup {
    x: String,
    y: String,
    items: Vec<DatasetFile>,
}

fn group_files(paths: &[String]) -> (Vec<DatasetGroup>, Vec<String>) {
    let mut groups: Vec<DatasetGroup> = Vec::new();
    let mut errors = Vec::new();
    let mut seen = HashSet::new();
    for path in paths {
        if !seen.insert(path) { continue; }
        let dataset = match parse_file(path) {
            Ok(dataset) => dataset,
            Err(error) => { errors.push(format!("{path}: {error}")); continue; }
        };
        let x = dataset.default_x.clone().unwrap_or_else(|| dataset.columns[0].clone());
        let y = dataset.default_y.clone().unwrap_or_else(|| dataset.columns[usize::from(dataset.columns.len() > 1)].clone());
        let item = DatasetFile { path: path.clone(), dataset };
        if let Some(group) = groups.iter_mut().find(|group| group.x == x && group.y == y) {
            group.items.push(item);
        } else {
            groups.push(DatasetGroup { x, y, items: vec![item] });
        }
    }
    for group in &mut groups {
        let columns: Vec<String> = group.items[0].dataset.columns.iter()
            .filter(|name| group.items.iter().all(|item| item.dataset.columns.contains(name)))
            .cloned().collect();
        for item in &mut group.items {
            if item.dataset.columns != columns {
                let indices: Vec<usize> = columns.iter().map(|name| item.dataset.columns.iter().position(|column| column == name).unwrap()).collect();
                for row in &mut item.dataset.rows { *row = indices.iter().map(|index| row[*index]).collect(); }
                item.dataset.columns = columns.clone();
            }
            item.dataset.default_x = Some(group.x.clone());
            item.dataset.default_y = Some(group.y.clone());
        }
    }
    (groups, errors)
}

#[no_mangle]
pub unsafe extern "C" fn plots_read_groups(paths: *const c_char) -> *mut c_char {
    let result = CStr::from_ptr(paths).to_str().map_err(|e| e.to_string())
        .and_then(|text| serde_json::from_str::<Vec<String>>(text).map_err(|e| e.to_string()));
    let value = match result {
        Ok(paths) => {
            let (groups, errors) = group_files(&paths);
            serde_json::json!({"groups": groups, "errors": errors})
        }
        Err(error) => serde_json::json!({"groups": [], "errors": [error]}),
    };
    CString::new(value.to_string()).unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn plots_free_string(value: *mut c_char) {
    if !value.is_null() { drop(CString::from_raw(value)); }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn group_fixture(tag: &str, files: &[(&str, &str, &str, &str)]) -> (std::path::PathBuf, Vec<String>) {
        let directory = std::env::temp_dir().join(format!("plots-group-{}-{tag}", std::process::id()));
        let mut paths = Vec::new();
        for (name, content, x, y) in files {
            let folder = directory.join(name);
            fs::create_dir_all(&folder).unwrap();
            let path = folder.join("data.csv");
            fs::write(&path, content).unwrap();
            fs::write(folder.join("metadata.json"), serde_json::json!({"default_x": x, "default_y": y}).to_string()).unwrap();
            paths.push(path.to_string_lossy().into_owned());
        }
        (directory, paths)
    }

    #[test]
    fn groups_shared_axes_and_aligns_columns() {
        let (directory, mut paths) = group_fixture("align", &[
            ("a", "Field,Moment,Extra\n1,10,99\n", "Field", "Moment"),
            ("b", "Moment,Field\n20,2\n", "Field", "Moment"),
        ]);
        paths.push(paths[0].clone());
        let (groups, errors) = group_files(&paths);
        assert!(errors.is_empty());
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].items.len(), 2);
        assert_eq!(groups[0].items[1].dataset.columns, vec!["Field", "Moment"]);
        assert_eq!(groups[0].items[1].dataset.rows, vec![vec![2.0, 20.0]]);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn separates_different_default_axes_even_with_identical_columns() {
        let (directory, paths) = group_fixture("axes", &[
            ("mh", "Field,Temperature,Moment\n1,30,10\n", "Field", "Moment"),
            ("mt", "Field,Temperature,Moment\n1,30,20\n", "Temperature", "Moment"),
        ]);
        let (groups, errors) = group_files(&paths);
        assert!(errors.is_empty());
        assert_eq!(groups.len(), 2);
        assert_eq!(groups[0].x, "Field");
        assert_eq!(groups[1].x, "Temperature");
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn reports_failed_files_without_discarding_valid_files() {
        let (directory, mut paths) = group_fixture("errors", &[("a", "X,Y\n1,2\n", "X", "Y")]);
        paths.push(directory.join("missing.csv").to_string_lossy().into_owned());
        let (groups, errors) = group_files(&paths);
        assert_eq!(groups.len(), 1);
        assert_eq!(errors.len(), 1);
        assert!(errors[0].contains("missing.csv"));
        fs::remove_dir_all(directory).unwrap();
    }

    const BASE: &str = "/Users/okadaharuto/Library/CloudStorage/GoogleDrive-ryutan521@gmail.com/マイドライブ/Lab/Database_legacy/rawdata";

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

