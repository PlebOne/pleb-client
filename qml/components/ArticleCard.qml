import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#1a1a1a"
    radius: 12
    implicitHeight: contentColumn.implicitHeight + 24
    
    property string noteId: ""
    property string authorPubkey: ""
    property string authorName: ""
    property string authorPicture: ""
    property string title: ""
    property string summary: ""
    property string image: ""
    property int publishedAt: 0
    property int readingTime: 1
    property int zapAmount: 0
    
    signal articleClicked(string noteId)
    signal authorClicked(string pubkey)
    
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.articleClicked(root.noteId)
    }
    
    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12
        
        // Cover Image
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            visible: root.image !== ""
            color: "#000000"
            radius: 8
            clip: true
            
            Image {
                anchors.fill: parent
                source: root.image
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
        
        // Title
        Text {
            Layout.fillWidth: true
            text: root.title
            color: "#ffffff"
            font.pixelSize: 22
            font.weight: Font.Bold
            wrapMode: Text.Wrap
        }
        
        // Summary
        Text {
            Layout.fillWidth: true
            text: root.summary
            color: "#cccccc"
            font.pixelSize: 16
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
        
        // Meta info (Author + Date + Reading Time)
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            
            // Author Avatar
            ProfileAvatar {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                imageUrl: root.authorPicture
                name: root.authorName
                
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        mouse.accepted = true
                        root.authorClicked(root.authorPubkey)
                    }
                }
            }
            
            Text {
                text: root.authorName
                color: "#9333ea"
                font.pixelSize: 14
                font.weight: Font.Medium
                
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        mouse.accepted = true
                        root.authorClicked(root.authorPubkey)
                    }
                }
            }
            
            Text {
                text: "•"
                color: "#666666"
            }
            
            Text {
                text: formatTimestamp(root.publishedAt)
                color: "#888888"
                font.pixelSize: 13
            }
            
            Text {
                text: "•"
                color: "#666666"
            }
            
            Text {
                text: root.readingTime + " min read"
                color: "#888888"
                font.pixelSize: 13
            }
            
            // Zap amount indicator (only show if has zaps)
            Rectangle {
                visible: root.zapAmount > 0
                color: "#2a2a2a"
                radius: 10
                implicitWidth: zapRow.implicitWidth + 12
                implicitHeight: 20
                
                RowLayout {
                    id: zapRow
                    anchors.centerIn: parent
                    spacing: 4
                    
                    Text {
                        text: "⚡"
                        font.pixelSize: 11
                    }
                    
                    Text {
                        text: formatZapAmount(root.zapAmount)
                        color: "#ffcc00"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
    
    function formatTimestamp(timestamp) {
        if (!timestamp) return ""
        var date = new Date(timestamp * 1000)
        return date.toLocaleDateString()
    }
    
    function formatZapAmount(sats) {
        if (sats >= 1000000) {
            return (sats / 1000000).toFixed(1) + "M"
        } else if (sats >= 1000) {
            return (sats / 1000).toFixed(1) + "k"
        }
        return sats.toString()
    }
}
