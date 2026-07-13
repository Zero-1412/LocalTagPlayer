//! Local Tag Player 的只读 Windows 媒体库扫描 sidecar。
//!
//! 进程只读取目录、stat 和首尾样本，不连接 SQLite；Dart Application 校验 stable
//! identity / relink 后再统一提交事务。输入输出使用无第三方依赖的小端二进制协议。

use std::collections::{HashMap, HashSet};
use std::env;
use std::fs::{self, File};
use std::io::{self, BufReader, BufWriter, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

/// 已知 SQLite 索引提供的文件元数据，仅用于复用 fingerprint。
struct KnownMetadata {
    size: i64,
    modified_ms: i64,
    fingerprint: String,
}

/// 扫描进程入口；参数依次为已知元数据协议文件和一个或多个 root。
fn main() {
    if let Err(error) = run() {
        eprintln!("library scan failed: {error}");
        std::process::exit(1);
    }
}

/// 读取已知索引，枚举 roots，并把完整只读快照写入 stdout。
fn run() -> io::Result<()> {
    let args: Vec<_> = env::args_os().skip(1).collect();
    if args.len() < 2 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "expected metadata file and at least one root",
        ));
    }
    let known = read_known_metadata(Path::new(&args[0]))?;
    let stdout = io::stdout();
    let mut writer = BufWriter::new(stdout.lock());
    writer.write_all(b"LTPS")?;
    write_u32(&mut writer, 1)?;
    let mut seen = HashSet::new();
    for (root_index, root_arg) in args.iter().skip(1).enumerate() {
        let root = PathBuf::from(root_arg);
        if scan_root(root_index as u32, &root, &known, &mut seen, &mut writer)? {
            writer.write_all(&[2])?;
            write_u32(&mut writer, root_index as u32)?;
        }
    }
    writer.write_all(&[0])?;
    writer.flush()
}

/// 深度优先枚举一个 root；任何目录读取失败都会阻止该 root 被标记为完整扫描。
fn scan_root<W: Write>(
    root_index: u32,
    root: &Path,
    known: &HashMap<String, KnownMetadata>,
    seen: &mut HashSet<String>,
    writer: &mut W,
) -> io::Result<bool> {
    if !root.is_dir() {
        return Ok(false);
    }
    let mut stack = vec![root.to_path_buf()];
    let mut complete = true;
    while let Some(directory) = stack.pop() {
        let entries = match fs::read_dir(&directory) {
            Ok(entries) => entries,
            Err(_) => {
                complete = false;
                continue;
            }
        };
        for entry in entries {
            let entry = match entry {
                Ok(entry) => entry,
                Err(_) => {
                    complete = false;
                    continue;
                }
            };
            let path = entry.path();
            let file_type = match entry.file_type() {
                Ok(file_type) => file_type,
                Err(_) => {
                    complete = false;
                    continue;
                }
            };
            if file_type.is_dir() {
                stack.push(path);
                continue;
            }
            if !file_type.is_file() || !is_video_path(&path) {
                continue;
            }
            let path_text = path.to_string_lossy().into_owned();
            let key = path_text.to_lowercase();
            if !seen.insert(key.clone()) {
                continue;
            }
            let metadata = match entry.metadata() {
                Ok(metadata) => metadata,
                Err(_) => continue,
            };
            let size = metadata.len() as i64;
            let modified_ms = metadata
                .modified()
                .ok()
                .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
                .map(|value| value.as_millis() as i64)
                .unwrap_or(-1);
            let reusable = known.get(&key).filter(|item| {
                item.size == size && item.modified_ms == modified_ms && !item.fingerprint.is_empty()
            });
            let fingerprint = match reusable {
                Some(item) => item.fingerprint.clone(),
                None => fingerprint_for(&path, size as u64)?,
            };
            writer.write_all(&[1])?;
            write_u32(writer, root_index)?;
            write_string(writer, &path_text)?;
            write_i64(writer, size)?;
            write_i64(writer, modified_ms)?;
            write_string(writer, &fingerprint)?;
        }
    }
    Ok(complete)
}

