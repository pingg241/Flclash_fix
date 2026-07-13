use crate::frb_generated::StreamSink;
use flutter_rust_bridge::for_generated::SseCodec;
use flutter_rust_bridge::frb;
use hmac::{Hmac, Mac};
use interprocess::local_socket::prelude::*;
use interprocess::local_socket::{GenericFilePath, ListenerNonblockingMode, ListenerOptions};
use sha2::Sha256;
use std::io::{self, Read, Write};
#[cfg(unix)]
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{self, SyncSender, TrySendError};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::{Duration, Instant};

#[cfg(unix)]
use std::os::unix::io::RawFd;

macro_rules! ipc_debug {
    ($($arg:tt)*) => {
        #[cfg(debug_assertions)]
        eprintln!($($arg)*);
    };
}

static RUNNING: AtomicBool = AtomicBool::new(false);
static CONNECTED: AtomicBool = AtomicBool::new(false);
static LAST_ERROR: Mutex<Option<String>> = Mutex::new(None);
static GENERATION: AtomicU64 = AtomicU64::new(0);
static EVENT_GENERATION: AtomicU64 = AtomicU64::new(0);
static LIFECYCLE: Mutex<()> = Mutex::new(());
static ACK_STATE: (Mutex<AckState>, Condvar) = (
    Mutex::new(AckState {
        generation: 0,
        acknowledged: 0,
    }),
    Condvar::new(),
);
#[cfg(unix)]
static SHUTDOWN_FD: Mutex<Option<RawFd>> = Mutex::new(None);

struct ServerState {
    connection: Option<ConnectionSender>,
    handle: Option<thread::JoinHandle<()>>,
}

#[derive(Clone)]
struct ConnectionSender {
    generation: u64,
    tx: SyncSender<Vec<u8>>,
    active: Arc<AtomicBool>,
}

static STATE: Mutex<ServerState> = Mutex::new(ServerState {
    connection: None,
    handle: None,
});

const TYPE_READY: u8 = 0x00;
const TYPE_CONNECTED: u8 = 0x01;
const TYPE_DISCONNECTED: u8 = 0x02;
const TYPE_DATA: u8 = 0x03;
const TYPE_ERROR: u8 = 0x04;

const MAX_IPC_FRAME_SIZE: usize = 64 << 20;
const HANDSHAKE_FRAME_SIZE: usize = 32;
const MIN_TOKEN_SIZE: usize = 16;
const MAX_TOKEN_SIZE: usize = 256;
const IO_POLL_INTERVAL: Duration = Duration::from_millis(10);
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(2);
const OUTBOUND_QUEUE_SIZE: usize = 256;
const EVENT_WINDOW_SIZE: u64 = 128;
const SERVER_PROOF_LABEL: &[u8] = b"flclash-ipc-server-v1";
const CORE_PROOF_LABEL: &[u8] = b"flclash-ipc-core-v1";

type HmacSha256 = Hmac<Sha256>;

struct AckState {
    generation: u64,
    acknowledged: u64,
}

fn make_data_frame(generation: u64, sequence: u64, payload: &[u8]) -> Vec<u8> {
    let mut frame = Vec::with_capacity(17 + payload.len());
    frame.push(TYPE_DATA);
    frame.extend_from_slice(&generation.to_le_bytes());
    frame.extend_from_slice(&sequence.to_le_bytes());
    frame.extend_from_slice(payload);
    frame
}

fn reset_ack_state(generation: u64) {
    let (lock, condition) = &ACK_STATE;
    if let Ok(mut state) = lock.lock() {
        state.generation = generation;
        state.acknowledged = 0;
        condition.notify_all();
    }
}

fn wait_for_event_credit(generation: u64, sequence: u64, active: &impl Fn() -> bool) -> bool {
    let (lock, condition) = &ACK_STATE;
    let mut state = match lock.lock() {
        Ok(state) => state,
        Err(_) => return false,
    };
    while state.generation == generation
        && sequence.saturating_sub(state.acknowledged) > EVENT_WINDOW_SIZE
        && active()
    {
        state = match condition.wait_timeout(state, IO_POLL_INTERVAL) {
            Ok((state, _)) => state,
            Err(_) => return false,
        };
    }
    state.generation == generation && active()
}

