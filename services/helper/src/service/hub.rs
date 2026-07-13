use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, VecDeque};
use std::convert::Infallible;
use std::fs::{File, OpenOptions};
use std::io::{self, BufRead, Read};
use std::net::{Ipv4Addr, SocketAddr};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};
use warp::Filter;

const LISTEN_PORT: u16 = 47890;
const CORE_EXECUTABLE: &str = "FlClashCore.exe";
const APP_EXECUTABLE: &str = "FlClash.exe";
const PIPE_PREFIX: &str = r"\\.\pipe\FlClashCore_";
const HOME_SUFFIX: &str = r"\appdata\roaming\com.follow\clash";
const IPC_TOKEN_ENV: &str = "FLCLASH_IPC_TOKEN";
const MAX_REQUEST_BODY_SIZE: u64 = 4096;
const MIN_IPC_TOKEN_SIZE: usize = 32;
const MAX_IPC_TOKEN_SIZE: usize = 256;
const REQUEST_ID_HEADER: &str = "x-flclash-request-id";
const OPERATION_TIMEOUT: Duration = Duration::from_secs(5);
const PROCESS_POLL_INTERVAL: Duration = Duration::from_millis(20);
const MAX_OPERATION_RECORDS: usize = 128;

#[derive(Debug, Deserialize, Serialize, Clone)]
#[serde(deny_unknown_fields)]
pub struct StartParams {
    pub path: String,
    pub args: Vec<String>,
    #[serde(rename = "ipcToken")]
    pub ipc_token: String,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct OperationResponse {
    done: bool,
    error: String,
}

enum OperationEntry {
    Running,
    Complete(String),
}

struct OperationRegistry {
    entries: HashMap<String, OperationEntry>,
    order: VecDeque<String>,
}

enum BeginOperation {
    Execute,
    Existing(OperationResponse),
}

struct ManagedChild {
    child: Child,
    #[cfg(windows)]
    _job: WindowsJob,
}

impl ManagedChild {
    fn new(mut child: Child) -> Result<Self, String> {
        #[cfg(windows)]
        {
            match WindowsJob::assign(&child) {
                Ok(job) => Ok(Self { child, _job: job }),
                Err(error) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    Err(error)
                }
            }
        }
        #[cfg(not(windows))]
        {
            Ok(Self { child })
        }
    }
}

#[cfg(windows)]
struct WindowsJob(isize);

#[cfg(windows)]
impl WindowsJob {
    fn assign(child: &Child) -> Result<Self, String> {
        use std::mem::size_of;
        use std::os::windows::io::AsRawHandle;
        use std::ptr;
        use windows_sys::Win32::System::JobObjects::{
            AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
            SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
            JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
        };

        let job = unsafe { CreateJobObjectW(ptr::null(), ptr::null()) };
        if job.is_null() {
            return Err(format!(
                "failed to create child process job: {}",
                io::Error::last_os_error()
            ));
        }
        let guard = Self(job as isize);
        let mut limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        let configured = unsafe {
            SetInformationJobObject(
                job,
                JobObjectExtendedLimitInformation,
                &limits as *const _ as *const _,
                size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            )
        };
        if configured == 0 {
            return Err(format!(
                "failed to configure child process job: {}",
                io::Error::last_os_error()
            ));
        }
        let assigned = unsafe {
            AssignProcessToJobObject(job, child.as_raw_handle() as *mut std::ffi::c_void)
        };
        if assigned == 0 {
            return Err(format!(
                "failed to assign child process job: {}",
                io::Error::last_os_error()
            ));
        }
        Ok(guard)
    }
}

#[cfg(windows)]
impl Drop for WindowsJob {
    fn drop(&mut self) {
        use windows_sys::Win32::Foundation::CloseHandle;
        unsafe {
            CloseHandle(self.0 as *mut std::ffi::c_void);
        }
    }
}

static LOGS: Lazy<Arc<Mutex<VecDeque<String>>>> =
    Lazy::new(|| Arc::new(Mutex::new(VecDeque::with_capacity(100))));