/// 判断扩展名是否属于当前产品支持的视频集合。
fn is_video_path(path: &Path) -> bool {
    matches!(
        path.extension()
            .and_then(|value| value.to_str())
            .map(|value| value.to_ascii_lowercase())
            .as_deref(),
        Some("mp4" | "mkv" | "avi" | "mov" | "wmv" | "flv" | "webm" | "m4v" | "ts")
    )
}

/// 读取首尾各 4 KiB 并生成与 Dart 基线一致的路径无关 FNV-1a fingerprint。
fn fingerprint_for(path: &Path, size: u64) -> io::Result<String> {
    const SAMPLE_SIZE: usize = 4096;
    let mut file = File::open(path)?;
    let first_len = usize::try_from(size.min(SAMPLE_SIZE as u64)).unwrap_or(SAMPLE_SIZE);
    let mut first = vec![0_u8; first_len];
    file.read_exact(&mut first)?;
    let tail_start = size
        .saturating_sub(SAMPLE_SIZE as u64)
        .max(first_len as u64);
    file.seek(SeekFrom::Start(tail_start))?;
    let tail_len =
        usize::try_from((size - tail_start).min(SAMPLE_SIZE as u64)).unwrap_or(SAMPLE_SIZE);
    let mut tail = vec![0_u8; tail_len];
    file.read_exact(&mut tail)?;
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in first.into_iter().chain(tail) {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    // Dart VM 的 64 位按位运算结果按有符号整数输出；保持相同文本形式才能复用既有 fingerprint。
    let signed_hash = hash as i64;
    let hash_text = if signed_hash < 0 {
        format!("-{:x}", signed_hash.unsigned_abs())
    } else {
        format!("{signed_hash:016x}")
    };
    Ok(format!("v2:{size}:{hash_text}"))
}

/// 读取 Dart 写出的已知元数据协议。
fn read_known_metadata(path: &Path) -> io::Result<HashMap<String, KnownMetadata>> {
    let mut reader = BufReader::new(File::open(path)?);
    let mut magic = [0_u8; 4];
    reader.read_exact(&mut magic)?;
    if &magic != b"LTPK" || read_u32(&mut reader)? != 1 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "invalid metadata protocol",
        ));
    }
    let count = read_u32(&mut reader)?;
    let mut result = HashMap::with_capacity(count as usize);
    for _ in 0..count {
        let path = read_string(&mut reader)?;
        result.insert(
            path.to_lowercase(),
            KnownMetadata {
                size: read_i64(&mut reader)?,
                modified_ms: read_i64(&mut reader)?,
                fingerprint: read_string(&mut reader)?,
            },
        );
    }
    Ok(result)
}

fn write_u32<W: Write>(writer: &mut W, value: u32) -> io::Result<()> {
    writer.write_all(&value.to_le_bytes())
}

fn write_i64<W: Write>(writer: &mut W, value: i64) -> io::Result<()> {
    writer.write_all(&value.to_le_bytes())
}

fn write_string<W: Write>(writer: &mut W, value: &str) -> io::Result<()> {
    let bytes = value.as_bytes();
    write_u32(writer, bytes.len() as u32)?;
    writer.write_all(bytes)
}

fn read_u32<R: Read>(reader: &mut R) -> io::Result<u32> {
    let mut bytes = [0_u8; 4];
    reader.read_exact(&mut bytes)?;
    Ok(u32::from_le_bytes(bytes))
}

fn read_i64<R: Read>(reader: &mut R) -> io::Result<i64> {
    let mut bytes = [0_u8; 8];
    reader.read_exact(&mut bytes)?;
    Ok(i64::from_le_bytes(bytes))
}

fn read_string<R: Read>(reader: &mut R) -> io::Result<String> {
    let length = read_u32(reader)? as usize;
    let mut bytes = vec![0_u8; length];
    reader.read_exact(&mut bytes)?;
    String::from_utf8(bytes)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "invalid utf-8"))
}
