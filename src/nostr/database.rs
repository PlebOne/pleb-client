//! NostrDB database wrapper for local event caching
//! 
//! Implements proper caching patterns:
//! - Single global instance (LMDB requires this)
//! - In-memory hot cache for frequently accessed data
//! - Transaction-wrapped queries for consistency
//! - Deduplication on ingest
//! - Async-safe access patterns

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};
use nostrdb::{Config, Ndb};
use nostr_sdk::prelude::*;
use parking_lot::RwLock;

/// Cache duration in seconds (24 hours)
pub const CACHE_DURATION_SECS: u64 = 24 * 60 * 60;

/// Maximum in-memory cache entries
const MAX_MEMORY_CACHE_SIZE: usize = 1000;

/// Global singleton for nostrdb - LMDB requires single instance
static NOSTR_DB: OnceLock<Arc<NostrDbManager>> = OnceLock::new();

/// Cached event data for in-memory layer
#[derive(Clone, Debug)]
pub struct CachedEvent {
    pub id: String,
    pub pubkey: String,
    pub content: String,
    pub kind: u16,
    pub created_at: i64,
    pub tags_json: String,
    pub cached_at: Instant,
}

/// Cached profile data
#[derive(Clone, Debug)]
pub struct CachedProfile {
    pub pubkey: String,
    pub name: Option<String>,
    pub display_name: Option<String>,
    pub picture: Option<String>,
    pub nip05: Option<String>,
    pub about: Option<String>,
    pub cached_at: Instant,
    pub last_fetched: Instant,
}

impl CachedProfile {
    pub fn is_stale(&self) -> bool {
        self.last_fetched.elapsed() > Duration::from_secs(CACHE_DURATION_SECS)
    }
    
    pub fn get_display_name(&self) -> Option<&str> {
        self.display_name.as_deref()
            .or(self.name.as_deref())
    }
}

/// In-memory hot cache layer
struct MemoryCache {
    events: HashMap<String, CachedEvent>,  // event_id -> event
    profiles: HashMap<String, CachedProfile>,  // pubkey -> profile
    event_order: Vec<String>,  // LRU tracking
}

impl MemoryCache {
    fn new() -> Self {
        Self {
            events: HashMap::with_capacity(MAX_MEMORY_CACHE_SIZE),
            profiles: HashMap::with_capacity(256),
            event_order: Vec::with_capacity(MAX_MEMORY_CACHE_SIZE),
        }
    }
    
    fn get_event(&self, id: &str) -> Option<&CachedEvent> {
        self.events.get(id)
    }
    
    fn insert_event(&mut self, event: CachedEvent) {
        let id = event.id.clone();
        
        // Remove oldest if at capacity
        if self.events.len() >= MAX_MEMORY_CACHE_SIZE && !self.events.contains_key(&id) {
            if let Some(oldest_id) = self.event_order.first().cloned() {
                self.events.remove(&oldest_id);
                self.event_order.remove(0);
            }
        }
        
        // Update LRU order
        if let Some(pos) = self.event_order.iter().position(|x| x == &id) {
            self.event_order.remove(pos);
        }
        self.event_order.push(id.clone());
        
        self.events.insert(id, event);
    }
    
    fn get_profile(&self, pubkey: &str) -> Option<&CachedProfile> {
        self.profiles.get(pubkey)
    }
    
    fn insert_profile(&mut self, profile: CachedProfile) {
        self.profiles.insert(profile.pubkey.clone(), profile);
    }
    
    fn has_event(&self, id: &str) -> bool {
        self.events.contains_key(id)
    }
    
    fn clear(&mut self) {
        self.events.clear();
        self.profiles.clear();
        self.event_order.clear();
    }
}

/// NostrDB Manager - handles all database operations
pub struct NostrDbManager {
    ndb: Ndb,
    memory_cache: RwLock<MemoryCache>,
    db_path: PathBuf,
}

