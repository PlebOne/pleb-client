import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// GIF Picker - Search and select GIFs from Tenor
// Re-uploads selected GIFs to NIP-96 server for privacy
Popup {
    id: root
    
    property var feedController: null
    property bool isBridging: false
    property string searchQuery: ""
    property var gifResults: []
    property string selectedGifUrl: ""
    
    signal gifSelected(string url)
    
    width: Math.min(500, parent.width - 40)
    height: Math.min(450, parent.height - 100)
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
    
    onOpened: {
        searchInput.text = ""
        gifResults = []
        isBridging = false
        selectedGifUrl = ""
        searchInput.forceActiveFocus()
        
        // Load trending GIFs on open
        if (feedController && feedController.has_tenor_api_key()) {
            loadTrending()
        }
    }
    
    function loadTrending() {
        if (!feedController) return
        
        var result = feedController.get_trending_gifs()
        try {
            var data = JSON.parse(result)
            if (data.error) {
                console.log("Tenor error:", data.error)
                gifResults = []
            } else {
                gifResults = data
            }
        } catch (e) {
            console.log("Failed to parse trending:", e)
            gifResults = []
        }
    }
    
    function searchGifs() {
        if (!feedController || searchQuery.trim().length === 0) {
            loadTrending()
            return
        }
        
        var result = feedController.search_gifs(searchQuery)
        try {
            var data = JSON.parse(result)
            if (data.error) {
                console.log("Tenor search error:", data.error)
                gifResults = []
            } else {
                gifResults = data
            }
        } catch (e) {
            console.log("Failed to parse search results:", e)
            gifResults = []
        }
    }
    
    function selectGif(gif) {
        if (isBridging) return
        
        selectedGifUrl = gif.url
        isBridging = true
        
        // Bridge the GIF (download from Tenor, re-upload to NIP-96)
        feedController.bridge_gif(gif.url)
    }
    
    // Handle bridge completion
    Connections {
        target: feedController
        ignoreUnknownSignals: true
        
        function onGif_bridged(url) {
            if (isBridging) {
                isBridging = false
                selectedGifUrl = ""
                root.gifSelected(url)
                root.close()
            }
        }
        
        function onGif_bridge_failed(error) {
            if (isBridging) {
                isBridging = false
                selectedGifUrl = ""
                console.log("GIF bridge failed:", error)
                // Could show error toast here
            }
        }
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
                spacing: 12
                
                Text {
                    text: "🎬 GIFs"
                    color: "#ffffff"
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
                
                Item { Layout.fillWidth: true }
                
                // Powered by Tenor
                Text {
                    text: "Powered by Tenor"
                    color: "#666666"
                    font.pixelSize: 11
                }
                
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
        
        // Search bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            Layout.margins: 12
            Layout.bottomMargin: 0
            color: "#252525"
            radius: 8
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                
                Text {
                    text: "🔍"
                    font.pixelSize: 16
                    color: "#666666"
                }
                
                TextField {
                    id: searchInput
                    Layout.fillWidth: true
                    placeholderText: "Search GIFs..."
                    placeholderTextColor: "#666666"
                    color: "#ffffff"
                    font.pixelSize: 14
                    
                    background: Rectangle {
                        color: "transparent"
                    }
                    
                    onTextChanged: {
                        searchQuery = text
                        searchTimer.restart()
                    }
                    
                    Keys.onReturnPressed: {
                        searchTimer.stop()
                        searchGifs()
                    }
                }
                
                BusyIndicator {
                    implicitWidth: 20
                    implicitHeight: 20
                    running: isBridging
                    visible: isBridging
                }
            }
        }
        
        // Debounce timer for search
        Timer {
            id: searchTimer
            interval: 500
            onTriggered: searchGifs()
        }
        
        // No API key warning
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            Layout.margins: 12
            color: "#2a1a1a"
            radius: 8
            visible: feedController && !feedController.has_tenor_api_key()
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                
                Text {
                    text: "⚠️"
                    font.pixelSize: 20
                }
                
                Text {
                    Layout.fillWidth: true
                    text: "Tenor API key not configured. Add it in Settings to enable GIF search."
                    color: "#ff9999"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
            }
        }
        
        // GIF grid
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 12
            clip: true
            
            GridView {
                id: gifGrid
                anchors.fill: parent
                cellWidth: (root.width - 48) / 3
                cellHeight: cellWidth
                model: gifResults
                
                delegate: Rectangle {
                    width: gifGrid.cellWidth - 4
                    height: gifGrid.cellHeight - 4
                    color: "#252525"
                    radius: 8
                    clip: true
                    
                    // Selection overlay for bridging
                    Rectangle {
                        anchors.fill: parent
                        color: "#9333ea"
                        opacity: selectedGifUrl === modelData.url ? 0.5 : 0
                        radius: 8
                        z: 2
                    }
                    
                    AnimatedImage {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: modelData.preview_url
                        fillMode: Image.PreserveAspectCrop
                        playing: true
                        asynchronous: true
                        
                        BusyIndicator {
                            anchors.centerIn: parent
                            running: parent.status === AnimatedImage.Loading
                            visible: running
                            implicitWidth: 24
                            implicitHeight: 24
                        }
                    }
                    
                    // Processing indicator
                    Rectangle {
                        anchors.fill: parent
                        color: "#000000"
                        opacity: selectedGifUrl === modelData.url && isBridging ? 0.7 : 0
                        radius: 8
                        z: 3
                        
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            
                            BusyIndicator {
                                anchors.horizontalCenter: parent.horizontalCenter
                                running: true
                                implicitWidth: 32
                                implicitHeight: 32
                            }
                            
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Uploading..."
                                color: "#ffffff"
                                font.pixelSize: 11
                            }
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: !isBridging
                        
                        onClicked: selectGif(modelData)
                    }
                }
            }
        }
        
        // Empty state
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: gifResults.length === 0 && feedController && feedController.has_tenor_api_key()
            text: searchQuery.length > 0 ? "No GIFs found" : "Search for GIFs above"
            color: "#666666"
            font.pixelSize: 14
        }
        
        // Privacy notice
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            color: "#151515"
            
            Text {
                anchors.centerIn: parent
                text: "🔒 GIFs are re-uploaded for privacy - Google won't see your posts"
                color: "#666666"
                font.pixelSize: 11
            }
        }
    }
}
