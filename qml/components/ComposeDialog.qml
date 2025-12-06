import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt.labs.platform as Platform

// Compose Dialog - Popup for creating new posts
Popup {
    id: root
    
    property var feedController: null
    property string replyToId: ""  // If set, this is a reply
    property string replyToAuthor: ""  // Author name of note being replied to
    property string replyToContent: ""  // Content preview of note being replied to
    
    // Track attached media URLs
    property var attachedMedia: []
    property bool isUploading: false
    
    signal posted()
    
    width: Math.min(600, parent.width - 40)
    height: Math.min(500, parent.height - 100)
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    
    background: Rectangle {
        color: "#1a1a1a"
        radius: 16
        border.color: "#333333"
        border.width: 1
    }
    
    // Reset state when opened
    onOpened: {
        composeInput.text = ""
        attachedMedia = []
        composeInput.forceActiveFocus()
    }
    
    // Reset on close
    onClosed: {
        replyToId = ""
        replyToAuthor = ""
        replyToContent = ""
        attachedMedia = []
    }
    
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        
        // Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: "transparent"
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                
                Text {
                    text: replyToId ? "Reply" : "New Post"
                    color: "#ffffff"
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
                
                Item { Layout.fillWidth: true }
                
                Button {
                    text: "×"
                    implicitWidth: 36
                    implicitHeight: 36
                    
                    background: Rectangle {
                        color: parent.hovered ? "#333333" : "transparent"
                        radius: 8
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: "#888888"
                        font.pixelSize: 24
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: root.close()
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#333333"
        }
        
        // Reply context (if replying)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: replyContextCol.implicitHeight + 24
            color: "#151515"
            visible: replyToId !== ""
            
            ColumnLayout {
                id: replyContextCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4
                
                Text {
                    text: "Replying to @" + replyToAuthor
                    color: "#9333ea"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
                
                Text {
                    Layout.fillWidth: true
                    text: replyToContent.length > 100 ? replyToContent.substring(0, 100) + "..." : replyToContent
                    color: "#888888"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }
        
        // Content area
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            
            TextArea {
                id: composeInput
                placeholderText: replyToId ? "Write your reply..." : "What's on your mind?"
                placeholderTextColor: "#666666"
                color: "#ffffff"
                font.pixelSize: 15
                wrapMode: TextEdit.Wrap
                
                background: Rectangle {
                    color: "transparent"
                }
                
                // Character count
                property int maxChars: 1000
            }
        }
        
        // Character count
        Text {
            Layout.alignment: Qt.AlignRight
            Layout.rightMargin: 16
            text: composeInput.text.length + " / " + composeInput.maxChars
            color: composeInput.text.length > composeInput.maxChars ? "#ef4444" : "#666666"
            font.pixelSize: 12
        }
        
        // Attached media preview
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            spacing: 8
            visible: root.attachedMedia.length > 0
            
            Repeater {
                model: root.attachedMedia
                
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
                                var media = root.attachedMedia.slice()
                                media.splice(index, 1)
                                root.attachedMedia = media
                            }
                        }
                    }
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#333333"
            Layout.topMargin: 8
        }
        
        // Action bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: "transparent"
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                
                // Media attach button
                Button {
                    implicitWidth: 44
                    implicitHeight: 44
                    enabled: !root.isUploading
                    
                    ToolTip.visible: hovered
                    ToolTip.text: "Attach image or video"
                    ToolTip.delay: 500
                    
                    background: Rectangle {
                        color: parent.pressed ? "#333333" : (parent.hovered ? "#252525" : "transparent")
                        radius: 8
                    }
                    
                    contentItem: Text {
                        text: "📷"
                        font.pixelSize: 20
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: fileInputDialog.open()
                }
                
                // Emoji button (placeholder)
                Button {
                    implicitWidth: 44
                    implicitHeight: 44
                    
                    ToolTip.visible: hovered
                    ToolTip.text: "Add emoji"
                    ToolTip.delay: 500
                    
                    background: Rectangle {
                        color: parent.pressed ? "#333333" : (parent.hovered ? "#252525" : "transparent")
                        radius: 8
                    }
                    
                    contentItem: Text {
                        text: "😊"
                        font.pixelSize: 20
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        // Insert a sample emoji into the text
                        composeInput.insert(composeInput.cursorPosition, "🤙")
                    }
                }
                
                Item { Layout.fillWidth: true }
                
                // Upload progress
                BusyIndicator {
                    running: root.isUploading
                    visible: running
                    implicitWidth: 32
                    implicitHeight: 32
                }
                
                // Post button
                Button {
                    text: replyToId ? "Reply" : "Post"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    implicitWidth: 100
                    implicitHeight: 44
                    enabled: composeInput.text.trim().length > 0 && 
                             composeInput.text.length <= composeInput.maxChars &&
                             !root.isUploading
                    
                    background: Rectangle {
                        color: parent.enabled ? (parent.pressed ? "#7c22c9" : "#9333ea") : "#333333"
                        radius: 8
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? "#ffffff" : "#666666"
                        font: parent.font
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        if (root.feedController) {
                            var content = composeInput.text.trim()
                            var media = root.attachedMedia
                            
                            if (replyToId) {
                                // Reply
                                root.feedController.reply_to_note(replyToId, content)
                            } else if (media.length > 0) {
                                // Post with media
                                root.feedController.post_note_with_media(content, JSON.stringify(media))
                            } else {
                                // Simple post
                                root.feedController.post_note(content)
                            }
                            
                            root.posted()
                            root.close()
                        }
                    }
                }
            }
        }
    }
    
    // File picker dialog
    FileDialog {
        id: fileInputDialog
        title: "Select Image or Video"
        nameFilters: ["Images (*.jpg *.jpeg *.png *.gif *.webp)", "Videos (*.mp4 *.webm *.mov)", "All supported (*.jpg *.jpeg *.png *.gif *.webp *.mp4 *.webm *.mov)"]
        selectedNameFilter.index: 2
        
        onAccepted: {
            var path = selectedFile.toString()
            // Remove file:// prefix for local files
            if (path.startsWith("file://")) {
                path = path.substring(7)
            }
            if (path) {
                // Upload to Blossom
                root.isUploading = true
                root.feedController.upload_media(path)
            }
        }
    }
    
    // Handle media upload completion
    Connections {
        target: feedController
        function onMedia_uploaded(url) {
            root.isUploading = false
            if (url) {
                var media = root.attachedMedia.slice()
                media.push(url)
                root.attachedMedia = media
            }
        }
        function onMedia_upload_failed(error) {
            root.isUploading = false
            console.log("Upload failed:", error)
        }
    }
}
