//! Signer module - D-Bus client for Pleb Signer and local signer service
//!
//! This module provides:
//! 1. A client to communicate with an external Pleb Signer instance
//! 2. An integrated signer that can act as a signer for other Nostr apps

pub mod client;
pub mod service;

pub use client::SignerClient;
