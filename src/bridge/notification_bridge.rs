//! Notification bridge - exposes notifications to QML

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(i32, notification_count)]
        #[qproperty(i32, unread_count)]
        #[qproperty(bool, is_loading)]
        #[qproperty(QString, error_message)]
        type NotificationController = super::NotificationControllerRust;

        /// Initialize with user's pubkey
        #[qinvokable]
        fn initialize(self: Pin<&mut NotificationController>, user_pubkey: &QString);

        /// Load notifications
        #[qinvokable]
        fn load_notifications(self: Pin<&mut NotificationController>);
        
        /// Refresh (load new notifications)
        #[qinvokable]
        fn refresh(self: Pin<&mut NotificationController>);
        
        /// Load more (pagination)
        #[qinvokable]
        fn load_more(self: Pin<&mut NotificationController>);
        
        /// Get notification at index (returns JSON)
        #[qinvokable]
        fn get_notification(self: &NotificationController, index: i32) -> QString;
        
        /// Mark notification as read
        #[qinvokable]
        fn mark_as_read(self: Pin<&mut NotificationController>, notification_id: &QString);
        
        /// Mark all as read
        #[qinvokable]
        fn mark_all_read(self: Pin<&mut NotificationController>);
        
        /// Check for new notifications since the most recent one
        /// This is a lightweight poll that prepends new notifications without clearing existing ones
        #[qinvokable]
        fn check_for_new(self: Pin<&mut NotificationController>);
    }

    unsafe extern "RustQt" {
        /// Emitted when notifications are updated
        #[qsignal]
        fn notifications_updated(self: Pin<&mut NotificationController>);
        
        /// Emitted when loading more completes
        #[qsignal]
        fn more_loaded(self: Pin<&mut NotificationController>, count: i32);
        
        /// Emitted when an error occurs
        #[qsignal]
        fn error_occurred(self: Pin<&mut NotificationController>, error: &QString);
        
        /// Emitted when new notifications are found during check_for_new
        #[qsignal]
        fn new_notifications_found(self: Pin<&mut NotificationController>, count: i32);
    }
    
    // Enable threading support for background work with UI updates
    impl cxx_qt::Threading for NotificationController {}
}

use std::pin::Pin;
use cxx_qt_lib::QString;
use cxx_qt::{CxxQtType, Threading};
use nostr_sdk::prelude::*;
use crate::nostr::profile::ProfileCache;
use crate::bridge::feed_bridge::create_authenticated_relay_manager;
use std::collections::HashMap;

// Global tokio runtime for notification operations
lazy_static::lazy_static! {
    static ref NOTIFICATION_RUNTIME: tokio::runtime::Runtime = tokio::runtime::Runtime::new().unwrap();
}

/// Notification types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NotificationType {
    Mention,
    Reply,
    Reaction,
    Zap,
    Repost,
}

impl NotificationType {
    pub fn as_str(&self) -> &'static str {
        match self {
            NotificationType::Mention => "mention",
            NotificationType::Reply => "reply",
            NotificationType::Reaction => "reaction",
            NotificationType::Zap => "zap",
            NotificationType::Repost => "repost",
        }
    }
    
    pub fn icon(&self) -> &'static str {
        match self {
            NotificationType::Mention => "@",
            NotificationType::Reply => "💬",
            NotificationType::Reaction => "❤️",
            NotificationType::Zap => "⚡",
            NotificationType::Repost => "🔁",
        }
    }
}

/// A notification ready for display
#[derive(Debug, Clone)]
pub struct DisplayNotification {
    pub id: String,
    pub notification_type: NotificationType,
    pub author_pubkey: String,
    pub author_name: String,
    pub author_picture: Option<String>,
    pub content_preview: String,
    pub referenced_event_id: Option<String>,
    pub created_at: i64,
    pub is_read: bool,
    pub reaction_content: Option<String>,
    pub zap_amount: Option<u64>,
}

