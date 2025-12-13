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

    // Local reactive properties that get updated when search completes
    // These drive the ListView models and are updated explicitly to ensure reactivity
    property int localNoteCount: 0
    property int localUserCount: 0
    property string localSearchType: "notes"

    // Update local properties from controller
    function syncFromController() {
        if (searchController) {
            localNoteCount = Number(searchController.note_count) || 0
            localUserCount = Number(searchController.user_count) || 0
            localSearchType = String(searchController.search_type || "notes")
            console.log("[SearchScreen] syncFromController: notes=", localNoteCount, "users=", localUserCount, "type=", localSearchType)
        }
    }
    
    // Keyboard navigation
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            searchInput.clear()
            searchController.clear_results()
            syncFromController()
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
            console.log("[SearchScreen] search_completed signal received")
            root.syncFromController()
            console.log(
                "[SearchScreen] After sync: type=", root.localSearchType,
                "noteCount=", root.localNoteCount,
                "userCount=", root.localUserCount,
                "noteList.visible=", noteList.visible,
                "userList.visible=", userList.visible,
                "noteList.model=", noteList.model,
                "userList.model=", userList.model
            )
        }
        
        function onNote_countChanged() {
            console.log("[SearchScreen] note_count changed to", searchController.note_count)
            root.localNoteCount = Number(searchController.note_count) || 0
        }
        
        function onUser_countChanged() {
            console.log("[SearchScreen] user_count changed to", searchController.user_count)
            root.localUserCount = Number(searchController.user_count) || 0
        }
        
        function onSearch_typeChanged() {
            console.log("[SearchScreen] search_type changed to", searchController.search_type)
            root.localSearchType = String(searchController.search_type || "notes")
        }
        
        function onError_occurred(error) {
            console.log("[SearchScreen] Error:", error)
        }
    }
    
    Component.onCompleted: {
        syncFromController()
    }
    
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        
        // Header with search bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 160
            color: "#111111"
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12
                
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
                                placeholderText: "Search users, notes, or #hashtags (fuzzy match)"
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
                                        
                                        // Check for explicit prefixes first
                                        if (query.startsWith("#")) {
                                            console.log("[SearchScreen] Calling search_hashtag (# prefix)")
                                            searchController.search_hashtag(query)
                                        } else if (query.startsWith("@") || query.startsWith("npub")) {
                                            console.log("[SearchScreen] Calling search_users (@ or npub prefix)")
                                            searchController.search_users(query.replace(/^@/, ""))
                                        } else {
                                            // Use currently selected search type, default to notes
                                            var currentType = root.localSearchType
                                            console.log("[SearchScreen] Using current search_type:", currentType)
                                            
                                            if (currentType === "users") {
                                                console.log("[SearchScreen] Calling search_users")
                                                searchController.search_users(query)
                                            } else if (currentType === "hashtags") {
                                                console.log("[SearchScreen] Calling search_hashtag")
                                                var hashQuery = query.startsWith("#") ? query : "#" + query
                                                searchController.search_hashtag(hashQuery)
                                            } else {
                                                // Default to notes search (including when search_type is empty/undefined)
                                                console.log("[SearchScreen] Calling search_notes (default)")
                                                searchController.search_notes(query)
                                            }
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
                                    root.syncFromController()
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
                            checked: root.localSearchType === "users"
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
                            checked: root.localSearchType === "notes"
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
                            checked: root.localSearchType === "hashtags"
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
                        
                        // Spacer
                        Item { width: 16; height: 1 }
                        
                        // Time range dropdown
                        ComboBox {
                            id: timeRangeCombo
                            implicitWidth: 100
                            implicitHeight: 44
                            
                            model: ListModel {
                                ListElement { text: "24 hours"; days: 1 }
                                ListElement { text: "7 days"; days: 7 }
                                ListElement { text: "30 days"; days: 30 }
                                ListElement { text: "90 days"; days: 90 }
                            }
                            
                            currentIndex: 1 // Default to 7 days
                            
                            textRole: "text"
                            
                            ToolTip.visible: hovered
                            ToolTip.text: "Time range for note searches"
                            ToolTip.delay: 500
                            
                            background: Rectangle {
                                color: parent.hovered ? "#252525" : "#1a1a1a"
                                radius: 8
                                border.color: "#333333"
                                border.width: 1
                            }
                            
                            contentItem: Text {
                                leftPadding: 12
                                rightPadding: timeRangeCombo.indicator.width + 8
                                text: timeRangeCombo.displayText
                                font.pixelSize: 13
                                color: "#ffffff"
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                            
                            indicator: Text {
                                x: timeRangeCombo.width - width - 8
                                y: (timeRangeCombo.height - height) / 2
                                text: "▼"
                                color: "#666666"
                                font.pixelSize: 10
                            }
                            
                            popup: Popup {
                                y: timeRangeCombo.height
                                width: timeRangeCombo.width
                                implicitHeight: contentItem.implicitHeight
                                padding: 1
                                
                                contentItem: ListView {
                                    clip: true
                                    implicitHeight: contentHeight
                                    model: timeRangeCombo.popup.visible ? timeRangeCombo.delegateModel : null
                                    currentIndex: timeRangeCombo.highlightedIndex
                                }
                                
                                background: Rectangle {
                                    color: "#1a1a1a"
                                    border.color: "#333333"
                                    radius: 8
                                }
                            }
                            
                            delegate: ItemDelegate {
                                width: timeRangeCombo.width
                                
                                contentItem: Text {
                                    text: model.text
                                    color: "#ffffff"
                                    font.pixelSize: 13
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                highlighted: timeRangeCombo.highlightedIndex === index
                                
                                background: Rectangle {
                                    color: highlighted ? "#333333" : "transparent"
                                }
                            }
                            
                            onCurrentIndexChanged: {
                                var days = model.get(currentIndex).days
                                console.log("[SearchScreen] Time range changed to:", days, "days")
                                if (searchController) {
                                    searchController.set_time_range(days)
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
                visible: root.localSearchType === "users"
                clip: true
                spacing: 8

                onVisibleChanged: {
                    console.log("[SearchScreen] userList.visible=", visible, "model=", model, "count=", count)
                }
                onCountChanged: {
                    console.log("[SearchScreen] userList.count=", count, "model=", model)
                }
                
                model: root.localUserCount
                
                delegate: Rectangle {
                    id: userDelegate
                    width: userList.width
                    height: 80
                    color: mouseArea.containsMouse ? "#1a1a1a" : "transparent"
                    radius: 12

                    // Track delegate reuse / index updates
                    property int displayIndex: index
                    
                    property var userData: null
                    
                    Component.onCompleted: {
                        loadData()
                    }

                    onDisplayIndexChanged: loadData()

                    function loadData() {
                        if (searchController) {
                            var json = searchController.get_user(displayIndex)
                            if (json) {
                                try {
                                    userData = JSON.parse("" + json)
                                } catch (e) {
                                    console.log("[SearchScreen] Error parsing user data:", e)
                                    userData = null
                                }
                            } else {
                                userData = null
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
                visible: root.localSearchType === "notes" || root.localSearchType === "hashtags"
                clip: true
                spacing: 8

                onVisibleChanged: {
                    console.log("[SearchScreen] noteList.visible=", visible, "model=", model, "count=", count)
                }
                onCountChanged: {
                    console.log("[SearchScreen] noteList.count=", count, "model=", model)
                }
                
                model: root.localNoteCount
                
                delegate: NoteCard {
                    id: noteDelegate
                    width: noteList.width
                    feedController: root.feedController

                    // Track delegate reuse / index updates
                    property int displayIndex: index
                    
                    Component.onCompleted: loadData()
                    onDisplayIndexChanged: loadData()
                    
                    function loadData() {
                        if (searchController) {
                            try {
                                var json = searchController.get_note(displayIndex)
                                if (json) {
                                    var note = JSON.parse("" + json)
                                    noteId = note.id || ""
                                    authorPubkey = note.pubkey || ""
                                    authorName = note.authorName || "Unknown"
                                    authorPicture = note.authorPicture || ""
                                    authorNip05 = note.authorNip05 || ""
                                    content = note.content || ""
                                    createdAt = note.createdAt || 0
                                    likes = note.likes || 0
                                    reposts = note.reposts || 0
                                    replies = note.replies || 0
                                    zapAmount = note.zapAmount || 0
                                    zapCount = note.zapCount || 0
                                    reactions = note.reactions || {}
                                    images = note.images || []
                                    videos = note.videos || []
                                    isReply = note.isReply || false
                                    replyTo = note.replyTo || ""
                                    replyToAuthorName = note.replyToAuthorName || ""
                                    isRepost = note.isRepost || false
                                    repostAuthorName = note.repostAuthorName || ""
                                    repostAuthorPicture = note.repostAuthorPicture || ""
                                }
                            } catch (e) {
                                console.log("[SearchScreen] Error parsing note data:", e)
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
                    root.localUserCount === 0 && root.localNoteCount === 0)
                
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
        width: 320
        height: 180
        color: "black"
        opacity: 0.8
        z: 9999
        visible: true
        Column {
            anchors.centerIn: parent
            spacing: 5
            Text { color: "white"; text: "Controller: " + (searchController ? "OK" : "NULL") }
            Text { color: "lime"; text: "Local Note Count: " + root.localNoteCount }
            Text { color: "lime"; text: "Local User Count: " + root.localUserCount }
            Text { color: "lime"; text: "Local Search Type: " + root.localSearchType }
            Text { color: "yellow"; text: "Rust note_count: " + (searchController ? searchController.note_count : "?") }
            Text { color: "yellow"; text: "Rust user_count: " + (searchController ? searchController.user_count : "?") }
            Text { color: "white"; text: "Is Searching: " + (searchController ? searchController.is_searching : "?") }
        }
    }
}