static PROCESS: Lazy<Arc<Mutex<Option<ManagedChild>>>> = Lazy::new(|| Arc::new(Mutex::new(None)));
static OPERATION_LOCK: Mutex<()> = Mutex::new(());
static OPERATIONS: Lazy<Mutex<OperationRegistry>> = Lazy::new(|| {
    Mutex::new(OperationRegistry {
        entries: HashMap::new(),
        order: VecDeque::new(),
    })
});

#[cfg(test)]
fn sha256_reader(mut reader: impl Read) -> io::Result<String> {
    sha256_reader_until(&mut reader, None)
}

fn sha256_reader_until(mut reader: impl Read, deadline: Option<Instant>) -> io::Result<String> {
    let mut hasher = Sha256::new();
    let mut buffer = [0; 8192];
    loop {
        if deadline.is_some_and(|value| Instant::now() >= value) {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "core hash operation timed out",
            ));
        }
        let bytes_read = reader.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    left.iter()
        .zip(right)
        .fold(0u8, |diff, (left, right)| diff | (left ^ right))
        == 0
}

fn normalize_windows_path(path: &str) -> String {
    let replaced = path.replace('/', "\\");
    let trimmed = replaced.trim_end_matches('\\');
    trimmed
        .strip_prefix("\\\\?\\")
        .unwrap_or(trimmed)
        .to_ascii_lowercase()
}

fn expected_sibling_path(helper_path: &Path, executable: &str) -> Result<PathBuf, String> {
    helper_path
        .parent()
        .map(|parent| parent.join(executable))
        .ok_or_else(|| "helper executable has no parent directory".to_string())
}

fn is_expected_core_path(path: &str, helper_path: &Path) -> bool {
    expected_sibling_path(helper_path, CORE_EXECUTABLE)
        .map(|expected| {
            normalize_windows_path(path) == normalize_windows_path(&expected.to_string_lossy())
        })
        .unwrap_or(false)
}

fn is_expected_app_path(path: &Path, helper_path: &Path) -> bool {
    expected_sibling_path(helper_path, APP_EXECUTABLE)
        .map(|expected| {
            normalize_windows_path(&path.to_string_lossy())
                == normalize_windows_path(&expected.to_string_lossy())
        })
        .unwrap_or(false)
}

fn valid_suffix(suffix: &str) -> bool {
    (1..=64).contains(&suffix.len())
        && suffix
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
}

fn is_valid_pipe_name(pipe: &str) -> bool {
    pipe.strip_prefix(PIPE_PREFIX).is_some_and(valid_suffix)
}

fn is_drive_absolute(path: &str) -> bool {
    let bytes = path.as_bytes();
    bytes.len() >= 3
        && bytes[0].is_ascii_alphabetic()
        && bytes[1] == b':'
        && matches!(bytes[2], b'\\' | b'/')
}

fn has_traversal_component(path: &str) -> bool {
    path.replace('/', "\\")
        .split('\\')
        .any(|component| matches!(component, "." | ".."))
}

fn is_valid_home_path(path: &str) -> bool {
    if path.is_empty()
        || path.len() > 1024
        || path.contains('\0')
        || !is_drive_absolute(path)
        || has_traversal_component(path)
    {
        return false;
    }
    normalize_windows_path(path).ends_with(HOME_SUFFIX)
}

fn is_valid_ipc_token(token: &str) -> bool {
    (MIN_IPC_TOKEN_SIZE..=MAX_IPC_TOKEN_SIZE).contains(&token.len())
        && token.is_ascii()
        && token.bytes().all(|byte| {
            byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'=' | b'+' | b'/')
        })
}

