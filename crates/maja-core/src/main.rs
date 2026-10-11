use std::{env, fs, io::{self, Write}, path::Path, time::UNIX_EPOCH};

fn json_string(value: &str) -> String {
    let mut out = String::from("\"");
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn listing_json_for_entries(path: &Path, mut entries: Vec<fs::DirEntry>) -> io::Result<String> {
    entries.sort_by_key(|entry| {
        let is_file = entry.file_type().map(|kind| !kind.is_dir()).unwrap_or(true);
        (is_file, entry.file_name().to_string_lossy().to_lowercase())
    });

    let mut out = format!("{{\"path\":{},\"entries\":[", json_string(&path.canonicalize()?.to_string_lossy()));
    for (index, entry) in entries.iter().enumerate() {
        if index > 0 { out.push(','); }
        let file_path = entry.path();
        let metadata = fs::symlink_metadata(&file_path).ok();
        let is_directory = fs::metadata(&file_path).ok().is_some_and(|m| m.is_dir());
        let size = metadata.as_ref().map_or(0, |m| m.len());
        let modified = metadata.as_ref().and_then(|m| m.modified().ok())
            .and_then(|time| time.duration_since(UNIX_EPOCH).ok()).map_or(0, |d| d.as_secs());
        let name = entry.file_name().to_string_lossy().into_owned();
        out.push_str(&format!("{{\"name\":{},\"path\":{},\"isDirectory\":{},\"size\":{},\"modified\":{},\"isHidden\":{}}}",
            json_string(&name), json_string(&file_path.to_string_lossy()), is_directory, size, modified, name.starts_with('.')));
    }
    out.push_str("]}");
    Ok(out)
}

fn listing_json(path: &Path) -> io::Result<String> {
    let entries = fs::read_dir(path)?.filter_map(Result::ok).collect::<Vec<_>>();
    listing_json_for_entries(path, entries)
}

fn collect_search(path: &Path, needle: &str, depth: usize, visited: &mut usize, results: &mut Vec<fs::DirEntry>) {
    if depth > 64 || *visited >= 100_000 || results.len() >= 5000 { return; }
    let Ok(children) = fs::read_dir(path) else { return; };
    for child in children.filter_map(Result::ok) {
        *visited += 1;
        if *visited >= 100_000 { return; }
        let name = child.file_name().to_string_lossy().into_owned();
        let Ok(kind) = child.file_type() else { continue; };
        if kind.is_dir() { collect_search(&child.path(), needle, depth + 1, visited, results); }
        if results.len() < 5000 && name.to_lowercase().contains(needle) {
            results.push(child);
            if results.len() >= 5000 { return; }
        }
    }
}

fn search_json(path: &Path, query: &str) -> io::Result<String> {
    let mut results = Vec::new();
    let mut visited = 0;
    collect_search(path, &query.to_lowercase(), 0, &mut visited, &mut results);
    listing_json_for_entries(path, results)
}

fn list(path: &Path) -> io::Result<()> {
    io::stdout().lock().write_all(listing_json(path)?.as_bytes())?;
    Ok(())
}

fn validate_name(name: &str) -> io::Result<()> {
    if name.is_empty() || name == "." || name == ".." || name.contains('/') || name.contains('\\') {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "Enter a valid file name."));
    }
    Ok(())
}

fn copy_path(source: &Path, destination: &Path) -> io::Result<()> {
    let metadata = fs::symlink_metadata(source)?;
    if metadata.is_dir() {
        fs::create_dir(destination)?;
        for child in fs::read_dir(source)? {
            let child = child?;
            copy_path(&child.path(), &destination.join(child.file_name()))?;
        }
        fs::set_permissions(destination, metadata.permissions())?;
    } else if metadata.file_type().is_symlink() {
        #[cfg(unix)]
        std::os::unix::fs::symlink(fs::read_link(source)?, destination)?;
        #[cfg(not(unix))]
        return Err(io::Error::new(io::ErrorKind::Unsupported, "Symbolic links are not supported here."));
    } else {
        fs::copy(source, destination)?;
    }
    Ok(())
}

