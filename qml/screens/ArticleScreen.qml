import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    color: "#0a0a0a"
    focus: true
    
    property var feedController: null
    property var appController: null
    property string noteId: ""
    
    signal backClicked()
    signal openProfile(string pubkey)
    
    property var articleData: null
    
    onNoteIdChanged: {
        if (noteId && feedController) {
            // We need a way to get a specific note by ID, or we assume it's in the current feed list
            // For now, let's assume the controller can fetch it or we pass the data.
            // But the standard pattern here is to load it.
            // Since we don't have a "get_note_by_id" exposed yet, we might need to rely on it being in the feed.
            // However, for a robust solution, we should probably fetch it.
            // For this iteration, let's assume we can find it in the feed or we'll implement a fetch.
            
            // Actually, let's just try to find it in the current feed model for now.
            // If not found, we might need to fetch.
            // But wait, `feedController.get_note(index)` uses index.
            // We need `feedController.get_note_by_id(id)`.
            // I'll add `get_note_by_id` to the Rust bridge later.
            
            // For now, let's just show a loading state or placeholder until we implement the backend fetch.
            loadArticle()
        }
    }
    
    function loadArticle() {
        if (!feedController) return
        
        // This is a placeholder. We need to implement `get_note_by_id` in Rust.
        // For now, we can iterate the current feed to find it if possible.
        var count = feedController.note_count
        for (var i = 0; i < count; i++) {
            var json = feedController.get_note(i)
            var note = JSON.parse(json)
            if (note.id === noteId) {
                articleData = note
                return
            }
        }
        
        // If not found in current feed (e.g. deep link), we need to fetch it.
        // We'll implement `load_thread` equivalent for articles or just `fetch_note`.
        // For now, let's just show what we have.
    }
    
    Keys.onEscapePressed: root.backClicked()
    
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        
        // Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: "#111111"
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 12
                
                Button {
                    text: "← Back"
                    onClicked: root.backClicked()
                    background: Rectangle { color: "transparent" }
                    contentItem: Text { text: parent.text; color: "white"; font.pixelSize: 16 }
                }
                
                Item { Layout.fillWidth: true }
            }
        }
        
        // Content
        ScrollView {
            id: scrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            
            Flickable {
                id: flickable
                contentWidth: parent.width
                contentHeight: contentColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                
                ColumnLayout {
                    id: contentColumn
                    width: flickable.width
                    spacing: 24
                    
                    Item { height: 20; Layout.fillWidth: true }
                    
                    // Centered content container
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.min(scrollView.width - 80, 800)
                        Layout.leftMargin: 40
                        Layout.rightMargin: 40
                        spacing: 24
                
                        // Cover Image
                        Image {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 400
                            source: (articleData && articleData.image) || ""
                            fillMode: Image.PreserveAspectCrop
                            visible: source != ""
                        }
                
                        // Title
                        Text {
                            Layout.fillWidth: true
                            text: (articleData && articleData.title) || ""
                            color: "#ffffff"
                            font.pixelSize: 32
                            font.weight: Font.Bold
                            wrapMode: Text.Wrap
                        }
                
                        // Author
                        RowLayout {
                            spacing: 12
                            visible: articleData !== null
                            
                            ProfileAvatar {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                imageUrl: (articleData && articleData.authorPicture) || ""
                                name: (articleData && articleData.authorName) || ""
                            }
                            
                            Column {
                                Text {
                                    text: (articleData && articleData.authorName) || ""
                                    color: "#ffffff"
                                    font.weight: Font.Bold
                                    font.pixelSize: 16
                                }
                                Text {
                                    text: articleData ? new Date((articleData.publishedAt || articleData.createdAt) * 1000).toLocaleDateString() : ""
                                    color: "#888888"
                                    font.pixelSize: 14
                                }
                            }
                        }
                
                        // Separator
                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: "#333333"
                        }
                        
                        // Body content - rendered with images and formatted text
                        ColumnLayout {
                            id: bodyContent
                            Layout.fillWidth: true
                            spacing: 16
                            
                            Repeater {
                                model: parseContent(articleData ? articleData.content : "")
                                
                                delegate: Loader {
                                    id: contentLoader
                                    Layout.fillWidth: true
                                    
                                    property var contentData: modelData
                                    
                                    sourceComponent: {
                                        if (modelData.type === "image") return imageComponent
                                        if (modelData.type === "nostr_note") return embeddedNoteComponent
                                        if (modelData.type === "nostr_profile") return embeddedProfileComponent
                                        return textComponent
                                    }
                                    
                                    onLoaded: {
                                        if (item) {
                                            item.contentData = Qt.binding(function() { return contentLoader.contentData })
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Separator before zap
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 20
                            height: 1
                            color: "#333333"
                        }
                        
                        // Zap Section
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            spacing: 16
                            
                            Text {
                                text: "Enjoyed this article?"
                                color: "#888888"
                                font.pixelSize: 16
                                Layout.alignment: Qt.AlignHCenter
                            }
                            
                            Button {
                                id: zapButton
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 200
                                Layout.preferredHeight: 50
                                
                                background: Rectangle {
                                    radius: 25
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: zapButton.pressed ? "#7c22c9" : "#9333ea" }
                                        GradientStop { position: 1.0; color: zapButton.pressed ? "#6b21a8" : "#7c3aed" }
                                    }
                                }
                                
                                contentItem: RowLayout {
                                    spacing: 8
                                    
                                    Text {
                                        text: "⚡"
                                        font.pixelSize: 20
                                    }
                                    
                                    Text {
                                        text: "Zap the Author"
                                        color: "white"
                                        font.pixelSize: 16
                                        font.weight: Font.Medium
                                    }
                                }
                                
                                onClicked: {
                                    if (articleData) {
                                        zapDialog.noteId = noteId
                                        zapDialog.authorName = articleData.authorName || ""
                                        zapDialog.open()
                                    }
                                }
                            }
                        }
                        
                        Item { height: 60; Layout.fillWidth: true }
                    }
                    
                    Item { height: 40; Layout.fillWidth: true }
                }
            }
        }
    }
    
    // Text content component
    Component {
        id: textComponent
        
        Text {
            property var contentData: null
            
            width: parent ? parent.width : 0
            text: contentData ? formatText(contentData.content) : ""
            color: "#dddddd"
            font.pixelSize: 18
            lineHeight: 1.6
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            
            onLinkActivated: function(link) {
                if (link.startsWith("nostr:")) {
                    // Handle nostr links - for now open in external handler
                    Qt.openUrlExternally(link)
                } else {
                    Qt.openUrlExternally(link)
                }
            }
        }
    }
    
    // Image component
    Component {
        id: imageComponent
        
        Rectangle {
            property var contentData: null
            
            width: parent ? parent.width : 0
            height: img.status === Image.Ready ? 
                Math.min(width * (img.implicitHeight / img.implicitWidth), 500) : 300
            color: "#1a1a1a"
            radius: 8
            clip: true
            
            Image {
                id: img
                anchors.fill: parent
                source: contentData ? contentData.url : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                
                BusyIndicator {
                    anchors.centerIn: parent
                    running: parent.status === Image.Loading
                    visible: running
                }
                
                Rectangle {
                    anchors.fill: parent
                    color: "#1a1a1a"
                    visible: parent.status === Image.Error
                    
                    Text {
                        anchors.centerIn: parent
                        text: "🖼️ Image failed to load"
                        color: "#666666"
                        font.pixelSize: 14
                    }
                }
            }
            
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: contentData ? Qt.openUrlExternally(contentData.url) : null
            }
        }
    }
    
    // Embedded note component
    Component {
        id: embeddedNoteComponent
        
        EmbeddedNote {
            property var contentData: null
            
            width: parent ? parent.width : 0
            nostrUri: contentData ? contentData.uri : ""
            feedController: root.feedController
        }
    }
    
    // Embedded profile component
    Component {
        id: embeddedProfileComponent
        
        EmbeddedProfile {
            property var contentData: null
            
            width: parent ? parent.width : 0
            nostrUri: contentData ? contentData.uri : ""
            feedController: root.feedController
            onClicked: function(pubkey) {
                root.openProfile(pubkey)
            }
        }
    }
    
    // Parse content into segments (text, images, nostr URIs)
    function parseContent(text) {
        if (!text) return []
        
        var segments = []
        var remaining = text
        
        // Pattern to match images (markdown and raw URLs)
        var imagePattern = /!\[([^\]]*)\]\(([^)]+)\)|https?:\/\/[^\s<>\[\]]+\.(?:jpg|jpeg|png|gif|webp|svg)/gi
        // Pattern to match nostr note URIs
        var notePattern = /nostr:(nevent[a-z0-9]+|naddr[a-z0-9]+|note[a-z0-9]+)/gi
        // Pattern to match nostr profile URIs
        var profilePattern = /nostr:(nprofile[a-z0-9]+|npub[a-z0-9]+)/gi
        
        // Combine all patterns with their types
        var allPatterns = [
            { regex: /!\[([^\]]*)\]\(([^)]+)\)/gi, type: "image", urlGroup: 2 },
            { regex: /(?<!["\(])https?:\/\/[^\s<>\[\]"]+\.(?:jpg|jpeg|png|gif|webp|svg)(?!["\)])/gi, type: "image_url" },
            { regex: /nostr:(nevent[a-z0-9]+|naddr[a-z0-9]+|note[a-z0-9]+)/gi, type: "nostr_note" },
            { regex: /nostr:(nprofile[a-z0-9]+|npub[a-z0-9]+)/gi, type: "nostr_profile" }
        ]
        
        // Find all matches with positions
        var matches = []
        
        // Markdown images: ![alt](url)
        var mdImageRegex = /!\[([^\]]*)\]\(([^)]+)\)/g
        var match
        while ((match = mdImageRegex.exec(text)) !== null) {
            matches.push({
                index: match.index,
                length: match[0].length,
                type: "image",
                url: match[2],
                alt: match[1]
            })
        }
        
        // Raw image URLs (not inside markdown or quotes)
        var rawImageRegex = /https?:\/\/[^\s<>\[\]"'\)]+\.(?:jpg|jpeg|png|gif|webp|svg)(?:\?[^\s<>\[\]"'\)]*)?/gi
        while ((match = rawImageRegex.exec(text)) !== null) {
            // Check if this URL is not part of a markdown image
            var isInMarkdown = matches.some(function(m) {
                return match.index >= m.index && match.index < m.index + m.length
            })
            if (!isInMarkdown) {
                matches.push({
                    index: match.index,
                    length: match[0].length,
                    type: "image",
                    url: match[0]
                })
            }
        }
        
        // Nostr note URIs
        var noteRegex = /nostr:(nevent[a-z0-9]+|naddr[a-z0-9]+|note[a-z0-9]+)/gi
        while ((match = noteRegex.exec(text)) !== null) {
            matches.push({
                index: match.index,
                length: match[0].length,
                type: "nostr_note",
                uri: match[0]
            })
        }
        
        // Nostr profile URIs
        var profRegex = /nostr:(nprofile[a-z0-9]+|npub[a-z0-9]+)/gi
        while ((match = profRegex.exec(text)) !== null) {
            matches.push({
                index: match.index,
                length: match[0].length,
                type: "nostr_profile",
                uri: match[0]
            })
        }
        
        // Sort by position
        matches.sort(function(a, b) { return a.index - b.index })
        
        // Build segments
        var lastIndex = 0
        for (var i = 0; i < matches.length; i++) {
            var m = matches[i]
            
            // Add text before this match
            if (m.index > lastIndex) {
                var textBefore = text.substring(lastIndex, m.index).trim()
                if (textBefore) {
                    segments.push({ type: "text", content: textBefore })
                }
            }
            
            // Add the match itself
            if (m.type === "image") {
                segments.push({ type: "image", url: m.url, alt: m.alt || "" })
            } else if (m.type === "nostr_note") {
                segments.push({ type: "nostr_note", uri: m.uri })
            } else if (m.type === "nostr_profile") {
                segments.push({ type: "nostr_profile", uri: m.uri })
            }
            
            lastIndex = m.index + m.length
        }
        
        // Add remaining text
        if (lastIndex < text.length) {
            var remaining = text.substring(lastIndex).trim()
            if (remaining) {
                segments.push({ type: "text", content: remaining })
            }
        }
        
        // If no segments, return the whole text
        if (segments.length === 0 && text.trim()) {
            segments.push({ type: "text", content: text })
        }
        
        return segments
    }
    
    // Format text content with markdown-like styling
    function formatText(text) {
        if (!text) return ""
        
        var result = text
        
        // Escape HTML first
        result = result.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        
        // Headers (must be at start of line)
        result = result.replace(/^### (.+)$/gm, '<h3 style="color: #ffffff; font-size: 22px; margin: 16px 0 8px 0;">$1</h3>')
        result = result.replace(/^## (.+)$/gm, '<h2 style="color: #ffffff; font-size: 26px; margin: 20px 0 10px 0;">$1</h2>')
        result = result.replace(/^# (.+)$/gm, '<h1 style="color: #ffffff; font-size: 30px; margin: 24px 0 12px 0;">$1</h1>')
        
        // Bold and italic
        result = result.replace(/\*\*\*(.+?)\*\*\*/g, '<b><i>$1</i></b>')
        result = result.replace(/\*\*(.+?)\*\*/g, '<b>$1</b>')
        result = result.replace(/\*(.+?)\*/g, '<i>$1</i>')
        result = result.replace(/___(.+?)___/g, '<b><i>$1</i></b>')
        result = result.replace(/__(.+?)__/g, '<b>$1</b>')
        result = result.replace(/_(.+?)_/g, '<i>$1</i>')
        
        // Inline code
        result = result.replace(/`([^`]+)`/g, '<span style="background-color: #2a2a2a; padding: 2px 6px; border-radius: 4px; font-family: monospace;">$1</span>')
        
        // Code blocks
        result = result.replace(/```[\w]*\n?([\s\S]*?)```/g, '<pre style="background-color: #1a1a1a; padding: 12px; border-radius: 8px; overflow-x: auto; font-family: monospace; margin: 12px 0;">$1</pre>')
        
        // Blockquotes
        result = result.replace(/^&gt; (.+)$/gm, '<blockquote style="border-left: 3px solid #9333ea; padding-left: 12px; margin: 8px 0; color: #aaaaaa;">$1</blockquote>')
        
        // Links (but not images which were already extracted)
        result = result.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" style="color: #9333ea; text-decoration: none;">$1</a>')
        
        // Raw URLs (not already in links)
        result = result.replace(/(?<![">])(https?:\/\/[^\s<>\[\]]+)(?![<"])/g, function(url) {
            // Don't link image URLs (they should be extracted)
            if (url.match(/\.(jpg|jpeg|png|gif|webp|svg)(\?.*)?$/i)) {
                return ''
            }
            var displayUrl = url.length > 60 ? url.substring(0, 57) + "..." : url
            return '<a href="' + url + '" style="color: #9333ea; text-decoration: none;">' + displayUrl + '</a>'
        })
        
        // Horizontal rules
        result = result.replace(/^---+$/gm, '<hr style="border: none; border-top: 1px solid #333333; margin: 20px 0;">')
        
        // Lists
        result = result.replace(/^[\*\-] (.+)$/gm, '• $1')
        result = result.replace(/^\d+\. (.+)$/gm, function(match, p1, offset, string) {
            return '  $1'
        })
        
        // Newlines to breaks (but preserve paragraph spacing)
        result = result.replace(/\n\n+/g, '<br><br>')
        result = result.replace(/\n/g, '<br>')
        
        // Clean up excessive breaks
        result = result.replace(/(<br>){3,}/g, '<br><br>')
        
        return result
    }

    // Zap Dialog
    ZapDialog {
        id: zapDialog
        feedController: root.feedController
        nwcConnected: appController ? appController.nwc_connected : false
        
        onZapSent: function(noteId, amount, comment) {
            console.log("Zap sent:", amount, "sats to article", noteId)
        }
    }
    
    // Handle zap results
    Connections {
        target: feedController
        enabled: feedController !== null
        
        function onZap_success(noteId, amount) {
            console.log("Zap successful:", amount, "sats to article", noteId)
        }
        
        function onZap_failed(noteId, error) {
            console.log("Zap failed for article:", noteId, error)
        }
    }
}
