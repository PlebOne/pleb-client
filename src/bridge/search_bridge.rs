//! Search bridge - QML bridge for search functionality
//! Supports searching for notes, users, and hashtags with time range filtering

use cxx_qt::CxxQtType;
use cxx_qt_lib::QString;
use std::pin::Pin;

use nostr_sdk::{Filter, Kind, Timestamp};

#[cxx_qt::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, query)]
        #[qproperty(bool, is_searching)]
        #[qproperty(i32, user_count)]
        #[qproperty(i32, note_count)]
        #[qproperty(QString, search_type)]
        #[qproperty(i32, time_range_days)]
        type SearchController = super::SearchControllerRust;

        #[qinvokable]
        fn search_users(self: Pin<&mut SearchController>, query: &QString);

        #[qinvokable]
        fn search_notes(self: Pin<&mut SearchController>, query: &QString);

        #[qinvokable]
        fn search_notes_with_time(self: Pin<&mut SearchController>, query: &QString, days: i32);

        #[qinvokable]
        fn search_hashtag(self: Pin<&mut SearchController>, hashtag: &QString);

        #[qinvokable]
        fn search_hashtag_with_time(self: Pin<&mut SearchController>, hashtag: &QString, days: i32);

        #[qinvokable]
        fn set_time_range(self: Pin<&mut SearchController>, days: i32);

        #[qinvokable]
        fn get_user(self: &SearchController, index: i32) -> QString;

        #[qinvokable]
        fn get_note(self: &SearchController, index: i32) -> QString;

        #[qinvokable]
        fn clear_results(self: Pin<&mut SearchController>);
    }

    unsafe extern "RustQt" {
        #[qsignal]
        fn search_completed(self: Pin<&mut SearchController>);

        #[qsignal]
        fn error_occurred(self: Pin<&mut SearchController>, error: QString);
    }

    impl cxx_qt::Threading for SearchController {}
}

use cxx_qt::Threading;

// Use global relay manager and local runtime
lazy_static::lazy_static! {
    static ref SEARCH_RUNTIME: tokio::runtime::Runtime = tokio::runtime::Runtime::new().unwrap();
}

// Alias for cleaner code
use crate::nostr::relay::GLOBAL_RELAY_MANAGER as SEARCH_RELAY_MANAGER;
use crate::nostr::database::NostrDbManager;

/// Search result types
#[derive(Clone, Debug, Default)]
pub struct UserResult {
    pub pubkey: String,
    pub name: String,
    pub display_name: String,
    pub picture: String,
    pub nip05: String,
    pub about: String,
}

#[derive(Clone, Debug, Default)]
pub struct NoteResult {
    pub id: String,
    pub pubkey: String,
    pub author_name: String,
    pub author_picture: String,
    pub content: String,
    pub created_at: i64,
}

/// Rust struct for SearchController
pub struct SearchControllerRust {
    query: QString,
    is_searching: bool,
    user_count: i32,
    note_count: i32,
    search_type: QString,
    time_range_days: i32,
    
    user_results: Vec<UserResult>,
    note_results: Vec<NoteResult>,
}

impl Default for SearchControllerRust {
    fn default() -> Self {
        Self {
            query: QString::default(),
            is_searching: false,
            user_count: 0,
            note_count: 0,
            search_type: QString::from("notes"), // Default to notes search
            time_range_days: 7, // Default to 7 days
            user_results: Vec::new(),
            note_results: Vec::new(),
        }
    }
}

/// Check if text contains all search words (fuzzy word matching)
fn fuzzy_match(text: &str, search_words: &[String]) -> bool {
    let text_lower = text.to_lowercase();
    // All search words must be found in the text
    search_words.iter().all(|word| text_lower.contains(word))
}

/// Calculate timestamp for N days ago
fn days_ago(days: i32) -> Timestamp {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let seconds_ago = (days as u64) * 24 * 60 * 60;
    Timestamp::from(now.saturating_sub(seconds_ago))
}