fn validate_start_params(params: &StartParams, helper_path: &Path) -> Result<(), String> {
    if !is_expected_core_path(&params.path, helper_path) {
        return Err("core executable must be next to the helper".into());
    }
    if params.args.len() != 2 {
        return Err("core requires exactly an IPC address and a home directory".into());
    }
    if !is_valid_pipe_name(&params.args[0]) {
        return Err("invalid IPC pipe name".into());
    }
    if !is_valid_home_path(&params.args[1]) {
        return Err("invalid core home directory".into());
    }
    if !is_valid_ipc_token(&params.ipc_token) {
        return Err("invalid IPC token".into());
    }
    Ok(())
}

fn open_core_locked(path: &Path) -> io::Result<File> {
    let mut options = OpenOptions::new();
    options.read(true);
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        use windows_sys::Win32::Storage::FileSystem::FILE_SHARE_READ;
        options.share_mode(FILE_SHARE_READ);
    }
    options.open(path)
}

fn check_token_header(header: Option<String>) -> Result<(), String> {
    if cfg!(debug_assertions) {
        return Ok(());
    }
    let expected = env!("TOKEN");
    if expected.len() != 64 || !expected.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err("helper authentication is not configured".into());
    }
    match header {
        Some(value) if constant_time_eq(value.as_bytes(), expected.as_bytes()) => Ok(()),
        _ => Err("unauthorized".into()),
    }
}

#[cfg(windows)]
fn ipv4_to_dword(address: Ipv4Addr) -> u32 {
    u32::from_ne_bytes(address.octets())
}

#[cfg(windows)]
fn port_to_dword(port: u16) -> u32 {
    port.to_be() as u32
}

#[cfg(windows)]
fn matching_client_pid(
    rows: &[windows_sys::Win32::NetworkManagement::IpHelper::MIB_TCPROW_OWNER_PID],
    remote: SocketAddr,
) -> Option<u32> {
    let SocketAddr::V4(remote) = remote else {
        return None;
    };
    let loopback = Ipv4Addr::LOCALHOST;
    rows.iter()
        .find(|row| {
            row.dwLocalAddr == ipv4_to_dword(*remote.ip())
                && row.dwLocalPort == port_to_dword(remote.port())
                && row.dwRemoteAddr == ipv4_to_dword(loopback)
                && row.dwRemotePort == port_to_dword(LISTEN_PORT)
        })
        .map(|row| row.dwOwningPid)
}

#[cfg(windows)]
fn tcp_owner_pid(remote: SocketAddr) -> Result<u32, String> {
    use std::ffi::c_void;
    use std::mem::size_of;
    use std::ptr;
    use windows_sys::Win32::Foundation::ERROR_INSUFFICIENT_BUFFER;
    use windows_sys::Win32::NetworkManagement::IpHelper::{
        GetExtendedTcpTable, MIB_TCPROW_OWNER_PID, TCP_TABLE_OWNER_PID_CONNECTIONS,
    };

    const AF_INET: u32 = 2;
    let mut size = 0u32;
    let initial = unsafe {
        GetExtendedTcpTable(
            ptr::null_mut(),
            &mut size,
            0,
            AF_INET,
            TCP_TABLE_OWNER_PID_CONNECTIONS,
            0,
        )
    };
    if initial != ERROR_INSUFFICIENT_BUFFER || size < size_of::<u32>() as u32 {
        return Err(format!("failed to size TCP owner table: {initial}"));
    }

    for _ in 0..3 {
        let mut buffer = vec![0u32; (size as usize).div_ceil(size_of::<u32>())];
        let status = unsafe {
            GetExtendedTcpTable(
                buffer.as_mut_ptr() as *mut c_void,
                &mut size,
                0,
                AF_INET,
                TCP_TABLE_OWNER_PID_CONNECTIONS,
                0,
            )
        };
        if status == ERROR_INSUFFICIENT_BUFFER {
            continue;
        }
        if status != 0 {
            return Err(format!("failed to read TCP owner table: {status}"));
        }
        let count = buffer[0] as usize;
        let available = (buffer.len() * size_of::<u32>() - size_of::<u32>())
            / size_of::<MIB_TCPROW_OWNER_PID>();
        if count > available {
            return Err("TCP owner table is malformed".into());
        }
        let rows = unsafe {
            std::slice::from_raw_parts(buffer.as_ptr().add(1) as *const MIB_TCPROW_OWNER_PID, count)
        };
        return matching_client_pid(rows, remote)
            .ok_or_else(|| "requesting process was not found".to_string());
    }
    Err("TCP owner table changed repeatedly".into())
}

