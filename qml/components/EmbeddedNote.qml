import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Embedded note card for displaying nostr:nevent, nostr:naddr, nostr:note references
Rectangle {
    id: root
    color: "#252525"
    radius: 8
    border.color: "#333333"
    border.width: 1
    implicitHeight: contentCol.implicitHeight + 16
    
    property string nostrUri: ""
    property var noteData: null
    property bool isLoading: false
    property bool hasError: false
    property var feedController: null
    property int retryCount: 0
    property int maxRetries: 5
    
    signal clicked(string noteId)
    
    Component.onCompleted: {
        if (nostrUri && !noteData) {
            loadNote()
        }
    }
    
    onNostrUriChanged: {
        noteData = null
        retryCount = 0
        hasError = false
        if (nostrUri) {
            loadNote()
        }
    }
    
    // Timer to retry loading from cache
    Timer {
        id: retryTimer
        interval: 500  // Check every 500ms
        repeat: true
        running: isLoading && retryCount < maxRetries
        onTriggered: {
            retryCount++
            loadNote()
        }
    }
    
    function loadNote() {
        if (!nostrUri || !feedController) return
        
        isLoading = true
        hasError = false
        
        var result = feedController.fetch_embedded_event(nostrUri)
        if (result && result !== "{}") {
            try {
                noteData = JSON.parse(result)
                isLoading = false
                retryTimer.stop()
            } catch (e) {
                console.warn("Failed to parse embedded note:", e)
                hasError = true
                isLoading = false
            }
        } else if (retryCount >= maxRetries) {
            // Give up after max retries
            hasError = true
            isLoading = false
        }
        // else: still loading, timer will retry
    }
    
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (noteData && noteData.id) {
                root.clicked(noteData.id)
            }
        }
    }
    
    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6
        
        // Loading state
        RowLayout {
            Layout.fillWidth: true
            visible: isLoading
            spacing: 8
            
            BusyIndicator {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                running: isLoading
            }
            
            Text {
                text: "Loading note..."
                color: "#888888"
                font.pixelSize: 12
            }
        }
        
        // Error state
        RowLayout {
            Layout.fillWidth: true
            visible: hasError && !isLoading
            spacing: 6
            
            Text {
                text: "📝"
                font.pixelSize: 14
            }
            
            Text {
                text: "Note not found or unavailable"
                color: "#666666"
                font.pixelSize: 12
                font.italic: true
            }
        }
        
        // Loaded note content
        ColumnLayout {
            Layout.fillWidth: true
            visible: noteData && !isLoading && !hasError
            spacing: 4
            
            // Author row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                
                // Mini avatar
                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 12
                    color: "#3a3a3a"
                    
                    Image {
                        anchors.fill: parent
                        anchors.margins: 0
                        source: noteData?.authorPicture || ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: Item {
                            property real radius: 12
                        }
                    }
                    
                    Text {
                        anchors.centerIn: parent
                        text: noteData?.authorName?.charAt(0)?.toUpperCase() || "?"
                        color: "#888888"
                        font.pixelSize: 12
                        visible: !noteData?.authorPicture
                    }
                }
                
                Text {
                    text: noteData?.authorName || "Unknown"
                    color: "#cccccc"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                
                Text {
                    text: noteData?.authorNip05 ? "✓" : ""
                    color: "#9333ea"
                    font.pixelSize: 10
                    visible: !!noteData?.authorNip05
                }
            }
            
            // Content
            Text {
                text: formatEmbeddedContent(noteData?.content || "")
                color: "#aaaaaa"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                maximumLineCount: 3
                elide: Text.ElideRight
            }
            
            // Timestamp
            Text {
                text: noteData ? formatTimestamp(noteData.createdAt) : ""
                color: "#666666"
                font.pixelSize: 11
            }
        }
    }
    
    function formatEmbeddedContent(text) {
        if (!text) return ""
        // Strip media URLs and nostr URIs for preview
        var cleaned = text.replace(/https?:\/\/[^\s]+\.(jpg|jpeg|png|gif|webp|mp4|webm|mov)/gi, "")
                         .replace(/nostr:(nevent|naddr|note|npub|nprofile)[a-z0-9]+/gi, "")
                         .replace(/\n+/g, " ")
                         .trim()
        return cleaned
    }
    
    function formatTimestamp(ts) {
        if (!ts || ts === 0) return ""
        
        var now = Date.now() / 1000
        var diff = now - ts
        
        if (diff < 60) return Math.floor(diff) + "s"
        if (diff < 3600) return Math.floor(diff / 60) + "m"
        if (diff < 86400) return Math.floor(diff / 3600) + "h"
        if (diff < 604800) return Math.floor(diff / 86400) + "d"
        
        var date = new Date(ts * 1000)
        return date.toLocaleDateString()
    }
}
