use std::path::PathBuf;
use std::sync::{LazyLock, RwLock};

static HOME: LazyLock<RwLock<PathBuf>> = LazyLock::new(|| {
    RwLock::new(
        std::env::var_os("BOSS_HOME")
            .map(PathBuf::from)
            .or_else(dirs::home_dir)
            .unwrap_or_else(|| PathBuf::from(".")),
    )
});

static OVERRIDDEN: RwLock<bool> = RwLock::new(false);

pub struct Paths;

impl Paths {
    pub fn home() -> PathBuf {
        HOME.read().unwrap().clone()
    }

    pub fn set_home(home: PathBuf) {
        *HOME.write().unwrap() = home;
        *OVERRIDDEN.write().unwrap() = true;
    }

    pub fn is_sandboxed() -> bool {
        *OVERRIDDEN.read().unwrap() || std::env::var_os("BOSS_HOME").is_some()
    }

    pub fn claude() -> PathBuf {
        Self::home().join(".claude")
    }

    pub fn codex() -> PathBuf {
        Self::home().join(".codex")
    }

    pub fn cursor() -> PathBuf {
        Self::home().join(".cursor")
    }

    pub fn pi() -> PathBuf {
        Self::home().join(".pi")
    }

    pub fn omp() -> PathBuf {
        Self::home().join(".omp")
    }

    pub fn gemini() -> PathBuf {
        Self::home().join(".gemini")
    }

    pub fn copilot() -> PathBuf {
        Self::home().join(".copilot")
    }

    pub fn config_dir() -> PathBuf {
        if Self::is_sandboxed() {
            return Self::home().join(if cfg!(target_os = "macos") { "Library/Application Support" } else { ".config" });
        }
        dirs::config_dir().unwrap_or_else(|| Self::home().join(".config"))
    }

    pub fn app_data() -> PathBuf {
        let base = if Self::is_sandboxed() {
            Self::home().join(if cfg!(target_os = "macos") { "Library/Application Support" } else { ".local/share" })
        } else {
            dirs::data_dir().unwrap_or_else(|| Self::home().join(".local/share"))
        };
        let dir = base.join("TheBoss");
        let _ = std::fs::create_dir_all(&dir);
        dir
    }
}
