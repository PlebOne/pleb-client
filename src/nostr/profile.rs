//! Profile cache - stores and retrieves user profile metadata

use nostr_sdk::prelude::*;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Cached profile data
#[derive(Debug, Clone, Default)]
pub struct ProfileCache {
    pub name: Option<String>,
    pub display_name: Option<String>,
    pub picture: Option<String>,
    pub banner: Option<String>,
    pub about: Option<String>,
    pub website: Option<String>,
    pub nip05: Option<String>,
    pub lud16: Option<String>,  // Lightning address
    pub lud06: Option<String>,  // LNURL
    pub cached_at: i64,
}

impl ProfileCache {
    /// Create from nostr Metadata
    pub fn from_metadata(metadata: &Metadata) -> Self {
        Self {
            name: metadata.name.clone(),
            display_name: metadata.display_name.clone(),
            picture: metadata.picture.clone(),
            banner: metadata.banner.clone(),
            about: metadata.about.clone(),
            website: metadata.website.clone(),
            nip05: metadata.nip05.clone(),
            lud16: metadata.lud16.clone(),
            lud06: metadata.lud06.clone(),
            cached_at: chrono::Utc::now().timestamp(),
        }
    }
    
    /// Create from a Kind::Metadata event
    pub fn from_event(event: &Event) -> Result<Self, String> {
        if event.kind != Kind::Metadata {
            return Err("Event is not a metadata event".to_string());
        }
        
        let metadata: Metadata = serde_json::from_str(&event.content)
            .map_err(|e| format!("Failed to parse metadata: {}", e))?;
        
        Ok(Self::from_metadata(&metadata))
    }
    
    /// Get best display name (display_name > name > default)
    pub fn get_display_name(&self, default: &str) -> String {
        self.display_name
            .clone()
            .or_else(|| self.name.clone())
            .unwrap_or_else(|| default.to_string())
    }
    
    /// Check if cache is stale (older than 24 hours)
    pub fn is_stale(&self) -> bool {
        let now = chrono::Utc::now().timestamp();
        now - self.cached_at > 24 * 60 * 60
    }
    
    /// Serialize to JSON
    pub fn to_json(&self) -> String {
        serde_json::json!({
            "name": self.name,
            "displayName": self.display_name,
            "picture": self.picture,
            "banner": self.banner,
            "about": self.about,
            "website": self.website,
            "nip05": self.nip05,
            "lud16": self.lud16,
            "cachedAt": self.cached_at,
        }).to_string()
    }
}

/// Global profile cache manager
pub struct ProfileCacheManager {
    profiles: HashMap<String, ProfileCache>,
    /// Pending profile fetches to batch
    pending_fetches: Vec<String>,
}

impl ProfileCacheManager {
    pub fn new() -> Self {
        Self {
            profiles: HashMap::new(),
            pending_fetches: Vec::new(),
        }
    }
    
    /// Get a cached profile
    pub fn get(&self, pubkey_hex: &str) -> Option<&ProfileCache> {
        self.profiles.get(pubkey_hex)
    }
    
    /// Insert or update a profile
    pub fn insert(&mut self, pubkey_hex: String, profile: ProfileCache) {
        self.profiles.insert(pubkey_hex, profile);
    }
    
    /// Check if profile exists and is not stale
    pub fn has_fresh(&self, pubkey_hex: &str) -> bool {
        self.profiles
            .get(pubkey_hex)
            .map(|p| !p.is_stale())
            .unwrap_or(false)
    }
    
    /// Queue a pubkey for batch fetching
    pub fn queue_fetch(&mut self, pubkey_hex: String) {
        if !self.has_fresh(&pubkey_hex) && !self.pending_fetches.contains(&pubkey_hex) {
            self.pending_fetches.push(pubkey_hex);
        }
    }
    
    /// Get and clear pending fetches
    pub fn take_pending(&mut self) -> Vec<String> {
        std::mem::take(&mut self.pending_fetches)
    }
    
    /// Get all cached profiles count
    pub fn len(&self) -> usize {
        self.profiles.len()
    }
    
    /// Clean up stale profiles
    pub fn cleanup_stale(&mut self) -> usize {
        let before = self.profiles.len();
        self.profiles.retain(|_, p| !p.is_stale());
        before - self.profiles.len()
    }
}

/// Thread-safe profile cache
pub type SharedProfileCache = Arc<RwLock<ProfileCacheManager>>;

/// Create a shared profile cache
pub fn create_shared_profile_cache() -> SharedProfileCache {
    Arc::new(RwLock::new(ProfileCacheManager::new()))
}
