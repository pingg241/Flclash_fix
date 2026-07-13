use rquickjs::{CatchResultExt, Context, Promise, Runtime};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

const MAX_CONCURRENT_EVALUATIONS: usize = 2;
const MAX_SCRIPT_BYTES: usize = 1024 * 1024;
const MAX_CONFIG_BYTES: usize = 16 * 1024 * 1024;
const MAX_OUTPUT_BYTES: usize = 16 * 1024 * 1024;
const MEMORY_LIMIT_BYTES: usize = 64 * 1024 * 1024;
const STACK_LIMIT_BYTES: usize = 1024 * 1024;
const MAX_TIMEOUT_MS: u32 = 15_000;
const DEFAULT_TIMEOUT_MS: u32 = MAX_TIMEOUT_MS;

static ACTIVE_EVALUATIONS: AtomicUsize = AtomicUsize::new(0);

struct EvaluationPermit;

impl EvaluationPermit {
    fn acquire() -> Result<Self, String> {
        ACTIVE_EVALUATIONS
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |active| {
                (active < MAX_CONCURRENT_EVALUATIONS).then_some(active + 1)
            })
            .map_err(|_| "Too many scripts are already running".to_owned())?;
        Ok(Self)
    }
}

impl Drop for EvaluationPermit {
    fn drop(&mut self) {
        ACTIVE_EVALUATIONS.fetch_sub(1, Ordering::AcqRel);
    }
}

#[flutter_rust_bridge::frb]
pub fn evaluate_script(script: String, config_json: String) -> Result<String, String> {
    evaluate_script_with_timeout(script, config_json, DEFAULT_TIMEOUT_MS)
}

fn evaluate_script_with_timeout(
    script: String,
    config_json: String,
    timeout_ms: u32,
) -> Result<String, String> {
    validate_input(&script, &config_json)?;
    let _permit = EvaluationPermit::acquire()?;
    let timeout = Duration::from_millis(timeout_ms.clamp(1, MAX_TIMEOUT_MS).into());
    let deadline = Instant::now() + timeout;
    let interrupted = Arc::new(AtomicBool::new(false));

    let runtime = Runtime::new().map_err(|error| format!("JavaScript runtime: {error}"))?;
    runtime.set_memory_limit(MEMORY_LIMIT_BYTES);
    runtime.set_max_stack_size(STACK_LIMIT_BYTES);
    let interrupt_flag = Arc::clone(&interrupted);
    runtime.set_interrupt_handler(Some(Box::new(move || {
        let expired = Instant::now() >= deadline;
        if expired {
            interrupt_flag.store(true, Ordering::Release);
        }
        expired
    })));

    let context =
        Context::full(&runtime).map_err(|error| format!("JavaScript context: {error}"))?;
    let result = context.with(|ctx| {
        ctx.eval::<(), _>(script)
            .catch(&ctx)
            .map_err(|error| error.to_string())?;
        ctx.globals()
            .set("__FLCLASH_CONFIG_JSON__", config_json)
            .catch(&ctx)
            .map_err(|error| error.to_string())?;
        let promise = ctx
            .eval::<Promise, _>(
                r#"
                (async () => {
                  if (typeof main !== 'function') {
                    throw new Error('Script must define a main function');
                  }
                  const config = JSON.parse(globalThis.__FLCLASH_CONFIG_JSON__);
                  delete globalThis.__FLCLASH_CONFIG_JSON__;
                  const value = await main(config);
                  const json = JSON.stringify(value ?? config);
                  if (typeof json !== 'string') {
                    throw new Error('Script result must be JSON serializable');
                  }
                  return json;
                })()
                "#,
            )
            .catch(&ctx)
            .map_err(|error| error.to_string())?;
        promise
            .finish::<String>()
            .catch(&ctx)
            .map_err(|error| error.to_string())
    });

    if interrupted.load(Ordering::Acquire) {
        return Err(format!(
            "Script evaluation timed out after {} ms",
            timeout.as_millis()
        ));
    }
    let output = result?;
    if output.len() > MAX_OUTPUT_BYTES {
        return Err(format!(
            "Script result exceeds the {} byte size limit",
            MAX_OUTPUT_BYTES
        ));
    }
    Ok(output)
}

fn validate_input(script: &str, config_json: &str) -> Result<(), String> {
    if script.len() > MAX_SCRIPT_BYTES {
        return Err(format!(
            "Script exceeds the {} byte size limit",
            MAX_SCRIPT_BYTES
        ));
    }
    if config_json.len() > MAX_CONFIG_BYTES {
        return Err(format!(
            "Config exceeds the {} byte size limit",
            MAX_CONFIG_BYTES
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Mutex, MutexGuard};

    static TEST_LOCK: Mutex<()> = Mutex::new(());

    fn test_lock() -> MutexGuard<'static, ()> {
        TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner())
    }

    fn evaluate(script: &str) -> Result<String, String> {
        evaluate_script_with_timeout(script.to_owned(), "{}".to_owned(), 100)
    }

    #[test]
    fn evaluates_normal_and_async_scripts() {
        let _test_guard = test_lock();
        assert_eq!(
            evaluate("function main(config) { config.port = 7890; return config; }").unwrap(),
            r#"{"port":7890}"#
        );
        assert_eq!(
            evaluate("async function main(config) { return Promise.resolve({ok: true}); }")
                .unwrap(),
            r#"{"ok":true}"#
        );
    }

    #[test]
    fn interrupts_sync_and_promise_job_loops() {
        let _test_guard = test_lock();
        let sync_error = evaluate("function main() { while (true) {} }").unwrap_err();
        assert!(sync_error.contains("timed out"), "{sync_error}");

        let promise_error = evaluate(
            "function main() { return Promise.resolve().then(() => { while (true) {} }); }",
        )
        .unwrap_err();
        assert!(promise_error.contains("timed out"), "{promise_error}");
    }

    #[test]
    fn rejects_memory_growth_exceptions_and_non_json_results() {
        let _test_guard = test_lock();
        let memory_error = evaluate(
            "function main() { const a = []; while (true) { a.push('x'.repeat(1048576)); } }",
        )
        .unwrap_err();
        assert!(
            memory_error.to_lowercase().contains("memory"),
            "{memory_error}"
        );

        let script_error = evaluate("function main() { throw new Error('broken'); }").unwrap_err();
        assert!(script_error.contains("broken"), "{script_error}");

        let json_error = evaluate("function main() { return 1n; }").unwrap_err();
        assert!(
            json_error.contains("serial") || json_error.contains("BigInt"),
            "{json_error}"
        );
    }

    #[test]
    fn repeated_runs_use_independent_contexts_and_release_permits() {
        let _test_guard = test_lock();
        for _ in 0..8 {
            assert_eq!(
                evaluate("const main = () => ({ok: true});").unwrap(),
                r#"{"ok":true}"#
            );
            assert_eq!(ACTIVE_EVALUATIONS.load(Ordering::Acquire), 0);
        }
    }

    #[test]
    fn enforces_concurrency_limit() {
        let _test_guard = test_lock();
        let _first = EvaluationPermit::acquire().unwrap();
        let _second = EvaluationPermit::acquire().unwrap();
        let error = EvaluationPermit::acquire().err().unwrap();
        assert!(error.contains("Too many scripts"));
    }
}
