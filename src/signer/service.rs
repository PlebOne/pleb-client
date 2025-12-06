//! D-Bus signer service - allows Pleb-Client to act as a signer for other apps
//!
//! This exposes the same D-Bus interface as Pleb Signer, allowing other Nostr
//! applications to use Pleb-Client for signing when it's running.

use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use zbus::{interface, connection::Builder as ConnectionBuilder, Connection};

/// D-Bus service name for Pleb-Client signer
pub const DBUS_NAME: &str = "com.plebclient.Signer";
pub const DBUS_PATH: &str = "/com/plebclient/Signer";

/// Response structure for D-Bus calls
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DbusResponse {
    pub success: bool,
    pub id: String,
    #[serde(default)]
    pub result: Option<String>,
    #[serde(default)]
    pub error: Option<String>,
}

impl DbusResponse {
    pub fn success(id: String, result: impl Serialize) -> String {
        serde_json::to_string(&DbusResponse {
            success: true,
            id,
            result: Some(serde_json::to_string(&result).unwrap_or_default()),
            error: None,
        }).unwrap_or_default()
    }

    pub fn error(id: String, error: impl ToString) -> String {
        serde_json::to_string(&DbusResponse {
            success: false,
            id,
            result: None,
            error: Some(error.to_string()),
        }).unwrap_or_default()
    }
}

/// Shared state for the signer service
pub struct SignerState {
    pub is_locked: bool,
    pub public_key: Option<String>,
    pub npub: Option<String>,
}

impl Default for SignerState {
    fn default() -> Self {
        Self {
            is_locked: true,
            public_key: None,
            npub: None,
        }
    }
}

/// D-Bus interface implementation for Pleb-Client as a signer
pub struct SignerService {
    state: Arc<RwLock<SignerState>>,
}

impl SignerService {
    pub fn new(state: Arc<RwLock<SignerState>>) -> Self {
        Self { state }
    }
}

#[interface(name = "com.plebclient.Signer1")]
impl SignerService {
    /// Check if the signer is unlocked and ready
    async fn is_ready(&self) -> bool {
        let state = self.state.read().await;
        !state.is_locked && state.public_key.is_some()
    }

    /// Get the version of this signer service
    fn version(&self) -> &str {
        env!("CARGO_PKG_VERSION")
    }

    /// Get the active public key
    async fn get_public_key(&self, _key_id: &str) -> String {
        let state = self.state.read().await;
        
        if state.is_locked {
            return DbusResponse::error(
                uuid::Uuid::new_v4().to_string(),
                "Signer is locked",
            );
        }
        
        match (&state.npub, &state.public_key) {
            (Some(npub), Some(pubkey)) => {
                #[derive(Serialize)]
                struct PubKeyResult {
                    npub: String,
                    pubkey_hex: String,
                }
                
                DbusResponse::success(
                    uuid::Uuid::new_v4().to_string(),
                    PubKeyResult {
                        npub: npub.clone(),
                        pubkey_hex: pubkey.clone(),
                    },
                )
            }
            _ => DbusResponse::error(
                uuid::Uuid::new_v4().to_string(),
                "No key available",
            ),
        }
    }

    /// Sign a Nostr event (placeholder - actual implementation would use nostr-sdk)
    async fn sign_event(&self, _event_json: &str, _key_id: &str, _app_id: &str) -> String {
        let state = self.state.read().await;
        
        if state.is_locked {
            return DbusResponse::error(
                uuid::Uuid::new_v4().to_string(),
                "Signer is locked",
            );
        }
        
        // TODO: Implement actual signing using stored keys
        DbusResponse::error(
            uuid::Uuid::new_v4().to_string(),
            "Signing not yet implemented in Pleb-Client signer service",
        )
    }

    /// NIP-04 encrypt (placeholder)
    async fn nip04_encrypt(
        &self,
        _plaintext: &str,
        _recipient_pubkey: &str,
        _key_id: &str,
        _app_id: &str,
    ) -> String {
        DbusResponse::error(
            uuid::Uuid::new_v4().to_string(),
            "NIP-04 encryption not yet implemented",
        )
    }

    /// NIP-04 decrypt (placeholder)
    async fn nip04_decrypt(
        &self,
        _ciphertext: &str,
        _sender_pubkey: &str,
        _key_id: &str,
        _app_id: &str,
    ) -> String {
        DbusResponse::error(
            uuid::Uuid::new_v4().to_string(),
            "NIP-04 decryption not yet implemented",
        )
    }

    /// NIP-44 encrypt (placeholder)
    async fn nip44_encrypt(
        &self,
        _plaintext: &str,
        _recipient_pubkey: &str,
        _key_id: &str,
        _app_id: &str,
    ) -> String {
        DbusResponse::error(
            uuid::Uuid::new_v4().to_string(),
            "NIP-44 encryption not yet implemented",
        )
    }

    /// NIP-44 decrypt (placeholder)
    async fn nip44_decrypt(
        &self,
        _ciphertext: &str,
        _sender_pubkey: &str,
        _key_id: &str,
        _app_id: &str,
    ) -> String {
        DbusResponse::error(
            uuid::Uuid::new_v4().to_string(),
            "NIP-44 decryption not yet implemented",
        )
    }
}

/// Start the D-Bus signer service
pub async fn start_signer_service(state: Arc<RwLock<SignerState>>) -> Result<Connection, zbus::Error> {
    let signer = SignerService::new(state);
    
    let connection = ConnectionBuilder::session()?
        .name(DBUS_NAME)?
        .serve_at(DBUS_PATH, signer)?
        .build()
        .await?;
    
    tracing::info!("Started D-Bus signer service at {}", DBUS_NAME);
    
    Ok(connection)
}
