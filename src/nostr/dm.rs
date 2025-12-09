//! Direct Message support for NIP-04 and NIP-17
//!
//! NIP-04: Legacy encrypted direct messages (kind 4)
//! NIP-17: Private Direct Messages with Gift Wrap (kind 1059)

#![allow(dead_code)]  // Planned infrastructure for future integration

use nostr_sdk::prelude::*;
use std::collections::HashMap;
use std::time::Duration;
use std::fs;
use std::path::PathBuf;

/// DM Protocol type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DmProtocol {
    /// Legacy NIP-04 encrypted DMs (kind 4)
    Nip04,
    /// Modern NIP-17 private DMs with gift wrap (kind 1059)
    Nip17,
}

impl Default for DmProtocol {
    fn default() -> Self {
        DmProtocol::Nip17
    }
}

/// Conversation category for organization
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ConversationCategory {
    /// Regular conversations (default)
    #[default]
    Regular,
    /// Favorited conversations
    Favorites,
    /// Archived conversations (out of mind)
    Archive,
    /// Unfiltered - never replied to
    Unfiltered,
}

impl ConversationCategory {
    pub fn as_str(&self) -> &'static str {
        match self {
            ConversationCategory::Regular => "regular",
            ConversationCategory::Favorites => "favorites",
            ConversationCategory::Archive => "archive",
            ConversationCategory::Unfiltered => "unfiltered",
        }
    }
    
    pub fn from_str(s: &str) -> Self {
        match s {
            "favorites" => ConversationCategory::Favorites,
            "archive" => ConversationCategory::Archive,
            "unfiltered" => ConversationCategory::Unfiltered,
            _ => ConversationCategory::Regular,
        }
    }
}

/// A conversation with another user
#[derive(Debug, Clone)]
pub struct DmConversation {
    pub peer_pubkey: String,
    pub peer_name: Option<String>,
    pub peer_picture: Option<String>,
    pub last_message: Option<String>,
    pub last_message_at: i64,
    pub unread_count: u32,
    pub protocol: DmProtocol,
    pub messages: Vec<DmMessage>,
    pub category: ConversationCategory,
    pub has_outgoing: bool,  // Track if we've ever replied
}

impl DmConversation {
    pub fn new(peer_pubkey: String, protocol: DmProtocol) -> Self {
        Self {
            peer_pubkey,
            peer_name: None,
            peer_picture: None,
            last_message: None,
            last_message_at: 0,
            unread_count: 0,
            protocol,
            messages: Vec::new(),
            category: ConversationCategory::Regular,
            has_outgoing: false,
        }
    }
    
    pub fn to_json(&self) -> String {
        // Determine effective category: if Regular and never replied, show as Unfiltered
        let effective_category = if self.category == ConversationCategory::Regular && !self.has_outgoing {
            ConversationCategory::Unfiltered
        } else {
            self.category
        };
        
        serde_json::json!({
            "peerPubkey": self.peer_pubkey,
            "peerName": self.peer_name,
            "peerPicture": self.peer_picture,
            "lastMessage": self.last_message,
            "lastMessageAt": self.last_message_at,
            "unreadCount": self.unread_count,
            "protocol": match self.protocol {
                DmProtocol::Nip04 => "NIP-04",
                DmProtocol::Nip17 => "NIP-17",
            },
            "category": effective_category.as_str(),
            "hasOutgoing": self.has_outgoing,
        }).to_string()
    }
}

/// A single direct message
#[derive(Debug, Clone)]
pub struct DmMessage {
    pub id: String,
    pub sender_pubkey: String,
    pub recipient_pubkey: String,
    pub content: String,
    pub created_at: i64,
    pub is_outgoing: bool,
    pub protocol: DmProtocol,
}

impl DmMessage {
    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "id": self.id,
            "senderPubkey": self.sender_pubkey,
            "content": self.content,
            "createdAt": self.created_at,
            "isOutgoing": self.is_outgoing,
        })
    }
}

