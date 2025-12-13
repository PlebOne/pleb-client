import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#000000"
    radius: 8
    clip: true
    
    property string url: ""
    property string videoId: ""
    
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
    
    // Get thumbnail URL
    function getThumbnailUrl(vidId) {
        if (!vidId) return ""
        return "https://img.youtube.com/vi/" + vidId + "/maxresdefault.jpg"
    }
    
    Component.onCompleted: {
        videoId = extractVideoId(url)
    }
    
    onUrlChanged: {
        videoId = extractVideoId(url)
    }
    
    // Thumbnail preview
    Rectangle {
        anchors.fill: parent
        color: "#1a1a1a"
        
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
        
        // Dark overlay
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
                onClicked: Qt.openUrlExternally(root.url)
            }
        }
        
        // YouTube branding
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
        
        // Open externally indicator
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 8
            width: externalRow.implicitWidth + 12
            height: 24
            radius: 4
            color: "#60000000"
            
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
                    text: "Opens in browser"
                    color: "#aaaaaa"
                    font.pixelSize: 10
                }
            }
        }
        
        // Full area clickable
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(root.url)
            z: -1
        }
    }
}
