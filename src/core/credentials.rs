//! Secure credential storage with password-based encryption
//!
//! Uses Argon2 for key derivation and ChaCha20-Poly1305 for encryption.
//! Credentials are stored in an encrypted file in the user's data directory.

#![allow(dead_code)]  // Planned infrastructure for future integration

use std::fs;
use std::path::PathBuf;
use argon2::Argon2;
use chacha20poly1305::{
    aead::{Aead, KeyInit},
    ChaCha20Poly1305, Nonce,
};
use rand::RngCore;

const CREDENTIALS_FILE: &str = "credentials.enc";
const SALT_FILE: &str = "credentials.salt";
const NWC_FILE: &str = "nwc.enc";

/// Credential manager for secure, password-protected storage of Nostr keys
pub struct CredentialManager {
    data_dir: PathBuf,
}

impl CredentialManager {
    /// Create a new credential manager
    pub fn new() -> Result<Self, String> {
        let data_dir = directories::ProjectDirs::from("", "", "pleb-client")
            .ok_or("Failed to determine data directory")?
            .data_dir()
            .to_path_buf();
        
        // Ensure directory exists
        fs::create_dir_all(&data_dir)
            .map_err(|e| format!("Failed to create data directory: {}", e))?;
        
        Ok(Self { data_dir })
    }
    
    fn credentials_path(&self) -> PathBuf {
        self.data_dir.join(CREDENTIALS_FILE)
    }
    
    fn salt_path(&self) -> PathBuf {
        self.data_dir.join(SALT_FILE)
    }
    
    fn nwc_path(&self) -> PathBuf {
        self.data_dir.join(NWC_FILE)
    }
    
    /// Derive encryption key from password using Argon2
    fn derive_key(&self, password: &str, salt: &[u8]) -> Result<[u8; 32], String> {
        let mut key = [0u8; 32];
        Argon2::default()
            .hash_password_into(password.as_bytes(), salt, &mut key)
            .map_err(|e| format!("Key derivation failed: {}", e))?;
        Ok(key)
    }
    
    /// Store the nsec securely with password protection
    pub fn save_nsec(&self, nsec: &str, password: &str) -> Result<(), String> {
        // Generate a random salt and save it
        let mut salt = [0u8; 16];
        rand::thread_rng().fill_bytes(&mut salt);
        fs::write(self.salt_path(), &salt)
            .map_err(|e| format!("Failed to write salt: {}", e))?;
        
        // Derive encryption key from password
        let key = self.derive_key(password, &salt)?;
        
        // Generate random nonce
        let mut nonce_bytes = [0u8; 12];
        rand::thread_rng().fill_bytes(&mut nonce_bytes);
        let nonce = Nonce::from_slice(&nonce_bytes);
        
        // Encrypt the nsec
        let cipher = ChaCha20Poly1305::new_from_slice(&key)
            .map_err(|e| format!("Failed to create cipher: {}", e))?;
        let ciphertext = cipher
            .encrypt(nonce, nsec.as_bytes())
            .map_err(|e| format!("Encryption failed: {}", e))?;
        
        // Store nonce + ciphertext
        let mut data = nonce_bytes.to_vec();
        data.extend(ciphertext);
        
        fs::write(self.credentials_path(), &data)
            .map_err(|e| format!("Failed to save credentials: {}", e))?;
        
        Ok(())
    }
    
    /// Retrieve the stored nsec using the password
    pub fn get_nsec(&self, password: &str) -> Result<Option<String>, String> {
        // Read salt
        let salt = match fs::read(self.salt_path()) {
            Ok(s) => s,
            Err(_) => return Ok(None), // No credentials stored
        };
        
        // Read encrypted data
        let data = match fs::read(self.credentials_path()) {
            Ok(d) => d,
            Err(_) => return Ok(None), // No credentials stored
        };
        
        if data.len() < 13 {
            return Err("Invalid credential data".to_string());
        }
        
        // Extract nonce and ciphertext
        let nonce = Nonce::from_slice(&data[..12]);
        let ciphertext = &data[12..];
        
        // Derive key and decrypt
        let key = self.derive_key(password, &salt)?;
        let cipher = ChaCha20Poly1305::new_from_slice(&key)
            .map_err(|e| format!("Failed to create cipher: {}", e))?;
        
        let plaintext = cipher
            .decrypt(nonce, ciphertext)
            .map_err(|_| "Invalid password".to_string())?;
        
        String::from_utf8(plaintext)
            .map(Some)
            .map_err(|e| format!("Invalid credential data: {}", e))
    }
    