impl ffi::SearchController {
    pub fn search_users(mut self: Pin<&mut Self>, query: &QString) {
        let query_str = query.to_string();
        println!("[Search] search_users called with query: '{}'", query_str);
        if query_str.trim().is_empty() {
            println!("[Search] Empty query, returning");
            return;
        }
        
        {
            let mut rust = self.as_mut().rust_mut();
            rust.query = query.clone();
            rust.is_searching = true;
            rust.search_type = QString::from("users");
            rust.user_results.clear();
            rust.user_count = 0;
        }
        self.as_mut().set_is_searching(true);
        self.as_mut().set_user_count(0);
        self.as_mut().set_search_type(QString::from("users"));
        
        let query_lower = query_str.to_lowercase();
        let qt_thread = self.qt_thread();
        
        std::thread::spawn(move || {
            println!("[Search] Background thread started");
            let result: Result<Vec<UserResult>, String> = SEARCH_RUNTIME.block_on(async {
                let mut results = Vec::new();
                let mut seen_pubkeys = std::collections::HashSet::new();
                
                // First, search local database cache
                println!("[Search] Searching local cache...");
                if let Ok(db) = NostrDbManager::global() {
                    let cached_count = db.profile_count();
                    println!("[Search] Local cache has {} profiles", cached_count);
                    
                    let local_results = db.search_profiles(&query_lower);
                    println!("[Search] Found {} matches in local cache", local_results.len());
                    
                    for profile in local_results {
                        if seen_pubkeys.insert(profile.pubkey.clone()) {
                            results.push(UserResult {
                                pubkey: profile.pubkey,
                                name: profile.name.unwrap_or_default(),
                                display_name: profile.display_name.unwrap_or_default(),
                                picture: profile.picture.unwrap_or_default(),
                                nip05: profile.nip05.unwrap_or_default(),
                                about: profile.about.unwrap_or_default(),
                            });
                        }
                    }
                }
                
                // Then fetch from relays to find more
                let rm = SEARCH_RELAY_MANAGER.read().unwrap();
                if let Some(manager) = rm.as_ref() {
                    println!("[Search] Fetching from relays (limit 500)...");
                    
                    // Fetch more metadata events with a larger limit
                    let filter = Filter::new()
                        .kind(Kind::Metadata)
                        .limit(500);
                    
                    match manager.client().fetch_events(filter, std::time::Duration::from_secs(15)).await {
                        Ok(events) => {
                            println!("[Search] Fetched {} metadata events from relays", events.len());
                            let mut relay_matches = 0;
                            
                            for event in events {
                                // Store in local cache for future searches
                                if let Ok(db) = NostrDbManager::global() {
                                    let _ = db.ingest_profile(&event);
                                }
                                
                                if let Ok(metadata) = serde_json::from_str::<serde_json::Value>(&event.content) {
                                    let name = metadata.get("name").and_then(|n| n.as_str()).unwrap_or("");
                                    let display_name = metadata.get("display_name").and_then(|n| n.as_str()).unwrap_or("");
                                    let nip05 = metadata.get("nip05").and_then(|n| n.as_str()).unwrap_or("");
                                    
                                    let name_lower = name.to_lowercase();
                                    let display_lower = display_name.to_lowercase();
                                    let nip05_lower = nip05.to_lowercase();
                                    
                                    let pubkey = event.pubkey.to_hex();
                                    
                                    if (name_lower.contains(&query_lower) 
                                        || display_lower.contains(&query_lower)
                                        || nip05_lower.contains(&query_lower))
                                        && seen_pubkeys.insert(pubkey.clone())
                                    {
                                        relay_matches += 1;
                                        results.push(UserResult {
                                            pubkey,
                                            name: name.to_string(),
                                            display_name: display_name.to_string(),
                                            picture: metadata.get("picture").and_then(|p| p.as_str()).unwrap_or("").to_string(),
                                            nip05: nip05.to_string(),
                                            about: metadata.get("about").and_then(|a| a.as_str()).unwrap_or("").to_string(),
                                        });
                                    }
                                }
                            }
                            println!("[Search] Found {} new matches from relays", relay_matches);
                        }
                        Err(e) => {
                            println!("[Search] ERROR fetching events: {:?}", e);
                        }
                    }
                } else {
                    println!("[Search] WARNING: Relay manager not available");
                }
                
                println!("[Search] Total results: {}", results.len());
                Ok(results)
            });
            
            println!("[Search] Search result: {:?}", result.as_ref().map(|r| r.len()));
            let _ = qt_thread.queue(move |mut qobject| {
                println!("[Search] Qt thread callback EXECUTING");
                match result {
                    Ok(results) => {
                        let count = results.len() as i32;
                        println!("[Search] Setting user_count to {}", count);
                        {
                            let mut rust = qobject.as_mut().rust_mut();
                            rust.user_results = results;
                        }
                        // Set properties through the setter methods to trigger QML notifications
                        qobject.as_mut().set_user_count(count);
                        qobject.as_mut().set_is_searching(false);
                        println!("[Search] Emitting search_completed signal");
                        qobject.as_mut().search_completed();
                        println!("[Search] Qt thread callback DONE, user_count should be {}", count);
                    }
                    Err(e) => {
                        println!("[Search] Error in callback: {}", e);
                        qobject.as_mut().set_is_searching(false);
                        qobject.as_mut().error_occurred(QString::from(e.as_str()));
                    }
                }
            });
        });
    }
    
