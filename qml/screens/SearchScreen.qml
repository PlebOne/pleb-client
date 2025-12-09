import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    color: "#0a0a0a"
    focus: true
    
    property var searchController: null
    property var feedController: null
    
    signal openProfile(string pubkey)
    signal openThread(string noteId)
    
    // Keyboard navigation
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            searchInput.clear()
            searchController.clear_results()
            event.accepted = true
        } else if (event.key === Qt.Key_Slash && !searchInput.activeFocus) {
            searchInput.forceActiveFocus()
            event.accepted = true
        }
    }
    
    Connections {
        target: searchController
        ignoreUnknownSignals: true
        function onSearch_completed() {
            console.log("[SearchScreen] Search completed - users:", searchController.user_count, "notes:", searchController.note_count, "search_type:", searchController.search_type)
        }
        function onError_occurred(error) {
            console.log("[SearchScreen] Error:", error)
        }
        function onUser_countChanged() {
            console.log("[SearchScreen] user_count changed to:", searchController.user_count)
        }
        function onSearch_typeChanged() {
            console.log("[SearchScreen] search_type changed to:", searchController.search_type)
        }
    }
    
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        
        // Header with search bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            color: "#111111"
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16
                
                Text {
                    text: "Search"
                    color: "#ffffff"
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }
                
                // Search input
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        color: "#1a1a1a"
                        radius: 22
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 8
                            
                            Text {
                                text: "🔍"
                                font.pixelSize: 16
                                color: "#666666"
                            }
                            
                            TextField {
                                id: searchInput
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                placeholderText: "Search users, notes, or #hashtags"
                                placeholderTextColor: "#666666"
                                color: "#ffffff"
                                font.pixelSize: 14
                                
                                background: Rectangle {
                                    color: "transparent"
                                }
                                
                                Keys.onReturnPressed: performSearch()
                                Keys.onEnterPressed: performSearch()
                                
                                function performSearch() {
                                    console.log("[SearchScreen] performSearch called")
                                    var query = text.trim()
                                    console.log("[SearchScreen] query:", query, "searchController:", searchController)
                                    if (query.length > 0) {
                                        if (!searchController) {
                                            console.log("[SearchScreen] ERROR: searchController is null!")
                                            return
                                        }
                                        if (query.startsWith("#")) {
                                            console.log("[SearchScreen] Calling search_hashtag")
                                            searchController.search_hashtag(query)
                                        } else if (query.startsWith("@") || query.startsWith("npub")) {
                                            console.log("[SearchScreen] Calling search_users for user query")
                                            searchController.search_users(query.replace(/^@/, ""))
                                        } else {
                                            // Default: search both users and notes
                                            console.log("[SearchScreen] Calling search_users for general query")
                                            searchController.search_users(query)
                                        }
                                        console.log("[SearchScreen] Search function called successfully")
                                    } else {
                                        console.log("[SearchScreen] Empty query, not searching")
                                    }
                                }
                            }
                            
                            Button {
                                visible: searchInput.text.length > 0
                                text: "×"
                                font.pixelSize: 16
                                implicitWidth: 24
                                implicitHeight: 24
                                
                                ToolTip.visible: hovered
                                ToolTip.text: "Clear search"
                                ToolTip.delay: 500
                                
                                background: Rectangle {
                                    color: parent.hovered ? "#333333" : "transparent"
                                    radius: 12
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    color: "#888888"
                                    font.pixelSize: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: {
                                    searchInput.clear()
                                    searchController.clear_results()
                                }
                            }
                        }
                    }
                    
                    // Search type buttons
                    Row {
                        spacing: 4
                        
                        Button {
                            text: "Users"
                            checkable: true
                            checked: searchController && searchController.search_type === "users"
                            implicitHeight: 44
                            
                            ToolTip.visible: hovered
                            ToolTip.text: "Search for users"
                            ToolTip.delay: 500
                            
                            background: Rectangle {
                                color: parent.checked ? "#9333ea" : (parent.hovered ? "#252525" : "#1a1a1a")
                                radius: 8
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            onClicked: {
                                if (searchInput.text.trim().length > 0) {
                                    searchController.search_users(searchInput.text.trim())
                                }
                            }
                        }
                        
                        Button {
                            text: "Notes"
                            checkable: true
                            checked: searchController && searchController.search_type === "notes"
                            implicitHeight: 44
                            
                            ToolTip.visible: hovered
                            ToolTip.text: "Search for notes"
                            ToolTip.delay: 500
                            
                            background: Rectangle {
                                color: parent.checked ? "#9333ea" : (parent.hovered ? "#252525" : "#1a1a1a")
                                radius: 8
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            onClicked: {
                                if (searchInput.text.trim().length > 0) {
                                    searchController.search_notes(searchInput.text.trim())
                                }
                            }
                        }
                        
                        Button {
                            text: "#Tags"
                            checkable: true
                            checked: searchController && searchController.search_type === "hashtags"
                            implicitHeight: 44
                            
                            ToolTip.visible: hovered
                            ToolTip.text: "Search for hashtags"
                            ToolTip.delay: 500
                            
                            background: Rectangle {
                                color: parent.checked ? "#9333ea" : (parent.hovered ? "#252525" : "#1a1a1a")
                                radius: 8
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            onClicked: {
                                var query = searchInput.text.trim()
                                if (query.length > 0) {
                                    if (!query.startsWith("#")) {
                                        query = "#" + query
                                    }
                                    searchController.search_hashtag(query)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Results area
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#0a0a0a"
            
            // User results
            ListView {
                id: userList
                anchors.fill: parent
                anchors.margins: 20
                clip: true
                spacing: 8
                
                model: searchController ? searchController.user_count : 0
                
                delegate: Rectangle {
                    id: userDelegate
                    width: userList.width
                    height: 80
                    color: mouseArea.containsMouse ? "#1a1a1a" : "transparent"
                    radius: 12
                    
                    property var userData: null
                    
                    Component.onCompleted: {
                        if (searchController) {
                            var json = searchController.get_user(index)
                            if (json) {
                                userData = JSON.parse(json)
                            }
                        }
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (userDelegate.userData && userDelegate.userData.pubkey) {
                                root.openProfile(userDelegate.userData.pubkey)
                            }
                        }
                    }
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12
                        
                        // Avatar
                        ProfileAvatar {
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48
                            imageUrl: (userDelegate.userData && userDelegate.userData.picture) || ""
                            name: (userDelegate.userData && userDelegate.userData.name) || "?"
                        }
                        
                        // Info
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            
                            Text {
                                text: (userDelegate.userData && (userDelegate.userData.displayName || userDelegate.userData.name)) || "Unknown"
                                color: "#ffffff"
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            
                            Text {
                                visible: userDelegate.userData && userDelegate.userData.nip05
                                text: (userDelegate.userData && userDelegate.userData.nip05) || ""
                                color: "#9333ea"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            
                            Text {
                                visible: userDelegate.userData && userDelegate.userData.about
                                text: ((userDelegate.userData && userDelegate.userData.about) || "").replace(/\n/g, " ")
                                color: "#888888"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                Layout.fillWidth: true
                            }
                        }
                        
                        // View button
                        Button {
                            text: "View"
                            implicitHeight: 32
                            
                            background: Rectangle {
                                color: parent.down ? "#7c22c9" : "#9333ea"
                                radius: 8
                                opacity: parent.hovered ? 1.0 : 0.8
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            onClicked: root.openProfile((userDelegate.userData && userDelegate.userData.pubkey) || "")
                        }
                    }
                }
            }

            
            // Note results
            ListView {
                id: noteList
                anchors.fill: parent
                anchors.margins: 20
                visible: searchController && (searchController.search_type === "notes" || searchController.search_type === "hashtags")
                clip: true
                spacing: 8
                
                model: searchController ? searchController.note_count : 0
                
                delegate: NoteCard {
                    id: noteDelegate
                    width: noteList.width
                    feedController: root.feedController
                    
                    Component.onCompleted: loadData()
                    
                    function loadData() {
                        if (searchController) {
                            try {
                                var json = searchController.get_note(index)
                                if (json) {
                                    var note = JSON.parse(json)
                                    noteId = note.id || ""
                                    authorPubkey = note.pubkey || ""
                                    authorName = note.authorName || "Unknown"
                                    authorPicture = note.authorPicture || ""
                                    content = note.content || ""
                                    createdAt = note.createdAt || 0
                                }
                            } catch (e) {
                                console.log("Error parsing note data:", e)
                            }
                        }
                    }
                    
                    onNoteClicked: function(id) {
                        root.openThread(id)
                    }
                    
                    onAuthorClicked: function(pubkey) {
                        root.openProfile(pubkey)
                    }
                    
                    onLikeClicked: {
                        if (root.feedController) root.feedController.like_note(noteId)
                    }
                    
                    onRepostClicked: {
                        if (root.feedController) root.feedController.repost_note(noteId)
                    }
                }
            }
            
            // Loading indicator
            BusyIndicator {
                anchors.centerIn: parent
                running: searchController && searchController.is_searching
                visible: running
            }
            
            // Empty state
            Column {
                anchors.centerIn: parent
                spacing: 12
                visible: !searchController || (!searchController.is_searching && 
                    searchController.user_count === 0 && searchController.note_count === 0)
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: searchInput.text.length > 0 ? "No results found" : "🔍"
                    color: "#666666"
                    font.pixelSize: searchInput.text.length > 0 ? 16 : 48
                }
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: searchInput.text.length > 0 ? "Try a different search term" : "Search for users, notes, or hashtags"
                    color: "#666666"
                    font.pixelSize: 14
                }
            }
        }
    }
    
    function formatTimestamp(timestamp) {
        if (!timestamp) return ""
        var date = new Date(timestamp * 1000)
        var now = new Date()
        var diff = Math.floor((now - date) / 1000)
        
        if (diff < 60) return "now"
        if (diff < 3600) return Math.floor(diff / 60) + "m"
        if (diff < 86400) return Math.floor(diff / 3600) + "h"
        if (diff < 604800) return Math.floor(diff / 86400) + "d"
        return date.toLocaleDateString()
    }

    // Debug Overlay
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 300
        height: 150
        color: "black"
        opacity: 0.8
        z: 9999
        visible: true
        Column {
            anchors.centerIn: parent
            spacing: 5
            Text { color: "white"; text: "Controller: " + (searchController ? "OK" : "NULL") }
            Text { color: "white"; text: "User Count: " + (searchController ? searchController.user_count : "?") }
            Text { color: "white"; text: "Note Count: " + (searchController ? searchController.note_count : "?") }
            Text { color: "white"; text: "Search Type: " + (searchController ? searchController.search_type : "?") }
            Text { color: "white"; text: "Is Searching: " + (searchController ? searchController.is_searching : "?") }
        }
    }
}
