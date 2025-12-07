import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#0a0a0a"
    
    property var appController: null
    property var relayList: []
    
    // Load relays from config
    function loadRelays() {
        if (appController) {
            try {
                var json = appController.get_relays()
                relayList = JSON.parse(json)
            } catch (e) {
                console.log("Failed to load relays:", e)
                relayList = []
            }
        }
    }
    
    // Load relays when component is ready or appController changes
    Component.onCompleted: loadRelays()
    onAppControllerChanged: loadRelays()
    onVisibleChanged: if (visible) loadRelays()
    
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
                
                Text {
                    text: "Relays"
                    color: "#ffffff"
                    font.pixelSize: 20
                    font.weight: Font.Bold
                }
                
                Item { Layout.fillWidth: true }
                
                // Connection status summary
                Text {
                    text: root.relayList.length + " relays configured"
                    color: "#888888"
                    font.pixelSize: 13
                }
            }
        }
        
        // Content
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            
            ColumnLayout {
                width: parent.width
                spacing: 24
                
                Item { Layout.preferredHeight: 12 }
                
                // Info banner about outbox model
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    color: "#1a1a2e"
                    radius: 12
                    implicitHeight: infoBannerContent.implicitHeight + 32
                    border.color: "#9333ea40"
                    border.width: 1
                    
                    ColumnLayout {
                        id: infoBannerContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 16
                        spacing: 8
                        
                        RowLayout {
                            spacing: 8
                            
                            Text {
                                text: "📡"
                                font.pixelSize: 16
                            }
                            
                            Text {
                                text: "Outbox Model (NIP-65)"
                                color: "#9333ea"
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }
                        }
                        
                        Text {
                            text: "Pleb Client automatically discovers which relays other users publish to and fetches content from those relays. Your configured relays are where your posts will be published."
                            color: "#888888"
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            lineHeight: 1.4
                        }
                    }
                }
                
                // Your Relays section
                RelaySection {
                    title: "Your Relays"
                    description: "Where your posts are published"
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        
                        // Relay list
                        Repeater {
                            model: root.relayList
                            
                            delegate: RelayItem {
                                relayUrl: modelData
                                onRemove: {
                                    if (root.appController) {
                                        root.appController.remove_relay(modelData)
                                        root.loadRelays()
                                    }
                                }
                            }
                        }
                        
                        // Empty state
                        Rectangle {
                            visible: root.relayList.length === 0
                            Layout.fillWidth: true
                            height: 80
                            color: "#151515"
                            radius: 8
                            border.color: "#333333"
                            border.width: 1
                            
                            Text {
                                anchors.centerIn: parent
                                text: "No relays configured\nAdd a relay below to get started"
                                color: "#666666"
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                lineHeight: 1.4
                            }
                        }
                        
                        // Add relay input
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 8
                            
                            TextField {
                                id: newRelayInput
                                Layout.fillWidth: true
                                placeholderText: "wss://relay.example.com"
                                color: "#ffffff"
                                font.pixelSize: 14
                                
                                background: Rectangle {
                                    color: "#0a0a0a"
                                    radius: 8
                                    border.color: newRelayInput.activeFocus ? "#9333ea" : "#333333"
                                    border.width: 1
                                }
                                
                                leftPadding: 12
                                rightPadding: 12
                                topPadding: 12
                                bottomPadding: 12
                                
                                Keys.onReturnPressed: addRelayBtn.clicked()
                                Keys.onEnterPressed: addRelayBtn.clicked()
                            }
                            
                            Button {
                                id: addRelayBtn
                                text: "Add Relay"
                                implicitWidth: 100
                                implicitHeight: 44
                                
                                ToolTip.visible: hovered
                                ToolTip.text: "Add relay to your list"
                                ToolTip.delay: 500
                                
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
                                
                                enabled: newRelayInput.text.trim() !== ""
                                
                                onClicked: {
                                    if (root.appController) {
                                        var url = newRelayInput.text.trim()
                                        // Auto-add wss:// if missing
                                        if (!url.startsWith("wss://") && !url.startsWith("ws://")) {
                                            url = "wss://" + url
                                        }
                                        if (root.appController.add_relay(url)) {
                                            newRelayInput.text = ""
                                            root.loadRelays()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Popular Relays section
                RelaySection {
                    title: "Popular Relays"
                    description: "Quick add commonly used relays"
                    
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        
                        Repeater {
                            model: [
                                "wss://relay.damus.io",
                                "wss://nos.lol",
                                "wss://relay.primal.net",
                                "wss://relay.snort.social",
                                "wss://nostr.wine",
                                "wss://relay.nostr.band",
                                "wss://purplepag.es",
                                "wss://relay.nos.social"
                            ]
                            
                            delegate: Button {
                                property bool alreadyAdded: root.relayList.indexOf(modelData) !== -1
                                
                                text: modelData.replace("wss://", "") + (alreadyAdded ? " ✓" : "")
                                implicitHeight: 36
                                enabled: !alreadyAdded
                                
                                ToolTip.visible: hovered && !alreadyAdded
                                ToolTip.text: "Add " + modelData
                                ToolTip.delay: 500
                                
                                background: Rectangle {
                                    color: alreadyAdded ? "#1a2e1a" : (parent.pressed ? "#333333" : (parent.hovered ? "#252525" : "#1a1a1a"))
                                    radius: 18
                                    border.color: alreadyAdded ? "#22c55e40" : "#333333"
                                    border.width: 1
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    color: alreadyAdded ? "#22c55e" : "#ffffff"
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: {
                                    if (root.appController && !alreadyAdded) {
                                        if (root.appController.add_relay(modelData)) {
                                            root.loadRelays()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Actions section
                RelaySection {
                    title: "Actions"
                    description: "Manage your relay configuration"
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        
                        Button {
                            text: "Reset to Defaults"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            
                            ToolTip.visible: hovered
                            ToolTip.text: "Reset to the default relay list"
                            ToolTip.delay: 500
                            
                            background: Rectangle {
                                color: parent.pressed ? "#333333" : "#252525"
                                radius: 8
                                border.color: "#404040"
                                border.width: 1
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#888888"
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            onClicked: {
                                if (root.appController) {
                                    root.appController.reset_relays_to_default()
                                    root.loadRelays()
                                }
                            }
                        }
                        
                        Button {
                            text: "Clear All"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            
                            ToolTip.visible: hovered
                            ToolTip.text: "Remove all relays"
                            ToolTip.delay: 500
                            
                            background: Rectangle {
                                color: parent.pressed ? "#7f1d1d" : "#2e1a1a"
                                radius: 8
                                border.color: "#dc262640"
                                border.width: 1
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#dc2626"
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            onClicked: {
                                // Remove all relays one by one
                                if (root.appController) {
                                    var relaysCopy = root.relayList.slice()
                                    for (var i = 0; i < relaysCopy.length; i++) {
                                        root.appController.remove_relay(relaysCopy[i])
                                    }
                                    root.loadRelays()
                                }
                            }
                        }
                    }
                }
                
                Item { Layout.preferredHeight: 40 }
            }
        }
    }
    
    // Section component
    component RelaySection: ColumnLayout {
        property string title: ""
        property string description: ""
        default property alias content: contentColumn.data
        
        Layout.fillWidth: true
        Layout.leftMargin: 20
        Layout.rightMargin: 20
        spacing: 12
        
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            
            Text {
                text: title.toUpperCase()
                color: "#888888"
                font.pixelSize: 12
                font.weight: Font.Medium
                font.letterSpacing: 1
            }
            
            Text {
                text: description
                color: "#555555"
                font.pixelSize: 12
                visible: description !== ""
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            color: "#111111"
            radius: 12
            implicitHeight: contentColumn.implicitHeight + 32
            
            ColumnLayout {
                id: contentColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 12
            }
        }
    }
    
    // Relay item component
    component RelayItem: Rectangle {
        property string relayUrl: ""
        signal remove()
        
        Layout.fillWidth: true
        height: 52
        color: relayMouseArea.containsMouse ? "#1f1f1f" : "#1a1a1a"
        radius: 8
        
        Behavior on color {
            ColorAnimation { duration: 100 }
        }
        
        MouseArea {
            id: relayMouseArea
            anchors.fill: parent
            hoverEnabled: true
        }
        
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: 12
            
            // Status indicator
            Rectangle {
                width: 10
                height: 10
                radius: 5
                color: "#22c55e"  // Green for connected
                
                // Pulse animation
                SequentialAnimation on opacity {
                    running: true
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.5; duration: 1500; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 0.5; to: 1.0; duration: 1500; easing.type: Easing.InOutQuad }
                }
            }
            
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                
                Text {
                    Layout.fillWidth: true
                    text: relayUrl.replace("wss://", "").replace("ws://", "")
                    color: "#ffffff"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                
                Text {
                    text: relayUrl.startsWith("wss://") ? "Secure WebSocket" : "WebSocket"
                    color: "#666666"
                    font.pixelSize: 11
                }
            }
            
            Button {
                implicitWidth: 36
                implicitHeight: 36
                text: "✕"
                
                ToolTip.visible: hovered
                ToolTip.text: "Remove relay"
                ToolTip.delay: 500
                
                background: Rectangle {
                    color: parent.pressed ? "#7f1d1d" : (parent.hovered ? "#991b1b" : "transparent")
                    radius: 8
                }
                
                contentItem: Text {
                    text: parent.text
                    color: parent.hovered ? "#ffffff" : "#666666"
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: remove()
            }
        }
    }
}
