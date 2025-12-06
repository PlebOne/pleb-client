import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#1a1a1a"
    radius: 12
    implicitHeight: contentColumn.implicitHeight + 32
    
    // Performance optimizations
    layer.enabled: false  // Disable layer unless needed
    antialiasing: false   // Disable antialiasing for rectangles
    
    property string noteId: ""
    property string authorName: ""
    property string authorPicture: ""
    property string authorNip05: ""
    property string content: ""
    property int createdAt: 0
    property int likes: 0
    property int reposts: 0
    property int replies: 0
    property int zapAmount: 0
    property var images: []
    property var videos: []
    property bool isReply: false
    property string replyTo: ""
    property bool isRepost: false
    property string repostAuthorName: ""
    property string repostAuthorPicture: ""
    property var feedController: null  // For embedded content fetching
    
    signal likeClicked()
    signal repostClicked()
    signal replyClicked()
    signal zapClicked()
    signal noteClicked(string noteId)
    
    // Main click area for opening thread
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.noteClicked(root.noteId)
        // Pass through to children that need interaction
        propagateComposedEvents: true
    }
    
    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        
        // Repost indicator
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: isRepost
            
            Text {
                text: "🔁"
                font.pixelSize: 12
            }
            
            Text {
                text: repostAuthorName + " reposted"
                color: "#666666"
                font.pixelSize: 12
            }
        }
        
        // Reply indicator
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: isReply && !isRepost
            
            Text {
                text: "↩️"
                font.pixelSize: 12
            }
            
            Text {
                text: "Replying to a note"
                color: "#666666"
                font.pixelSize: 12
            }
        }
        
        // Header: author info
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            // Avatar
            ProfileAvatar {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                name: authorName
                imageUrl: authorPicture
            }
            
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                
                RowLayout {
                    spacing: 6
                    
                    Text {
                        text: authorName
                        color: "#ffffff"
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        Layout.maximumWidth: 200
                    }
                    
                    // NIP-05 verification badge
                    Text {
                        text: "✓"
                        color: "#9333ea"
                        font.pixelSize: 12
                        visible: authorNip05 !== ""
                    }
                }
                
                RowLayout {
                    spacing: 8
                    
                    Text {
                        text: authorNip05 !== "" ? authorNip05 : ""
                        color: "#666666"
                        font.pixelSize: 12
                        visible: authorNip05 !== ""
                        elide: Text.ElideRight
                        Layout.maximumWidth: 150
                    }
                    
                    Text {
                        text: formatTimestamp(createdAt)
                        color: "#888888"
                        font.pixelSize: 12
                    }
                }
            }
        }
        
        // Content
        Text {
            text: formatContent(content)
            color: "#ffffff"
            font.pixelSize: 15
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            lineHeight: 1.4
            textFormat: Text.StyledText
            onLinkActivated: (link) => Qt.openUrlExternally(link)
            
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }
        
        // Embedded nostr notes (nevent, naddr, note)
        Repeater {
            model: extractNostrUris(content)
            
            delegate: EmbeddedNote {
                Layout.fillWidth: true
                nostrUri: modelData
                feedController: root.feedController
                onClicked: (noteId) => root.noteClicked(noteId)
            }
        }
        
        // Embedded nostr profiles (nprofile, npub)
        Repeater {
            model: extractProfileUris(content)
            
            delegate: EmbeddedProfile {
                Layout.fillWidth: true
                nostrUri: modelData
                feedController: root.feedController
                // TODO: onClicked navigate to profile screen
            }
        }
        
        // Link previews (non-media URLs)
        Repeater {
            model: extractPreviewUrls(content)
            
            delegate: LinkPreview {
                Layout.fillWidth: true
                url: modelData
                feedController: root.feedController
            }
        }
        
        // Image gallery
        Flow {
            Layout.fillWidth: true
            spacing: 8
            visible: images && images.length > 0
            
            Repeater {
                model: images || []
                
                delegate: Rectangle {
                    width: images.length === 1 ? Math.min(contentColumn.width, 400) : Math.min((contentColumn.width - 8) / 2, 200)
                    height: width * 0.75
                    radius: 8
                    color: "#2a2a2a"
                    clip: true
                    
                    Image {
                        anchors.fill: parent
                        source: modelData
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        
                        // Loading placeholder
                        Rectangle {
                            anchors.fill: parent
                            color: "#2a2a2a"
                            visible: parent.status === Image.Loading
                            
                            BusyIndicator {
                                anchors.centerIn: parent
                                running: parent.visible
                                width: 24
                                height: 24
                            }
                        }
                        
                        // Error placeholder
                        Rectangle {
                            anchors.fill: parent
                            color: "#2a2a2a"
                            visible: parent.status === Image.Error
                            
                            Text {
                                anchors.centerIn: parent
                                text: "🖼️"
                                font.pixelSize: 24
                                color: "#666666"
                            }
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof imageViewer !== 'undefined' && imageViewer) {
                                imageViewer.showImage(modelData, images, index)
                            } else {
                                Qt.openUrlExternally(modelData)
                            }
                        }
                    }
                }
            }
        }
        
        // Video player
        Repeater {
            model: videos || []
            
            delegate: VideoPlayer {
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                source: modelData
                autoPlay: false
            }
        }
        
        // Action bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 24
            
            // Reply
            ActionButton {
                icon: "💬"
                count: replies
                onClicked: root.replyClicked()
            }
            
            // Repost
            ActionButton {
                icon: "🔄"
                count: reposts
                onClicked: root.repostClicked()
            }
            
            // Like
            ActionButton {
                icon: "❤️"
                count: likes
                onClicked: root.likeClicked()
            }
            
            // Zap
            ActionButton {
                icon: "⚡"
                count: zapAmount > 0 ? Math.floor(zapAmount / 1000) : 0
                suffix: zapAmount > 0 ? "k" : ""
                highlight: true
                onClicked: root.zapClicked()
            }
            
            Item { Layout.fillWidth: true }
        }
    }
    
    function formatTimestamp(ts) {
        if (ts === 0) return ""
        
        var now = Date.now() / 1000
        var diff = now - ts
        
        if (diff < 60) return Math.floor(diff) + "s"
        if (diff < 3600) return Math.floor(diff / 60) + "m"
        if (diff < 86400) return Math.floor(diff / 3600) + "h"
        if (diff < 604800) return Math.floor(diff / 86400) + "d"
        
        var date = new Date(ts * 1000)
        return date.toLocaleDateString()
    }
    
    function formatContent(text) {
        if (!text) return ""
        
        // Escape HTML
        var escaped = text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        
        // Remove nostr: URIs for notes (they're shown as embeds below)
        escaped = escaped.replace(/nostr:(nevent|naddr|note)[a-z0-9]+/gi, "")
        
        // Remove nostr: URIs for profiles (they're shown as embeds below)
        escaped = escaped.replace(/nostr:(nprofile|npub)[a-z0-9]+/gi, "")
        
        // Convert URLs to links (but not image/video URLs which are displayed separately)
        var urlPattern = /https?:\/\/[^\s<>\[\]]+/g
        escaped = escaped.replace(urlPattern, function(url) {
            var lower = url.toLowerCase()
            // Don't link media URLs (they're shown as embeds)
            if (lower.match(/\.(jpg|jpeg|png|gif|webp|mp4|webm|mov)$/)) {
                return ""
            }
            // Return shortened link text for cleaner display
            var displayUrl = url.length > 50 ? url.substring(0, 47) + "..." : url
            return '<a href="' + url + '" style="color: #9333ea;">' + displayUrl + '</a>'
        })
        
        // Convert newlines
        escaped = escaped.replace(/\n/g, "<br>")
        
        // Clean up multiple line breaks from removed content
        escaped = escaped.replace(/(<br>){3,}/g, "<br><br>")
        
        return escaped.trim()
    }
    
    // Extract nostr:nevent, nostr:naddr, nostr:note URIs from content
    function extractNostrUris(text) {
        if (!text) return []
        
        var uris = []
        var pattern = /nostr:(nevent[a-z0-9]+|naddr[a-z0-9]+|note[a-z0-9]+)/gi
        var match
        
        while ((match = pattern.exec(text)) !== null) {
            uris.push(match[0])
        }
        
        // Deduplicate
        return [...new Set(uris)]
    }
    
    // Extract nostr:nprofile, nostr:npub URIs from content
    function extractProfileUris(text) {
        if (!text) return []
        
        var uris = []
        var pattern = /nostr:(nprofile[a-z0-9]+|npub[a-z0-9]+)/gi
        var match
        
        while ((match = pattern.exec(text)) !== null) {
            uris.push(match[0])
        }
        
        // Deduplicate
        return [...new Set(uris)]
    }
    
    // Extract URLs for link previews (non-media, non-nostr)
    function extractPreviewUrls(text) {
        if (!text) return []
        
        var urls = []
        var pattern = /https?:\/\/[^\s<>\[\]]+/g
        var match
        
        while ((match = pattern.exec(text)) !== null) {
            var url = match[0]
            var lower = url.toLowerCase()
            
            // Skip media URLs (shown in gallery)
            if (lower.match(/\.(jpg|jpeg|png|gif|webp|mp4|webm|mov)$/)) {
                continue
            }
            
            // Skip nostr.band and other nostr links (they're just note references)
            if (lower.includes("nostr.band") || lower.includes("primal.net") || 
                lower.includes("snort.social") || lower.includes("iris.to")) {
                continue
            }
            
            urls.push(url)
        }
        
        // Deduplicate and limit to first 2 previews
        return [...new Set(urls)].slice(0, 2)
    }
    
    component ActionButton: MouseArea {
        property string icon: ""
        property int count: 0
        property string suffix: ""
        property bool highlight: false
        
        width: row.width
        height: row.height
        cursorShape: Qt.PointingHandCursor
        
        RowLayout {
            id: row
            spacing: 6
            
            Text {
                text: icon
                font.pixelSize: 16
            }
            
            Text {
                text: count > 0 ? count.toString() + suffix : ""
                color: highlight ? "#facc15" : "#888888"
                font.pixelSize: 13
            }
        }
    }
}