#[frb]
pub fn acknowledge_ipc_events(generation: u64, through_sequence: u64) {
    let (lock, condition) = &ACK_STATE;
    if let Ok(mut state) = lock.lock() {
        if state.generation != generation || through_sequence <= state.acknowledged {
            return;
        }
        state.acknowledged = through_sequence;
        condition.notify_all();
    }
}

fn make_frame(ty: u8, payload: &[u8]) -> Vec<u8> {
    let mut v = Vec::with_capacity(1 + payload.len());
    v.push(ty);
    v.extend_from_slice(payload);
    v
}

fn validate_token(token: &str) -> Result<(), String> {
    if !(MIN_TOKEN_SIZE..=MAX_TOKEN_SIZE).contains(&token.len()) {
        return Err(format!(
            "IPC token length must be between {MIN_TOKEN_SIZE} and {MAX_TOKEN_SIZE} bytes"
        ));
    }
    if !token.is_ascii() || token.bytes().any(|byte| byte.is_ascii_control()) {
        return Err("IPC token must contain printable ASCII characters only".into());
    }
    Ok(())
}

fn valid_socket_suffix(suffix: &str) -> bool {
    (1..=64).contains(&suffix.len())
        && suffix
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
}

fn validate_socket_name(name: &str) -> Result<(), String> {
    #[cfg(unix)]
    {
        let path = Path::new(name);
        if path.parent() != Some(Path::new("/tmp")) {
            return Err("IPC socket must be created directly under /tmp".into());
        }
        let file_name = path
            .file_name()
            .and_then(|value| value.to_str())
            .ok_or("IPC socket name is not valid UTF-8")?;
        let suffix = file_name
            .strip_prefix("FlClashSocket_")
            .and_then(|value| value.strip_suffix(".sock"))
            .ok_or("Invalid IPC socket name")?;
        if !valid_socket_suffix(suffix) {
            return Err("Invalid IPC socket suffix".into());
        }
    }
    #[cfg(windows)]
    {
        let suffix = name
            .strip_prefix(r"\\.\pipe\FlClashCore_")
            .ok_or("Invalid IPC pipe name")?;
        if !valid_socket_suffix(suffix) {
            return Err("Invalid IPC pipe suffix".into());
        }
    }
    Ok(())
}

fn proof(token: &[u8], label: &[u8]) -> [u8; HANDSHAKE_FRAME_SIZE] {
    let mut mac = HmacSha256::new_from_slice(token).expect("HMAC accepts keys of any size");
    mac.update(label);
    mac.finalize().into_bytes().into()
}

fn verify_proof(token: &[u8], label: &[u8], candidate: &[u8]) -> bool {
    let mut mac = HmacSha256::new_from_slice(token).expect("HMAC accepts keys of any size");
    mac.update(label);
    mac.verify_slice(candidate).is_ok()
}

fn cleanup_socket(path: &str) {
    #[cfg(unix)]
    {
        if std::fs::symlink_metadata(path).is_ok() {
            let _ = std::fs::remove_file(path);
        }
    }
    #[cfg(windows)]
    {
        let _ = path;
    }
}

#[frb]
pub fn restart_ipc_server(
    name: String,
    token: String,
    sink: StreamSink<Vec<u8>, SseCodec>,
) -> Result<(), String> {
    validate_socket_name(&name)?;
    validate_token(&token)?;
    let _lifecycle = LIFECYCLE
        .lock()
        .map_err(|error| format!("Lifecycle lock poisoned: {error}"))?;
    stop_current_server()?;

    let new_gen = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
    ipc_debug!("[IPC] restart_ipc_server: gen={new_gen}, name={name}");

    cleanup_socket(&name);

    RUNNING.store(true, Ordering::SeqCst);
    ipc_debug!("[IPC] restart_ipc_server: RUNNING=true, spawning io_loop");

    let handle = thread::Builder::new()
        .name("ipc-server".into())
        .spawn(move || io_loop(name, token.into_bytes(), sink, new_gen))
        .map_err(|e| {
            RUNNING.store(false, Ordering::SeqCst);
            ipc_debug!("[IPC] restart_ipc_server: spawn failed: {e}");
            format!("Failed to spawn thread: {e}")
        })?;

    STATE
        .lock()
        .map_err(|error| format!("State lock poisoned: {error}"))?
        .handle = Some(handle);
    ipc_debug!("[IPC] restart_ipc_server: done, thread spawned");

    Ok(())
}