    pub fn search_notes(mut self: Pin<&mut Self>, query: &QString) {
        // Use the stored time range, defaulting to 7 days
        let days = {
            let rust = self.as_ref();
            if rust.time_range_days > 0 { rust.time_range_days } else { 7 }
        };
        self.search_notes_with_time(query, days);
    }
    
    pub fn search_notes_with_time(mut self: Pin<&mut Self>, query: &QString, days: i32) {
        let query_str = query.to_string();
        if query_str.trim().is_empty() {
            return;
        }
        
        {
            let mut rust = self.as_mut().rust_mut();
            rust.query = query.clone();
            rust.is_searching = true;
            rust.search_type = QString::from("notes");
            rust.note_results.clear();
            rust.note_count = 0;
            rust.time_range_days = days;
        }
        self.as_mut().set_is_searching(true);
        self.as_mut().set_note_count(0);
        self.as_mut().set_search_type(QString::from("notes"));
        self.as_mut().set_time_range_days(days);
        
        // Split query into words for fuzzy matching
        let search_words: Vec<String> = query_str
            .to_lowercase()
            .split_whitespace()
            .map(|s| s.to_string())
            .collect();
        
        let qt_thread = self.qt_thread();
        let since_timestamp = days_ago(days);
        
        println!("[Search] Searching notes with {} words, last {} days", search_words.len(), days);
        
        std::thread::spawn(move || {
            let result = SEARCH_RUNTIME.block_on(async {
                let rm = SEARCH_RELAY_MANAGER.read().unwrap();
                let Some(manager) = rm.as_ref() else {
                    return Err("Relay manager not initialized".to_string());
                };
                
                let mut results = Vec::new();
                
                // Fetch notes within time range
                let filter = Filter::new()
                    .kind(Kind::TextNote)
                    .since(since_timestamp)
                    .limit(1000);
                
                println!("[Search] Fetching notes since timestamp: {}", since_timestamp.as_secs());
                
                if let Ok(events) = manager.client().fetch_events(filter, std::time::Duration::from_secs(20)).await {
                    println!("[Search] Fetched {} notes, filtering with fuzzy match", events.len());
                    
                    // First pass: collect matching notes and their author pubkeys
                    let mut matching_events = Vec::new();
                    let mut author_pubkeys = std::collections::HashSet::new();
                    
                    for event in events {
                        // Fuzzy match: all search words must appear in the content
                        if fuzzy_match(&event.content, &search_words) {
                            author_pubkeys.insert(event.pubkey);
                            matching_events.push(event);
                            
                            if matching_events.len() >= 100 {
                                break;
                            }
                        }
                    }
                    
                    println!("[Search] Found {} matching notes from {} authors", matching_events.len(), author_pubkeys.len());
                    
                    // Fetch author profiles from relays
                    if !author_pubkeys.is_empty() {
                        let pubkeys: Vec<_> = author_pubkeys.into_iter().collect();
                        let profile_filter = Filter::new()
                            .kind(Kind::Metadata)
                            .authors(pubkeys)
                            .limit(200);
                        
                        println!("[Search] Fetching profiles for {} authors...", profile_filter.authors.as_ref().map(|a| a.len()).unwrap_or(0));
                        
                        if let Ok(profile_events) = manager.client().fetch_events(profile_filter, std::time::Duration::from_secs(10)).await {
                            println!("[Search] Fetched {} profile events", profile_events.len());
                            // Store profiles in local cache
                            for event in profile_events {
                                if let Ok(db) = NostrDbManager::global() {
                                    let _ = db.ingest_profile(&event);
                                }
                            }
                        }
                    }
                    
                    // Second pass: build results with resolved author info
                    for event in matching_events {
                        let mut author_name = String::new();
                        let mut author_picture = String::new();
                        
                        // Try to resolve author profile from cache (now populated)
                        if let Ok(db) = NostrDbManager::global() {
                            if let Some(profile) = db.get_profile(&event.pubkey.to_hex()) {
                                author_name = profile.display_name.or(profile.name).unwrap_or_default();
                                author_picture = profile.picture.unwrap_or_default();
                            }
                        }

                        results.push(NoteResult {
                            id: event.id.to_hex(),
                            pubkey: event.pubkey.to_hex(),
                            author_name,
                            author_picture,
                            content: event.content.clone(),
                            created_at: event.created_at.as_secs() as i64,
                        });
                    }
                    
                    println!("[Search] Built {} results with author info", results.len());
                }
                
                // Sort by created_at descending (newest first)
                results.sort_by(|a, b| b.created_at.cmp(&a.created_at));
                
                println!("[Search] Sorted {} results, returning from async block", results.len());
                Ok(results)
            });
            
            println!("[Search] Async block finished, queuing Qt callback");
            let _ = qt_thread.queue(move |mut qobject| {
                println!("[Search] Qt callback started for notes");
                match result {
                    Ok(results) => {
                        let count = results.len() as i32;
                        println!("[Search] Updating note count to {}", count);
                        {
                            let mut rust = qobject.as_mut().rust_mut();
                            rust.note_results = results;
                            rust.note_count = count;
                            rust.is_searching = false;
                        }
                        qobject.as_mut().set_note_count(count);
                        qobject.as_mut().set_is_searching(false);
                        qobject.as_mut().search_completed();
                        println!("[Search] Notes search completed signal emitted");
                    }
                    Err(e) => {
                        println!("[Search] Error in notes search: {}", e);
                        qobject.as_mut().rust_mut().is_searching = false;
                        qobject.as_mut().set_is_searching(false);
                        qobject.as_mut().error_occurred(QString::from(&e));
                    }
                }
            });
        });
    }
    
