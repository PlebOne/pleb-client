import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    color: "#0a0a0a"
    
    property var dmController: null
    property var appController: null
    
    // Initialize when visible and controllers are ready
    onVisibleChanged: {
        if (visible && dmController && appController && appController.public_key.toString() !== "") {
            console.log("[DEBUG] DmScreen visible, initializing DM controller")
            dmController.initialize(appController.public_key)
            dmController.load_conversations()
        }
    }
    
    // Connect to DM controller signals
    Connections {
        target: dmController
        ignoreUnknownSignals: true
        
        function onConversations_updated() {
            console.log("[DEBUG] Conversations updated, count:", dmController ? dmController.conversation_count : 0)
            conversationList.model = dmController ? dmController.conversation_count : 0
        }
        
        function onMessages_updated() {
            console.log("[DEBUG] Messages updated")
            if (dmController) {
                var json = dmController.get_messages()
                messageList.model = JSON.parse(json)
            }
        }
        
        function onMessage_sent(messageId) {
            console.log("[DEBUG] Message sent:", messageId)
        }
        
        function onError_occurred(error) {
            console.log("[DEBUG] DM error:", error)
        }
    }
    
    RowLayout {
        anchors.fill: parent
        spacing: 0
        
        // Conversation list
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 320
            color: "#111111"
            
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
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        
                        Text {
                            text: "Messages"
                            color: "#ffffff"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        // Refresh button
                        Button {
                            text: "↻"
                            font.pixelSize: 18
                            
                            ToolTip.visible: hovered
                            ToolTip.text: "Refresh messages"
                            ToolTip.delay: 500
                            
                            background: Rectangle {
                                color: parent.pressed ? "#333333" : "transparent"
                                radius: 8
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#888888"
                                font: parent.font
                            }
                            
                            onClicked: {
                                if (dmController) dmController.refresh()
                            }
                        }
                        
                        Button {
                            text: "+"
                            font.pixelSize: 20
                            
                            ToolTip.visible: hovered
                            ToolTip.text: "Start new conversation"
                            ToolTip.delay: 500
                            
                            background: Rectangle {
                                color: parent.pressed ? "#333333" : "transparent"
                                radius: 8
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#9333ea"
                                font: parent.font
                            }
                            
                            onClicked: newConvoDialog.open()
                        }
                    }
                }
                
                // Loading indicator
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    color: "#1a1a1a"
                    visible: dmController && dmController.is_loading
                    
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        
                        BusyIndicator {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            running: parent.visible
                        }
                        
                        Text {
                            text: "Loading..."
                            color: "#888888"
                            font.pixelSize: 13
                        }
                    }
                }
                
                // Category tabs
                Rectangle {
                    id: categoryTabBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    color: "#0d0d0d"
                    
                    property var categoryCounts: ({all: 0, favorites: 0, unfiltered: 0, regular: 0, archive: 0})
                    property string currentCategory: "all"
                    
                    Component.onCompleted: updateCounts()
                    
                    function updateCounts() {
                        if (dmController) {
                            try {
                                var json = dmController.get_category_counts()
                                categoryCounts = JSON.parse(json)
                            } catch (e) {
                                console.log("Failed to parse category counts:", e)
                            }
                        }
                    }
                    
                    Connections {
                        target: dmController
                        ignoreUnknownSignals: true
                        
                        function onConversations_updated() {
                            categoryTabBar.updateCounts()
                        }
                    }
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 2
                        
                        // Inbox tab (regular conversations not in other categories)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.topMargin: 4
                            Layout.bottomMargin: 4
                            color: parent.parent.currentCategory === "all" ? "#2a2a2a" : "transparent"
                            radius: 6
                            
                            Text {
                                anchors.centerIn: parent
                                text: "📥 " + parent.parent.parent.categoryCounts.all
                                color: parent.parent.parent.currentCategory === "all" ? "#ffffff" : "#888888"
                                font.pixelSize: 11
                                font.weight: parent.parent.parent.currentCategory === "all" ? Font.Medium : Font.Normal
                            }
                            
                            ToolTip.visible: ma0.containsMouse
                            ToolTip.text: "Inbox - conversations not in other categories"
                            ToolTip.delay: 500
                            
                            MouseArea {
                                id: ma0
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: {
                                    parent.parent.parent.currentCategory = "all"
                                    if (dmController) dmController.set_category_filter("all")
                                }
                            }
                        }
                        
                        // Favorites tab
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.topMargin: 4
                            Layout.bottomMargin: 4
                            color: parent.parent.currentCategory === "favorites" ? "#2a2a2a" : "transparent"
                            radius: 6
                            
                            Text {
                                anchors.centerIn: parent
                                text: "⭐ " + parent.parent.parent.categoryCounts.favorites
                                color: parent.parent.parent.currentCategory === "favorites" ? "#fbbf24" : "#888888"
                                font.pixelSize: 11
                                font.weight: parent.parent.parent.currentCategory === "favorites" ? Font.Medium : Font.Normal
                            }
                            
                            ToolTip.visible: ma1.containsMouse
                            ToolTip.text: "Favorites"
                            ToolTip.delay: 500
                            
                            MouseArea {
                                id: ma1
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: {
                                    parent.parent.parent.currentCategory = "favorites"
                                    if (dmController) dmController.set_category_filter("favorites")
                                }
                            }
                        }
                        
                        // Unfiltered tab (new/never replied)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.topMargin: 4
                            Layout.bottomMargin: 4
                            color: parent.parent.currentCategory === "unfiltered" ? "#2a2a2a" : "transparent"
                            radius: 6
                            
                            Text {
                                anchors.centerIn: parent
                                text: "📬 " + parent.parent.parent.categoryCounts.unfiltered
                                color: parent.parent.parent.currentCategory === "unfiltered" ? "#60a5fa" : "#888888"
                                font.pixelSize: 11
                                font.weight: parent.parent.parent.currentCategory === "unfiltered" ? Font.Medium : Font.Normal
                            }
                            
                            ToolTip.visible: ma2.containsMouse
                            ToolTip.text: "Unfiltered (never replied)"
                            ToolTip.delay: 500
                            
                            MouseArea {
                                id: ma2
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: {
                                    parent.parent.parent.currentCategory = "unfiltered"
                                    if (dmController) dmController.set_category_filter("unfiltered")
                                }
                            }
                        }
                        
                        // Archive tab
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.topMargin: 4
                            Layout.bottomMargin: 4
                            color: parent.parent.currentCategory === "archive" ? "#2a2a2a" : "transparent"
                            radius: 6
                            
                            Text {
                                anchors.centerIn: parent
                                text: "🗄️ " + parent.parent.parent.categoryCounts.archive
                                color: parent.parent.parent.currentCategory === "archive" ? "#a78bfa" : "#888888"
                                font.pixelSize: 11
                                font.weight: parent.parent.parent.currentCategory === "archive" ? Font.Medium : Font.Normal
                            }
                            
                            ToolTip.visible: ma3.containsMouse
                            ToolTip.text: "Archive"
                            ToolTip.delay: 500
                            
                            MouseArea {
                                id: ma3
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: {
                                    parent.parent.parent.currentCategory = "archive"
                                    if (dmController) dmController.set_category_filter("archive")
                                }
                            }
                        }
                    }
                }
                
                // Conversation list
                ListView {
                    id: conversationList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    
                    model: dmController ? dmController.conversation_count : 0
                    
                    delegate: Rectangle {
                        id: convoDelegate
                        width: conversationList.width
                        height: 70
                        color: convoData && dmController && dmController.selected_conversation.toString() === convoData.peerPubkey 
                            ? "#1a1a1a" : "transparent"
                        
                        property var convoData: null
                        
                        Component.onCompleted: {
                            if (dmController) {
                                var json = dmController.get_conversation(index)
                                try {
                                    convoData = JSON.parse(json)
                                } catch (e) {
                                    console.log("Failed to parse conversation:", e)
                                }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    categoryMenu.popup()
                                } else if (dmController && convoData) {
                                    dmController.select_conversation(convoData.peerPubkey)
                                }
                            }
                        }
                        
                        // Category context menu
                        Menu {
                            id: categoryMenu
                            
                            MenuItem {
                                text: "⭐ Add to Favorites"
                                onTriggered: {
                                    if (dmController && convoDelegate.convoData) {
                                        dmController.set_conversation_category(convoDelegate.convoData.peerPubkey, "favorites")
                                    }
                                }
                            }
                            MenuItem {
                                text: "📥 Move to Inbox"
                                onTriggered: {
                                    if (dmController && convoDelegate.convoData) {
                                        dmController.set_conversation_category(convoDelegate.convoData.peerPubkey, "regular")
                                    }
                                }
                            }
                            MenuItem {
                                text: "🗄️ Archive"
                                onTriggered: {
                                    if (dmController && convoDelegate.convoData) {
                                        dmController.set_conversation_category(convoDelegate.convoData.peerPubkey, "archive")
                                    }
                                }
                            }
                        }
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12
                            
                            ProfileAvatar {
                                Layout.preferredWidth: 46
                                Layout.preferredHeight: 46
                                name: convoDelegate.convoData ? convoDelegate.convoData.peerName || "?" : "?"
                                imageUrl: convoDelegate.convoData ? convoDelegate.convoData.peerPicture || "" : ""
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                
                                Text {
                                    text: convoDelegate.convoData ? convoDelegate.convoData.peerName || "Unknown" : "Unknown"
                                    color: "#ffffff"
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                
                                Text {
                                    text: convoDelegate.convoData ? convoDelegate.convoData.lastMessage || "" : ""
                                    color: "#888888"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            
                            ColumnLayout {
                                spacing: 4
                                
                                // Protocol badge
                                Rectangle {
                                    Layout.preferredHeight: 16
                                    Layout.preferredWidth: protocolBadgeText.width + 8
                                    radius: 4
                                    color: convoDelegate.convoData && convoDelegate.convoData.protocol === "NIP-04" ? "#3b2a1a" : "#1a2a3b"
                                    visible: convoDelegate.convoData && convoDelegate.convoData.protocol
                                    
                                    Text {
                                        id: protocolBadgeText
                                        anchors.centerIn: parent
                                        text: convoDelegate.convoData ? convoDelegate.convoData.protocol : ""
                                        color: convoDelegate.convoData && convoDelegate.convoData.protocol === "NIP-04" ? "#f59e0b" : "#22c55e"
                                        font.pixelSize: 9
                                        font.weight: Font.Medium
                                    }
                                }
                                
                                // Unread badge
                                Rectangle {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    Layout.alignment: Qt.AlignRight
                                    radius: 10
                                    color: "#9333ea"
                                    visible: convoDelegate.convoData && convoDelegate.convoData.unreadCount > 0
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: convoDelegate.convoData ? convoDelegate.convoData.unreadCount : ""
                                        color: "#ffffff"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                        }
                    }
                    
                    // Empty state
                    Text {
                        anchors.centerIn: parent
                        text: "No conversations yet\nStart a new conversation!"
                        color: "#666666"
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        visible: conversationList.count === 0 && !(dmController && dmController.is_loading)
                    }
                }
            }
        }
        
        // Separator
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: "#2a2a2a"
        }
        
        // Chat area
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#0a0a0a"
            
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                visible: dmController && dmController.selected_conversation !== ""
                
                // Chat header
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    color: "#111111"
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        
                        Text {
                            text: "Chat"
                            color: "#ffffff"
                            font.pixelSize: 16
                            font.weight: Font.Medium
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        // Protocol indicator (shows send protocol, click to toggle)
                        Rectangle {
                            Layout.preferredHeight: 24
                            Layout.preferredWidth: protocolRow.width + 16
                            radius: 12
                            color: dmController && dmController.get_protocol() === "NIP-04" ? "#3b2a1a" : "#1a2a3b"
                            
                            RowLayout {
                                id: protocolRow
                                anchors.centerIn: parent
                                spacing: 4
                                
                                Text {
                                    text: "↑"
                                    color: "#666666"
                                    font.pixelSize: 9
                                }
                                
                                Text {
                                    id: protocolText
                                    text: dmController ? dmController.get_protocol() : "NIP-17"
                                    color: dmController && dmController.get_protocol() === "NIP-04" ? "#f59e0b" : "#22c55e"
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dmController.toggle_protocol()
                            }
                            
                            ToolTip.visible: hovered
                            ToolTip.text: "Click to switch send protocol\nNIP-04: Legacy (widely supported)\nNIP-17: Modern (more private)"
                            ToolTip.delay: 500
                            
                            property bool hovered: false
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: parent.hovered = true
                                onExited: parent.hovered = false
                                onClicked: dmController.toggle_protocol()
                            }
                        }
                    }
                }
                
                // Messages
                ListView {
                    id: messageList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    leftMargin: 16
                    rightMargin: 16
                    topMargin: 16
                    bottomMargin: 16
                    verticalLayoutDirection: ListView.BottomToTop
                    
                    model: {
                        if (!dmController) return []
                        var json = dmController.get_messages()
                        return JSON.parse(json)
                    }
                    
                    delegate: Rectangle {
                        width: Math.min(messageList.width - 100, messageText.implicitWidth + 32)
                        height: messageText.height + 24
                        radius: 16
                        color: modelData.isOutgoing ? "#9333ea" : "#1a1a1a"
                        anchors.right: modelData.isOutgoing ? parent.right : undefined
                        anchors.left: modelData.isOutgoing ? undefined : parent.left
                        
                        Text {
                            id: messageText
                            anchors.centerIn: parent
                            width: parent.width - 32
                            text: modelData.content
                            color: "#ffffff"
                            font.pixelSize: 14
                            wrapMode: Text.WordWrap
                        }
                    }
                }
                
                // Compose
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    color: "#111111"
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12
                        
                        TextField {
                            id: dmInput
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            placeholderText: "Type a message..."
                            color: "#ffffff"
                            font.pixelSize: 14
                            
                            background: Rectangle {
                                color: "#1a1a1a"
                                radius: 8
                                border.color: dmInput.activeFocus ? "#9333ea" : "#333333"
                                border.width: 1
                            }
                            
                            leftPadding: 16
                            rightPadding: 16
                            
                            Keys.onReturnPressed: sendButton.clicked()
                        }
                        
                        Button {
                            id: sendButton
                            text: "Send"
                            Layout.preferredHeight: parent.height
                            Layout.preferredWidth: 70
                            
                            ToolTip.visible: hovered
                            ToolTip.text: "Send message (Enter)"
                            ToolTip.delay: 500
                            
                            background: Rectangle {
                                color: parent.enabled ? "#9333ea" : "#333333"
                                radius: 8
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            enabled: dmInput.text.trim() !== ""
                            
                            onClicked: {
                                if (dmController) {
                                    dmController.send_message(dmInput.text.trim())
                                    dmInput.text = ""
                                }
                            }
                        }
                    }
                }
            }
            
            // No conversation selected
            Text {
                anchors.centerIn: parent
                text: "Select a conversation"
                color: "#666666"
                font.pixelSize: 16
                visible: !dmController || dmController.selected_conversation === ""
            }
        }
    }
    
    // New conversation dialog
    Dialog {
        id: newConvoDialog
        title: "New Conversation"
        modal: true
        anchors.centerIn: parent
        width: 400
        
        background: Rectangle {
            color: "#1a1a1a"
            radius: 12
        }
        
        ColumnLayout {
            anchors.fill: parent
            spacing: 16
            
            Text {
                text: "Enter npub or public key"
                color: "#888888"
                font.pixelSize: 14
            }
            
            TextField {
                id: newPubkeyInput
                Layout.fillWidth: true
                placeholderText: "npub1..."
                color: "#ffffff"
                font.pixelSize: 14
                
                background: Rectangle {
                    color: "#0a0a0a"
                    radius: 8
                    border.color: newPubkeyInput.activeFocus ? "#9333ea" : "#333333"
                    border.width: 1
                }
                
                leftPadding: 16
                rightPadding: 16
                topPadding: 12
                bottomPadding: 12
            }
        }
        
        standardButtons: Dialog.Cancel | Dialog.Ok
        
        onAccepted: {
            if (dmController && newPubkeyInput.text.trim() !== "") {
                dmController.start_conversation(newPubkeyInput.text.trim())
                newPubkeyInput.text = ""
            }
        }
    }
}