#[cfg(unix)]
fn shutdown_old_fd() {
    if let Ok(mut guard) = SHUTDOWN_FD.lock() {
        if let Some(fd) = guard.take() {
            ipc_debug!("[IPC] shutdown_old_fd: shutting down fd={fd}");
            if unsafe { libc::shutdown(fd, libc::SHUT_RDWR) } != 0 {
                ipc_debug!(
                    "[IPC] shutdown_old_fd: shutdown failed: {}",
                    io::Error::last_os_error()
                );
            }
        }
    }
}

#[cfg(not(unix))]
fn shutdown_old_fd() {}

fn stop_current_server() -> Result<(), String> {
    RUNNING.store(false, Ordering::SeqCst);
    CONNECTED.store(false, Ordering::SeqCst);
    ACK_STATE.1.notify_all();
    let old_handle = {
        let mut guard = STATE
            .lock()
            .map_err(|error| format!("State lock poisoned: {error}"))?;
        if let Some(connection) = guard.connection.take() {
            connection.active.store(false, Ordering::SeqCst);
        }
        guard.handle.take()
    };
    shutdown_old_fd();
    if let Some(handle) = old_handle {
        ipc_debug!("[IPC] joining old server thread...");
        handle
            .join()
            .map_err(|_| "IPC server thread panicked".to_string())?;
        ipc_debug!("[IPC] old server thread joined");
    }
    Ok(())
}

#[frb]
pub fn stop_ipc_server() -> Result<(), String> {
    ipc_debug!(
        "[IPC] stop_ipc_server: RUNNING={}",
        RUNNING.load(Ordering::SeqCst)
    );
    let _lifecycle = LIFECYCLE
        .lock()
        .map_err(|error| format!("Lifecycle lock poisoned: {error}"))?;
    stop_current_server()
}

#[frb]
pub fn ipc_server_status() -> bool {
    RUNNING.load(Ordering::SeqCst)
}

#[frb]
pub fn is_ipc_connected() -> bool {
    CONNECTED.load(Ordering::SeqCst)
}

#[frb]
pub fn send_ipc_message(data: Vec<u8>) -> Result<(), String> {
    if data.len() > MAX_IPC_FRAME_SIZE {
        return Err(format!(
            "IPC frame is too large: {} > {MAX_IPC_FRAME_SIZE}",
            data.len()
        ));
    }
    if !CONNECTED.load(Ordering::SeqCst) {
        return Err("IPC client is not connected".into());
    }
    if let Ok(mut guard) = LAST_ERROR.lock() {
        if let Some(err) = guard.take() {
            ipc_debug!("[IPC] send_ipc_message: returning cached error: {err}");
            return Err(err);
        }
    }
    let connection = STATE
        .lock()
        .map_err(|error| format!("State lock poisoned: {error}"))?
        .connection
        .clone()
        .ok_or("IPC server is not running")?;
    match connection.tx.try_send(data) {
        Ok(()) => Ok(()),
        Err(TrySendError::Disconnected(_)) => Err("IPC writer is disconnected".into()),
        Err(TrySendError::Full(_)) => {
            let message = "IPC outbound queue is full; connection closed".to_string();
            connection.active.store(false, Ordering::SeqCst);
            CONNECTED.store(false, Ordering::SeqCst);
            if let Ok(mut guard) = STATE.lock() {
                if guard
                    .connection
                    .as_ref()
                    .is_some_and(|current| current.generation == connection.generation)
                {
                    guard.connection = None;
                }
            }
            if let Ok(mut guard) = LAST_ERROR.lock() {
                *guard = Some(message.clone());
            }
            shutdown_old_fd();
            Err(message)
        }
    }
}

fn interrupted_error() -> io::Error {
    io::Error::new(io::ErrorKind::Interrupted, "IPC server is stopping")
}

fn check_io_state(deadline: Option<Instant>, active: &impl Fn() -> bool) -> io::Result<()> {
    if !active() {
        return Err(interrupted_error());
    }
    if deadline.is_some_and(|value| Instant::now() >= value) {
        return Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "IPC operation timed out",
        ));
    }
    Ok(())
}