    pub fn search_hashtag(mut self: Pin<&mut Self>, hashtag: &QString) {
        // Use the stored time range, defaulting to 7 days
        let days = {
            let rust = self.as_ref();
            if rust.time_range_days > 0 { rust.time_range_days } else { 7 }
        };
        self.search_hashtag_with_time(hashtag, days);
    }
    
    pub fn search_hashtag_with_time(mut self: Pin<&mut Self>, hashtag: &QString, days: i32) {
        let hashtag_str = hashtag.to_string();
        let hashtag_clean = hashtag_str.trim_start_matches('#').to_lowercase();
        
        if hashtag_clean.is_empty() {
            return;
        }
        
        {
            let mut rust = self.as_mut().rust_mut();
            rust.query = QString::from(&format!("#{}", hashtag_clean));
            rust.is_searching = true;
            rust.search_type = QString::from("hashtags");
            rust.note_results.clear();
            rust.note_count = 0;
            rust.time_range_days = days;
        }
        self.as_mut().set_is_searching(true);
        self.as_mut().set_note_count(0);
        self.as_mut().set_search_type(QString::from("hashtags"));
        self.as_mut().set_time_range_days(days);
        
        let qt_thread = self.qt_thread();
        let since_timestamp = days_ago(days);
        
        println!("[Search] Searching hashtag #{} in last {} days", hashtag_clean, days);
        
        std::thread::spawn(move || {
            let result = SEARCH_RUNTIME.block_on(async {
                let rm = SEARCH_RELAY_MANAGER.read().unwrap();
                let Some(manager) = rm.as_ref() else {
                    return Err("Relay manager not initialized".to_string());
                };
                
                let mut results = Vec::new();
                
                // Search by hashtag tag with time filter
                let filter = Filter::new()
                    .kind(Kind::TextNote)
                    .hashtag(hashtag_clean.clone())
                    .since(since_timestamp)
                    .limit(200);
                
                if let Ok(events) = manager.client().fetch_events(filter, std::time::Duration::from_secs(20)).await {
                    println!("[Search] Found {} notes with #{}", events.len(), hashtag_clean);
                    
                    // Collect author pubkeys for profile fetching
                    let author_pubkeys: std::collections::HashSet<_> = events.iter()
                        .map(|e| e.pubkey)
                        .collect();
                    
                    // Fetch author profiles from relays
                    if !author_pubkeys.is_empty() {
                        let pubkeys: Vec<_> = author_pubkeys.into_iter().collect();
                        let profile_filter = Filter::new()
                            .kind(Kind::Metadata)
                            .authors(pubkeys)
                            .limit(200);
                        
                        println!("[Search] Fetching profiles for hashtag search authors...");
                        
                        if let Ok(profile_events) = manager.client().fetch_events(profile_filter, std::time::Duration::from_secs(10)).await {
                            println!("[Search] Fetched {} profile events", profile_events.len());
                            for event in profile_events {
                                if let Ok(db) = NostrDbManager::global() {
                                    let _ = db.ingest_profile(&event);
                                }
                            }
                        }
                    }
                    
                    // Build results with resolved author info
                    for event in events {
                        let mut author_name = String::new();
                        let mut author_picture = String::new();
                        
                        // Try to resolve author profile from cache (now populated)
                        if let Ok(db) = NostrDbManager::global() {
                            if let Some(profile) = db.get_profile(&event.pubkey.to_hex()) {
                                author_name = profile.display_name.or(profile.name).unwrap_or_default();
                                author_picture = profile.picture.unwrap_or_default();
                            }
                        }

                        results.push(NoteResult {
                            id: event.id.to_hex(),
                            pubkey: event.pubkey.to_hex(),
                            author_name,
                            author_picture,
                            content: event.content.clone(),
                            created_at: event.created_at.as_secs() as i64,
                        });
                    }
                }
                
                // Sort by created_at descending (newest first)
                results.sort_by(|a, b| b.created_at.cmp(&a.created_at));
                
                Ok(results)
            });
            
            let _ = qt_thread.queue(move |mut qobject| {
                match result {
                    Ok(results) => {
                        let count = results.len() as i32;
                        {
                            let mut rust = qobject.as_mut().rust_mut();
                            rust.note_results = results;
                            rust.note_count = count;
                            rust.is_searching = false;
                        }
                        qobject.as_mut().set_note_count(count);
                        qobject.as_mut().set_is_searching(false);
                        qobject.as_mut().search_completed();
                    }
                    Err(e) => {
                        qobject.as_mut().rust_mut().is_searching = false;
                        qobject.as_mut().set_is_searching(false);
                        qobject.as_mut().error_occurred(QString::from(&e));
                    }
                }
            });
        });
    }
    
