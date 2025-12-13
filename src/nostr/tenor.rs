//! Tenor GIF service with privacy-preserving NIP-96 re-upload
//! 
//! This module implements a three-step process:
//! 1. Search Tenor for GIFs
//! 2. Download the GIF bytes (privacy firewall)
//! 3. Re-upload to a NIP-96 compatible server
//!
//! This ensures users' privacy - Tenor never sees the Nostr post,
//! and Nostr relays never see Tenor URLs.

use nostr_sdk::prelude::*;
use reqwest::header::{HeaderMap, HeaderValue, AUTHORIZATION, CONTENT_TYPE};
use serde::{Deserialize, Serialize};

/// GIF result from Tenor search
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GifResult {
    /// URL of the full-size GIF
    pub url: String,
    /// URL of the preview/thumbnail GIF (smaller, loads faster)
    pub preview_url: String,
    /// Width in pixels
    pub width: u32,
    /// Height in pixels  
    pub height: u32,
    /// Tenor content ID
    pub id: String,
}

/// Response from Tenor API
#[derive(Debug, Deserialize)]
struct TenorSearchResponse {
    results: Vec<TenorResult>,
}

#[derive(Debug, Deserialize)]
struct TenorResult {
    id: String,
    media_formats: TenorMediaFormats,
}

#[derive(Debug, Deserialize)]
struct TenorMediaFormats {
    gif: Option<TenorMedia>,
    tinygif: Option<TenorMedia>,
    mediumgif: Option<TenorMedia>,
}

#[derive(Debug, Clone, Deserialize)]
struct TenorMedia {
    url: String,
    dims: Vec<u32>,
}

/// NIP-96 server info from .well-known
#[derive(Debug, Deserialize)]
struct Nip96ServerInfo {
    api_url: String,
    #[serde(default)]
    supported_nips: Vec<u32>,
}

/// NIP-96 upload response
#[derive(Debug, Deserialize)]
struct Nip96UploadResponse {
    status: String,
    #[serde(default)]
    message: Option<String>,
    nip94_event: Option<Nip94Event>,
}

#[derive(Debug, Deserialize)]
struct Nip94Event {
    tags: Vec<Vec<String>>,
}

/// Search Tenor for GIFs
/// 
/// # Arguments
/// * `api_key` - Google Cloud API key with Tenor API enabled
/// * `query` - Search term
/// * `limit` - Maximum number of results (default 20)
/// 
/// # Returns
/// List of GIF results with URLs and dimensions
pub async fn search_gifs(
    api_key: &str,
    query: &str,
    limit: u32,
) -> Result<Vec<GifResult>, String> {
    let client = reqwest::Client::new();
    
    let url = format!(
        "https://tenor.googleapis.com/v2/search?q={}&key={}&client_key=PlebClient&limit={}&media_filter=gif,tinygif,mediumgif",
        urlencoding::encode(query),
        api_key,
        limit
    );
    
    tracing::debug!("Searching Tenor: {}", query);
    
    let response = client
        .get(&url)
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await
        .map_err(|e| format!("Tenor request failed: {}", e))?;
    
    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!("Tenor API error ({}): {}", status, body));
    }
    
    let data: TenorSearchResponse = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse Tenor response: {}", e))?;
    
    let results: Vec<GifResult> = data.results
        .into_iter()
        .filter_map(|r| {
            // Prefer mediumgif for posting, tinygif for preview
            let gif = r.media_formats.mediumgif.or(r.media_formats.gif)?;
            let preview = r.media_formats.tinygif.unwrap_or_else(|| gif.clone());
            
            Some(GifResult {
                url: gif.url,
                preview_url: preview.url,
                width: gif.dims.first().copied().unwrap_or(0),
                height: gif.dims.get(1).copied().unwrap_or(0),
                id: r.id,
            })
        })
        .collect();
    
    tracing::info!("Found {} GIFs for query: {}", results.len(), query);
    
    Ok(results)
}

/// Get trending GIFs from Tenor
pub async fn get_trending_gifs(
    api_key: &str,
    limit: u32,
) -> Result<Vec<GifResult>, String> {
    let client = reqwest::Client::new();
    
    let url = format!(
        "https://tenor.googleapis.com/v2/featured?key={}&client_key=PlebClient&limit={}&media_filter=gif,tinygif,mediumgif",
        api_key,
        limit
    );
    
    let response = client
        .get(&url)
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await
        .map_err(|e| format!("Tenor request failed: {}", e))?;
    
    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!("Tenor API error ({}): {}", status, body));
    }
    
    let data: TenorSearchResponse = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse Tenor response: {}", e))?;
    
    let results: Vec<GifResult> = data.results
        .into_iter()
        .filter_map(|r| {
            let gif = r.media_formats.mediumgif.or(r.media_formats.gif)?;
            let preview = r.media_formats.tinygif.unwrap_or_else(|| gif.clone());
            
            Some(GifResult {
                url: gif.url,
                preview_url: preview.url,
                width: gif.dims.first().copied().unwrap_or(0),
                height: gif.dims.get(1).copied().unwrap_or(0),
                id: r.id,
            })
        })
        .collect();
    
    Ok(results)
}

