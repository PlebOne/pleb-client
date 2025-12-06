//! Blossom protocol implementation for media uploads
//! See: https://github.com/hzrd149/blossom

use nostr_sdk::prelude::*;
use reqwest::header::{HeaderMap, HeaderValue, AUTHORIZATION, CONTENT_TYPE};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::Path;

/// Response from Blossom server after successful upload
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlossomUploadResponse {
    pub sha256: String,
    pub size: u64,
    pub url: String,
    #[serde(rename = "type")]
    pub mime_type: Option<String>,
    pub uploaded: Option<u64>,
}

/// Upload media to a Blossom server
/// 
/// # Arguments
/// * `server_url` - Base URL of the Blossom server (e.g., "https://blossom.band")
/// * `file_path` - Path to the local file to upload
/// * `keys` - Nostr keys for signing the authorization event
/// 
/// # Returns
/// The URL of the uploaded file on success
pub async fn upload_media(
    server_url: &str,
    file_path: &str,
    keys: &Keys,
) -> Result<BlossomUploadResponse, String> {
    let path = Path::new(file_path);
    
    // Read the file
    let file_data = tokio::fs::read(path)
        .await
        .map_err(|e| format!("Failed to read file: {}", e))?;
    
    // Calculate SHA256 hash
    let mut hasher = Sha256::new();
    hasher.update(&file_data);
    let hash = hasher.finalize();
    let hash_hex = hex::encode(hash);
    
    // Detect MIME type
    let mime_type = mime_guess::from_path(path)
        .first()
        .map(|m| m.to_string())
        .unwrap_or_else(|| "application/octet-stream".to_string());
    
    tracing::info!("Uploading {} ({} bytes, {})", file_path, file_data.len(), mime_type);
    
    // Create Blossom authorization event (kind 24242)
    // The event content is "Upload <filename>" and tags include the hash
    let filename = path.file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("file");
    
    let now = Timestamp::now();
    let expiration = Timestamp::from(now.as_u64() + 300); // 5 minutes
    
    // Build the authorization event
    // Blossom uses kind 24242 for upload auth
    let auth_event = EventBuilder::new(
        Kind::Custom(24242),
        format!("Upload {}", filename),
    )
    .tag(Tag::custom(TagKind::Custom("t".into()), vec!["upload".to_string()]))
    .tag(Tag::custom(TagKind::Custom("x".into()), vec![hash_hex.clone()]))
    .tag(Tag::expiration(expiration))
    .sign_with_keys(keys)
    .map_err(|e| format!("Failed to sign auth event: {}", e))?;
    
    // Encode the event as base64 for Authorization header
    let auth_json = serde_json::to_string(&auth_event)
        .map_err(|e| format!("Failed to serialize auth event: {}", e))?;
    let auth_base64 = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, auth_json);
    
    // Build headers
    let mut headers = HeaderMap::new();
    headers.insert(
        AUTHORIZATION,
        HeaderValue::from_str(&format!("Nostr {}", auth_base64))
            .map_err(|e| format!("Invalid auth header: {}", e))?,
    );
    headers.insert(
        CONTENT_TYPE,
        HeaderValue::from_str(&mime_type)
            .map_err(|e| format!("Invalid content type: {}", e))?,
    );
    
    // Upload endpoint
    let upload_url = format!("{}/upload", server_url.trim_end_matches('/'));
    
    // Make the upload request
    let client = reqwest::Client::new();
    let response = client
        .put(&upload_url)
        .headers(headers)
        .body(file_data)
        .timeout(std::time::Duration::from_secs(120))
        .send()
        .await
        .map_err(|e| format!("Upload request failed: {}", e))?;
    
    let status = response.status();
    let body = response.text().await
        .map_err(|e| format!("Failed to read response: {}", e))?;
    
    if !status.is_success() {
        return Err(format!("Upload failed ({}): {}", status, body));
    }
    
    // Parse the response
    let upload_response: BlossomUploadResponse = serde_json::from_str(&body)
        .map_err(|e| format!("Failed to parse response: {} - Body: {}", e, body))?;
    
    tracing::info!("Upload successful: {}", upload_response.url);
    
    Ok(upload_response)
}

/// Get the media type category from a MIME type
pub fn get_media_category(mime_type: &str) -> &'static str {
    if mime_type.starts_with("image/") {
        "image"
    } else if mime_type.starts_with("video/") {
        "video"
    } else if mime_type.starts_with("audio/") {
        "audio"
    } else {
        "file"
    }
}

/// Check if a file is a supported media type
pub fn is_supported_media(file_path: &str) -> bool {
    let mime = mime_guess::from_path(file_path)
        .first()
        .map(|m| m.to_string())
        .unwrap_or_default();
    
    mime.starts_with("image/") || mime.starts_with("video/")
}

/// Get the file extension for supported types
pub fn get_supported_extensions() -> Vec<&'static str> {
    vec![
        // Images
        "jpg", "jpeg", "png", "gif", "webp", "svg",
        // Videos
        "mp4", "webm", "mov", "avi", "mkv",
    ]
}