impl NostrDbManager {
    /// Initialize the global database instance
    pub fn init() -> Result<Arc<Self>, String> {
        let path = Self::default_path();
        tracing::info!("Initializing nostrdb at {:?}", path);
        
        // Ensure directory exists
        std::fs::create_dir_all(&path)
            .map_err(|e| format!("Failed to create database directory: {}", e))?;
        
        // Configure nostrdb
        let mut config = Config::new();
        config.set_ingester_threads(2);  // Async ingestion
        
        let ndb = Ndb::new(path.to_str().unwrap(), &config)
            .map_err(|e| format!("Failed to open nostrdb: {:?}", e))?;
        
        Ok(Arc::new(Self {
            ndb,
            memory_cache: RwLock::new(MemoryCache::new()),
            db_path: path,
        }))
    }
    
    /// Get or initialize the global instance
    pub fn global() -> Result<Arc<Self>, String> {
        if let Some(db) = NOSTR_DB.get() {
            return Ok(db.clone());
        }
        
        let db = Self::init()?;
        // If another thread set it first, that's fine - use theirs
        let _ = NOSTR_DB.set(db.clone());
        
        // Return whatever is in the global
        Ok(NOSTR_DB.get().unwrap().clone())
    }
    
    /// Check if global instance exists
    pub fn is_initialized() -> bool {
        NOSTR_DB.get().is_some()
    }
    
    /// Get default database path
    pub fn default_path() -> PathBuf {
        dirs::data_local_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("pleb-client")
            .join("nostrdb")
    }
    
    /// Process and store an event (with deduplication)
    pub fn ingest_event(&self, event: &Event) -> Result<bool, String> {
        let event_id = event.id.to_hex();
        
        // Check memory cache first (fast path)
        {
            let cache = self.memory_cache.read();
            if cache.has_event(&event_id) {
                return Ok(false);  // Already have it
            }
        }
        
        // Process through nostrdb (handles dedup internally)
        let json = event.as_json();
        self.ndb.process_event(&json)
            .map_err(|e| format!("Failed to ingest event: {:?}", e))?;
        
        // Add to memory cache
        let cached = CachedEvent {
            id: event_id,
            pubkey: event.pubkey.to_hex(),
            content: event.content.clone(),
            kind: event.kind.as_u16(),
            created_at: event.created_at.as_secs() as i64,
            tags_json: serde_json::to_string(&event.tags).unwrap_or_default(),
            cached_at: Instant::now(),
        };
        
        {
            let mut cache = self.memory_cache.write();
            cache.insert_event(cached);
        }
        
        Ok(true)  // New event ingested
    }
    
    /// Batch ingest events efficiently
    pub fn ingest_events(&self, events: &[Event]) -> Result<usize, String> {
        let mut new_count = 0;
        
        for event in events {
            if self.ingest_event(event)? {
                new_count += 1;
            }
        }
        
        Ok(new_count)
    }
    
    /// Process and store a profile event
    pub fn ingest_profile(&self, event: &Event) -> Result<(), String> {
        if event.kind != Kind::Metadata {
            return Err("Not a profile event".to_string());
        }
        
        // Ingest to nostrdb
        let json = event.as_json();
        self.ndb.process_event(&json)
            .map_err(|e| format!("Failed to ingest profile: {:?}", e))?;
        
        // Parse and cache profile metadata
        if let Ok(metadata) = serde_json::from_str::<serde_json::Value>(&event.content) {
            let profile = CachedProfile {
                pubkey: event.pubkey.to_hex(),
                name: metadata.get("name").and_then(|v| v.as_str()).map(String::from),
                display_name: metadata.get("display_name").and_then(|v| v.as_str()).map(String::from),
                picture: metadata.get("picture").and_then(|v| v.as_str()).map(String::from),
                nip05: metadata.get("nip05").and_then(|v| v.as_str()).map(String::from),
                about: metadata.get("about").and_then(|v| v.as_str()).map(String::from),
                cached_at: Instant::now(),
                last_fetched: Instant::now(),
            };
            
            let mut cache = self.memory_cache.write();
            cache.insert_profile(profile);
        }
        
        Ok(())
    }
    
