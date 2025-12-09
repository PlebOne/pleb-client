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
    property string sortBy: "chronological" // "chronological" or "zaps"
    property var sortedNotes: []
    
    signal openArticle(string noteId)
    signal openProfile(string pubkey)
    
    // Keyboard navigation
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            feedList.flick(0, -800)
            event.accepted = true
        } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            feedList.flick(0, 800)
            event.accepted = true
        } else if (event.key === Qt.Key_R) {
            if (feedController) feedController.refresh()
            event.accepted = true
        }
    }
    
    onVisibleChanged: {
        if (visible) {
            forceActiveFocus()
            // Load reads_following feed if we're not already on a reads feed
            if (feedController && !feedController.current_feed.toString().startsWith("reads_")) {
                feedController.load_feed("reads_following")
            }
        }
    }
    
    // Also load on component creation in case visible doesn't trigger
    Component.onCompleted: {
        if (visible && feedController && !feedController.current_feed.toString().startsWith("reads_")) {
            feedController.load_feed("reads_following")
        }
    }
    
    property var feedTypes: ["Following", "Global"]
    
    Connections {
        target: feedController
        ignoreUnknownSignals: true
        function onFeed_updated() {
            updateSortedNotes()
        }
        function onMore_loaded(count) {
            updateSortedNotes()
        }
    }
    
    // Function to sort and update the notes list
    function updateSortedNotes() {
        if (!feedController) {
            sortedNotes = []
            return
        }
        
        var notes = []
        var count = feedController.note_count
        for (var i = 0; i < count; i++) {
            var json = feedController.get_note(i)
            var note = JSON.parse(json)
            note.originalIndex = i
            notes.push(note)
        }
        
        if (sortBy === "zaps") {
            notes.sort(function(a, b) {
                return (b.zapAmount || 0) - (a.zapAmount || 0)
            })
        } else {
            // Chronological (newest first) - use publishedAt or createdAt
            notes.sort(function(a, b) {
                var timeA = a.publishedAt || a.createdAt || 0
                var timeB = b.publishedAt || b.createdAt || 0
                return timeB - timeA
            })
        }
        
        sortedNotes = notes
    }
    
    onSortByChanged: {
        updateSortedNotes()
    }
    
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
                
                Text {
                    text: "Reads"
                    color: "#ffffff"
                    font.pixelSize: 20
                    font.weight: Font.Bold
                }
                
                Row {
                    spacing: 4
                    Repeater {
                        model: root.feedTypes
                        delegate: Rectangle {
                            width: tabText.implicitWidth + 24
                            height: 32
                            radius: 16
                            color: feedController && feedController.current_feed.toString() === ("reads_" + modelData.toLowerCase())
                                ? "#9333ea" : "transparent"
                            border.color: feedController && feedController.current_feed.toString() === ("reads_" + modelData.toLowerCase())
                                ? "#9333ea" : "#333333"
                            border.width: 1
                            
                            Text {
                                id: tabText
                                anchors.centerIn: parent
                                text: modelData
                                color: feedController && feedController.current_feed.toString() === ("reads_" + modelData.toLowerCase())
                                    ? "#ffffff" : "#aaaaaa"
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (feedController) {
                                        feedController.load_feed("reads_" + modelData.toLowerCase())
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Sort dropdown
                Rectangle {
                    width: sortRow.implicitWidth + 16
                    height: 32
                    radius: 16
                    color: "#1a1a1a"
                    border.color: "#333333"
                    border.width: 1
                    
                    RowLayout {
                        id: sortRow
                        anchors.centerIn: parent
                        spacing: 6
                        
                        Text {
                            text: "Sort:"
                            color: "#888888"
                            font.pixelSize: 12
                        }
                        
                        Text {
                            text: sortBy === "zaps" ? "⚡ Most Zaps" : "🕐 Newest"
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        
                        Text {
                            text: "▼"
                            color: "#666666"
                            font.pixelSize: 8
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sortMenu.open()
                    }
                    
                    Menu {
                        id: sortMenu
                        y: parent.height + 4
                        
                        background: Rectangle {
                            implicitWidth: 160
                            color: "#1a1a1a"
                            border.color: "#333333"
                            border.width: 1
                            radius: 8
                        }
                        
                        MenuItem {
                            text: "🕐 Newest First"
                            onTriggered: sortBy = "chronological"
                            
                            background: Rectangle {
                                color: sortBy === "chronological" ? "#2a2a2a" : (parent.hovered ? "#252525" : "transparent")
                                radius: 4
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: sortBy === "chronological" ? "#9333ea" : "#ffffff"
                                font.pixelSize: 13
                                leftPadding: 8
                            }
                        }
                        
                        MenuItem {
                            text: "⚡ Most Zaps"
                            onTriggered: sortBy = "zaps"
                            
                            background: Rectangle {
                                color: sortBy === "zaps" ? "#2a2a2a" : (parent.hovered ? "#252525" : "transparent")
                                radius: 4
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: sortBy === "zaps" ? "#9333ea" : "#ffffff"
                                font.pixelSize: 13
                                leftPadding: 8
                            }
                        }
                    }
                }
                
                Item { Layout.fillWidth: true }
                
                Button {
                    text: "🔄"
                    onClicked: if (feedController) feedController.refresh()
                    background: Rectangle { color: "transparent" }
                    contentItem: Text { text: parent.text; color: "white"; font.pixelSize: 18 }
                }
            }
        }
        
        // Feed List
        ListView {
            id: feedList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 16
            topMargin: 20
            bottomMargin: 20
            
            // Performance optimizations
            cacheBuffer: 600
            flickDeceleration: 2500
            maximumFlickVelocity: 6000
            boundsBehavior: Flickable.StopAtBounds
            pixelAligned: true
            reuseItems: true
            highlightFollowsCurrentItem: false
            
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                minimumSize: 0.1
            }
            
            model: sortedNotes.length
            
            delegate: Item {
                width: feedList.width
                height: articleCard.height
                
                property var noteData: sortedNotes[index] || {}
                
                ArticleCard {
                    id: articleCard
                    // Max width of 700px, centered, with minimum margins
                    width: Math.min(700, parent.width - 40)
                    anchors.horizontalCenter: parent.horizontalCenter
                    
                    noteId: noteData.id || ""
                    authorPubkey: noteData.pubkey || ""
                    authorName: noteData.authorName || "Unknown"
                    authorPicture: noteData.authorPicture || ""
                    title: noteData.title || "Untitled"
                    summary: noteData.summary || (noteData.content ? noteData.content.substring(0, 200) + "..." : "")
                    image: noteData.image || ""
                    publishedAt: noteData.publishedAt || noteData.createdAt || 0
                    readingTime: noteData.content ? Math.ceil(noteData.content.length / 1000) : 1
                    zapAmount: noteData.zapAmount || 0
                    
                    onArticleClicked: function(id) {
                        root.openArticle(id)
                    }
                    
                    onAuthorClicked: function(pubkey) {
                        root.openProfile(pubkey)
                    }
                }
            }
            
            // Loading indicator
            footer: Item {
                width: parent.width
                height: 60
                visible: feedController && feedController.is_loading
                
                BusyIndicator {
                    anchors.centerIn: parent
                    running: true
                }
            }
            
            // Empty state
            Text {
                anchors.centerIn: parent
                visible: sortedNotes.length === 0 && feedController && !feedController.is_loading
                text: "No long-form articles found"
                color: "#666666"
                font.pixelSize: 16
            }
        }
        
        // Loading overlay for initial load
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#0a0a0a"
            visible: feedController && feedController.is_loading && sortedNotes.length === 0
            
            Column {
                anchors.centerIn: parent
                spacing: 16
                
                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    running: true
                }
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Loading articles..."
                    color: "#888888"
                    font.pixelSize: 14
                }
            }
        }
    }
}