#[cfg(windows)]
fn process_image_path(pid: u32) -> Result<PathBuf, String> {
    use std::ffi::OsString;
    use std::os::windows::ffi::OsStringExt;
    use windows_sys::Win32::Foundation::CloseHandle;
    use windows_sys::Win32::System::Threading::{
        OpenProcess, QueryFullProcessImageNameW, PROCESS_QUERY_LIMITED_INFORMATION,
    };

    let process = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid) };
    if process.is_null() {
        return Err(format!(
            "failed to open requesting process: {}",
            io::Error::last_os_error()
        ));
    }
    let mut buffer = vec![0u16; 32768];
    let mut size = buffer.len() as u32;
    let success = unsafe { QueryFullProcessImageNameW(process, 0, buffer.as_mut_ptr(), &mut size) };
    unsafe {
        CloseHandle(process);
    }
    if success == 0 {
        return Err(format!(
            "failed to inspect requesting process: {}",
            io::Error::last_os_error()
        ));
    }
    buffer.truncate(size as usize);
    Ok(PathBuf::from(OsString::from_wide(&buffer)))
}

fn check_request_caller(remote: Option<SocketAddr>) -> Result<(), String> {
    #[cfg(windows)]
    {
        let remote = remote
            .filter(SocketAddr::is_ipv4)
            .ok_or("missing IPv4 caller")?;
        if !remote.ip().is_loopback() {
            return Err("caller is not local".into());
        }
        let pid = tcp_owner_pid(remote)?;
        let actual = process_image_path(pid)?;
        let helper = std::env::current_exe().map_err(|error| error.to_string())?;
        if !is_expected_app_path(&actual, &helper) {
            return Err("request did not originate from FlClash".into());
        }
        if tcp_owner_pid(remote)? != pid {
            return Err("requesting process changed during authorization".into());
        }
        Ok(())
    }
    #[cfg(not(windows))]
    {
        let _ = remote;
        if cfg!(debug_assertions) {
            Ok(())
        } else {
            Err("release helper is only supported on Windows".into())
        }
    }
}

fn authorize(header: Option<String>, remote: Option<SocketAddr>) -> Result<(), String> {
    check_token_header(header)?;
    check_request_caller(remote)
}

fn ensure_before_deadline(deadline: Instant) -> Result<(), String> {
    if Instant::now() >= deadline {
        return Err("helper operation timed out".into());
    }
    Ok(())
}

fn take_process() -> Result<Option<ManagedChild>, String> {
    PROCESS
        .lock()
        .map_err(|error| format!("process lock poisoned: {error}"))
        .map(|mut process| process.take())
}

fn store_process(managed: ManagedChild) -> Result<(), String> {
    let mut process = PROCESS
        .lock()
        .map_err(|error| format!("process lock poisoned: {error}"))?;
    *process = Some(managed);
    Ok(())
}

fn stop_managed(mut managed: ManagedChild, deadline: Instant) -> Result<(), String> {
    match managed.child.try_wait() {
        Ok(Some(_)) => return Ok(()),
        Ok(None) => {}
        Err(error) => return Err(format!("failed to inspect core process: {error}")),
    }
    if let Err(error) = managed.child.kill() {
        if managed.child.try_wait().ok().flatten().is_some() {
            return Ok(());
        }
        return Err(format!("failed to terminate core process: {error}"));
    }
    loop {
        match managed.child.try_wait() {
            Ok(Some(_)) => return Ok(()),
            Ok(None) if Instant::now() < deadline => thread::sleep(PROCESS_POLL_INTERVAL),
            Ok(None) => return Err("timed out waiting for core process to exit".into()),
            Err(error) => return Err(format!("failed to wait for core process: {error}")),
        }
    }
}