impl DisplayNotification {
    /// Create from a nostr-sdk Event
    pub fn from_event(event: &Event, profile: Option<&ProfileCache>, _user_pubkey: &PublicKey) -> Self {
        let id = event.id.to_hex();
        let created_at = event.created_at.as_secs() as i64;
        
        // Determine notification type based on event kind
        let notification_type = match event.kind {
            Kind::TextNote => {
                if has_event_tag(event) {
                    NotificationType::Reply
                } else {
                    NotificationType::Mention
                }
            }
            Kind::Reaction => NotificationType::Reaction,
            Kind::ZapReceipt => NotificationType::Zap,
            Kind::Repost => NotificationType::Repost,
            _ => NotificationType::Mention,
        };
        
        // For zaps, get the actual sender from the description tag (zap request)
        // For other notifications, use event.pubkey
        let author_pubkey = if notification_type == NotificationType::Zap {
            extract_zap_sender(event).unwrap_or_else(|| event.pubkey.to_hex())
        } else {
            event.pubkey.to_hex()
        };
        
        // Get referenced event ID from tags
        let referenced_event_id = get_referenced_event_id(event);
        
        tracing::debug!(
            "Creating notification: id={}, type={:?}, referenced_event_id={:?}, tags_count={}",
            id, notification_type, referenced_event_id, event.tags.len()
        );
        
        // Get content preview
        let content_preview = match notification_type {
            NotificationType::Reaction => {
                if event.content.is_empty() {
                    "liked your note".to_string()
                } else {
                    format!("reacted {} to your note", event.content)
                }
            }
            NotificationType::Zap => {
                let amount = extract_zap_amount(event);
                format!("zapped {} sats", amount.unwrap_or(0))
            }
            NotificationType::Repost => "reposted your note".to_string(),
            NotificationType::Reply => {
                let preview = truncate_content(&event.content, 100);
                format!("replied: {}", preview)
            }
            NotificationType::Mention => {
                let preview = truncate_content(&event.content, 100);
                format!("mentioned you: {}", preview)
            }
        };
        
        // Get author info from profile cache
        let (author_name, author_picture) = profile
            .map(|p| (
                p.name.clone().unwrap_or_else(|| format_npub(&author_pubkey)),
                p.picture.clone(),
            ))
            .unwrap_or_else(|| (format_npub(&author_pubkey), None));
        
        // Extract reaction content and zap amount
        let reaction_content = if notification_type == NotificationType::Reaction {
            Some(if event.content.is_empty() { "❤️".to_string() } else { event.content.clone() })
        } else {
            None
        };
        
        let zap_amount = if notification_type == NotificationType::Zap {
            extract_zap_amount(event)
        } else {
            None
        };
        
        Self {
            id,
            notification_type,
            author_pubkey,
            author_name,
            author_picture,
            content_preview,
            referenced_event_id,
            created_at,
            is_read: false,
            reaction_content,
            zap_amount,
        }
    }
    
    /// Serialize to JSON for QML consumption
    pub fn to_json(&self) -> String {
        serde_json::json!({
            "id": self.id,
            "type": self.notification_type.as_str(),
            "typeIcon": self.notification_type.icon(),
            "authorPubkey": self.author_pubkey,
            "authorName": self.author_name,
            "authorPicture": self.author_picture,
            "contentPreview": self.content_preview,
            "referencedEventId": self.referenced_event_id,
            "createdAt": self.created_at,
            "isRead": self.is_read,
            "reactionContent": self.reaction_content,
            "zapAmount": self.zap_amount,
        }).to_string()
    }
}

/// Helper to check if event has an 'e' tag (is a reply)
fn has_event_tag(event: &Event) -> bool {
    event.tags.iter().any(|tag| {
        tag.kind() == TagKind::SingleLetter(SingleLetterTag::lowercase(Alphabet::E))
    })
}

/// Helper to get the referenced event ID from tags
fn get_referenced_event_id(event: &Event) -> Option<String> {
    for tag in event.tags.iter() {
        if let Some(TagStandard::Event { event_id, .. }) = tag.as_standardized() {
            return Some(event_id.to_hex());
        }
    }
    None
}