/// DM Manager handles fetching and organizing direct messages
pub struct DmManager {
    user_pubkey: Option<PublicKey>,
    conversations: HashMap<String, DmConversation>,
    categories_file: Option<PathBuf>,
}

impl DmManager {
    pub fn new() -> Self {
        Self {
            user_pubkey: None,
            conversations: HashMap::new(),
            categories_file: None,
        }
    }
    
    pub fn set_user_pubkey(&mut self, pubkey: PublicKey) {
        self.user_pubkey = Some(pubkey);
        
        // Set up categories file path
        if let Some(config_dir) = dirs::config_dir() {
            let app_dir = config_dir.join("pleb-client");
            let _ = fs::create_dir_all(&app_dir);
            self.categories_file = Some(app_dir.join(format!("dm_categories_{}.json", pubkey.to_hex()[..16].to_string())));
            self.load_categories();
        }
    }
    
    /// Load categories from local storage
    fn load_categories(&mut self) {
        if let Some(ref path) = self.categories_file {
            if let Ok(content) = fs::read_to_string(path) {
                if let Ok(categories) = serde_json::from_str::<HashMap<String, String>>(&content) {
                    let count = categories.len();
                    for (pubkey, cat_str) in categories {
                        if let Some(convo) = self.conversations.get_mut(&pubkey) {
                            convo.category = ConversationCategory::from_str(&cat_str);
                        }
                    }
                    tracing::info!("Loaded {} DM categories from storage", count);
                }
            }
        }
    }
    
    /// Save categories to local storage
    fn save_categories(&self) {
        if let Some(ref path) = self.categories_file {
            let categories: HashMap<String, String> = self.conversations
                .iter()
                .filter(|(_, c)| c.category != ConversationCategory::Regular)
                .map(|(k, c)| (k.clone(), c.category.as_str().to_string()))
                .collect();
            
            if let Ok(json) = serde_json::to_string_pretty(&categories) {
                if let Err(e) = fs::write(path, json) {
                    tracing::error!("Failed to save DM categories: {}", e);
                }
            }
        }
    }
    
    /// Apply loaded categories to conversations
    pub fn apply_saved_categories(&mut self) {
        if let Some(ref path) = self.categories_file {
            if let Ok(content) = fs::read_to_string(path) {
                if let Ok(categories) = serde_json::from_str::<HashMap<String, String>>(&content) {
                    for (pubkey, cat_str) in categories {
                        if let Some(convo) = self.conversations.get_mut(&pubkey) {
                            convo.category = ConversationCategory::from_str(&cat_str);
                        }
                    }
                }
            }
        }
    }
    
    /// Get all conversations sorted by last message time
    pub fn get_conversations(&self) -> Vec<&DmConversation> {
        let mut convos: Vec<&DmConversation> = self.conversations.values().collect();
        convos.sort_by(|a, b| b.last_message_at.cmp(&a.last_message_at));
        convos
    }
    
    /// Get conversations filtered by category
    pub fn get_conversations_by_category(&self, category: Option<ConversationCategory>) -> Vec<&DmConversation> {
        let mut convos: Vec<&DmConversation> = self.conversations.values()
            .filter(|c| {
                match category {
                    // Inbox tab - only show conversations we've communicated with, not in other categories
                    None => c.has_outgoing && c.category == ConversationCategory::Regular,
                    Some(ConversationCategory::Favorites) => c.category == ConversationCategory::Favorites,
                    Some(ConversationCategory::Archive) => c.category == ConversationCategory::Archive,
                    Some(ConversationCategory::Unfiltered) => {
                        // Show conversations with no outgoing messages OR explicitly marked unfiltered
                        (!c.has_outgoing && c.category == ConversationCategory::Regular) || 
                        c.category == ConversationCategory::Unfiltered
                    },
                    Some(ConversationCategory::Regular) => {
                        // Same as Inbox - for direct filter usage
                        c.has_outgoing && c.category == ConversationCategory::Regular
                    },
                }
            })
            .collect();
        convos.sort_by(|a, b| b.last_message_at.cmp(&a.last_message_at));
        convos
    }
    