fn stop_inner(deadline: Instant) -> Result<(), String> {
    let _operation = OPERATION_LOCK
        .lock()
        .map_err(|error| format!("operation lock poisoned: {error}"))?;
    ensure_before_deadline(deadline)?;
    if let Some(managed) = take_process()? {
        stop_managed(managed, deadline)?;
    }
    Ok(())
}

fn start_inner(params: StartParams, deadline: Instant) -> Result<(), String> {
    let _operation = OPERATION_LOCK
        .lock()
        .map_err(|error| format!("operation lock poisoned: {error}"))?;
    ensure_before_deadline(deadline)?;
    let helper_path = std::env::current_exe().map_err(|error| error.to_string())?;
    validate_start_params(&params, &helper_path)?;

    let core_path = Path::new(&params.path);
    if !Path::new(&params.args[1]).is_dir() {
        return Err("core home directory does not exist".into());
    }
    let mut core_file = open_core_locked(core_path)
        .map_err(|error| format!("failed to open core executable: {error}"))?;
    if !cfg!(debug_assertions) {
        let actual = sha256_reader_until(&mut core_file, Some(deadline))
            .map_err(|error| format!("failed to hash core executable: {error}"))?;
        if !constant_time_eq(actual.as_bytes(), env!("TOKEN").as_bytes()) {
            return Err("core executable hash mismatch".into());
        }
    }

    ensure_before_deadline(deadline)?;
    if let Some(managed) = take_process()? {
        stop_managed(managed, deadline)?;
    }
    ensure_before_deadline(deadline)?;
    let child = Command::new(core_path)
        .args(&params.args)
        .env(IPC_TOKEN_ENV, &params.ipc_token)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("failed to start core: {error}"))?;
    let mut managed = ManagedChild::new(child)?;
    if let Err(error) = ensure_before_deadline(deadline) {
        let cleanup = stop_managed(managed, Instant::now() + Duration::from_secs(1));
        return Err(match cleanup {
            Ok(()) => error,
            Err(cleanup_error) => format!("{error}; cleanup failed: {cleanup_error}"),
        });
    }
    let stderr = managed.child.stderr.take();
    store_process(managed)?;
    drop(core_file);

    if let Some(stderr) = stderr {
        thread::spawn(move || {
            let reader = io::BufReader::new(stderr);
            for line in reader.lines() {
                match line {
                    Ok(output) => log_message(output),
                    Err(_) => break,
                }
            }
        });
    }
    Ok(())
}

fn start(params: StartParams, deadline: Instant) -> String {
    match start_inner(params, deadline) {
        Ok(()) => String::new(),
        Err(error) => {
            log_message(error.clone());
            error
        }
    }
}

pub(crate) fn stop() -> String {
    stop_with_deadline(Instant::now() + OPERATION_TIMEOUT)
}

fn stop_with_deadline(deadline: Instant) -> String {
    match stop_inner(deadline) {
        Ok(()) => String::new(),
        Err(error) => {
            let message = error;
            log_message(message.clone());
            message
        }
    }
}

fn log_message(message: String) {
    if let Ok(mut log_buffer) = LOGS.lock() {
        if log_buffer.len() == 100 {
            log_buffer.pop_front();
        }
        log_buffer.push_back(message);
    }
}

fn get_logs() -> String {
    LOGS.lock()
        .map(|log_buffer| log_buffer.iter().cloned().collect::<Vec<_>>().join("\n"))
        .unwrap_or_else(|error| format!("log lock poisoned: {error}"))
}