fn read_exact_interruptible(
    reader: &mut impl Read,
    buffer: &mut [u8],
    deadline: Option<Instant>,
    active: &impl Fn() -> bool,
) -> io::Result<()> {
    let mut offset = 0;
    while offset < buffer.len() {
        check_io_state(deadline, active)?;
        match reader.read(&mut buffer[offset..]) {
            Ok(0) => {
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "IPC peer closed the connection",
                ));
            }
            Ok(count) => offset += count,
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(IO_POLL_INTERVAL);
            }
            Err(error) => return Err(error),
        }
    }
    Ok(())
}

fn write_all_interruptible(
    writer: &mut impl Write,
    buffer: &[u8],
    deadline: Option<Instant>,
    active: &impl Fn() -> bool,
) -> io::Result<()> {
    let mut offset = 0;
    while offset < buffer.len() {
        check_io_state(deadline, active)?;
        match writer.write(&buffer[offset..]) {
            Ok(0) => {
                return Err(io::Error::new(
                    io::ErrorKind::WriteZero,
                    "write returned zero",
                ))
            }
            Ok(count) => offset += count,
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(IO_POLL_INTERVAL);
            }
            Err(error) => return Err(error),
        }
    }
    writer.flush()
}

fn write_frame_interruptible(
    writer: &mut impl Write,
    data: &[u8],
    deadline: Option<Instant>,
    active: &impl Fn() -> bool,
) -> io::Result<()> {
    if data.len() > MAX_IPC_FRAME_SIZE {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "IPC frame is too large: {} > {MAX_IPC_FRAME_SIZE}",
                data.len()
            ),
        ));
    }
    let len = data.len() as u32;
    write_all_interruptible(writer, &len.to_le_bytes(), deadline, active)?;
    write_all_interruptible(writer, data, deadline, active)
}

fn read_frame_interruptible(
    reader: &mut impl Read,
    max_size: usize,
    deadline: Option<Instant>,
    active: &impl Fn() -> bool,
) -> io::Result<Vec<u8>> {
    let mut len_buf = [0u8; 4];
    read_exact_interruptible(reader, &mut len_buf, deadline, active)?;
    let len = u32::from_le_bytes(len_buf) as usize;
    if len > max_size {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("IPC frame is too large: {len} > {max_size}"),
        ));
    }
    let mut payload = vec![0u8; len];
    read_exact_interruptible(reader, &mut payload, deadline, active)?;
    Ok(payload)
}

fn authenticate_stream(
    stream: &mut (impl Read + Write),
    token: &[u8],
    active: &impl Fn() -> bool,
) -> io::Result<()> {
    let deadline = Some(Instant::now() + HANDSHAKE_TIMEOUT);
    let server_proof = proof(token, SERVER_PROOF_LABEL);
    write_frame_interruptible(stream, &server_proof, deadline, active)?;

    let core_proof = read_frame_interruptible(stream, HANDSHAKE_FRAME_SIZE, deadline, active)?;
    if core_proof.len() != HANDSHAKE_FRAME_SIZE
        || !verify_proof(token, CORE_PROOF_LABEL, &core_proof)
    {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "IPC authentication failed",
        ));
    }
    Ok(())
}

fn is_current_gen(gen: u64) -> bool {
    GENERATION.load(Ordering::SeqCst) == gen
}

fn save_shutdown_fd(stream: &LocalSocketStream) {
    #[cfg(unix)]
    {
        use std::os::fd::AsRawFd;
        use std::os::unix::io::AsFd;
        let LocalSocketStream::UdSocket(ref s) = stream;
        if let Ok(mut guard) = SHUTDOWN_FD.lock() {
            *guard = Some(s.as_fd().as_raw_fd());
        }
    }
    #[cfg(not(unix))]
    {
        let _ = stream;
    }
}

fn clear_shutdown_fd() {
    #[cfg(unix)]
    {
        if let Ok(mut guard) = SHUTDOWN_FD.lock() {
            *guard = None;
        }
    }
}

