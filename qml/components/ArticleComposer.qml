import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt.labs.platform as Platform

// Article Composer - Full-featured long-form content editor (NIP-23)
Popup {
    id: root
    
    property var feedController: null
    property var appController: null
    
    // Article metadata
    property string articleTitle: ""
    property string articleSummary: ""
    property string articleImage: ""  // Featured image URL
    property string articleSlug: ""   // d-tag identifier
    property var articleTags: []      // Hashtags
    
    // Draft management
    property string currentDraftId: ""
    property bool hasUnsavedChanges: false
    property var drafts: []
    
    // UI state
    property bool isZenMode: false
    property bool isUploading: false
    property bool isPublishing: false
    property bool showDraftsList: false
    property bool showMetadataPanel: true
    
    signal published(string noteId)
    signal draftSaved(string draftId)
    
    // Full screen in zen mode, otherwise centered popup
    width: isZenMode ? parent.width : Math.min(900, parent.width - 40)
    height: isZenMode ? parent.height : Math.min(700, parent.height - 60)
    x: isZenMode ? 0 : Math.round((parent.width - width) / 2)
    y: isZenMode ? 0 : Math.round((parent.height - height) / 2)
    modal: true
    closePolicy: isZenMode ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
    padding: 0
    
    background: Rectangle {
        color: isZenMode ? "#0a0a0a" : "#111111"
        radius: isZenMode ? 0 : 16
        border.color: isZenMode ? "transparent" : "#333333"
        border.width: isZenMode ? 0 : 1
    }
    
    // Track changes
    onArticleTitleChanged: hasUnsavedChanges = true
    onArticleSummaryChanged: hasUnsavedChanges = true
    onArticleImageChanged: hasUnsavedChanges = true
    
    // Auto-generate slug from title
    function generateSlug() {
        if (articleTitle && !currentDraftId) {
            var slug = articleTitle.toLowerCase()
                .replace(/[^a-z0-9\s-]/g, '')
                .replace(/\s+/g, '-')
                .substring(0, 50)
            articleSlug = slug + "-" + Date.now().toString(36)
        }
    }
    
    // Load drafts on open
    onOpened: {
        loadDrafts()
        contentEditor.forceActiveFocus()
        hasUnsavedChanges = false
    }
    
    // Confirm before closing with unsaved changes
    onAboutToHide: {
        if (hasUnsavedChanges && !isPublishing) {
            // Could show confirmation dialog here
        }
    }
    
    // Reset state
    function resetEditor() {
        articleTitle = ""
        articleSummary = ""
        articleImage = ""
        articleSlug = ""
        articleTags = []
        contentEditor.text = ""
        currentDraftId = ""
        hasUnsavedChanges = false
        isZenMode = false
        showDraftsList = false
    }
    
    // Load drafts from filesystem
    function loadDrafts() {
        if (feedController) {
            var json = feedController.load_article_drafts()
            try {
                drafts = JSON.parse(json)
            } catch (e) {
                drafts = []
            }
        }
    }
    
    // Load a specific draft
    function loadDraft(draftId) {
        // Find draft in loaded drafts list
        for (var i = 0; i < drafts.length; i++) {
            if (drafts[i].id === draftId) {
                var draft = drafts[i]
                articleTitle = draft.title || ""
                articleSummary = draft.summary || ""
                articleImage = draft.image || ""
                articleSlug = draft.slug || ""
                articleTags = draft.tags || []
                contentEditor.text = draft.content || ""
                currentDraftId = draftId
                hasUnsavedChanges = false
                showDraftsList = false
                return
            }
        }
    }
    
    // Save current draft
    function saveDraft() {
        if (!feedController) return
        
        var draft = {
            id: currentDraftId,
            title: articleTitle,
            summary: articleSummary,
            image: articleImage,
            slug: articleSlug || generateSlug(),
            tags: articleTags,
            content: contentEditor.text
        }
        
        var result = feedController.save_article_draft(JSON.stringify(draft))
        
        try {
            var response = JSON.parse(result)
            if (response.id) {
                currentDraftId = response.id
                hasUnsavedChanges = false
                loadDrafts()
                draftSaved(response.id)
            } else if (response.error) {
                console.log("Failed to save draft:", response.error)
            }
        } catch (e) {
            console.log("Failed to parse save result:", e)
        }
    }
    
    // Delete a draft
    function deleteDraft(draftId) {
        if (feedController) {
            feedController.delete_article_draft(draftId)
            if (currentDraftId === draftId) {
                resetEditor()
            }
            loadDrafts()
        }
    }
    
    // Publish the article
    function publishArticle() {
        if (!feedController || !articleTitle.trim() || !contentEditor.text.trim()) {
            return
        }
        
        isPublishing = true
        
        // Generate slug if not set
        if (!articleSlug) {
            generateSlug()
        }
        
        var metadata = {
            title: articleTitle.trim(),
            summary: articleSummary.trim(),
            image: articleImage,
            slug: articleSlug,
            tags: articleTags
        }
        
        feedController.publish_long_form(
            contentEditor.text,
            JSON.stringify(metadata)
        )
    }
    
    // Handle publish result
    Connections {
        target: feedController
        ignoreUnknownSignals: true
        
        function onArticle_published(eventId, naddr) {
            if (isPublishing) {
                isPublishing = false
                // Delete draft after successful publish
                if (currentDraftId) {
                    deleteDraft(currentDraftId)
                }
                published(eventId)
                root.close()
                resetEditor()
            }
        }
        
        function onArticle_publish_failed(error) {
            if (isPublishing) {
                isPublishing = false
                // Show error - could add a proper error display
                console.log("Publish failed:", error)
            }
        }
        
        function onMedia_uploaded(url) {
            isUploading = false
            // Insert image at cursor position
            var pos = contentEditor.cursorPosition
            var before = contentEditor.text.substring(0, pos)
            var after = contentEditor.text.substring(pos)
            contentEditor.text = before + "\n\n![Image](" + url + ")\n\n" + after
            contentEditor.cursorPosition = pos + url.length + 14
        }
        
        function onMedia_upload_failed(error) {
            isUploading = false
            console.log("Upload failed:", error)
        }
    }
    
    // Main layout
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        
        // Header bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: isZenMode ? "#0a0a0a" : "#1a1a1a"
            visible: !isZenMode || showMetadataPanel
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                
                // Close button
                Button {
                    implicitWidth: 36
                    implicitHeight: 36
                    
                    background: Rectangle {
                        color: parent.hovered ? "#333333" : "transparent"
                        radius: 8
                    }
                    
                    contentItem: Text {
                        text: "←"
                        color: "#888888"
                        font.pixelSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        if (isZenMode) {
                            isZenMode = false
                        } else {
                            root.close()
                        }
                    }
                }
                
                Text {
                    text: currentDraftId ? "Edit Article" : "New Article"
                    color: "#ffffff"
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
                
                // Unsaved indicator
                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: "#f59e0b"
                    visible: hasUnsavedChanges
                    
                    ToolTip.visible: mouseArea.containsMouse
                    ToolTip.text: "Unsaved changes"
                    
                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }
                
                Item { Layout.fillWidth: true }
                
                // Word count
                Text {
                    text: {
                        var words = contentEditor.text.trim().split(/\s+/).filter(w => w.length > 0).length
                        return words + " words"
                    }
                    color: "#666666"
                    font.pixelSize: 12
                }
                
                // Drafts button
                Button {
                    text: "📁 Drafts"
                    implicitHeight: 32
                    
                    background: Rectangle {
                        color: showDraftsList ? "#333333" : (parent.hovered ? "#2a2a2a" : "transparent")
                        radius: 6
                        border.color: "#444444"
                        border.width: 1
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: "#cccccc"
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: showDraftsList = !showDraftsList
                }
                
                // Save draft button
                Button {
                    text: "💾 Save"
                    implicitHeight: 32
                    enabled: contentEditor.text.trim().length > 0 || articleTitle.trim().length > 0
                    
                    background: Rectangle {
                        color: parent.enabled ? (parent.hovered ? "#2a2a2a" : "transparent") : "transparent"
                        radius: 6
                        border.color: parent.enabled ? "#444444" : "#333333"
                        border.width: 1
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? "#cccccc" : "#555555"
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: saveDraft()
                }
                
                // Zen mode button
                Button {
                    text: isZenMode ? "Exit Zen" : "🧘 Zen"
                    implicitHeight: 32
                    
                    background: Rectangle {
                        color: isZenMode ? "#9333ea" : (parent.hovered ? "#2a2a2a" : "transparent")
                        radius: 6
                        border.color: isZenMode ? "#9333ea" : "#444444"
                        border.width: 1
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        isZenMode = !isZenMode
                        if (isZenMode) {
                            showDraftsList = false
                        }
                    }
                }
                
                // Publish button
                Button {
                    text: isPublishing ? "Publishing..." : "✨ Publish"
                    implicitHeight: 36
                    enabled: !isPublishing && articleTitle.trim().length > 0 && contentEditor.text.trim().length > 0
                    
                    background: Rectangle {
                        color: parent.enabled ? (parent.hovered ? "#7c22ce" : "#9333ea") : "#333333"
                        radius: 8
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? "#ffffff" : "#666666"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: publishArticle()
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#333333"
            visible: !isZenMode
        }
        
        // Main content area
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            
            // Drafts sidebar
            Rectangle {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                color: "#0d0d0d"
                visible: showDraftsList && !isZenMode
                
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        color: "#151515"
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            
                            Text {
                                text: "Saved Drafts"
                                color: "#ffffff"
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }
                            
                            Item { Layout.fillWidth: true }
                            
                            Text {
                                text: drafts.length + ""
                                color: "#666666"
                                font.pixelSize: 12
                            }
                        }
                    }
                    
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: drafts
                        
                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 72
                            color: currentDraftId === modelData.id ? "#1a1a2e" : (draftHover.containsMouse ? "#151515" : "transparent")
                            
                            MouseArea {
                                id: draftHover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: loadDraft(modelData.id)
                            }
                            
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 4
                                
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.title || "Untitled"
                                    color: "#ffffff"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                
                                Text {
                                    Layout.fillWidth: true
                                    text: (modelData.content || "").substring(0, 60) + "..."
                                    color: "#888888"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                
                                RowLayout {
                                    spacing: 8
                                    
                                    Text {
                                        text: new Date(modelData.updatedAt).toLocaleDateString()
                                        color: "#666666"
                                        font.pixelSize: 11
                                    }
                                    
                                    Item { Layout.fillWidth: true }
                                    
                                    Text {
                                        text: "🗑"
                                        color: deleteHover.containsMouse ? "#ef4444" : "#666666"
                                        font.pixelSize: 14
                                        
                                        MouseArea {
                                            id: deleteHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: deleteDraft(modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Empty state
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - 40
                            height: 100
                            color: "transparent"
                            visible: drafts.length === 0
                            
                            Column {
                                anchors.centerIn: parent
                                spacing: 8
                                
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "📝"
                                    font.pixelSize: 32
                                }
                                
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "No drafts yet"
                                    color: "#666666"
                                    font.pixelSize: 13
                                }
                            }
                        }
                    }
                    
                    // New draft button
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        color: "#151515"
                        
                        Button {
                            anchors.centerIn: parent
                            text: "+ New Draft"
                            
                            background: Rectangle {
                                color: parent.hovered ? "#222222" : "transparent"
                                radius: 6
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#9333ea"
                                font.pixelSize: 13
                            }
                            
                            onClicked: {
                                resetEditor()
                                showDraftsList = false
                            }
                        }
                    }
                }
            }
            
            Rectangle {
                width: 1
                Layout.fillHeight: true
                color: "#333333"
                visible: showDraftsList && !isZenMode
            }
            
            // Editor area
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                
                // Metadata panel (collapsible in zen mode)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: metadataContent.implicitHeight + 32
                    color: isZenMode ? "#0a0a0a" : "#151515"
                    visible: showMetadataPanel && !isZenMode
                    
                    ColumnLayout {
                        id: metadataContent
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 16
                        
                        // Title input
                        TextField {
                            id: titleInput
                            Layout.fillWidth: true
                            placeholderText: "Article title..."
                            text: articleTitle
                            onTextChanged: articleTitle = text
                            color: "#ffffff"
                            placeholderTextColor: "#555555"
                            font.pixelSize: 24
                            font.weight: Font.Bold
                            
                            background: Rectangle {
                                color: "transparent"
                            }
                        }
                        
                        // Summary input
                        TextField {
                            id: summaryInput
                            Layout.fillWidth: true
                            placeholderText: "Brief summary (appears in previews)..."
                            text: articleSummary
                            onTextChanged: articleSummary = text
                            color: "#cccccc"
                            placeholderTextColor: "#555555"
                            font.pixelSize: 14
                            
                            background: Rectangle {
                                color: "transparent"
                            }
                        }
                        
                        // Featured image and tags row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16
                            
                            // Featured image
                            Rectangle {
                                Layout.preferredWidth: 120
                                Layout.preferredHeight: 68
                                radius: 8
                                color: "#1a1a1a"
                                border.color: imageDropArea.containsDrag ? "#9333ea" : "#333333"
                                border.width: 1
                                
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: articleImage
                                    fillMode: Image.PreserveAspectCrop
                                    visible: articleImage !== ""
                                    
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 6
                                        color: "transparent"
                                        border.color: "#333333"
                                        border.width: 1
                                    }
                                }
                                
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    visible: articleImage === ""
                                    
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "🖼"
                                        font.pixelSize: 20
                                    }
                                    
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "Cover"
                                        color: "#666666"
                                        font.pixelSize: 11
                                    }
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: coverImageDialog.open()
                                }
                                
                                DropArea {
                                    id: imageDropArea
                                    anchors.fill: parent
                                    
                                    onDropped: function(drop) {
                                        if (drop.hasUrls && drop.urls.length > 0) {
                                            uploadCoverImage(drop.urls[0])
                                        }
                                    }
                                }
                                
                                // Remove image button
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 4
                                    width: 20
                                    height: 20
                                    radius: 10
                                    color: "#000000"
                                    opacity: 0.8
                                    visible: articleImage !== ""
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: "×"
                                        color: "#ffffff"
                                        font.pixelSize: 14
                                    }
                                    
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: articleImage = ""
                                    }
                                }
                            }
                            
                            // Tags input
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                
                                Text {
                                    text: "Tags"
                                    color: "#888888"
                                    font.pixelSize: 12
                                }
                                
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    
                                    Repeater {
                                        model: articleTags
                                        
                                        Rectangle {
                                            width: tagText.implicitWidth + 24
                                            height: 28
                                            radius: 14
                                            color: "#1a1a2e"
                                            
                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 4
                                                
                                                Text {
                                                    id: tagText
                                                    text: "#" + modelData
                                                    color: "#9333ea"
                                                    font.pixelSize: 12
                                                }
                                                
                                                Text {
                                                    text: "×"
                                                    color: "#666666"
                                                    font.pixelSize: 12
                                                    
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            var tags = articleTags.slice()
                                                            tags.splice(index, 1)
                                                            articleTags = tags
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    
                                    // Add tag input
                                    TextField {
                                        id: tagInput
                                        width: 100
                                        height: 28
                                        placeholderText: "+ tag"
                                        placeholderTextColor: "#555555"
                                        color: "#ffffff"
                                        font.pixelSize: 12
                                        
                                        background: Rectangle {
                                            color: "#1a1a1a"
                                            radius: 14
                                            border.color: tagInput.activeFocus ? "#9333ea" : "#333333"
                                            border.width: 1
                                        }
                                        
                                        onAccepted: {
                                            var tag = text.trim().replace(/^#/, '')
                                            if (tag && articleTags.indexOf(tag) === -1) {
                                                articleTags = articleTags.concat([tag])
                                            }
                                            text = ""
                                        }
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
                    visible: !isZenMode
                }
                
                // Writing area - the main editor
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: isZenMode ? "#0a0a0a" : "#111111"
                    
                    // Zen mode title (inline)
                    TextField {
                        id: zenTitleInput
                        anchors.top: parent.top
                        anchors.topMargin: isZenMode ? 60 : 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(700, parent.width - 80)
                        visible: isZenMode
                        placeholderText: "Title"
                        text: articleTitle
                        onTextChanged: articleTitle = text
                        color: "#ffffff"
                        placeholderTextColor: "#444444"
                        font.pixelSize: 32
                        font.weight: Font.Bold
                        font.family: "Georgia, serif"
                        horizontalAlignment: Text.AlignHCenter
                        
                        background: Rectangle {
                            color: "transparent"
                        }
                    }
                    
                    ScrollView {
                        id: editorScroll
                        anchors.top: isZenMode ? zenTitleInput.bottom : parent.top
                        anchors.topMargin: isZenMode ? 24 : 20
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 20
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(700, parent.width - 80)
                        contentWidth: availableWidth
                        
                        TextArea {
                            id: contentEditor
                            width: parent.width
                            placeholderText: isZenMode ? "Begin writing..." : "Write your article here...\n\nMarkdown is supported. Use **bold**, *italic*, # headers, and ![alt](url) for images."
                            placeholderTextColor: "#444444"
                            color: "#e0e0e0"
                            selectionColor: "#9333ea"
                            selectedTextColor: "#ffffff"
                            
                            // Beautiful writing font
                            font.pixelSize: isZenMode ? 20 : 16
                            font.family: "Georgia, 'Times New Roman', serif"
                            font.letterSpacing: 0.3
                            
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.PlainText
                            
                            background: Rectangle {
                                color: "transparent"
                            }
                            
                            onTextChanged: hasUnsavedChanges = true
                            
                            // Keyboard shortcuts
                            Keys.onPressed: function(event) {
                                // Ctrl+S to save draft
                                if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                                    saveDraft()
                                    event.accepted = true
                                }
                                // Escape to exit zen mode
                                else if (event.key === Qt.Key_Escape && isZenMode) {
                                    isZenMode = false
                                    event.accepted = true
                                }
                                // Ctrl+Enter to publish
                                else if (event.key === Qt.Key_Return && (event.modifiers & Qt.ControlModifier)) {
                                    publishArticle()
                                    event.accepted = true
                                }
                            }
                        }
                    }
                    
                    // Zen mode toolbar (floating)
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottomMargin: 30
                        width: toolbarRow.implicitWidth + 24
                        height: 44
                        radius: 22
                        color: "#1a1a1a"
                        border.color: "#333333"
                        border.width: 1
                        visible: isZenMode
                        opacity: zenToolbarHover.containsMouse ? 1.0 : 0.5
                        
                        Behavior on opacity {
                            NumberAnimation { duration: 200 }
                        }
                        
                        MouseArea {
                            id: zenToolbarHover
                            anchors.fill: parent
                            hoverEnabled: true
                            propagateComposedEvents: true
                        }
                        
                        RowLayout {
                            id: toolbarRow
                            anchors.centerIn: parent
                            spacing: 8
                            
                            Button {
                                implicitWidth: 32
                                implicitHeight: 32
                                ToolTip.text: "Add image"
                                ToolTip.visible: hovered
                                
                                background: Rectangle {
                                    color: parent.hovered ? "#333333" : "transparent"
                                    radius: 8
                                }
                                
                                contentItem: Text {
                                    text: "🖼"
                                    font.pixelSize: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: inlineImageDialog.open()
                            }
                            
                            Rectangle {
                                width: 1
                                height: 20
                                color: "#333333"
                            }
                            
                            Button {
                                implicitWidth: 32
                                implicitHeight: 32
                                ToolTip.text: "Save draft (Ctrl+S)"
                                ToolTip.visible: hovered
                                
                                background: Rectangle {
                                    color: parent.hovered ? "#333333" : "transparent"
                                    radius: 8
                                }
                                
                                contentItem: Text {
                                    text: "💾"
                                    font.pixelSize: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: saveDraft()
                            }
                            
                            Rectangle {
                                width: 1
                                height: 20
                                color: "#333333"
                            }
                            
                            Button {
                                implicitWidth: 32
                                implicitHeight: 32
                                ToolTip.text: "Exit zen mode (Esc)"
                                ToolTip.visible: hovered
                                
                                background: Rectangle {
                                    color: parent.hovered ? "#333333" : "transparent"
                                    radius: 8
                                }
                                
                                contentItem: Text {
                                    text: "✕"
                                    color: "#888888"
                                    font.pixelSize: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: isZenMode = false
                            }
                        }
                    }
                }
                
                // Bottom toolbar (non-zen mode)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    color: "#151515"
                    visible: !isZenMode
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 8
                        
                        // Insert image button
                        Button {
                            text: "🖼 Add Image"
                            implicitHeight: 36
                            
                            background: Rectangle {
                                color: parent.hovered ? "#2a2a2a" : "#1a1a1a"
                                radius: 8
                                border.color: "#333333"
                                border.width: 1
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#cccccc"
                                font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            onClicked: inlineImageDialog.open()
                        }
                        
                        // Uploading indicator
                        RowLayout {
                            visible: isUploading
                            spacing: 8
                            
                            BusyIndicator {
                                implicitWidth: 20
                                implicitHeight: 20
                                running: isUploading
                            }
                            
                            Text {
                                text: "Uploading..."
                                color: "#888888"
                                font.pixelSize: 13
                            }
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        // Metadata toggle
                        Button {
                            text: showMetadataPanel ? "Hide Details" : "Show Details"
                            implicitHeight: 32
                            
                            background: Rectangle {
                                color: parent.hovered ? "#2a2a2a" : "transparent"
                                radius: 6
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: "#888888"
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            onClicked: showMetadataPanel = !showMetadataPanel
                        }
                        
                        // Character count
                        Text {
                            text: contentEditor.text.length + " chars"
                            color: "#555555"
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }
    
    // File dialogs
    FileDialog {
        id: coverImageDialog
        title: "Select Cover Image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.gif *.webp)"]
        onAccepted: uploadCoverImage(selectedFile)
    }
    
    FileDialog {
        id: inlineImageDialog
        title: "Select Image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.gif *.webp)"]
        onAccepted: uploadInlineImage(selectedFile)
    }
    
    // Upload functions
    function uploadCoverImage(fileUrl) {
        if (!feedController) return
        isUploading = true
        
        // Store that this is for cover image
        root._pendingCoverUpload = true
        
        var path = fileUrl.toString().replace("file://", "")
        feedController.upload_media(path)
    }
    
    property bool _pendingCoverUpload: false
    
    function uploadInlineImage(fileUrl) {
        if (!feedController) return
        isUploading = true
        root._pendingCoverUpload = false
        
        var path = fileUrl.toString().replace("file://", "")
        feedController.upload_media(path)
    }
    
    // Override media upload handler to distinguish cover vs inline
    Connections {
        target: feedController
        ignoreUnknownSignals: true
        
        function onMedia_uploaded(url) {
            isUploading = false
            
            if (root._pendingCoverUpload) {
                articleImage = url
                root._pendingCoverUpload = false
            } else {
                // Insert inline image
                var pos = contentEditor.cursorPosition
                var before = contentEditor.text.substring(0, pos)
                var after = contentEditor.text.substring(pos)
                contentEditor.text = before + "\n\n![Image](" + url + ")\n\n" + after
                contentEditor.cursorPosition = pos + url.length + 14
            }
        }
    }
}