fn valid_request_id(request_id: &str) -> bool {
    request_id.len() == 32 && request_id.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn begin_operation(request_id: &str) -> Result<BeginOperation, String> {
    if !valid_request_id(request_id) {
        return Err("invalid helper operation request id".into());
    }
    let mut registry = OPERATIONS
        .lock()
        .map_err(|error| format!("operation registry lock poisoned: {error}"))?;
    if let Some(entry) = registry.entries.get(request_id) {
        return Ok(BeginOperation::Existing(match entry {
            OperationEntry::Running => OperationResponse {
                done: false,
                error: String::new(),
            },
            OperationEntry::Complete(error) => OperationResponse {
                done: true,
                error: error.clone(),
            },
        }));
    }
    if registry.order.len() >= MAX_OPERATION_RECORDS {
        let completed = registry.order.iter().position(|request_id| {
            matches!(
                registry.entries.get(request_id),
                Some(OperationEntry::Complete(_))
            )
        });
        let Some(index) = completed else {
            return Err("too many helper operations are pending".into());
        };
        if let Some(request_id) = registry.order.remove(index) {
            registry.entries.remove(&request_id);
        }
    }
    registry
        .entries
        .insert(request_id.to_string(), OperationEntry::Running);
    registry.order.push_back(request_id.to_string());
    Ok(BeginOperation::Execute)
}

fn finish_operation(request_id: &str, error: String) -> OperationResponse {
    if let Ok(mut registry) = OPERATIONS.lock() {
        registry.entries.insert(
            request_id.to_string(),
            OperationEntry::Complete(error.clone()),
        );
    }
    OperationResponse { done: true, error }
}

fn operation_status(request_id: &str) -> OperationResponse {
    if !valid_request_id(request_id) {
        return OperationResponse {
            done: true,
            error: "invalid helper operation request id".into(),
        };
    }
    match OPERATIONS.lock() {
        Ok(registry) => match registry.entries.get(request_id) {
            Some(OperationEntry::Running) => OperationResponse {
                done: false,
                error: String::new(),
            },
            Some(OperationEntry::Complete(error)) => OperationResponse {
                done: true,
                error: error.clone(),
            },
            None => OperationResponse {
                done: true,
                error: "helper operation was not found".into(),
            },
        },
        Err(error) => OperationResponse {
            done: true,
            error: format!("operation registry lock poisoned: {error}"),
        },
    }
}

async fn execute_operation(
    request_id: String,
    operation: impl FnOnce(Instant) -> String + Send + 'static,
) -> OperationResponse {
    let deadline = Instant::now() + OPERATION_TIMEOUT;
    match begin_operation(&request_id) {
        Ok(BeginOperation::Existing(response)) => response,
        Err(error) => OperationResponse { done: true, error },
        Ok(BeginOperation::Execute) => {
            let error = match tokio::task::spawn_blocking(move || operation(deadline)).await {
                Ok(error) => error,
                Err(error) => format!("helper operation task failed: {error}"),
            };
            finish_operation(&request_id, error)
        }
    }
}

fn error_response(error: String) -> OperationResponse {
    OperationResponse { done: true, error }
}

pub async fn run_service() -> anyhow::Result<()> {
    let token_header = warp::header::optional::<String>("x-flclash-token");
    let request_id_header = warp::header::optional::<String>(REQUEST_ID_HEADER);
    let remote = warp::addr::remote();

    let api_ping = warp::get()
        .and(warp::path("ping"))
        .and(warp::path::end())
        .and(token_header.clone())
        .and(remote.clone())
        .map(|header: Option<String>, remote: Option<SocketAddr>| {
            if let Err(message) = authorize(header, remote) {
                return message;
            }
            env!("TOKEN").to_string()
        });

    let api_start = warp::post()
        .and(warp::path("start"))
        .and(warp::path::end())
        .and(token_header.clone())
        .and(remote.clone())
        .and(warp::body::content_length_limit(MAX_REQUEST_BODY_SIZE))
        .and(warp::body::json())
        .and(request_id_header.clone())
        .and_then(
            |header: Option<String>,
             remote: Option<SocketAddr>,
             params: StartParams,
             request_id: Option<String>| async move {
                let response = match authorize(header, remote) {
                    Err(error) => error_response(error),
                    Ok(()) => match request_id {
                        Some(request_id) => {
                            execute_operation(request_id, move |deadline| start(params, deadline))
                                .await
                        }
                        None => error_response("missing helper operation request id".into()),
                    },
                };
                Ok::<_, Infallible>(warp::reply::json(&response))
            },
        );

    let api_stop = warp::post()
        .and(warp::path("stop"))
        .and(warp::path::end())
        .and(token_header.clone())
        .and(remote.clone())
        .and(request_id_header)
        .and_then(|header: Option<String>, remote: Option<SocketAddr>, request_id: Option<String>| async move {
            let response = match authorize(header, remote) {
                Err(error) => error_response(error),
                Ok(()) => match request_id {
                    Some(request_id) => execute_operation(request_id, stop_with_deadline).await,
                    None => error_response("missing helper operation request id".into()),
                },
            };
            Ok::<_, Infallible>(warp::reply::json(&response))
        });

    let api_operation = warp::get()
        .and(warp::path("operation"))
        .and(warp::path::param::<String>())
        .and(warp::path::end())
        .and(token_header.clone())
        .and(remote.clone())
        .map(
            |request_id: String, header: Option<String>, remote: Option<SocketAddr>| {
                let response = match authorize(header, remote) {
                    Ok(()) => operation_status(&request_id),
                    Err(error) => error_response(error),
                };
                warp::reply::json(&response)
            },
        );

    let api_logs = warp::get()
        .and(warp::path("logs"))
        .and(warp::path::end())
        .and(token_header)
        .and(remote)
        .map(|header: Option<String>, remote: Option<SocketAddr>| {
            if let Err(message) = authorize(header, remote) {
                return message;
            }
            get_logs()
        });

    warp::serve(
        api_ping
            .or(api_start)
            .or(api_stop)
            .or(api_operation)
            .or(api_logs),
    )
    .run(([127, 0, 0, 1], LISTEN_PORT))
    .await;
    let _ = stop();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn valid_params(helper: &Path) -> StartParams {
        StartParams {
            path: expected_sibling_path(helper, CORE_EXECUTABLE)
                .unwrap()
                .to_string_lossy()
                .into_owned(),
            args: vec![
                r"\\.\pipe\FlClashCore_1234".into(),
                r"C:\Users\tester\AppData\Roaming\com.follow\clash".into(),
            ],
            ipc_token: "0123456789abcdef0123456789abcdef".into(),
        }
    }

    #[test]
    fn start_params_accept_only_fixed_core_and_schema() {
        let helper = Path::new(r"C:\Program Files\FlClash\FlClashHelperService.exe");
        let params = valid_params(helper);
        assert!(validate_start_params(&params, helper).is_ok());

        let mut invalid = params.clone();
        invalid.path = r"C:\Temp\FlClashCore.exe".into();
        assert!(validate_start_params(&invalid, helper).is_err());

        let mut invalid = params.clone();
        invalid.args.push("--extra".into());
        assert!(validate_start_params(&invalid, helper).is_err());

        let mut invalid = params;
        invalid.args[0] = r"\\.\pipe\attacker".into();
        assert!(validate_start_params(&invalid, helper).is_err());
    }

    #[test]
    fn caller_path_accepts_only_sibling_flclash_binary() {
        let helper = Path::new(r"C:\Program Files\FlClash\FlClashHelperService.exe");
        assert!(is_expected_app_path(
            Path::new(r"c:/program files/flclash/FlClash.exe"),
            helper
        ));
        assert!(!is_expected_app_path(
            Path::new(r"C:\Users\attacker\FlClash.exe"),
            helper
        ));
        assert!(!is_expected_app_path(
            Path::new(r"C:\Program Files\FlClash\other.exe"),
            helper
        ));
    }

    #[test]
    fn home_path_rejects_root_traversal_and_unrelated_directories() {
        assert!(is_valid_home_path(
            r"C:\Users\test\AppData\Roaming\com.follow\clash"
        ));
        assert!(!is_valid_home_path(r"C:\"));
        assert!(!is_valid_home_path(
            r"C:\Users\test\..\Admin\AppData\Roaming\com.follow\clash"
        ));
        assert!(!is_valid_home_path(r"C:\Windows\System32"));
        assert!(!is_valid_home_path(
            r"\\server\share\AppData\Roaming\com.follow\clash"
        ));
    }

    #[test]
    fn pipe_and_token_validation_reject_injection() {
        assert!(is_valid_pipe_name(r"\\.\pipe\FlClashCore_abCD-_09"));
        assert!(!is_valid_pipe_name(r"\\.\pipe\FlClashCore_..\evil"));
        assert!(!is_valid_pipe_name("127.0.0.1:9000"));
        assert!(is_valid_ipc_token(
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        ));
        assert!(!is_valid_ipc_token("short"));
        assert!(!is_valid_ipc_token("0123456789abcdef0123456789abcde\0"));
    }

    #[test]
    fn sha256_reader_hashes_the_opened_stream() {
        let hash = sha256_reader(Cursor::new(b"FlClash".as_slice())).unwrap();
        assert_eq!(
            hash,
            "47106c2529ab4219cfdf9096078462ab46dfae584f97bf8c530e35d7fab98021"
        );
    }

    #[cfg(windows)]
    #[test]
    fn tcp_owner_match_uses_client_side_tuple() {
        use windows_sys::Win32::NetworkManagement::IpHelper::MIB_TCPROW_OWNER_PID;

        let remote: SocketAddr = "127.0.0.1:54321".parse().unwrap();
        let matching = MIB_TCPROW_OWNER_PID {
            dwLocalAddr: ipv4_to_dword(Ipv4Addr::LOCALHOST),
            dwLocalPort: port_to_dword(54321),
            dwRemoteAddr: ipv4_to_dword(Ipv4Addr::LOCALHOST),
            dwRemotePort: port_to_dword(LISTEN_PORT),
            dwOwningPid: 42,
            ..Default::default()
        };
        let server_side = MIB_TCPROW_OWNER_PID {
            dwLocalAddr: ipv4_to_dword(Ipv4Addr::LOCALHOST),
            dwLocalPort: port_to_dword(LISTEN_PORT),
            dwRemoteAddr: ipv4_to_dword(Ipv4Addr::LOCALHOST),
            dwRemotePort: port_to_dword(54321),
            dwOwningPid: 7,
            ..Default::default()
        };
        assert_eq!(
            matching_client_pid(&[server_side, matching], remote),
            Some(42)
        );
    }

    #[cfg(windows)]
    #[test]
    fn stop_managed_kills_and_reaps_child_within_deadline() {
        let child = Command::new("cmd")
            .args(["/C", "ping -n 30 127.0.0.1 >NUL"])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .unwrap();
        let process = ManagedChild::new(child).unwrap();
        stop_managed(process, Instant::now() + Duration::from_secs(2)).unwrap();
    }

    #[test]
    fn operation_ids_deduplicate_and_publish_final_result() {
        let request_id = "0123456789abcdef0123456789abcdef";
        assert!(matches!(
            begin_operation(request_id).unwrap(),
            BeginOperation::Execute
        ));
        let pending = operation_status(request_id);
        assert!(!pending.done);
        let completed = finish_operation(request_id, "failure".into());
        assert!(completed.done);
        assert_eq!(completed.error, "failure");
        let duplicate = begin_operation(request_id).unwrap();
        let BeginOperation::Existing(duplicate) = duplicate else {
            panic!("duplicate request executed twice");
        };
        assert!(duplicate.done);
        assert_eq!(duplicate.error, "failure");
    }

    #[test]
    fn queued_operation_expires_before_it_can_change_process_state() {
        let guard = OPERATION_LOCK.lock().unwrap();
        let deadline = Instant::now() + Duration::from_millis(20);
        let worker = thread::spawn(move || stop_inner(deadline));
        thread::sleep(Duration::from_millis(40));
        drop(guard);
        assert_eq!(
            worker.join().unwrap().unwrap_err(),
            "helper operation timed out"
        );
    }
}