    pub fn set_time_range(mut self: Pin<&mut Self>, days: i32) {
        self.as_mut().set_time_range_days(days);
    }
    
    pub fn get_user(&self, index: i32) -> QString {
        println!("[Search] get_user called for index {}", index);
        if index < 0 || index as usize >= self.user_results.len() {
            println!("[Search] get_user index out of bounds or results empty");
            return QString::from("{}");
        }
        
        let user = &self.user_results[index as usize];
        let json = serde_json::json!({
            "pubkey": user.pubkey,
            "name": user.name,
            "displayName": user.display_name,
            "picture": user.picture,
            "nip05": user.nip05,
            "about": user.about,
        });
        
        QString::from(&json.to_string())
    }
    
    pub fn get_note(&self, index: i32) -> QString {
        if index < 0 || index as usize >= self.note_results.len() {
            return QString::from("{}");
        }
        
        let note = &self.note_results[index as usize];
        let json = serde_json::json!({
            "id": note.id,
            "pubkey": note.pubkey,
            "authorName": note.author_name,
            "authorPicture": note.author_picture,
            "content": note.content,
            "createdAt": note.created_at,
        });
        
        QString::from(&json.to_string())
    }
    
    pub fn clear_results(mut self: Pin<&mut Self>) {
        {
            let mut rust = self.as_mut().rust_mut();
            rust.user_results.clear();
            rust.note_results.clear();
            rust.user_count = 0;
            rust.note_count = 0;
            rust.query = QString::default();
        }
        self.as_mut().set_user_count(0);
        self.as_mut().set_note_count(0);
        self.as_mut().set_query(QString::default());
    }
}
