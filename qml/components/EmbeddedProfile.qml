import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Embedded profile card for displaying nostr:nprofile references
Rectangle {
    id: root
    color: "#252525"
    radius: 8
    border.color: "#9333ea"
    border.width: 1
    implicitHeight: contentCol.implicitHeight + 16
    
    property string nostrUri: ""
    property var profileData: null
    property bool isLoading: false
    property bool hasError: false
    property var feedController: null
    property int retryCount: 0
    property int maxRetries: 5
    
    signal clicked(string pubkey)
    
    Component.onCompleted: {
        if (nostrUri && !profileData) {
            loadProfile()
        }
    }
    
    onNostrUriChanged: {
        profileData = null
        retryCount = 0
        hasError = false
        if (nostrUri) {
            loadProfile()
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
            loadProfile()
        }
    }
    
    function loadProfile() {
        if (!nostrUri || !feedController) return
        
        isLoading = true
        hasError = false
        
        var result = feedController.fetch_embedded_profile(nostrUri)
        if (result && result !== "{}") {
            try {
                profileData = JSON.parse(result)
                isLoading = false
                retryTimer.stop()
            } catch (e) {
                console.warn("Failed to parse embedded profile:", e)
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
        onClicked: {
            if (profileData && profileData.pubkey) {
                root.clicked(profileData.pubkey)
            }
        }
    }
    
    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        
        // Loading state
        RowLayout {
            Layout.fillWidth: true
            visible: isLoading
            spacing: 8
            
            BusyIndicator {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                running: isLoading
            }
            
            Text {
                text: "Loading profile..."
                color: "#888888"
                font.pixelSize: 12
            }
        }
        
        // Error state
        RowLayout {
            Layout.fillWidth: true
            visible: hasError && !isLoading
            spacing: 6
            
            Text {
                text: "👤"
                font.pixelSize: 14
            }
            
            Text {
                text: "Profile not found or unavailable"
                color: "#666666"
                font.pixelSize: 12
                font.italic: true
            }
        }
        
        // Loaded profile content
        ColumnLayout {
            Layout.fillWidth: true
            visible: profileData && !isLoading && !hasError
            spacing: 8
            
            // Profile header row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                
                // Avatar
                Rectangle {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    radius: 24
                    color: "#3a3a3a"
                    
                    Image {
                        anchors.fill: parent
                        source: profileData?.picture || ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: Item {
                            property real radius: 24
                        }
                    }
                    
                    Text {
                        anchors.centerIn: parent
                        text: getInitial()
                        color: "#888888"
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        visible: !profileData?.picture
                    }
                }
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    
                    // Display name
                    RowLayout {
                        spacing: 6
                        
                        Text {
                            text: profileData?.displayName || profileData?.name || "Unknown"
                            color: "#ffffff"
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            Layout.maximumWidth: 200
                        }
                        
                        // NIP-05 verification badge
                        Text {
                            text: "✓"
                            color: "#9333ea"
                            font.pixelSize: 12
                            visible: profileData?.nip05 ? true : false
                        }
                    }
                    
                    // NIP-05 identifier
                    Text {
                        text: formatNip05(profileData?.nip05 || "")
                        color: "#888888"
                        font.pixelSize: 12
                        visible: profileData?.nip05 ? true : false
                        elide: Text.ElideRight
                        Layout.maximumWidth: 200
                    }
                    
                    // Shortened npub
                    Text {
                        text: profileData?.npub ? shortenNpub(profileData.npub) : ""
                        color: "#666666"
                        font.pixelSize: 11
                        font.family: "monospace"
                        visible: !!(!profileData?.nip05 && profileData?.npub)
                    }
                }
                
                // Follow indicator badge
                Rectangle {
                    Layout.preferredWidth: followLabel.implicitWidth + 16
                    Layout.preferredHeight: 24
                    radius: 12
                    color: "#9333ea"
                    visible: false  // TODO: implement following check
                    
                    Text {
                        id: followLabel
                        anchors.centerIn: parent
                        text: "Following"
                        color: "#ffffff"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }
            }
            
            // About text (if available)
            Text {
                text: truncateAbout(profileData?.about || "")
                color: "#aaaaaa"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                maximumLineCount: 2
                elide: Text.ElideRight
                visible: profileData?.about ? true : false
            }
            
            // Lightning address (if available)
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: profileData?.lud16 ? true : false
                
                Text {
                    text: "⚡"
                    font.pixelSize: 12
                }
                
                Text {
                    text: profileData?.lud16 || ""
                    color: "#facc15"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
    }
    
    function getInitial() {
        if (profileData?.displayName) {
            return profileData.displayName.charAt(0).toUpperCase()
        }
        if (profileData?.name) {
            return profileData.name.charAt(0).toUpperCase()
        }
        return "?"
    }
    
    function formatNip05(nip05) {
        if (!nip05) return ""
        // Remove _@ prefix if present (common convention)
        if (nip05.startsWith("_@")) {
            return nip05.substring(2)
        }
        return nip05
    }
    
    function shortenNpub(npub) {
        if (!npub || npub.length < 20) return npub
        return npub.substring(0, 12) + "..." + npub.substring(npub.length - 8)
    }
    
    function truncateAbout(text) {
        if (!text) return ""
        // Clean up the text
        var cleaned = text.replace(/\n+/g, " ").trim()
        if (cleaned.length > 150) {
            return cleaned.substring(0, 147) + "..."
        }
        return cleaned
    }
}
