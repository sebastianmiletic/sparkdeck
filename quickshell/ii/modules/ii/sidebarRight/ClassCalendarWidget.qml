pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    clip: true
    property date selectedDate: initialDate()
    property var selectedClasses: ClassSchedule.classesForDate(selectedDate)
    readonly property date now: DateTime.clock.date

    function initialDate() {
        const date = new Date()
        date.setHours(12, 0, 0, 0)
        if (date.getDay() === 6) date.setDate(date.getDate() + 2)
        else if (date.getDay() === 0) date.setDate(date.getDate() + 1)
        return date
    }

    function showDate(date) {
        const copy = new Date(date.getTime())
        copy.setHours(12, 0, 0, 0)
        root.selectedDate = copy
        root.selectedClasses = ClassSchedule.classesForDate(copy)
    }

    function moveDay(offset) {
        const date = new Date(root.selectedDate.getTime())
        date.setDate(date.getDate() + offset)
        showDate(date)
    }

    function resetDate() {
        showDate(initialDate())
    }

    function minutes(time) {
        if (!time) return -1
        const parts = String(time).split(":")
        if (parts.length < 2) return -1
        return Number(parts[0]) * 60 + Number(parts[1])
    }

    function isSelectedDateToday() {
        return Qt.formatDate(root.selectedDate, "yyyy-MM-dd") === Qt.formatDate(root.now, "yyyy-MM-dd")
    }

    function hasEnded(entry) {
        const end = minutes(entry.end)
        return isSelectedDateToday() && end >= 0
            && root.now.getHours() * 60 + root.now.getMinutes() >= end
    }

    function isHappening(entry) {
        if (!isSelectedDateToday()) return false
        const start = minutes(entry.start)
        const end = minutes(entry.end)
        const current = root.now.getHours() * 60 + root.now.getMinutes()
        return start >= 0 && current >= start && (end < 0 || current < end)
    }

    function relevantClassIndex() {
        if (!isSelectedDateToday() || root.selectedClasses.length === 0) return -1
        const current = root.now.getHours() * 60 + root.now.getMinutes()
        for (let i = 0; i < root.selectedClasses.length; ++i) {
            if (isHappening(root.selectedClasses[i])) return i
        }
        for (let i = 0; i < root.selectedClasses.length; ++i) {
            if (minutes(root.selectedClasses[i].start) > current) return i
        }
        return root.selectedClasses.length - 1
    }

    function scrollToRelevantClass() {
        const index = relevantClassIndex()
        if (index >= 0) classList.positionViewAtIndex(index, ListView.Center)
    }

    Connections {
        target: ClassSchedule
        function onListChanged() {
            root.selectedClasses = ClassSchedule.classesForDate(root.selectedDate)
            if (GlobalStates.sidebarRightOpen)
                Qt.callLater(() => root.scrollToRelevantClass())
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) {
                root.resetDate()
                Qt.callLater(() => root.scrollToRelevantClass())
            }
        }
    }

    Component.onCompleted: {
        if (GlobalStates.sidebarRightOpen)
            Qt.callLater(() => root.scrollToRelevantClass())
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText { text: Translation.tr("Classes"); color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold }
                StyledText { text: Qt.formatDate(root.selectedDate, "dddd, d MMMM"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
            }
            NavButton { symbol: "chevron_left"; accessibleName: Translation.tr("Previous day"); onClicked: root.moveDay(-1) }
            NavButton { symbol: "chevron_right"; accessibleName: Translation.tr("Next day"); onClicked: root.moveDay(1) }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border }
        StyledListView {
            id: classList
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: 4; clip: true; model: root.selectedClasses
            delegate: Rectangle {
                required property var modelData
                readonly property bool ended: root.hasEnded(modelData)
                readonly property bool happening: root.isHappening(modelData)
                width: classList.width; height: 58; radius: Appearance.rounding.small
                color: happening ? Appearance.colors.colPrimaryContainer
                    : (ended ? Appearance.colors.colLayer2Disabled : "transparent")
                RowLayout {
                    anchors.fill: parent; anchors.margins: 8; spacing: 10
                    Rectangle {
                        Layout.fillHeight: true; implicitWidth: 3; radius: 2
                        color: ended ? Appearance.colors.colSubtext
                            : (happening ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.title || Translation.tr("Untitled class")
                            elide: Text.ElideRight
                            color: ended ? Appearance.colors.colOnLayer2Disabled : Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            text: modelData.room || Translation.tr("Room not set")
                            color: ended ? Appearance.colors.colOnLayer2Disabled : Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                    StyledText {
                        text: modelData.end ? `${modelData.start}–${modelData.end}` : modelData.start
                        color: ended ? Appearance.colors.colOnLayer2Disabled : (happening ? Appearance.colors.colPrimary : Appearance.colors.colSubtext)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                    }
                }
            }
            ColumnLayout {
                anchors.centerIn: parent; visible: root.selectedClasses.length === 0; spacing: 6
                MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "event_available"; iconSize: 34; color: Appearance.colors.colSubtext }
                StyledText { Layout.alignment: Qt.AlignHCenter; text: Translation.tr("No classes this day"); color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold }
                StyledText { Layout.alignment: Qt.AlignHCenter; visible: ClassSchedule.list.length === 0; text: Translation.tr("Add your timetable in Super+I → Productivity"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
            }
        }
    }

    component NavButton: Rectangle {
        id: navButton
        required property string symbol
        required property string accessibleName
        signal clicked()
        implicitWidth: 32
        implicitHeight: 32
        radius: 10
        color: navMouse.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
        Accessible.name: accessibleName
        Accessible.role: Accessible.Button
        MaterialSymbol { anchors.centerIn: parent; text: navButton.symbol; iconSize: 20; color: Appearance.colors.colOnLayer2 }
        MouseArea {
            id: navMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: navButton.clicked()
        }
    }
}
