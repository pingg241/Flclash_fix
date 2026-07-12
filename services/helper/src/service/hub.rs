use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::VecDeque;
use std::fs::File;
use std::io::{BufRead, Error, Read};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::{io, thread};
use warp::Filter;

const LISTEN_PORT: u16 = 47890;

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct StartParams {
    pub path: String,
    pub arg: String,
}

fn sha256_file(path: &str) -> Result<String, Error> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0; 4096];

    loop {
        let bytes_read = file.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }

    Ok(format!("{:x}", hasher.finalize()))
}

static LOGS: Lazy<Arc<Mutex<VecDeque<String>>>> =
    Lazy::new(|| Arc::new(Mutex::new(VecDeque::with_capacity(100))));
static PROCESS: Lazy<Arc<Mutex<Option<std::process::Child>>>> =
    Lazy::new(|| Arc::new(Mutex::new(None)));

fn is_safe_start_params(start_params: &StartParams) -> bool {
    let path = start_params.path.trim();
    let arg = start_params.arg.trim();
    if path.is_empty() || arg.is_empty() {
        return false;
    }
    if path.contains('\0') || arg.contains('\0') {
        return false;
    }
    // Only allow absolute Windows or Unix paths.
    let is_windows_abs = path.len() >= 3
        && path.as_bytes()[0].is_ascii_alphabetic()
        && path.as_bytes()[1] == b':'
        && (path.as_bytes()[2] == b'\\' || path.as_bytes()[2] == b'/');
    let is_unix_abs = path.starts_with('/');
    if !is_windows_abs && !is_unix_abs {
        return false;
    }
    // Reject path traversal and shell metacharacters in the executable path.
    if path.contains("..") || path.contains('|') || path.contains('&') || path.contains(';') {
        return false;
    }
    true
}

fn check_token_header(header: Option<String>) -> Result<(), String> {
    if cfg!(debug_assertions) {
        return Ok(());
    }
    let expected = env!("TOKEN");
    if expected.is_empty() {
        return Ok(());
    }
    match header {
        Some(value) if value == expected => Ok(()),
        _ => Err("unauthorized".to_string()),
    }
}

fn start(start_params: StartParams) -> String {
    if !is_safe_start_params(&start_params) {
        return "invalid start params".to_string();
    }
    if !cfg!(debug_assertions) {
        let sha256 = sha256_file(start_params.path.as_str()).unwrap_or("".to_string());
        if sha256 != env!("TOKEN") {
            return format!("The SHA256 hash of the program requesting execution is: {}. The helper program only allows execution of applications with the SHA256 hash: {}.", sha256,  env!("TOKEN"),);
        }
    }
    stop();
    let mut process = PROCESS.lock().unwrap();
    match Command::new(&start_params.path)
        .stderr(Stdio::piped())
        .arg(&start_params.arg)
        .spawn()
    {
        Ok(child) => {
            *process = Some(child);
            if let Some(ref mut child) = *process {
                let stderr = child.stderr.take().unwrap();
                let reader = io::BufReader::new(stderr);
                thread::spawn(move || {
                    for line in reader.lines() {
                        match line {
                            Ok(output) => {
                                log_message(output);
                            }
                            Err(_) => {
                                break;
                            }
                        }
                    }
                });
            }
            "".to_string()
        }
        Err(e) => {
            log_message(e.to_string());
            e.to_string()
        }
    }
}

fn stop() -> String {
    let mut process = PROCESS.lock().unwrap();
    if let Some(mut child) = process.take() {
        let _ = child.kill();
        let _ = child.wait();
    }
    *process = None;
    "".to_string()
}

fn log_message(message: String) {
    let mut log_buffer = LOGS.lock().unwrap();
    if log_buffer.len() == 100 {
        log_buffer.pop_front();
    }
    log_buffer.push_back(format!("{}\n", message));
}

fn get_logs() -> String {
    let log_buffer = LOGS.lock().unwrap();
    log_buffer
        .iter()
        .cloned()
        .collect::<Vec<String>>()
        .join("\n")
}

pub async fn run_service() -> anyhow::Result<()> {
    let token_header = warp::header::optional::<String>("x-flclash-token");

    let api_ping = warp::get()
        .and(warp::path("ping"))
        .and(token_header.clone())
        .map(|header: Option<String>| {
            if let Err(msg) = check_token_header(header) {
                return msg;
            }
            env!("TOKEN").to_string()
        });

    let api_start = warp::post()
        .and(warp::path("start"))
        .and(token_header.clone())
        .and(warp::body::json())
        .map(|header: Option<String>, start_params: StartParams| {
            if let Err(msg) = check_token_header(header) {
                return msg;
            }
            start(start_params)
        });

    let api_stop = warp::post()
        .and(warp::path("stop"))
        .and(token_header.clone())
        .map(|header: Option<String>| {
            if let Err(msg) = check_token_header(header) {
                return msg;
            }
            stop()
        });

    let api_logs = warp::get()
        .and(warp::path("logs"))
        .and(token_header)
        .map(|header: Option<String>| {
            if let Err(msg) = check_token_header(header) {
                return msg;
            }
            get_logs()
        });

    warp::serve(api_ping.or(api_start).or(api_stop).or(api_logs))
        .run(([127, 0, 0, 1], LISTEN_PORT))
        .await;

    Ok(())
}
