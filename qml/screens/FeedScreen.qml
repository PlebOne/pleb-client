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
    
    // Signal to request thread view navigation
    signal openThread(string noteId)
    
    // Keyboard navigation
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            // Scroll down
            feedList.flick(0, -800)
            event.accepted = true
        } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            // Scroll up
            feedList.flick(0, 800)
            event.accepted = true
        } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
            // Go to bottom (Shift+G)
            feedList.positionViewAtEnd()
            event.accepted = true
        } else if (event.key === Qt.Key_G) {
            // Go to top
            feedList.positionViewAtBeginning()
            event.accepted = true
        } else if (event.key === Qt.Key_R) {
            // Refresh
            if (feedController) feedController.refresh()
            event.accepted = true
        } else if (event.key === Qt.Key_N) {
            // Check for new
            if (feedController) feedController.check_for_new()
            event.accepted = true
        } else if (event.key === Qt.Key_Question) {
            // Toggle keyboard shortcuts help
            if (shortcutPopup.visible) {
                shortcutPopup.close()
            } else {
                shortcutPopup.open()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Space) {
            // Page down
            feedList.flick(0, -1500)
            event.accepted = true
        } else if (event.key === Qt.Key_Home) {
            feedList.positionViewAtBeginning()
            event.accepted = true
        } else if (event.key === Qt.Key_End) {
            feedList.positionViewAtEnd()
            event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
            feedList.flick(0, -1500)
            event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
            feedList.flick(0, 1500)
            event.accepted = true
        } else if (event.key === Qt.Key_1) {
            // Switch to Following feed
            if (feedController) feedController.load_feed("following")
            event.accepted = true
        } else if (event.key === Qt.Key_2) {
            // Switch to Replies feed
            if (feedController) feedController.load_feed("replies")
            event.accepted = true
        } else if (event.key === Qt.Key_3 && appController && appController.show_global_feed) {
            // Switch to Global feed (if enabled)
            if (feedController) feedController.load_feed("global")
            event.accepted = true
        }
    }
    
    // Ensure focus when visible
    onVisibleChanged: if (visible) forceActiveFocus()
    
    // Feed types - dynamically computed based on settings
    property var feedTypes: {
        var types = ["Following", "Replies"]  // Following = posts only, Replies = combined
        if (appController && appController.show_global_feed) {
            types.push("Global")
        }
        return types
    }
    
    // Helper function for empty message
    function getFeedEmptyMessage() {
        if (!feedController) return "No notes to show"
        var feed = feedController.current_feed.toString()
        switch(feed) {
            case "home":
            case "following": 
            case "replies": return "No posts from people you follow"
            case "global": return "No notes found"
            default: return "No notes to show"
        }
    }
    
    // Reload notes when feed updates
    Connections {
        target: feedController
        ignoreUnknownSignals: true
        function onFeed_updated() {
            feedList.model = feedController ? feedController.note_count : 0
        }
        function onMore_loaded(count) {
            feedList.model = feedController ? feedController.note_count : 0
        }
        function onNew_notes_found(count) {
            feedList.model = feedController ? feedController.note_count : 0
            if (count > 0) {
                // Scroll to top to show new notes
                feedList.positionViewAtBeginning()
            }
        }
        function onError_occurred(error) {
            console.log("Feed error:", error)
        }
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
                    text: "Feed"
                    color: "#ffffff"
                    font.pixelSize: 20
                    font.weight: Font.Bold
                }
                
                // Feed type tabs (Following / Replies / Global - based on settings)
                Row {
                    spacing: 4
                    
                    Repeater {
                        model: root.feedTypes
                        
                        delegate: Rectangle {
                            width: tabText.implicitWidth + 24
                            height: 32
                            radius: 16
                            color: feedController && feedController.current_feed.toString() === modelData.toLowerCase() 
                                ? "#9333ea" : "transparent"
                            border.color: feedController && feedController.current_feed.toString() === modelData.toLowerCase()
                                ? "#9333ea" : "#333333"
                            border.width: 1
                            
                            Text {
                                id: tabText
                                anchors.centerIn: parent
                                text: modelData
                                color: feedController && feedController.current_feed.toString() === modelData.toLowerCase()
                                    ? "#ffffff" : "#aaaaaa"
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                
                                onClicked: {
                                    if (feedController) {
                                        feedController.load_feed(modelData.toLowerCase())
                                    }
                                }
                                
                                onEntered: {
                                    if (!(feedController && feedController.current_feed.toString() === modelData.toLowerCase())) {
                                        parent.color = "#1a1a1a"
                                    }
                                }
                                onExited: {
                                    if (!(feedController && feedController.current_feed.toString() === modelData.toLowerCase())) {
                                        parent.color = "transparent"
                                    }
                                }
                            }
                        }
                    }
                }
                
                Item { Layout.fillWidth: true }
                
                // Check for new button
                Button {
                    text: "⬆️ New"
                    font.pixelSize: 14
                    
                    background: Rectangle {
                        color: parent.pressed ? "#1a5233" : "#1e3a2f"
                        radius: 8
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: "#22c55e"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        if (feedController) {
                            feedController.check_for_new()
                        }
                    }
                }
                
                // Keyboard shortcuts help button
                Button {
                    id: kbHelpBtn
                    implicitWidth: 40
                    implicitHeight: 36
                    
                    ToolTip.visible: hovered
                    ToolTip.text: "Keyboard shortcuts (?)"
                    ToolTip.delay: 500
                    
                    background: Rectangle {
                        color: parent.pressed ? "#333333" : (parent.hovered ? "#252525" : "#1a1a1a")
                        radius: 8
                        border.color: "#333333"
                        border.width: 1
                    }
                    
                    contentItem: Text {
                        text: "⌨️"
                        font.pixelSize: 22
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        shortcutPopup.open()
                    }
                }
                
                // Refresh button
                Button {
                    text: "🔄"
                    font.pixelSize: 18
                    
                    background: Rectangle {
                        color: parent.pressed ? "#333333" : "#1a1a1a"
                        radius: 8
                    }
                    
                    onClicked: {
                        if (feedController) {
                            feedController.refresh()
                        }
                    }
                }
            }
        }
        
        // Feed list
        ListView {
            id: feedList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 12
            leftMargin: 20
            rightMargin: 20
            topMargin: 20
            bottomMargin: 20
            
            // Performance optimizations for smooth scrolling
            cacheBuffer: 800  // Reduced cache buffer - less items to create at once
            flickDeceleration: 2500  // Smoother deceleration
            maximumFlickVelocity: 6000  // Slightly reduced for smoother feel
            boundsBehavior: Flickable.StopAtBounds
            pixelAligned: true  // Sharper rendering
            reuseItems: true  // Reuse delegate instances
            
            // Disable highlight following to reduce overhead
            highlightFollowsCurrentItem: false
            
            // Smooth scrolling animation
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                minimumSize: 0.1
            }
            
            model: feedController ? feedController.note_count : 0
            
            delegate: NoteCard {
                id: noteDelegate
                width: feedList.width - 40
                feedController: root.feedController  // Pass for embedded content
                
                // Track the index this delegate is displaying
                property int displayIndex: index
                
                // Function to load note data for the current index
                function loadNoteData() {
                    if (root.feedController && displayIndex >= 0) {
                        var noteJson = root.feedController.get_note(displayIndex)
                        if (noteJson) {
                            var note = JSON.parse(noteJson)
                            noteId = note.id || ""
                            authorName = note.authorName || "Unknown"
                            authorPicture = note.authorPicture || ""
                            authorNip05 = note.authorNip05 || ""
                            content = note.content || ""
                            createdAt = note.createdAt || 0
                            likes = note.likes || 0
                            reposts = note.reposts || 0
                            replies = note.replies || 0
                            zapAmount = note.zapAmount || 0
                            images = note.images || []
                            videos = note.videos || []
                            isReply = note.isReply || false
                            replyTo = note.replyTo || ""
                            isRepost = note.isRepost || false
                            repostAuthorName = note.repostAuthorName || ""
                            repostAuthorPicture = note.repostAuthorPicture || ""
                        }
                    }
                }
                
                // Load data when first created
                Component.onCompleted: loadNoteData()
                
                // Reload data when index changes (delegate reuse)
                onDisplayIndexChanged: loadNoteData()
                
                // Handle delegate reuse - reload data when pooled/reused
                ListView.onPooled: {
                    // Clear data when pooled to avoid stale display
                    noteId = ""
                    content = ""
                    authorName = ""
                    authorPicture = ""
                    images = []
                    videos = []
                    isRepost = false
                    repostAuthorName = ""
                }
                
                ListView.onReused: {
                    // Reload data when delegate is reused for a new index
                    loadNoteData()
                }
                
                onLikeClicked: feedController.like_note(noteId)
                onRepostClicked: feedController.repost_note(noteId)
                onReplyClicked: root.openThread(noteId) // Open thread to reply
                onZapClicked: feedController.zap_note(noteId, 21, "") // Default 21 sats zap
                onNoteClicked: function(id) {
                    console.log("Opening thread for note:", id)
                    root.openThread(id)
                }
            }
            
            // Infinite scroll - load more when near bottom
            property bool loadMorePending: false
            
            onContentYChanged: {
                // Trigger load when we're within 500px of the bottom
                var distanceFromBottom = contentHeight - (contentY + height)
                if (contentHeight > height && distanceFromBottom < 500 && 
                    !feedController.is_loading && !loadMorePending) {
                    loadMorePending = true
                    feedController.load_more()
                }
            }
            
            // Reset the pending flag when loading completes
            Connections {
                target: feedController
                function onMore_loaded(count) {
                    feedList.loadMorePending = false
                }
                function onError_occurred(error) {
                    feedList.loadMorePending = false
                }
            }
            
            // Loading indicator - prominent overlay for initial load
            Rectangle {
                id: loadingOverlay
                anchors.centerIn: parent
                width: 280
                height: 140
                radius: 16
                color: "#1a1a1a"
                border.color: "#333333"
                border.width: 1
                visible: feedController && feedController.is_loading && feedController.note_count === 0
                
                Column {
                    anchors.centerIn: parent
                    spacing: 16
                    
                    BusyIndicator {
                        anchors.horizontalCenter: parent.horizontalCenter
                        running: parent.parent.visible
                        width: 48
                        height: 48
                    }
                    
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Loading your feed..."
                        color: "#ffffff"
                        font.pixelSize: 16
                        font.weight: Font.Medium
                    }
                    
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: feedController && feedController.loading_status.toString() !== "" 
                            ? feedController.loading_status.toString() 
                            : "Please wait..."
                        color: "#888888"
                        font.pixelSize: 13
                    }
                }
            }
            
            // Small loading indicator for subsequent loads (refresh, load more)
            BusyIndicator {
                anchors.centerIn: parent
                running: feedController && feedController.is_loading && feedController.note_count > 0
                visible: running
                width: 32
                height: 32
            }
            
            // Empty state
            Column {
                anchors.centerIn: parent
                spacing: 12
                visible: !feedController || (!feedController.is_loading && feedController.note_count === 0)
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.getFeedEmptyMessage()
                    color: "#666666"
                    font.pixelSize: 16
                }
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: feedController && feedController.error_message.toString() !== "" 
                        ? feedController.error_message.toString() 
                        : ""
                    color: "#ff6b6b"
                    font.pixelSize: 13
                    visible: text !== ""
                    wrapMode: Text.WordWrap
                    width: Math.min(400, root.width - 80)
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
        
        // Compose bar with media support
        Rectangle {
            Layout.fillWidth: true
            Layout.minimumHeight: 70
            Layout.preferredHeight: composeColumn.implicitHeight + 24
            color: "#111111"
            
            // Track attached media URLs
            property var attachedMedia: []
            property bool isUploading: false
            
            ColumnLayout {
                id: composeColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                
                // Media preview row (when media is attached)
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: parent.parent.attachedMedia.length > 0
                    
                    Repeater {
                        model: parent.parent.parent.attachedMedia
                        
                        delegate: Rectangle {
                            width: 80
                            height: 80
                            radius: 8
                            color: "#2a2a2a"
                            clip: true
                            
                            Image {
                                anchors.fill: parent
                                source: modelData
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: !modelData.match(/\.(mp4|webm|mov)$/i)
                            }
                            
                            // Video indicator
                            Rectangle {
                                anchors.fill: parent
                                color: "#2a2a2a"
                                visible: modelData.match(/\.(mp4|webm|mov)$/i)
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "🎬"
                                    font.pixelSize: 24
                                }
                            }
                            
                            // Remove button
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 4
                                width: 20
                                height: 20
                                radius: 10
                                color: "#000000"
                                opacity: 0.7
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: "#ffffff"
                                    font.pixelSize: 12
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var media = composeColumn.parent.attachedMedia.slice()
                                        media.splice(index, 1)
                                        composeColumn.parent.attachedMedia = media
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Input row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    // Media attach button
                    Button {
                        id: attachBtn
                        text: "📷"
                        font.pixelSize: 18
                        implicitWidth: 44
                        implicitHeight: 44
                        enabled: !composeColumn.parent.isUploading
                        
                        ToolTip.visible: hovered
                        ToolTip.text: "Attach image or video"
                        ToolTip.delay: 500
                        
                        background: Rectangle {
                            color: parent.pressed ? "#333333" : (parent.hovered ? "#252525" : "#1a1a1a")
                            radius: 8
                            border.color: "#333333"
                            border.width: 1
                        }
                        
                        onClicked: mediaFileDialog.open()
                    }
                    
                    TextField {
                        id: composeInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        placeholderText: "What's on your mind?"
                        color: "#ffffff"
                        font.pixelSize: 14
                        
                        background: Rectangle {
                            color: "#1a1a1a"
                            radius: 8
                            border.color: composeInput.activeFocus ? "#9333ea" : "#333333"
                            border.width: 1
                        }
                        
                        leftPadding: 16
                        rightPadding: 16
                    }
                    
                    // Upload progress indicator
                    BusyIndicator {
                        running: composeColumn.parent.isUploading
                        visible: running
                        implicitWidth: 32
                        implicitHeight: 32
                    }
                    
                    Button {
                        text: "Post"
                        Layout.preferredHeight: 44
                        Layout.preferredWidth: 80
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        
                        background: Rectangle {
                            color: parent.enabled ? (parent.pressed ? "#7c22ce" : "#9333ea") : "#333333"
                            radius: 8
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            font: parent.font
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        enabled: (composeInput.text.trim() !== "" || composeColumn.parent.attachedMedia.length > 0) && !composeColumn.parent.isUploading
                        
                        onClicked: {
                            if (feedController) {
                                var media = composeColumn.parent.attachedMedia
                                if (media.length > 0) {
                                    feedController.post_note_with_media(
                                        composeInput.text.trim(),
                                        JSON.stringify(media)
                                    )
                                } else {
                                    feedController.post_note(composeInput.text.trim())
                                }
                                composeInput.text = ""
                                composeColumn.parent.attachedMedia = []
                            }
                        }
                    }
                }
            }
        }
    }
    
    // File dialog for media selection
    Loader {
        id: mediaFileDialogLoader
        active: false
        sourceComponent: Item {}
    }
    
    // Platform file dialog (we'll use a custom solution)
    Item {
        id: mediaFileDialog
        
        function open() {
            // Use Qt.labs.platform FileDialog if available, otherwise fall back
            fileDialogComponent.createObject(root).open()
        }
        
        Component {
            id: fileDialogComponent
            
            Popup {
                id: fileSelectPopup
                anchors.centerIn: parent
                width: 500
                height: 400
                modal: true
                focus: true
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                
                background: Rectangle {
                    color: "#1a1a1a"
                    radius: 12
                    border.color: "#333333"
                    border.width: 1
                }
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12
                    
                    Text {
                        text: "Enter file path"
                        color: "#ffffff"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                    }
                    
                    Text {
                        text: "Supported: JPG, PNG, GIF, WebP, MP4, WebM, MOV"
                        color: "#888888"
                        font.pixelSize: 12
                    }
                    
                    TextField {
                        id: filePathInput
                        Layout.fillWidth: true
                        placeholderText: "/home/user/image.jpg"
                        color: "#ffffff"
                        font.pixelSize: 14
                        
                        background: Rectangle {
                            color: "#0a0a0a"
                            radius: 8
                            border.color: filePathInput.activeFocus ? "#9333ea" : "#333333"
                            border.width: 1
                        }
                        
                        leftPadding: 12
                        rightPadding: 12
                        topPadding: 12
                        bottomPadding: 12
                    }
                    
                    Text {
                        id: uploadStatus
                        color: "#888888"
                        font.pixelSize: 12
                        visible: text !== ""
                    }
                    
                    Item { Layout.fillHeight: true }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        
                        Item { Layout.fillWidth: true }
                        
                        Button {
                            text: "Cancel"
                            implicitWidth: 100
                            implicitHeight: 40
                            
                            background: Rectangle {
                                color: parent.pressed ? "#333333" : "#252525"
                                radius: 8
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            onClicked: fileSelectPopup.close()
                        }
                        
                        Button {
                            text: composeColumn.parent.isUploading ? "Uploading..." : "Upload"
                            implicitWidth: 100
                            implicitHeight: 40
                            enabled: filePathInput.text.trim() !== "" && !composeColumn.parent.isUploading
                            
                            background: Rectangle {
                                color: parent.enabled ? (parent.pressed ? "#7c22ce" : "#9333ea") : "#333333"
                                radius: 8
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            onClicked: {
                                var path = filePathInput.text.trim()
                                if (path && feedController) {
                                    composeColumn.parent.isUploading = true
                                    uploadStatus.text = "Uploading..."
                                    uploadStatus.color = "#888888"
                                    
                                    var result = feedController.upload_media(path)
                                    try {
                                        var data = JSON.parse(result)
                                        if (data.url) {
                                            // Success - add to attached media
                                            var media = composeColumn.parent.attachedMedia.slice()
                                            media.push(data.url)
                                            composeColumn.parent.attachedMedia = media
                                            fileSelectPopup.close()
                                        } else if (data.error) {
                                            uploadStatus.text = "Error: " + data.error
                                            uploadStatus.color = "#ff6b6b"
                                        }
                                    } catch (e) {
                                        uploadStatus.text = "Upload failed"
                                        uploadStatus.color = "#ff6b6b"
                                    }
                                    composeColumn.parent.isUploading = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Keyboard Shortcuts Popup
    Popup {
        id: shortcutPopup
        anchors.centerIn: parent
        width: 340
        height: contentColumn.implicitHeight + 48
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        background: Rectangle {
            color: "#1a1a1a"
            radius: 12
            border.color: "#333333"
            border.width: 1
        }
        
        Column {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16
            
            // Header
            RowLayout {
                width: parent.width
                
                Text {
                    text: "⌨️ Keyboard Shortcuts"
                    color: "#ffffff"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
                
                Item { Layout.fillWidth: true }
                
                Text {
                    text: "✕"
                    color: "#666666"
                    font.pixelSize: 18
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shortcutPopup.close()
                    }
                }
            }
            
            Rectangle {
                width: parent.width
                height: 1
                color: "#333333"
            }
            
            // Navigation section
            Column {
                width: parent.width
                spacing: 8
                
                Text {
                    text: "Navigation"
                    color: "#9333ea"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                
                ShortcutRow { key: "J"; desc: "Scroll down" }
                ShortcutRow { key: "K"; desc: "Scroll up" }
                ShortcutRow { key: "G"; desc: "Go to top" }
                ShortcutRow { key: "Shift + G"; desc: "Go to bottom" }
            }
            
            Rectangle {
                width: parent.width
                height: 1
                color: "#252525"
            }
            
            // Actions section
            Column {
                width: parent.width
                spacing: 8
                
                Text {
                    text: "Actions"
                    color: "#9333ea"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                
                ShortcutRow { key: "R"; desc: "Refresh feed" }
                ShortcutRow { key: "N"; desc: "Check for new posts" }
                ShortcutRow { key: "?"; desc: "Toggle this help" }
            }
            
            Rectangle {
                width: parent.width
                height: 1
                color: "#252525"
            }
            
            // Tabs section
            Column {
                width: parent.width
                spacing: 8
                
                Text {
                    text: "Feed Tabs"
                    color: "#9333ea"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                
                ShortcutRow { key: "1"; desc: "Following feed" }
                ShortcutRow { key: "2"; desc: "Replies feed" }
                ShortcutRow { key: "3"; desc: "Global feed (if enabled)" }
            }
        }
    }
    
    // Reusable shortcut row component
    component ShortcutRow: RowLayout {
        property string key: ""
        property string desc: ""
        width: parent.width
        spacing: 12
        
        Rectangle {
            Layout.preferredWidth: keyText.implicitWidth + 16
            Layout.preferredHeight: 24
            color: "#252525"
            radius: 4
            border.color: "#404040"
            border.width: 1
            
            Text {
                id: keyText
                anchors.centerIn: parent
                text: key
                color: "#cccccc"
                font.pixelSize: 12
                font.family: "monospace"
                font.weight: Font.Medium
            }
        }
        
        Text {
            text: desc
            color: "#888888"
            font.pixelSize: 13
        }
        
        Item { Layout.fillWidth: true }
    }
}
