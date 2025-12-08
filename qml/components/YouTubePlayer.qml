import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine

Rectangle {
    id: root
    color: "#000000"
    radius: 8
    clip: true
    
    property string url: ""
    property string videoId: ""
    property bool autoPlay: false
    property bool isPlaying: false
    
    // Extract video ID from various YouTube URL formats
    function extractVideoId(urlStr) {
        if (!urlStr) return ""
        
        // youtube.com/watch?v=VIDEO_ID
        var match = urlStr.match(/[?&]v=([^&]+)/)
        if (match) return match[1]
        
        // youtu.be/VIDEO_ID
        match = urlStr.match(/youtu\.be\/([^?&]+)/)
        if (match) return match[1]
        
        // youtube.com/embed/VIDEO_ID
        match = urlStr.match(/youtube\.com\/embed\/([^?&]+)/)
        if (match) return match[1]
        
        // youtube.com/shorts/VIDEO_ID
        match = urlStr.match(/youtube\.com\/shorts\/([^?&]+)/)
        if (match) return match[1]
        
        return ""
    }
    
    // Check if URL is a YouTube URL
    function isYouTubeUrl(urlStr) {
        if (!urlStr) return false
        var lower = urlStr.toLowerCase()
        return lower.includes("youtube.com") || lower.includes("youtu.be")
    }
    
    // Get thumbnail URL
    function getThumbnailUrl(vidId) {
        if (!vidId) return ""
        // Try maxresdefault first, fallback handled by Image
        return "https://img.youtube.com/vi/" + vidId + "/maxresdefault.jpg"
    }
    
    // Get embed URL for YouTube video
    function getEmbedUrl(vidId) {
        if (!vidId) return ""
        // Use YouTube embed with enablejsapi and origin for proper API access
        return "https://www.youtube.com/embed/" + vidId + "?enablejsapi=1&rel=0&autoplay=1&playsinline=1&origin=https://www.youtube.com"
    }
    
    Component.onCompleted: {
        videoId = extractVideoId(url)
    }
    
    onUrlChanged: {
        videoId = extractVideoId(url)
        isPlaying = false
    }
    
    // Thumbnail preview (shown before playing)
    Rectangle {
        id: thumbnailContainer
        anchors.fill: parent
        color: "#1a1a1a"
        visible: !isPlaying
        
        Image {
            id: thumbnail
            anchors.fill: parent
            source: getThumbnailUrl(videoId)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            
            // Fallback to hqdefault if maxresdefault fails
            onStatusChanged: {
                if (status === Image.Error && source.toString().includes("maxresdefault")) {
                    source = "https://img.youtube.com/vi/" + videoId + "/hqdefault.jpg"
                }
            }
            
            // Loading placeholder
            Rectangle {
                anchors.fill: parent
                color: "#1a1a1a"
                visible: thumbnail.status === Image.Loading
                
                BusyIndicator {
                    anchors.centerIn: parent
                    running: parent.visible
                    width: 32
                    height: 32
                }
            }
        }
        
        // Dark overlay for better visibility of play button
        Rectangle {
            anchors.fill: parent
            color: "#40000000"
        }
        
        // YouTube-style play button
        Rectangle {
            id: playButton
            anchors.centerIn: parent
            width: 68
            height: 48
            radius: 12
            color: playButtonArea.containsMouse ? "#ff0000" : "#cc0000"
            
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
            
            // Play triangle
            Canvas {
                anchors.centerIn: parent
                width: 20
                height: 24
                
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.fillStyle = "#ffffff"
                    ctx.beginPath()
                    ctx.moveTo(0, 0)
                    ctx.lineTo(width, height / 2)
                    ctx.lineTo(0, height)
                    ctx.closePath()
                    ctx.fill()
                }
            }
            
            MouseArea {
                id: playButtonArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                
                onClicked: {
                    // Open YouTube externally - browser embed doesn't work reliably
                    Qt.openUrlExternally(root.url)
                }
            }
        }
        
        // YouTube branding / video title indicator
        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 8
            width: youtubeLabel.implicitWidth + 16
            height: 24
            radius: 4
            color: "#cc000000"
            
            RowLayout {
                id: youtubeLabel
                anchors.centerIn: parent
                spacing: 4
                
                Text {
                    text: "▶"
                    color: "#ff0000"
                    font.pixelSize: 12
                }
                
                Text {
                    text: "YouTube"
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
            ToolTip.text: "Open in external player"
            ToolTip.delay: 500
        }
    }
    
    // WebEngineView for embedded playback
    Loader {
        id: webViewLoader
        anchors.fill: parent
        active: isPlaying
        
        sourceComponent: WebEngineView {
            id: webView
            
            // Critical settings for YouTube embed playback
            settings.playbackRequiresUserGesture: false
            settings.javascriptEnabled: true
            settings.pluginsEnabled: true
            settings.localStorageEnabled: true
            settings.localContentCanAccessRemoteUrls: true
            settings.allowRunningInsecureContent: false
            settings.autoLoadImages: true
            settings.fullScreenSupportEnabled: true
            settings.accelerated2dCanvasEnabled: true
            settings.webGLEnabled: true
            
            // Load YouTube embed URL with API enabled
            url: getEmbedUrl(videoId)
            
            // Handle loading
            onLoadingChanged: function(loadRequest) {
                if (loadRequest.status === WebEngineView.LoadFailedStatus) {
                    console.log("YouTube embed failed to load:", loadRequest.errorString)
                }
            }
            
            // Handle fullscreen requests
            onFullScreenRequested: function(request) {
                request.accept()
            }
            
            // Handle feature permission requests (media, audio, etc.)
            onFeaturePermissionRequested: function(securityOrigin, feature) {
                console.log("Permission requested for:", feature, "from:", securityOrigin)
                grantFeaturePermission(securityOrigin, feature, true)
            }
        }
    }
    
    // Close/Stop button when playing
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        width: 32
        height: 32
        radius: 16
        color: closeArea.containsMouse ? "#ffffff" : "#80000000"
        visible: isPlaying
        z: 100
        
        Text {
            anchors.centerIn: parent
            text: "✕"
            color: closeArea.containsMouse ? "#000000" : "#ffffff"
            font.pixelSize: 16
            font.weight: Font.Bold
        }
        
        MouseArea {
            id: closeArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            
            onClicked: {
                isPlaying = false
            }
        }
        
        ToolTip.visible: closeArea.containsMouse
        ToolTip.text: "Stop video"
        ToolTip.delay: 500
    }
}