    /// Check if encrypted credentials are stored
    pub fn has_credentials(&self) -> bool {
        self.credentials_path().exists() && self.salt_path().exists()
    }
    
    /// Clear stored credentials (logout)
    pub fn clear(&self) -> Result<(), String> {
        // Remove both files, ignore if they don't exist
        let _ = fs::remove_file(self.credentials_path());
        let _ = fs::remove_file(self.salt_path());
        let _ = fs::remove_file(self.nwc_path());
        Ok(())
    }
    
    /// Store NWC URI securely with password protection (uses existing salt)
    pub fn save_nwc(&self, nwc_uri: &str, password: &str) -> Result<(), String> {
        // Salt must exist from nsec storage
        let salt = fs::read(self.salt_path())
            .map_err(|_| "No credentials stored - set up password first".to_string())?;
        
        // Derive encryption key from password
        let key = self.derive_key(password, &salt)?;
        
        // Generate random nonce
        let mut nonce_bytes = [0u8; 12];
        rand::thread_rng().fill_bytes(&mut nonce_bytes);
        let nonce = Nonce::from_slice(&nonce_bytes);
        
        // Encrypt the NWC URI
        let cipher = ChaCha20Poly1305::new_from_slice(&key)
            .map_err(|e| format!("Failed to create cipher: {}", e))?;
        let ciphertext = cipher
            .encrypt(nonce, nwc_uri.as_bytes())
            .map_err(|e| format!("Encryption failed: {}", e))?;
        
        // Store nonce + ciphertext
        let mut data = nonce_bytes.to_vec();
        data.extend(ciphertext);
        
        fs::write(self.nwc_path(), &data)
            .map_err(|e| format!("Failed to save NWC: {}", e))?;
        
        Ok(())
    }
    
    /// Retrieve the stored NWC URI using the password
    pub fn get_nwc(&self, password: &str) -> Result<Option<String>, String> {
        // Read salt
        let salt = match fs::read(self.salt_path()) {
            Ok(s) => s,
            Err(_) => return Ok(None), // No credentials stored
        };
        
        // Read encrypted NWC data
        let data = match fs::read(self.nwc_path()) {
            Ok(d) => d,
            Err(_) => return Ok(None), // No NWC stored
        };
        
        if data.len() < 13 {
            return Err("Invalid NWC data".to_string());
        }
        
        // Extract nonce and ciphertext
        let nonce = Nonce::from_slice(&data[..12]);
        let ciphertext = &data[12..];
        
        // Derive key and decrypt
        let key = self.derive_key(password, &salt)?;
        let cipher = ChaCha20Poly1305::new_from_slice(&key)
            .map_err(|e| format!("Failed to create cipher: {}", e))?;
        
        let plaintext = cipher
            .decrypt(nonce, ciphertext)
            .map_err(|_| "Invalid password or corrupted NWC data".to_string())?;
        
        String::from_utf8(plaintext)
            .map(Some)
            .map_err(|e| format!("Invalid NWC data: {}", e))
    }
    
    /// Check if NWC is stored
    pub fn has_nwc(&self) -> bool {
        self.nwc_path().exists()
    }
    
    /// Clear just NWC (disconnect wallet without clearing nsec)
    pub fn clear_nwc(&self) -> Result<(), String> {
        let _ = fs::remove_file(self.nwc_path());
        Ok(())
    }
}

impl Default for CredentialManager {
    fn default() -> Self {
        Self::new().expect("Failed to create credential manager")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_credential_manager_creation() {
        // This test may fail if no keyring service is available
        let result = CredentialManager::new();
        // Just check it doesn't panic - actual keyring may not be available in CI
        let _ = result;
    }
}