    /// Get counts for each category
    pub fn get_category_counts(&self) -> (i32, i32, i32, i32, i32) {
        let mut inbox = 0i32;  // Conversations we've communicated with, not in other categories
        let mut favorites = 0i32;
        let mut unfiltered = 0i32;
        let mut regular = 0i32;
        let mut archive = 0i32;
        
        for c in self.conversations.values() {
            match c.category {
                ConversationCategory::Favorites => favorites += 1,
                ConversationCategory::Archive => archive += 1,
                ConversationCategory::Unfiltered => unfiltered += 1,
                ConversationCategory::Regular => {
                    if !c.has_outgoing {
                        // Never communicated with - goes to Unfiltered
                        unfiltered += 1;
                    } else {
                        // Communicated with, not categorized - goes to Inbox
                        inbox += 1;
                        regular += 1;
                    }
                }
            }
        }
        
        // inbox count is used for the "Inbox" tab (replaces old "all" count)
        (inbox, favorites, unfiltered, regular, archive)
    }
    
    /// Set category for a conversation
    pub fn set_category(&mut self, peer_pubkey: &str, category: ConversationCategory) {
        if let Some(convo) = self.conversations.get_mut(peer_pubkey) {
            convo.category = category;
            self.save_categories();
            tracing::info!("Set category for {} to {:?}", &peer_pubkey[..16], category);
        }
    }
    
    /// Get a specific conversation
    pub fn get_conversation(&self, peer_pubkey: &str) -> Option<&DmConversation> {
        self.conversations.get(peer_pubkey)
    }
    
    /// Get or create a conversation
    pub fn get_or_create_conversation(&mut self, peer_pubkey: String, protocol: DmProtocol) -> &mut DmConversation {
        self.conversations.entry(peer_pubkey.clone())
            .or_insert_with(|| DmConversation::new(peer_pubkey, protocol))
    }
    
    /// Add a message to a conversation
    pub fn add_message(&mut self, msg: DmMessage) {
        let peer_pubkey = if msg.is_outgoing {
            msg.recipient_pubkey.clone()
        } else {
            msg.sender_pubkey.clone()
        };
        
        let convo = self.get_or_create_conversation(peer_pubkey, msg.protocol);
        
        // Track if we have outgoing messages
        if msg.is_outgoing {
            convo.has_outgoing = true;
        }
        
        // Update conversation metadata
        if msg.created_at > convo.last_message_at {
            convo.last_message = Some(truncate_message(&msg.content, 50));
            convo.last_message_at = msg.created_at;
        }
        
        // Add message if not already present
        if !convo.messages.iter().any(|m| m.id == msg.id) {
            convo.messages.push(msg);
            // Sort messages by time
            convo.messages.sort_by(|a, b| a.created_at.cmp(&b.created_at));
        }
    }
    
    /// Update profile info for a conversation
    pub fn update_peer_profile(&mut self, peer_pubkey: &str, name: Option<String>, picture: Option<String>) {
        if let Some(convo) = self.conversations.get_mut(peer_pubkey) {
            convo.peer_name = name;
            convo.peer_picture = picture;
        }
    }
    
    /// Get total unread count
    pub fn total_unread(&self) -> u32 {
        self.conversations.values().map(|c| c.unread_count).sum()
    }
    
    /// Mark conversation as read
    pub fn mark_read(&mut self, peer_pubkey: &str) {
        if let Some(convo) = self.conversations.get_mut(peer_pubkey) {
            convo.unread_count = 0;
        }
    }
    
    /// Clear all data
    pub fn clear(&mut self) {
        self.conversations.clear();
        self.user_pubkey = None;
    }
}

