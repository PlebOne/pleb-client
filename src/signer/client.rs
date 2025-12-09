//! D-Bus client for communicating with Pleb Signer
//!
//! This client connects to an external Pleb Signer instance running on the system
//! to perform signing operations without handling private keys directly.

#![allow(dead_code)]  // Planned infrastructure for future integration

use serde::{Deserialize, Serialize};
use zbus::{Connection, Proxy};

/// D-Bus service details for Pleb Signer
const DBUS_SERVICE: &str = "com.plebsigner.Signer";
const DBUS_PATH: &str = "/com/plebsigner/Signer";
const DBUS_INTERFACE: &str = "com.plebsigner.Signer1";

/// Response from the signer service
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignerResponse {
    pub success: bool,
    pub id: String,
    #[serde(default)]
    pub result: Option<String>,
    #[serde(default)]
    pub error: Option<String>,
}

/// Public key result from GetPublicKey
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PublicKeyResult {
    pub npub: String,
    pub pubkey_hex: String,
}

/// Signed event result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedEventResult {
    pub event_json: String,
    pub event_id: String,
}

/// Encryption result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptResult {
    pub ciphertext: String,
}

/// Decryption result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DecryptResult {
    pub plaintext: String,
}

/// Key info from ListKeys
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyInfo {
    pub name: String,
    pub npub: String,
    pub pubkey_hex: String,
    pub is_active: bool,
}

/// Error type for signer operations
#[derive(Debug, thiserror::Error)]
pub enum SignerError {
    #[error("D-Bus connection error: {0}")]
    ConnectionError(String),
    
    #[error("Signer not ready (locked or not running)")]
    NotReady,
    
    #[error("Signer error: {0}")]
    SignerError(String),
    
    #[error("Parse error: {0}")]
    ParseError(String),
}

/// Client for communicating with Pleb Signer via D-Bus
pub struct SignerClient {
    connection: Connection,
    app_id: String,
}

impl SignerClient {
    /// Create a new signer client and connect to D-Bus
    pub async fn new(app_id: &str) -> Result<Self, SignerError> {
        let connection = Connection::session()
            .await
            .map_err(|e| SignerError::ConnectionError(e.to_string()))?;
        
        tracing::info!("Connected to D-Bus session bus");
        
        Ok(Self {
            connection,
            app_id: app_id.to_string(),
        })
    }

    /// Get a proxy to the signer service
    async fn get_proxy(&self) -> Result<Proxy<'_>, SignerError> {
        Proxy::new(
            &self.connection,
            DBUS_SERVICE,
            DBUS_PATH,
            DBUS_INTERFACE,
        )
        .await
        .map_err(|e| SignerError::ConnectionError(e.to_string()))
    }

    /// Parse a signer response
    fn parse_response<T: for<'de> Deserialize<'de>>(&self, response: &str) -> Result<T, SignerError> {
        let resp: SignerResponse = serde_json::from_str(response)
            .map_err(|e| SignerError::ParseError(e.to_string()))?;
        
        if !resp.success {
            return Err(SignerError::SignerError(
                resp.error.unwrap_or_else(|| "Unknown error".into())
            ));
        }
        
        let result_str = resp.result
            .ok_or_else(|| SignerError::ParseError("No result in response".into()))?;
        
        serde_json::from_str(&result_str)
            .map_err(|e| SignerError::ParseError(e.to_string()))
    }

    /// Check if the signer is ready (unlocked and running)
    pub async fn is_ready(&self) -> Result<bool, SignerError> {
        let proxy = self.get_proxy().await?;
        
        let result: bool = proxy.call("IsReady", &())
            .await
            .map_err(|e| SignerError::ConnectionError(e.to_string()))?;
        
        Ok(result)
    }

    /// Get the signer version
    pub async fn version(&self) -> Result<String, SignerError> {
        let proxy = self.get_proxy().await?;
        
        let result: String = proxy.call("Version", &())
            .await
            .map_err(|e| SignerError::ConnectionError(e.to_string()))?;
        
        Ok(result)
    }

    /// Get the active public key
    pub async fn get_public_key(&self) -> Result<PublicKeyResult, SignerError> {
        let proxy = self.get_proxy().await?;
        
        let result: String = proxy.call("GetPublicKey", &("",))
            .await
            .map_err(|e| SignerError::ConnectionError(e.to_string()))?;
        
        self.parse_response(&result)
    }

    /// List all available keys
    pub async fn list_keys(&self) -> Result<Vec<KeyInfo>, SignerError> {
        let proxy = self.get_proxy().await?;
        
        let result: String = proxy.call("ListKeys", &())
            .await
            .map_err(|e| SignerError::ConnectionError(e.to_string()))?;
        
        serde_json::from_str(&result)
            .map_err(|e| SignerError::ParseError(e.to_string()))
    }

    /// Sign a Nostr event
    pub async fn sign_event(&self, event_json: &str) -> Result<SignedEventResult, SignerError> {
        let proxy = self.get_proxy().await?;
        
        let result: String = proxy.call("SignEvent", &(event_json, "", &self.app_id))
            .await
            .map_err(|e| SignerError::ConnectionError(e.to_string()))?;
        
        self.parse_response(&result)
    }

    /// NIP-04 encrypt a message
    pub async fn nip04_encrypt(
        &self,
        plaintext: &str,
        recipient_pubkey: &str,
    ) -> Result<String, SignerError> {
        let proxy = self.get_proxy().await?;
        
        let result: String = proxy.call("Nip04Encrypt", &(plaintext, recipient_pubkey, "", &self.app_id))
            .await
            .map_err(|e| SignerError::ConnectionError(e.to_string()))?;
        
        let encrypted: EncryptResult = self.parse_response(&result)?;
        Ok(encrypted.ciphertext)
    }

    /// NIP-04 decrypt a message
    pub async fn nip04_decrypt(
        &self,
        ciphertext: &str,
        sender_pubkey: &str,
    ) -> Result<String, SignerError> {
        let proxy = self.get_proxy().await?;
        
        let result: String = proxy.call("Nip04Decrypt", &(ciphertext, sender_pubkey, "", &self.app_id))
            .await
            .map_err(|e| SignerError::ConnectionError(e.to_string()))?;
        
        let decrypted: DecryptResult = self.parse_response(&result)?;
        Ok(decrypted.plaintext)
    }

    /// NIP-44 encrypt a message
    pub async fn nip44_encrypt(
        &self,
        plaintext: &str,
        recipient_pubkey: &str,
    ) -> Result<String, SignerError> {
        let proxy = self.get_proxy().await?;
        
        let result: String = proxy.call("Nip44Encrypt", &(plaintext, recipient_pubkey, "", &self.app_id))
            .await
            .map_err(|e| SignerError::ConnectionError(e.to_string()))?;
        
        let encrypted: EncryptResult = self.parse_response(&result)?;
        Ok(encrypted.ciphertext)
    }

    /// NIP-44 decrypt a message
    pub async fn nip44_decrypt(
        &self,
        ciphertext: &str,
        sender_pubkey: &str,
    ) -> Result<String, SignerError> {
        let proxy = self.get_proxy().await?;
        
        let result: String = proxy.call("Nip44Decrypt", &(ciphertext, sender_pubkey, "", &self.app_id))
            .await
            .map_err(|e| SignerError::ConnectionError(e.to_string()))?;
        
        let decrypted: DecryptResult = self.parse_response(&result)?;
        Ok(decrypted.plaintext)
    }
}