/// Download a GIF from Tenor and re-upload to a NIP-96 server
/// 
/// This is the privacy-preserving step: we download from Google's servers
/// and re-upload to a Nostr-friendly host, so Google never sees the post.
/// 
/// # Arguments
/// * `tenor_url` - URL of the GIF on Tenor's servers
/// * `nip96_server` - Base URL of the NIP-96 server (e.g., "https://nostr.build")
/// * `keys` - Nostr keys for signing the NIP-98 auth event
/// 
/// # Returns
/// The URL of the re-uploaded GIF on the NIP-96 server
pub async fn bridge_gif_to_nostr(
    tenor_url: &str,
    nip96_server: &str,
    keys: &Keys,
) -> Result<String, String> {
    let client = reqwest::Client::new();
    
    // Step 1: Download the GIF from Tenor
    tracing::info!("Downloading GIF from Tenor: {}", tenor_url);
    
    let gif_response = client
        .get(tenor_url)
        .timeout(std::time::Duration::from_secs(30))
        .send()
        .await
        .map_err(|e| format!("Failed to download GIF: {}", e))?;
    
    if !gif_response.status().is_success() {
        return Err(format!("Failed to download GIF: HTTP {}", gif_response.status()));
    }
    
    let gif_bytes = gif_response
        .bytes()
        .await
        .map_err(|e| format!("Failed to read GIF bytes: {}", e))?;
    
    tracing::info!("Downloaded {} bytes", gif_bytes.len());
    
    // Step 2: Discover the NIP-96 upload endpoint
    let well_known_url = format!("{}/.well-known/nostr/nip96.json", nip96_server.trim_end_matches('/'));
    
    let info_response = client
        .get(&well_known_url)
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await
        .map_err(|e| format!("Failed to fetch NIP-96 info: {}", e))?;
    
    if !info_response.status().is_success() {
        return Err(format!("NIP-96 server info not found: HTTP {}", info_response.status()));
    }
    
    let server_info: Nip96ServerInfo = info_response
        .json()
        .await
        .map_err(|e| format!("Failed to parse NIP-96 info: {}", e))?;
    
    let upload_url = server_info.api_url;
    tracing::info!("NIP-96 upload endpoint: {}", upload_url);
    
    // Step 3: Create NIP-98 authorization event
    let now = Timestamp::now();
    
    // Create the auth event (kind 27235)
    let auth_event = EventBuilder::new(
        Kind::Custom(27235),
        "", // Empty content for NIP-98
    )
    .tag(Tag::custom(TagKind::Custom("u".into()), vec![upload_url.clone()]))
    .tag(Tag::custom(TagKind::Custom("method".into()), vec!["POST".to_string()]))
    .sign_with_keys(keys)
    .map_err(|e| format!("Failed to sign auth event: {}", e))?;
    
    // Encode as base64 for Authorization header
    let auth_json = serde_json::to_string(&auth_event)
        .map_err(|e| format!("Failed to serialize auth event: {}", e))?;
    let auth_base64 = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, auth_json);
    
    // Step 4: Upload via multipart form
    let form = reqwest::multipart::Form::new()
        .part("file", reqwest::multipart::Part::bytes(gif_bytes.to_vec())
            .file_name("tenor.gif")
            .mime_str("image/gif")
            .map_err(|e| format!("Failed to create form part: {}", e))?
        );
    
    let mut headers = HeaderMap::new();
    headers.insert(
        AUTHORIZATION,
        HeaderValue::from_str(&format!("Nostr {}", auth_base64))
            .map_err(|e| format!("Invalid auth header: {}", e))?,
    );
    
    let upload_response = client
        .post(&upload_url)
        .headers(headers)
        .multipart(form)
        .timeout(std::time::Duration::from_secs(60))
        .send()
        .await
        .map_err(|e| format!("Upload failed: {}", e))?;
    
    let status = upload_response.status();
    let body = upload_response
        .text()
        .await
        .map_err(|e| format!("Failed to read upload response: {}", e))?;
    
    if !status.is_success() {
        return Err(format!("Upload failed ({}): {}", status, body));
    }
    
    // Parse NIP-96 response to get the URL
    let response: Nip96UploadResponse = serde_json::from_str(&body)
        .map_err(|e| format!("Failed to parse upload response: {} - Body: {}", e, body))?;
    
    if response.status != "success" {
        return Err(format!("Upload failed: {}", response.message.unwrap_or_default()));
    }
    
    // Extract URL from nip94_event tags
    let url = response.nip94_event
        .and_then(|evt| {
            evt.tags.iter()
                .find(|tag| tag.first().map(|s| s == "url").unwrap_or(false))
                .and_then(|tag| tag.get(1).cloned())
        })
        .ok_or_else(|| "No URL in upload response".to_string())?;
    
    tracing::info!("GIF re-uploaded successfully: {}", url);
    
    Ok(url)
}

/// Get the dimensions string for imeta tag
pub fn format_dimensions(width: u32, height: u32) -> String {
    format!("{}x{}", width, height)
}