fn io_loop(name: String, token: Vec<u8>, sink: StreamSink<Vec<u8>, SseCodec>, gen: u64) {
    ipc_debug!("[IPC] io_loop[{gen}]: started");

    let fs_name = match name.clone().to_fs_name::<GenericFilePath>() {
        Ok(n) => n,
        Err(e) => {
            ipc_debug!("[IPC] io_loop[{gen}]: name error: {e}");
            let _ = sink.add(make_frame(
                TYPE_ERROR,
                format!("name error: {e}").as_bytes(),
            ));
            if is_current_gen(gen) {
                RUNNING.store(false, Ordering::SeqCst);
            }
            return;
        }
    };

    let listener = match ListenerOptions::new().name(fs_name).create_sync() {
        Ok(l) => l,
        Err(e) => {
            ipc_debug!("[IPC] io_loop[{gen}]: bind error: {e}");
            let _ = sink.add(make_frame(
                TYPE_ERROR,
                format!("bind error: {e}").as_bytes(),
            ));
            if is_current_gen(gen) {
                RUNNING.store(false, Ordering::SeqCst);
            }
            return;
        }
    };

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Err(error) = std::fs::set_permissions(&name, std::fs::Permissions::from_mode(0o600))
        {
            ipc_debug!("[IPC] io_loop[{gen}]: chmod error: {error}");
            let _ = sink.add(make_frame(
                TYPE_ERROR,
                format!("socket permission error: {error}").as_bytes(),
            ));
            if is_current_gen(gen) {
                RUNNING.store(false, Ordering::SeqCst);
            }
            cleanup_socket(&name);
            return;
        }
    }

    if let Err(e) = listener.set_nonblocking(ListenerNonblockingMode::Accept) {
        ipc_debug!("[IPC] io_loop[{gen}]: set_nonblocking error: {e}");
        let _ = sink.add(make_frame(
            TYPE_ERROR,
            format!("set_nonblocking error: {e}").as_bytes(),
        ));
        if is_current_gen(gen) {
            RUNNING.store(false, Ordering::SeqCst);
        }
        return;
    }

    ipc_debug!("[IPC] io_loop[{gen}]: listener bound, sending TYPE_READY");
    let _ = sink.add(make_frame(TYPE_READY, &[]));

    while RUNNING.load(Ordering::SeqCst) {
        let stream = match listener.accept() {
            Ok(s) => {
                ipc_debug!("[IPC] io_loop[{gen}]: client accepted");
                s
            }
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(100));
                continue;
            }
            Err(e) => {
                ipc_debug!("[IPC] io_loop[{gen}]: accept error: {e}");
                if RUNNING.load(Ordering::SeqCst) {
                    let _ = sink.add(make_frame(
                        TYPE_ERROR,
                        format!("accept error: {e}").as_bytes(),
                    ));
                }
                break;
            }
        };

        if let Err(e) = stream.set_nonblocking(true) {
            ipc_debug!("[IPC] io_loop[{gen}]: set_nonblocking(true) error: {e}");
            let _ = sink.add(make_frame(
                TYPE_ERROR,
                format!("stream nonblocking error: {e}").as_bytes(),
            ));
            continue;
        }

        save_shutdown_fd(&stream);

        let active = || RUNNING.load(Ordering::SeqCst) && is_current_gen(gen);
        let mut stream = stream;
        if let Err(_error) = authenticate_stream(&mut stream, &token, &active) {
            ipc_debug!("[IPC] io_loop[{gen}]: authentication failed: {_error}");
            clear_shutdown_fd();
            continue;
        }
        if !active() {
            clear_shutdown_fd();
            break;
        }

        let event_generation = EVENT_GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
        reset_ack_state(event_generation);

        let (tx, rx) = mpsc::sync_channel::<Vec<u8>>(OUTBOUND_QUEUE_SIZE);
        let running = Arc::new(AtomicBool::new(true));
        if let Ok(mut guard) = STATE.lock() {
            guard.connection = Some(ConnectionSender {
                generation: gen,
                tx,
                active: Arc::clone(&running),
            });
        }

        ipc_debug!("[IPC] io_loop[{gen}]: client connected, sending TYPE_CONNECTED");
        if let Ok(mut guard) = LAST_ERROR.lock() {
            *guard = None;
        }
        CONNECTED.store(true, Ordering::SeqCst);
        if sink.add(make_frame(TYPE_CONNECTED, &[])).is_err() {
            ipc_debug!("[IPC] io_loop[{gen}]: sink closed on TYPE_CONNECTED");
            CONNECTED.store(false, Ordering::SeqCst);
            break;
        }

        let (recv_half, send_half) = stream.split();
        let wr = Arc::clone(&running);

        let (err_tx, err_rx) = mpsc::channel::<String>();

        let writer = thread::spawn(move || {
            let mut sender = send_half;
            while wr.load(Ordering::SeqCst) {
                match rx.recv_timeout(IO_POLL_INTERVAL) {
                    Ok(data) => {
                        let active = || {
                            wr.load(Ordering::SeqCst)
                                && RUNNING.load(Ordering::SeqCst)
                                && is_current_gen(gen)
                        };
                        if let Err(e) = write_frame_interruptible(&mut sender, &data, None, &active)
                        {
                            let _ = err_tx.send(format!("write error: {e}"));
                            break;
                        }
                    }
                    Err(mpsc::RecvTimeoutError::Timeout) => continue,
                    Err(mpsc::RecvTimeoutError::Disconnected) => break,
                }
            }
            wr.store(false, Ordering::SeqCst);
        });

        let mut receiver = recv_half;
        let mut event_sequence = 0u64;
        loop {
            let active = || {
                running.load(Ordering::SeqCst)
                    && RUNNING.load(Ordering::SeqCst)
                    && is_current_gen(gen)
            };
            let next_sequence = event_sequence + 1;
            if !wait_for_event_credit(event_generation, next_sequence, &active) {
                break;
            }
            match read_frame_interruptible(&mut receiver, MAX_IPC_FRAME_SIZE, None, &active) {
                Ok(data) => {
                    event_sequence = next_sequence;
                    if sink
                        .add(make_data_frame(event_generation, event_sequence, &data))
                        .is_err()
                    {
                        ipc_debug!("[IPC] io_loop[{gen}]: sink closed on TYPE_DATA");
                        break;
                    }
                }
                Err(e) => {
                    ipc_debug!("[IPC] io_loop[{gen}]: read error: {e}");
                    let _ = sink.add(make_frame(
                        TYPE_ERROR,
                        format!("read error: {e}").as_bytes(),
                    ));
                    break;
                }
            }
        }

        running.store(false, Ordering::SeqCst);

        clear_shutdown_fd();

        if let Ok(mut guard) = STATE.lock() {
            if guard
                .connection
                .as_ref()
                .is_some_and(|connection| connection.generation == gen)
            {
                guard.connection = None;
            }
        }
        writer.join().ok();

        if let Ok(msg) = err_rx.try_recv() {
            ipc_debug!("[IPC] io_loop[{gen}]: writer error: {msg}");
            if is_current_gen(gen) {
                if let Ok(mut guard) = LAST_ERROR.lock() {
                    *guard = Some(msg.clone());
                }
            }
            let _ = sink.add(make_frame(TYPE_ERROR, msg.as_bytes()));
        }

        ipc_debug!("[IPC] io_loop[{gen}]: disconnected, sending TYPE_DISCONNECTED");
        if is_current_gen(gen) {
            CONNECTED.store(false, Ordering::SeqCst);
        }
        if sink.add(make_frame(TYPE_DISCONNECTED, &[])).is_err() {
            ipc_debug!("[IPC] io_loop[{gen}]: sink closed on TYPE_DISCONNECTED");
            break;
        }
    }

    ipc_debug!(
        "[IPC] io_loop[{gen}]: exiting (RUNNING={})",
        RUNNING.load(Ordering::SeqCst)
    );
    if is_current_gen(gen) {
        ipc_debug!("[IPC] io_loop[{gen}]: is current gen, cleaning up");
        RUNNING.store(false, Ordering::SeqCst);
        if let Ok(mut guard) = STATE.lock() {
            if guard
                .connection
                .as_ref()
                .is_some_and(|connection| connection.generation == gen)
            {
                guard.connection = None;
            }
        }
        cleanup_socket(&name);
    } else {
        ipc_debug!(
            "[IPC] io_loop[{gen}]: stale gen (current={}), skipping cleanup",
            GENERATION.load(Ordering::SeqCst)
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    struct ScriptedStream {
        input: Cursor<Vec<u8>>,
        output: Vec<u8>,
    }

    impl Read for ScriptedStream {
        fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
            self.input.read(buffer)
        }
    }

    impl Write for ScriptedStream {
        fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
            self.output.extend_from_slice(buffer);
            Ok(buffer.len())
        }

        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    fn frame(payload: &[u8]) -> Vec<u8> {
        let mut frame = Vec::with_capacity(4 + payload.len());
        frame.extend_from_slice(&(payload.len() as u32).to_le_bytes());
        frame.extend_from_slice(payload);
        frame
    }

    #[test]
    fn frame_limit_is_checked_before_payload_allocation() {
        let mut input = Cursor::new(((MAX_IPC_FRAME_SIZE + 1) as u32).to_le_bytes());
        let error =
            read_frame_interruptible(&mut input, MAX_IPC_FRAME_SIZE, None, &|| true).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::InvalidData);
    }

    #[test]
    fn interrupted_read_stops_without_waiting_for_io() {
        let mut input = Cursor::new(Vec::<u8>::new());
        let error =
            read_frame_interruptible(&mut input, MAX_IPC_FRAME_SIZE, None, &|| false).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
    }

    #[test]
    fn mutual_hmac_handshake_accepts_only_core_proof() {
        let token = b"0123456789abcdef0123456789abcdef";
        let core_proof = proof(token, CORE_PROOF_LABEL);
        let mut stream = ScriptedStream {
            input: Cursor::new(frame(&core_proof)),
            output: Vec::new(),
        };

        authenticate_stream(&mut stream, token, &|| true).unwrap();
        let mut server_output = Cursor::new(stream.output);
        let server_proof =
            read_frame_interruptible(&mut server_output, HANDSHAKE_FRAME_SIZE, None, &|| true)
                .unwrap();
        assert!(verify_proof(token, SERVER_PROOF_LABEL, &server_proof));
        assert!(!verify_proof(token, CORE_PROOF_LABEL, &server_proof));
    }

    #[test]
    fn mutual_hmac_handshake_rejects_wrong_proof() {
        let token = b"0123456789abcdef0123456789abcdef";
        let mut stream = ScriptedStream {
            input: Cursor::new(frame(&[0u8; HANDSHAKE_FRAME_SIZE])),
            output: Vec::new(),
        };
        let error = authenticate_stream(&mut stream, token, &|| true).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::PermissionDenied);
    }

    #[test]
    fn token_validation_rejects_short_and_control_values() {
        assert!(validate_token("0123456789abcdef0123456789abcdef").is_ok());
        assert!(validate_token("short").is_err());
        assert!(validate_token("0123456789abcdef0123456789abcde\n").is_err());
    }

    #[test]
    fn socket_name_validation_rejects_unrelated_paths() {
        #[cfg(unix)]
        {
            assert!(validate_socket_name("/tmp/FlClashSocket_123.sock").is_ok());
            assert!(validate_socket_name("/tmp/../etc/passwd").is_err());
            assert!(validate_socket_name("/tmp/FlClashSocket_../evil.sock").is_err());
        }
        #[cfg(windows)]
        {
            assert!(validate_socket_name(r"\\.\pipe\FlClashCore_123").is_ok());
            assert!(validate_socket_name(r"\\.\pipe\attacker").is_err());
            assert!(validate_socket_name(r"\\.\pipe\FlClashCore_..\evil").is_err());
        }
    }

    #[test]
    fn bounded_outbound_queue_reports_saturation() {
        let (tx, _rx) = mpsc::sync_channel(1);
        tx.try_send(vec![1]).unwrap();
        assert!(matches!(tx.try_send(vec![2]), Err(TrySendError::Full(_))));
    }

    #[test]
    fn event_credit_has_a_fixed_memory_window() {
        reset_ack_state(10_001);
        acknowledge_ipc_events(10_000, 50);
        acknowledge_ipc_events(10_001, 8);
        acknowledge_ipc_events(10_001, 3);
        {
            let state = ACK_STATE.0.lock().unwrap();
            assert_eq!(state.generation, 10_001);
            assert_eq!(state.acknowledged, 8);
        }

        let generation = 10_002;
        reset_ack_state(generation);
        assert!(wait_for_event_credit(
            generation,
            EVENT_WINDOW_SIZE,
            &|| true
        ));

        let waiter = thread::spawn(move || {
            wait_for_event_credit(generation, EVENT_WINDOW_SIZE + 1, &|| true)
        });
        thread::sleep(Duration::from_millis(20));
        assert!(!waiter.is_finished());
        acknowledge_ipc_events(generation, 1);
        assert!(waiter.join().unwrap());
    }

    #[test]
    fn concurrent_stops_are_serialized_and_idempotent() {
        let workers = (0..8)
            .map(|_| thread::spawn(stop_ipc_server))
            .collect::<Vec<_>>();
        for worker in workers {
            worker.join().unwrap().unwrap();
        }
        assert!(!ipc_server_status());
        assert!(!is_ipc_connected());
    }
}