fn unique_copy_path(source: &Path) -> io::Result<std::path::PathBuf> {
    let parent = source.parent().ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "The item has no parent folder."))?;
    let name = source.file_name().ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "The item has no name."))?.to_string_lossy();
    for suffix in 1..1000 {
        let candidate_name = if suffix == 1 { format!("{name} copy") } else { format!("{name} copy {suffix}") };
        let candidate = parent.join(candidate_name);
        if !candidate.exists() { return Ok(candidate); }
    }
    Err(io::Error::new(io::ErrorKind::AlreadyExists, "Could not find an available copy name."))
}

fn operate(mut args: impl Iterator<Item = std::ffi::OsString>) -> io::Result<()> {
    let command = args.next().and_then(|s| s.into_string().ok()).unwrap_or_default();
    match command.as_str() {
        "create-folder" => {
            let parent = args.next().map(std::path::PathBuf::from).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing parent folder."))?;
            let name = args.next().and_then(|s| s.into_string().ok()).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing folder name."))?;
            validate_name(&name)?;
            fs::create_dir(parent.join(name))?;
        }
        "create-file" => {
            let parent = args.next().map(std::path::PathBuf::from).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing parent folder."))?;
            let name = args.next().and_then(|s| s.into_string().ok()).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing file name."))?;
            validate_name(&name)?;
            fs::OpenOptions::new().write(true).create_new(true).open(parent.join(name))?;
        }
        "rename" => {
            let source = args.next().map(std::path::PathBuf::from).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing item path."))?;
            let name = args.next().and_then(|s| s.into_string().ok()).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing new name."))?;
            validate_name(&name)?;
            let destination = source.parent()
                .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "The item has no parent folder."))?
                .join(name);
            fs::rename(source, destination)?;
        }
        "duplicate" => {
            let source = args.next().map(std::path::PathBuf::from).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing item path."))?;
            let destination = unique_copy_path(&source)?;
            copy_path(&source, &destination)?;
        }
        "link" => {
            let source = args.next().map(std::path::PathBuf::from).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing source path."))?;
            let destination = args.next().map(std::path::PathBuf::from).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing link destination."))?;
            #[cfg(unix)]
            std::os::unix::fs::symlink(source, destination)?;
            #[cfg(not(unix))]
            return Err(io::Error::new(io::ErrorKind::Unsupported, "Links are not supported here."));
        }
        "copy" => {
            let source = args.next().map(std::path::PathBuf::from).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing source path."))?;
            let destination = args.next().map(std::path::PathBuf::from).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing destination path."))?;
            copy_path(&source, &destination)?;
        }
        "move" => {
            let source = args.next().map(std::path::PathBuf::from).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing source path."))?;
            let destination = args.next().map(std::path::PathBuf::from).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing destination path."))?;
            match fs::rename(&source, &destination) {
                Ok(()) => (),
                Err(rename_error) => {
                    copy_path(&source, &destination).map_err(|_| rename_error)?;
                    if source.is_dir() { fs::remove_dir_all(&source)?; } else { fs::remove_file(&source)?; }
                }
            }
        }
        _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, "Unknown file operation.")),
    }
    Ok(())
}

fn main() {
    let mut args = env::args_os().skip(1);
    let command = args.next().and_then(|s| s.into_string().ok()).unwrap_or_default();
    let result = if command == "list" {
        let path = args.next().map(Into::into).unwrap_or_else(|| env::current_dir().unwrap_or_default());
        list(&path)
    } else if command == "search" {
        let path = args.next().map(std::path::PathBuf::from).unwrap_or_else(|| env::current_dir().unwrap_or_default());
        let query = args.next().and_then(|value| value.into_string().ok()).unwrap_or_default();
        search_json(&path, &query).and_then(|json| io::stdout().lock().write_all(json.as_bytes()))
    } else {
        operate(std::iter::once(command.into()).chain(args))
    };
    if let Err(error) = result {
        eprintln!("{error}");
        std::process::exit(2);
    }
}