/// Helper to extract zap sender pubkey from a zap receipt's description tag
/// The description tag contains the original zap request, which has the sender's pubkey
fn extract_zap_sender(event: &Event) -> Option<String> {
    for tag in event.tags.iter() {
        if tag.kind() == TagKind::Description {
            if let Some(desc) = tag.content() {
                if let Ok(request) = serde_json::from_str::<serde_json::Value>(desc) {
                    // The zap request has the sender's pubkey in the "pubkey" field
                    if let Some(pubkey) = request.get("pubkey").and_then(|p| p.as_str()) {
                        return Some(pubkey.to_string());
                    }
                }
            }
        }
    }
    None
}

/// Helper to extract zap amount from a zap receipt
fn extract_zap_amount(event: &Event) -> Option<u64> {
    // Zap amount is in the bolt11 invoice in the 'bolt11' tag
    for tag in event.tags.iter() {
        if let Some(TagStandard::Bolt11(bolt11)) = tag.as_standardized() {
            if let Some(amount) = parse_bolt11_amount(&bolt11) {
                return Some(amount);
            }
        }
    }
    // Fallback: try description tag
    for tag in event.tags.iter() {
        if tag.kind() == TagKind::Description {
            if let Some(desc) = tag.content() {
                if let Ok(request) = serde_json::from_str::<serde_json::Value>(desc) {
                    if let Some(tags) = request.get("tags").and_then(|t| t.as_array()) {
                        for t in tags {
                            if let Some(arr) = t.as_array() {
                                if arr.first().and_then(|v| v.as_str()) == Some("amount") {
                                    if let Some(amt_str) = arr.get(1).and_then(|v| v.as_str()) {
                                        if let Ok(msats) = amt_str.parse::<u64>() {
                                            return Some(msats / 1000);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    None
}

/// Simple bolt11 amount parser (returns sats)
fn parse_bolt11_amount(bolt11: &str) -> Option<u64> {
    let lower = bolt11.to_lowercase();
    
    let amount_start = if lower.starts_with("lnbc") {
        4
    } else if lower.starts_with("lntb") || lower.starts_with("lnbcrt") {
        if lower.starts_with("lnbcrt") { 6 } else { 4 }
    } else {
        return None;
    };
    
    let rest = &lower[amount_start..];
    
    let mut num_str = String::new();
    let mut multiplier_char = None;
    
    for c in rest.chars() {
        if c.is_ascii_digit() {
            num_str.push(c);
        } else {
            multiplier_char = Some(c);
            break;
        }
    }
    
    if num_str.is_empty() {
        return None;
    }
    
    let base: u64 = num_str.parse().ok()?;
    
    let sats = match multiplier_char {
        Some('m') => base * 100_000,
        Some('u') => base * 100,
        Some('n') => base / 10,
        Some('p') => base / 10_000,
        _ => base,
    };
    
    Some(sats)
}

/// Truncate content for preview
fn truncate_content(content: &str, max_len: usize) -> String {
    if content.len() <= max_len {
        content.to_string()
    } else {
        format!("{}...", &content[..max_len])
    }
}

/// Format pubkey as npub for display
fn format_npub(pubkey: &str) -> String {
    if pubkey.len() > 16 {
        format!("{}...{}", &pubkey[..8], &pubkey[pubkey.len()-8..])
    } else {
        pubkey.to_string()
    }
}

/// Rust implementation of NotificationController
pub struct NotificationControllerRust {
    notification_count: i32,
    unread_count: i32,
    is_loading: bool,
    error_message: QString,
    
    // Internal state
    notifications: Vec<DisplayNotification>,
    user_pubkey: Option<PublicKey>,
    profiles: HashMap<String, ProfileCache>,
    oldest_timestamp: Option<Timestamp>,
    newest_timestamp: Option<i64>,  // Track newest notification for check_for_new
    is_checking: bool,  // Separate flag for check_for_new to not block UI
}

impl Default for NotificationControllerRust {
    fn default() -> Self {
        Self {
            notification_count: 0,
            unread_count: 0,
            is_loading: false,
            error_message: QString::from(""),
            notifications: Vec::new(),
            user_pubkey: None,
            profiles: HashMap::new(),
            oldest_timestamp: None,
            newest_timestamp: None,
            is_checking: false,
        }
    }
}

impl qobject::NotificationController {
    /// Initialize with user's pubkey
    pub fn initialize(mut self: Pin<&mut Self>, user_pubkey: &QString) {
        let pubkey_str = user_pubkey.to_string();
        tracing::info!("Initializing NotificationController for: {}", pubkey_str);
        
        // Parse pubkey
        let pubkey = if pubkey_str.starts_with("npub") {
            PublicKey::from_bech32(&pubkey_str).ok()
        } else {
            PublicKey::from_hex(&pubkey_str).ok()
        };
        
        {
            let mut rust = self.as_mut().rust_mut();
            rust.user_pubkey = pubkey;
        }
        
        // Auto-load notifications after init
        self.load_notifications();
    }
    
    /// Load notifications (non-blocking with proper Qt threading)
    pub fn load_notifications(mut self: Pin<&mut Self>) {
        let user_pubkey = {
            let rust = self.as_ref();
            rust.user_pubkey.clone()
        };
        
        let Some(pubkey) = user_pubkey else {
            tracing::warn!("Cannot load notifications: user pubkey not set");
            return;
        };
        
        self.as_mut().set_is_loading(true);
        
        // Get qt_thread handle for UI updates
        let qt_thread = self.qt_thread();
        
        // Spawn background thread - does NOT block the main thread
        std::thread::spawn(move || {
            let result = NOTIFICATION_RUNTIME.block_on(async {
                // Create a temporary relay manager for fetching
                let mut manager = create_authenticated_relay_manager();
                manager.connect().await?;
                
                let events = manager.fetch_notifications(&pubkey, 100, None).await?;
                
                // Collect unique pubkeys for profile fetching
                let pubkeys: Vec<PublicKey> = events
                    .iter()
                    .map(|e| e.pubkey)
                    .collect::<std::collections::HashSet<_>>()
                    .into_iter()
                    .collect();
                
                // Fetch profiles
                let profile_events = manager.fetch_profiles(&pubkeys).await.unwrap_or_default();
                
                let mut profiles = HashMap::new();
                for event in profile_events.iter() {
                    if let Ok(profile) = ProfileCache::from_event(event) {
                        profiles.insert(event.pubkey.to_hex(), profile);
                    }
                }
                
                // Convert events to display notifications
                let mut notifications: Vec<DisplayNotification> = events
                    .iter()
                    .map(|e| {
                        let profile = profiles.get(&e.pubkey.to_hex());
                        DisplayNotification::from_event(e, profile, &pubkey)
                    })
                    .collect();
                
                // Sort by timestamp (newest first)
                notifications.sort_by(|a, b| b.created_at.cmp(&a.created_at));
                
                // Get oldest timestamp for pagination and newest for check_for_new
                let oldest = notifications.last().map(|n| Timestamp::from(n.created_at as u64));
                let newest = notifications.first().map(|n| n.created_at);
                
                Ok::<_, String>((notifications, profiles, oldest, newest))
            });
            
            // Queue UI update back to Qt thread
            match result {
                Ok((notifications, profiles, oldest, newest)) => {
                    let count = notifications.len() as i32;
                    let unread = notifications.iter().filter(|n| !n.is_read).count() as i32;
                    let _ = qt_thread.queue(move |mut qobject| {
                        {
                            let mut rust = qobject.as_mut().rust_mut();
                            rust.notifications = notifications;
                            rust.profiles = profiles;
                            rust.oldest_timestamp = oldest;
                            rust.newest_timestamp = newest;
                            rust.notification_count = count;
                            rust.unread_count = unread;
                        }
                        qobject.as_mut().set_notification_count(count);
                        qobject.as_mut().set_unread_count(unread);
                        qobject.as_mut().set_is_loading(false);
                        qobject.as_mut().set_error_message(QString::from(""));
                        qobject.as_mut().notifications_updated();
                        tracing::info!("Loaded {} notifications ({} unread)", count, unread);
                    });
                }
                Err(e) => {
                    let error_msg = e.clone();
                    let _ = qt_thread.queue(move |mut qobject| {
                        tracing::error!("Failed to load notifications: {}", error_msg);
                        qobject.as_mut().set_is_loading(false);
                        qobject.as_mut().set_error_message(QString::from(&error_msg));
                        qobject.as_mut().error_occurred(&QString::from(&error_msg));
                    });
                }
            }
        });
    }
    
    /// Refresh (reload notifications)
    pub fn refresh(self: Pin<&mut Self>) {
        self.load_notifications();
    }
    
    /// Load more (pagination)
    pub fn load_more(mut self: Pin<&mut Self>) {
        let (user_pubkey, oldest, existing_profiles) = {
            let rust = self.as_ref();
            (rust.user_pubkey.clone(), rust.oldest_timestamp, rust.profiles.clone())
        };
        
        let Some(pubkey) = user_pubkey else {
            return;
        };
        
        let Some(until_ts) = oldest else {
            return;
        };
        
        self.as_mut().set_is_loading(true);
        
        let qt_thread = self.qt_thread();
        
        std::thread::spawn(move || {
            let result = NOTIFICATION_RUNTIME.block_on(async {
                let mut manager = create_authenticated_relay_manager();
                manager.connect().await?;
                
                let events = manager.fetch_notifications(&pubkey, 50, Some(until_ts)).await?;
                
                // Fetch any new profiles
                let pubkeys: Vec<PublicKey> = events
                    .iter()
                    .filter(|e| !existing_profiles.contains_key(&e.pubkey.to_hex()))
                    .map(|e| e.pubkey)
                    .collect::<std::collections::HashSet<_>>()
                    .into_iter()
                    .collect();
                
                let mut profiles = existing_profiles;
                if !pubkeys.is_empty() {
                    let profile_events = manager.fetch_profiles(&pubkeys).await.unwrap_or_default();
                    for event in profile_events.iter() {
                        if let Ok(profile) = ProfileCache::from_event(event) {
                            profiles.insert(event.pubkey.to_hex(), profile);
                        }
                    }
                }
                
                let mut notifications: Vec<DisplayNotification> = events
                    .iter()
                    .map(|e| {
                        let profile = profiles.get(&e.pubkey.to_hex());
                        DisplayNotification::from_event(e, profile, &pubkey)
                    })
                    .collect();
                
                notifications.sort_by(|a, b| b.created_at.cmp(&a.created_at));
                let oldest = notifications.last().map(|n| Timestamp::from(n.created_at as u64));
                
                Ok::<_, String>((notifications, profiles, oldest))
            });
            
            let _ = qt_thread.queue(move |mut qobject| {
                match result {
                    Ok((mut new_notifications, profiles, oldest)) => {
                        let new_count = new_notifications.len() as i32;
                        let new_unread = new_notifications.iter().filter(|n| !n.is_read).count() as i32;
                        let (total, unread) = {
                            let mut rust = qobject.as_mut().rust_mut();
                            rust.notifications.append(&mut new_notifications);
                            rust.profiles = profiles;
                            if oldest.is_some() {
                                rust.oldest_timestamp = oldest;
                            }
                            rust.notification_count = rust.notifications.len() as i32;
                            rust.unread_count += new_unread;
                            (rust.notification_count, rust.unread_count)
                        };
                        qobject.as_mut().set_notification_count(total);
                        qobject.as_mut().set_unread_count(unread);
                        qobject.as_mut().set_is_loading(false);
                        qobject.as_mut().more_loaded(new_count);
                    }
                    Err(e) => {
                        tracing::error!("Failed to load more notifications: {}", e);
                        qobject.as_mut().set_is_loading(false);
                        qobject.as_mut().error_occurred(&QString::from(&e));
                    }
                }
            });
        });
    }
    
    /// Get notification at index
    pub fn get_notification(&self, index: i32) -> QString {
        if let Some(notification) = self.notifications.get(index as usize) {
            QString::from(&notification.to_json())
        } else {
            QString::from("{}")
        }
    }
    
    /// Mark notification as read
    pub fn mark_as_read(mut self: Pin<&mut Self>, notification_id: &QString) {
        let id = notification_id.to_string();
        let unread = {
            let mut rust = self.as_mut().rust_mut();
            if let Some(n) = rust.notifications.iter_mut().find(|n| n.id == id) {
                if !n.is_read {
                    n.is_read = true;
                    rust.unread_count = rust.unread_count.saturating_sub(1);
                }
            }
            rust.unread_count
        };
        self.as_mut().set_unread_count(unread);
    }
    
    /// Mark all as read
    pub fn mark_all_read(mut self: Pin<&mut Self>) {
        {
            let mut rust = self.as_mut().rust_mut();
            for n in rust.notifications.iter_mut() {
                n.is_read = true;
            }
            rust.unread_count = 0;
        }
        self.as_mut().set_unread_count(0);
        // Signal UI to refresh so isRead changes are reflected
        self.as_mut().notifications_updated();
    }
    
    /// Check for new notifications since the most recent one
    /// This is a lightweight poll that prepends new notifications without clearing existing ones
    pub fn check_for_new(mut self: Pin<&mut Self>) {
        let (user_pubkey, newest_timestamp, is_checking, existing_profiles) = {
            let rust = self.as_ref();
            (
                rust.user_pubkey.clone(),
                rust.newest_timestamp,
                rust.is_checking,
                rust.profiles.clone(),
            )
        };
        
        // Don't check if already checking or loading
        if is_checking {
            tracing::debug!("check_for_new: already checking, skipping");
            return;
        }
        
        let Some(pubkey) = user_pubkey else {
            tracing::warn!("check_for_new: user pubkey not set");
            return;
        };
        
        // If no notifications yet, do a full load instead
        let Some(newest_ts) = newest_timestamp else {
            tracing::info!("check_for_new: no existing notifications, doing full load");
            return;
        };
        
        tracing::debug!("check_for_new: checking for notifications newer than {}", newest_ts);
        
        // Mark as checking (don't set is_loading to avoid UI flicker)
        {
            let mut rust = self.as_mut().rust_mut();
            rust.is_checking = true;
        }
        
        let qt_thread = self.qt_thread();
        
        std::thread::spawn(move || {
            let result = NOTIFICATION_RUNTIME.block_on(async {
                let mut manager = create_authenticated_relay_manager();
                manager.connect().await?;
                
                // Fetch recent notifications - use 'since' to only get newer ones
                let since_ts = Timestamp::from((newest_ts + 1) as u64);
                
                // Build filters for each notification type with 'since'
                let mention_filter = Filter::new()
                    .kind(Kind::TextNote)
                    .pubkey(pubkey)
                    .since(since_ts)
                    .limit(50);
                
                let reaction_filter = Filter::new()
                    .kind(Kind::Reaction)
                    .pubkey(pubkey)
                    .since(since_ts)
                    .limit(50);
                
                let zap_filter = Filter::new()
                    .kind(Kind::ZapReceipt)
                    .pubkey(pubkey)
                    .since(since_ts)
                    .limit(50);
                
                let repost_filter = Filter::new()
                    .kind(Kind::Repost)
                    .pubkey(pubkey)
                    .since(since_ts)
                    .limit(50);
                
                // Fetch all in parallel
                let timeout = std::time::Duration::from_secs(10);
                let (mentions, reactions, zaps, reposts) = tokio::join!(
                    manager.client().fetch_events(mention_filter, timeout),
                    manager.client().fetch_events(reaction_filter, timeout),
                    manager.client().fetch_events(zap_filter, timeout),
                    manager.client().fetch_events(repost_filter, timeout)
                );
                
                let mut combined = Events::default();
                
                for events_result in [mentions, reactions, zaps, reposts] {
                    if let Ok(events) = events_result {
                        for event in events.into_iter() {
                            // Skip events from the user themselves
                            if event.pubkey != pubkey {
                                combined.insert(event);
                            }
                        }
                    }
                }
                
                if combined.is_empty() {
                    return Ok::<_, String>((vec![], HashMap::new()));
                }
                
                tracing::debug!("check_for_new: found {} new notification events", combined.len());
                
                // Fetch profiles for new authors we don't have
                let new_pubkeys: Vec<PublicKey> = combined
                    .iter()
                    .filter(|e| !existing_profiles.contains_key(&e.pubkey.to_hex()))
                    .map(|e| e.pubkey)
                    .collect::<std::collections::HashSet<_>>()
                    .into_iter()
                    .collect();
                
                let mut profiles = existing_profiles;
                if !new_pubkeys.is_empty() {
                    let profile_events = manager.fetch_profiles(&new_pubkeys).await.unwrap_or_default();
                    for event in profile_events.iter() {
                        if let Ok(profile) = ProfileCache::from_event(event) {
                            profiles.insert(event.pubkey.to_hex(), profile);
                        }
                    }
                }
                
                // Convert to display notifications
                let mut notifications: Vec<DisplayNotification> = combined
                    .iter()
                    .map(|e| {
                        let profile = profiles.get(&e.pubkey.to_hex());
                        DisplayNotification::from_event(e, profile, &pubkey)
                    })
                    .collect();
                
                // Sort by timestamp (newest first)
                notifications.sort_by(|a, b| b.created_at.cmp(&a.created_at));
                
                Ok((notifications, profiles))
            });
            
            let _ = qt_thread.queue(move |mut qobject| {
                // Reset checking flag
                {
                    let mut rust = qobject.as_mut().rust_mut();
                    rust.is_checking = false;
                }
                
                match result {
                    Ok((new_notifications, profiles)) => {
                        if new_notifications.is_empty() {
                            tracing::debug!("check_for_new: no new notifications");
                            qobject.as_mut().new_notifications_found(0);
                            return;
                        }
                        
                        let new_count = new_notifications.len() as i32;
                        let _new_unread = new_notifications.iter().filter(|n| !n.is_read).count() as i32;
                        
                        // Get the newest timestamp from new notifications
                        let new_newest = new_notifications.first().map(|n| n.created_at);
                        
                        // Prepend new notifications to existing ones
                        let (total, unread) = {
                            let mut rust = qobject.as_mut().rust_mut();
                            
                            // Deduplicate: filter out any notifications that already exist
                            let existing_ids: std::collections::HashSet<_> = rust.notifications.iter().map(|n| n.id.clone()).collect();
                            let truly_new: Vec<_> = new_notifications.into_iter()
                                .filter(|n| !existing_ids.contains(&n.id))
                                .collect();
                            
                            if truly_new.is_empty() {
                                return;
                            }
                            
                            let truly_new_count = truly_new.len();
                            let truly_new_unread = truly_new.iter().filter(|n| !n.is_read).count();
                            
                            // Prepend new notifications
                            let mut combined = truly_new;
                            combined.append(&mut rust.notifications);
                            rust.notifications = combined;
                            
                            // Update profiles
                            rust.profiles = profiles;
                            
                            // Update newest timestamp
                            if let Some(newest) = new_newest {
                                if rust.newest_timestamp.map_or(true, |old| newest > old) {
                                    rust.newest_timestamp = Some(newest);
                                }
                            }
                            
                            rust.notification_count = rust.notifications.len() as i32;
                            rust.unread_count += truly_new_unread as i32;
                            
                            tracing::info!("check_for_new: added {} new notifications ({} unread)", truly_new_count, truly_new_unread);
                            
                            (rust.notification_count, rust.unread_count)
                        };
                        
                        qobject.as_mut().set_notification_count(total);
                        qobject.as_mut().set_unread_count(unread);
                        qobject.as_mut().new_notifications_found(new_count);
                        qobject.as_mut().notifications_updated();
                    }
                    Err(e) => {
                        tracing::error!("check_for_new failed: {}", e);
                        // Don't show error to user for background check
                    }
                }
            });
        });
    }
}