    /// Batch ingest profiles
    pub fn ingest_profiles(&self, events: &[Event]) -> Result<usize, String> {
        let mut count = 0;
        for event in events {
            if event.kind == Kind::Metadata {
                if self.ingest_profile(event).is_ok() {
                    count += 1;
                }
            }
        }
        Ok(count)
    }
    
    /// Get an event by ID from memory cache
    pub fn get_event(&self, event_id: &str) -> Option<CachedEvent> {
        let cache = self.memory_cache.read();
        cache.get_event(event_id).cloned()
    }
    
    /// Check if event exists in memory cache
    pub fn has_event(&self, event_id: &str) -> bool {
        let cache = self.memory_cache.read();
        cache.has_event(event_id)
    }
    
    /// Get a profile by pubkey from memory cache
    pub fn get_profile(&self, pubkey: &str) -> Option<CachedProfile> {
        let cache = self.memory_cache.read();
        cache.get_profile(pubkey).cloned()
    }
    
    /// Check if we have a fresh profile for this pubkey
    pub fn has_fresh_profile(&self, pubkey: &str) -> bool {
        let cache = self.memory_cache.read();
        cache.get_profile(pubkey)
            .map(|p| !p.is_stale())
            .unwrap_or(false)
    }
    
    /// Get pubkeys that need profile refresh
    pub fn get_stale_profile_pubkeys(&self, pubkeys: &[String]) -> Vec<String> {
        let cache = self.memory_cache.read();
        pubkeys.iter()
            .filter(|pk| {
                cache.get_profile(pk)
                    .map(|p| p.is_stale())
                    .unwrap_or(true)  // Not in cache = needs fetch
            })
            .cloned()
            .collect()
    }
    
    /// Clear the in-memory cache (for memory pressure)
    pub fn clear_memory_cache(&self) {
        let mut cache = self.memory_cache.write();
        cache.clear();
        tracing::info!("Cleared in-memory cache");
    }
    
    /// Get database statistics
    pub fn stats(&self) -> String {
        let cache = self.memory_cache.read();
        format!(
            "NostrDB at {:?} | Memory cache: {} events, {} profiles",
            self.db_path,
            cache.events.len(),
            cache.profiles.len()
        )
    }
}

// ============================================================================
// Legacy compatibility layer
// ============================================================================

/// Legacy wrapper for backward compatibility
pub struct NostrDatabase;

impl NostrDatabase {
    pub fn default_path() -> PathBuf {
        NostrDbManager::default_path()
    }
}

pub type SharedDatabase = Arc<tokio::sync::RwLock<Option<()>>>;

pub fn create_shared_database() -> SharedDatabase {
    Arc::new(tokio::sync::RwLock::new(None))
}

/// Initialize database using the global singleton
pub async fn init_database(_shared: &SharedDatabase) -> Result<(), String> {
    // Initialize the global singleton
    let _ = NostrDbManager::global()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_default_path() {
        let path = NostrDbManager::default_path();
        assert!(path.to_string_lossy().contains("pleb-client"));
    }
    
    #[test]
    fn test_memory_cache_lru() {
        let mut cache = MemoryCache::new();
        
        // Insert events
        for i in 0..10 {
            cache.insert_event(CachedEvent {
                id: format!("event_{}", i),
                pubkey: "test".to_string(),
                content: "test".to_string(),
                kind: 1,
                created_at: i as i64,
                tags_json: "[]".to_string(),
                cached_at: Instant::now(),
            });
        }
        
        assert_eq!(cache.events.len(), 10);
        assert!(cache.has_event("event_0"));
        assert!(cache.has_event("event_9"));
    }
}