/// Fetch NIP-04 DMs from relays
pub async fn fetch_nip04_dms(
    client: &Client,
    user_pubkey: &PublicKey,
    limit: usize,
) -> Result<Events, String> {
    // Fetch DMs sent TO us (we are in the p tag)
    let incoming_filter = Filter::new()
        .kind(Kind::EncryptedDirectMessage)
        .pubkey(*user_pubkey)
        .limit(limit);
    
    // Fetch DMs sent BY us
    let outgoing_filter = Filter::new()
        .kind(Kind::EncryptedDirectMessage)
        .author(*user_pubkey)
        .limit(limit);
    
    // Reduced timeout for faster initial load
    let timeout = Duration::from_secs(8);
    
    let (incoming, outgoing) = tokio::join!(
        client.fetch_events(incoming_filter, timeout),
        client.fetch_events(outgoing_filter, timeout)
    );
    
    let mut combined = Events::default();
    
    if let Ok(events) = incoming {
        for event in events.into_iter() {
            combined.insert(event);
        }
    }
    
    if let Ok(events) = outgoing {
        for event in events.into_iter() {
            combined.insert(event);
        }
    }
    
    tracing::info!("Fetched {} NIP-04 DM events", combined.len());
    Ok(combined)
}

/// Fetch NIP-17 gift-wrapped DMs from relays
pub async fn fetch_nip17_dms(
    client: &Client,
    user_pubkey: &PublicKey,
    limit: usize,
) -> Result<Events, String> {
    // NIP-17 uses gift wrap (kind 1059) addressed to us
    let filter = Filter::new()
        .kind(Kind::GiftWrap)
        .pubkey(*user_pubkey)
        .limit(limit);
    
    let timeout = Duration::from_secs(15);
    
    client
        .fetch_events(filter, timeout)
        .await
        .map_err(|e| format!("Failed to fetch NIP-17 DMs: {}", e))
}

/// Extract peer pubkey from a NIP-04 DM event
pub fn get_nip04_peer(event: &Event, user_pubkey: &PublicKey) -> Option<PublicKey> {
    if event.pubkey == *user_pubkey {
        // Outgoing message - peer is in the p tag
        for tag in event.tags.iter() {
            if let Some(TagStandard::PublicKey { public_key, .. }) = tag.as_standardized() {
                return Some(public_key.clone());
            }
        }
    } else {
        // Incoming message - peer is the author
        return Some(event.pubkey);
    }
    None
}

/// Create a NIP-04 DM event (unsigned)
pub fn create_nip04_dm_event(
    recipient_pubkey: &PublicKey,
    encrypted_content: &str,
) -> UnsignedEvent {
    let tags = vec![Tag::public_key(*recipient_pubkey)];
    
    EventBuilder::new(Kind::EncryptedDirectMessage, encrypted_content)
        .tags(tags)
        .build(PublicKey::from_slice(&[0; 32]).unwrap()) // Placeholder, will be signed
}

/// Create a NIP-17 gift-wrapped DM
/// This is more complex and involves:
/// 1. Create a kind 14 rumor (unsigned DM)
/// 2. Seal it with kind 13 (encrypted to recipient)
/// 3. Gift wrap it with kind 1059
pub fn create_nip17_rumor(
    recipient_pubkey: &PublicKey,
    content: &str,
) -> UnsignedEvent {
    // Kind 14 = chat message (NIP-17)
    let tags = vec![Tag::public_key(*recipient_pubkey)];
    
    EventBuilder::new(Kind::Custom(14), content)
        .tags(tags)
        .build(PublicKey::from_slice(&[0; 32]).unwrap())
}

/// Helper to truncate message for preview
fn truncate_message(content: &str, max_len: usize) -> String {
    if content.len() <= max_len {
        content.to_string()
    } else {
        format!("{}...", &content[..max_len])
    }
}

/// Format a hex pubkey as npub for display
pub fn format_pubkey_short(pubkey: &str) -> String {
    if let Ok(pk) = PublicKey::parse(pubkey) {
        // to_bech32() is infallible for PublicKey
        let npub = pk.to_bech32().expect("bech32 encoding");
        return format!("{}...{}", &npub[..12], &npub[npub.len()-6..]);
    }
    format!("{}...{}", &pubkey[..8], &pubkey[pubkey.len()-6..])
}
