import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Link preview card for displaying OpenGraph metadata from URLs
Rectangle {
    id: root
    color: "#252525"
    radius: 8
    border.color: "#333333"
    border.width: 1
    implicitHeight: contentCol.implicitHeight + 16
    
    property string url: ""
    property var previewData: null
    property bool isLoading: false
    property bool hasError: false
    property var feedController: null
    property int retryCount: 0
    property int maxRetries: 5
    
    Component.onCompleted: {
        if (url && !previewData) {
            loadPreview()
        }
    }
    
    onUrlChanged: {
        previewData = null
        retryCount = 0
        hasError = false
        if (url) {
            loadPreview()
        }
    }
    
    // Timer to retry loading from cache
    Timer {
        id: retryTimer
        interval: 500
        repeat: true
        running: isLoading && retryCount < maxRetries
        onTriggered: {
            retryCount++
            loadPreview()
        }
    }
    
    function loadPreview() {
        if (!url || !feedController) return
        
        // Skip media URLs
        var lower = url.toLowerCase()
        if (lower.match(/\.(jpg|jpeg|png|gif|webp|mp4|webm|mov)$/)) {
            hasError = true
            return
        }
        
        isLoading = true
        hasError = false
        
        var result = feedController.fetch_link_preview(url)
        if (result && result !== "{}") {
            try {
                previewData = JSON.parse(result)
                isLoading = false
                retryTimer.stop()
                
                // Check if we got useful data
                if (!previewData.title && !previewData.description && !previewData.image) {
                    hasError = true
                }
            } catch (e) {
                console.warn("Failed to parse link preview:", e)
                hasError = true
                isLoading = false
            }
        } else if (retryCount >= maxRetries) {
            hasError = true
            isLoading = false
        }
    }
    
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Qt.openUrlExternally(url)
    }
    
    visible: !hasError && (isLoading || previewData)
    
    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: 0
        spacing: 0
        
        // Loading state
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            visible: isLoading
            spacing: 8
            
            BusyIndicator {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                running: isLoading
            }
            
            Text {
                text: "Loading preview..."
                color: "#888888"
                font.pixelSize: 12
            }
        }
        
        // Preview content
        ColumnLayout {
            Layout.fillWidth: true
            visible: previewData && !isLoading
            spacing: 0
            
            // Preview image - uses aspect ratio fit to avoid cropping
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: previewImage.status === Image.Ready ? 
                    Math.min(previewImage.implicitHeight * (width / previewImage.implicitWidth), 250) : 
                    (previewData?.image ? 150 : 0)
                Layout.maximumHeight: 250
                color: "#2a2a2a"
                visible: !!(previewData?.image)
                clip: true
                
                Image {
                    id: previewImage
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    source: previewData?.image || ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    
                    Rectangle {
                        anchors.fill: parent
                        color: "#2a2a2a"
                        visible: parent.status === Image.Loading
                        
                        BusyIndicator {
                            anchors.centerIn: parent
                            running: parent.visible
                            width: 20
                            height: 20
                        }
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        color: "#2a2a2a"
                        visible: parent.status === Image.Error
                    }
                }
            }
            
            // Text content
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 10
                spacing: 4
                
                // Site name
                Text {
                    text: previewData?.siteName || extractDomain(url)
                    color: "#888888"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    visible: text !== ""
                }
                
                // Title
                Text {
                    text: previewData?.title || ""
                    color: "#ffffff"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    visible: text !== ""
                }
                
                // Description
                Text {
                    text: previewData?.description || ""
                    color: "#aaaaaa"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    visible: text !== ""
                }
            }
        }
    }
    
    function extractDomain(urlStr) {
        try {
            var match = urlStr.match(/^https?:\/\/([^\/]+)/i)
            return match ? match[1] : ""
        } catch (e) {
            return ""
        }
    }
}
