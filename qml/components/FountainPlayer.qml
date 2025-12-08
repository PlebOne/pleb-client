import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

// Fountain.fm podcast player - plays audio/video in-client
Rectangle {
    id: root
    color: "#252525"
    radius: 8
    clip: true
    implicitHeight: isPlaying ? 280 : contentColumn.implicitHeight + 16
    
    property string url: ""
    property var feedController: null
    property var previewData: null
    property bool isLoading: false
    property bool hasError: false
    property bool isPlaying: false
    property int retryCount: 0
    property int maxRetries: 5
    
    // Check if URL is a Fountain.fm URL
    function isFountainUrl(urlStr) {
        if (!urlStr) return false
        var lower = urlStr.toLowerCase()
        return lower.includes("fountain.fm/episode") || lower.includes("fountain.fm/show")
    }
    
    Component.onCompleted: {
        if (url && !previewData) {
            loadPreview()
        }
    }
    
    onUrlChanged: {
        previewData = null
        retryCount = 0
        hasError = false
        isPlaying = false
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
        
        isLoading = true
        hasError = false
        
        var result = feedController.fetch_link_preview(url)
        if (result && result !== "{}") {
            try {
                previewData = JSON.parse(result)
                isLoading = false
                retryTimer.stop()
                
                // Check if we got audio/video data (required for Fountain)
                if (!previewData.audio && !previewData.video) {
                    // Fountain pages always have audio, keep retrying
                    if (retryCount >= maxRetries) {
                        hasError = true
                    }
                }
            } catch (e) {
                console.warn("Failed to parse Fountain preview:", e)
                if (retryCount >= maxRetries) {
                    hasError = true
                    isLoading = false
                }
            }
        } else if (retryCount >= maxRetries) {
            hasError = true
            isLoading = false
        }
    }
    
    // Media player for audio playback
    MediaPlayer {
        id: mediaPlayer
        source: isPlaying && previewData ? (previewData.audio || previewData.video || "") : ""
        audioOutput: AudioOutput {
            id: audioOutput
            volume: volumeSlider.value
        }
        videoOutput: videoOutput
        
        onErrorOccurred: (error, errorString) => {
            console.log("Fountain playback error:", errorString)
        }
        
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia) {
                isPlaying = false
            }
        }
    }
    
    // Video output (for video podcasts)
    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        visible: isPlaying && previewData && previewData.video
        fillMode: VideoOutput.PreserveAspectFit
    }
    
    // Content column (preview mode)
    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: 0
        spacing: 0
        visible: !isPlaying
        
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
                text: "Loading podcast..."
                color: "#888888"
                font.pixelSize: 12
            }
        }
        
        // Preview content
        ColumnLayout {
            Layout.fillWidth: true
            visible: previewData && !isLoading
            spacing: 0
            
            // Podcast cover art with play overlay
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: previewData?.image ? 180 : 0
                color: "#1a1a1a"
                visible: !!(previewData?.image)
                clip: true
                
                Image {
                    id: coverArt
                    anchors.fill: parent
                    source: previewData?.image || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    
                    Rectangle {
                        anchors.fill: parent
                        color: "#2a2a2a"
                        visible: parent.status === Image.Loading
                        
                        BusyIndicator {
                            anchors.centerIn: parent
                            running: parent.visible
                            width: 24
                            height: 24
                        }
                    }
                }
                
                // Dark overlay for better visibility
                Rectangle {
                    anchors.fill: parent
                    color: "#40000000"
                }
                
                // Play button overlay
                Rectangle {
                    id: playButton
                    anchors.centerIn: parent
                    width: 64
                    height: 64
                    radius: 32
                    color: playButtonArea.containsMouse ? "#9333ea" : "#7928ca"
                    
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                    
                    Text {
                        anchors.centerIn: parent
                        text: "▶"
                        color: "#ffffff"
                        font.pixelSize: 24
                    }
                    
                    MouseArea {
                        id: playButtonArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        
                        onClicked: {
                            if (previewData && (previewData.audio || previewData.video)) {
                                isPlaying = true
                                mediaPlayer.play()
                            } else {
                                // Fallback to external if no audio URL
                                Qt.openUrlExternally(root.url)
                            }
                        }
                    }
                }
                
                // Fountain branding
                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    width: fountainLabel.implicitWidth + 16
                    height: 24
                    radius: 4
                    color: "#cc000000"
                    
                    RowLayout {
                        id: fountainLabel
                        anchors.centerIn: parent
                        spacing: 4
                        
                        Text {
                            text: "🎙"
                            font.pixelSize: 12
                        }
                        
                        Text {
                            text: "Fountain"
                            color: "#ffffff"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }
                
                // Open externally button
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    width: externalRow.implicitWidth + 12
                    height: 24
                    radius: 4
                    color: externalArea.containsMouse ? "#80ffffff" : "#60000000"
                    
                    RowLayout {
                        id: externalRow
                        anchors.centerIn: parent
                        spacing: 4
                        
                        Text {
                            text: "↗"
                            color: "#ffffff"
                            font.pixelSize: 12
                        }
                        
                        Text {
                            text: "Open"
                            color: "#ffffff"
                            font.pixelSize: 10
                        }
                    }
                    
                    MouseArea {
                        id: externalArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        
                        onClicked: {
                            Qt.openUrlExternally(root.url)
                        }
                    }
                    
                    ToolTip.visible: externalArea.containsMouse
                    ToolTip.text: "Open in Fountain app"
                    ToolTip.delay: 500
                }
            }
            
            // Title and description
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 12
                spacing: 4
                
                Text {
                    Layout.fillWidth: true
                    text: previewData?.title || "Podcast Episode"
                    color: "#ffffff"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                }
                
                Text {
                    Layout.fillWidth: true
                    text: previewData?.description || ""
                    color: "#888888"
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    visible: text !== ""
                }
            }
        }
        
        // Error state
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            visible: hasError
            spacing: 8
            
            Text {
                text: "🎙️"
                font.pixelSize: 32
                color: "#666666"
                Layout.alignment: Qt.AlignHCenter
            }
            
            Text {
                text: "Couldn't load podcast"
                color: "#888888"
                font.pixelSize: 14
                Layout.alignment: Qt.AlignHCenter
            }
            
            Button {
                Layout.alignment: Qt.AlignHCenter
                text: "Open in Fountain"
                onClicked: Qt.openUrlExternally(root.url)
                
                background: Rectangle {
                    color: parent.hovered ? "#3a3a3a" : "#2a2a2a"
                    radius: 4
                    border.color: "#444444"
                    border.width: 1
                }
                
                contentItem: Text {
                    text: parent.text
                    color: "#ffffff"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
    
    // Playing mode - full player
    Rectangle {
        anchors.fill: parent
        color: "#1a1a1a"
        visible: isPlaying
        
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            
            // Cover art or video (top area)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#000000"
                
                Image {
                    anchors.fill: parent
                    source: previewData?.image || ""
                    fillMode: Image.PreserveAspectCrop
                    visible: !videoOutput.visible
                    opacity: 0.3
                }
                
                // Small cover in corner when playing audio
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 12
                    width: 80
                    height: 80
                    radius: 8
                    color: "#2a2a2a"
                    visible: !videoOutput.visible
                    
                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: previewData?.image || ""
                        fillMode: Image.PreserveAspectCrop
                    }
                }
                
                // Title overlay
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 60
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: "#cc000000" }
                    }
                    
                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        text: previewData?.title || "Podcast Episode"
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                }
            }
            
            // Controls bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                color: "#252525"
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    
                    // Progress slider
                    Slider {
                        id: progressSlider
                        Layout.fillWidth: true
                        from: 0
                        to: mediaPlayer.duration > 0 ? mediaPlayer.duration : 1
                        value: mediaPlayer.position
                        
                        onMoved: {
                            mediaPlayer.position = value
                        }
                        
                        background: Rectangle {
                            x: progressSlider.leftPadding
                            y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                            width: progressSlider.availableWidth
                            height: 4
                            radius: 2
                            color: "#3a3a3a"
                            
                            Rectangle {
                                width: progressSlider.visualPosition * parent.width
                                height: parent.height
                                color: "#9333ea"
                                radius: 2
                            }
                        }
                        
                        handle: Rectangle {
                            x: progressSlider.leftPadding + progressSlider.visualPosition * (progressSlider.availableWidth - width)
                            y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                            width: 12
                            height: 12
                            radius: 6
                            color: progressSlider.pressed ? "#ffffff" : "#9333ea"
                        }
                    }
                    
                    // Time and controls row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        
                        // Time display
                        Text {
                            text: formatTime(mediaPlayer.position) + " / " + formatTime(mediaPlayer.duration)
                            color: "#888888"
                            font.pixelSize: 11
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        // Play/Pause button
                        Rectangle {
                            width: 36
                            height: 36
                            radius: 18
                            color: playPauseArea.containsMouse ? "#9333ea" : "#7928ca"
                            
                            Text {
                                anchors.centerIn: parent
                                text: mediaPlayer.playbackState === MediaPlayer.PlayingState ? "⏸" : "▶"
                                color: "#ffffff"
                                font.pixelSize: 16
                            }
                            
                            MouseArea {
                                id: playPauseArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                
                                onClicked: {
                                    if (mediaPlayer.playbackState === MediaPlayer.PlayingState) {
                                        mediaPlayer.pause()
                                    } else {
                                        mediaPlayer.play()
                                    }
                                }
                            }
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        // Volume slider
                        RowLayout {
                            spacing: 4
                            
                            Text {
                                text: audioOutput.volume === 0 ? "🔇" : audioOutput.volume < 0.5 ? "🔉" : "🔊"
                                font.pixelSize: 14
                            }
                            
                            Slider {
                                id: volumeSlider
                                Layout.preferredWidth: 60
                                from: 0
                                to: 1
                                value: 0.8
                                
                                background: Rectangle {
                                    x: volumeSlider.leftPadding
                                    y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                    width: volumeSlider.availableWidth
                                    height: 3
                                    radius: 1.5
                                    color: "#3a3a3a"
                                    
                                    Rectangle {
                                        width: volumeSlider.visualPosition * parent.width
                                        height: parent.height
                                        color: "#9333ea"
                                        radius: 1.5
                                    }
                                }
                                
                                handle: Rectangle {
                                    x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                                    y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: volumeSlider.pressed ? "#ffffff" : "#9333ea"
                                }
                            }
                        }
                        
                        // Close button
                        Rectangle {
                            width: 28
                            height: 28
                            radius: 14
                            color: closeArea.containsMouse ? "#ff4444" : "#3a3a3a"
                            
                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: "#ffffff"
                                font.pixelSize: 12
                            }
                            
                            MouseArea {
                                id: closeArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                
                                onClicked: {
                                    mediaPlayer.stop()
                                    isPlaying = false
                                }
                            }
                            
                            ToolTip.visible: closeArea.containsMouse
                            ToolTip.text: "Stop playing"
                            ToolTip.delay: 500
                        }
                    }
                }
            }
        }
    }
    
    function formatTime(ms) {
        if (ms <= 0) return "0:00"
        var totalSeconds = Math.floor(ms / 1000)
        var hours = Math.floor(totalSeconds / 3600)
        var minutes = Math.floor((totalSeconds % 3600) / 60)
        var seconds = totalSeconds % 60
        
        if (hours > 0) {
            return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
        }
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
}
