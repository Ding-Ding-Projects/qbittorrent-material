/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026  qBittorrent-Material contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

/*!
    \qmltype SuperConfirmDialog
    \brief The deliberate gate in front of an irreversible action.

    Two independently operated keys must both be turned before the confirmation
    slider becomes usable, and only a full-range slide authorizes the action.
    Nothing happens on a partial slide, on one key, or on a slider released
    early — it springs back and the gate stays shut.

    The dialog anchors beside the control that opened it when there is room, and
    falls back to centring only when the anchor would put it off screen. It is
    built in the application's own UI layer; there is no helper window, hosted
    page, or external service anywhere in this flow.

    \section2 Honesty

    \l actionText and \l affectedText state the exact action and exactly what it
    affects. They are rendered verbatim at every language mode and funny level:
    the surrounding copy may be styled, but a user must never be unsure what the
    slider is about to do.

    \section2 Accessibility

    Every control is keyboard-operable with a visible focus ring and a
    screen-reader name that includes its current state. Escape and the emergency
    exit are always available, even mid-slide. Focus returns to
    \l originatingControl on every exit path. When \c ThemeManager.reducedMotion is set
    the progress and completion animations are replaced by their end states
    rather than being played.
*/
Dialog {
    id: root

    /*! Short imperative naming the action, e.g. "Delete 12 torrents". */
    property string actionText: ""

    /*! Exactly what is affected, e.g. "12 torrents and their content files". */
    property string affectedText: ""

    /*! Extra consequence line; shown verbatim when non-empty. */
    property string consequenceText: ""

    /*! Label of the final authorizing control. */
    property string confirmLabel: qsTr("Slide to confirm")

    /*! The control that opened this gate; focus returns here on every exit. */
    property Item originatingControl: null

    /*! Emitted only after both keys and a full-range slide. */
    signal authorized()

    /*! Emitted on escape, emergency exit, or dismissal. */
    signal cancelled()

    readonly property bool bothKeysTurned: keyOne.checked && keyTwo.checked
    readonly property bool authorizing: confirmSlider.value >= confirmSlider.to
    readonly property bool reducedMotion: ThemeManager.reducedMotion === true

    title: qsTr("Confirm an irreversible action")
    modal: true
    parent: Overlay.overlay
    width: Math.min(560, (parent ? parent.width : 560) * 0.92)
    padding: Spacing.xl

    // Anchored beside the originating control where it fits; centred only when
    // anchoring would push the gate off screen.
    x: {
        if (!root.parent)
            return 0
        if (!root.originatingControl)
            return Math.round((root.parent.width - root.width) / 2)
        const origin = root.originatingControl.mapToItem(root.parent, 0, 0)
        const preferred = origin.x + root.originatingControl.width + Spacing.md
        if ((preferred + root.width) <= root.parent.width)
            return preferred
        const leftOf = origin.x - root.width - Spacing.md
        if (leftOf >= 0)
            return leftOf
        return Math.max(0, Math.round((root.parent.width - root.width) / 2))
    }
    y: {
        if (!root.parent)
            return 0
        if (!root.originatingControl)
            return Math.round((root.parent.height - root.height) / 2)
        const origin = root.originatingControl.mapToItem(root.parent, 0, 0)
        return Math.max(Spacing.md,
            Math.min(origin.y, root.parent.height - root.height - Spacing.md))
    }

    // Escape must always work, including mid-slide.
    closePolicy: Popup.CloseOnEscape

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
        border.width: Math.max(1, Spacing.outlineWidth)
        border.color: Theme.color("error")
    }

    function _reset() {
        keyOne.checked = false
        keyTwo.checked = false
        confirmSlider.value = 0
        completion.done = false
    }

    function _restoreFocus() {
        if (root.originatingControl)
            root.originatingControl.forceActiveFocus()
    }

    onOpened: {
        Log.info("ui", "SuperConfirmDialog opened for: " + root.actionText)
        root._reset()
        keyOne.forceActiveFocus()
    }

    onRejected: {
        Log.info("ui", "SuperConfirmDialog cancelled: " + root.actionText)
        root._reset()
        root.cancelled()
        root._restoreFocus()
    }

    header: RowLayout {
        spacing: Spacing.sm

        MDIcon {
            icon: Icons.error
            size: Spacing.iconSize
            color: Theme.color("error")
            Layout.leftMargin: Spacing.lg
        }
        Label {
            text: root.title
            font: Typography.headlineSmall
            color: Theme.color("onSurface")
            elide: Text.ElideRight
            Layout.fillWidth: true
            topPadding: Spacing.lg
            bottomPadding: Spacing.sm
            rightPadding: Spacing.lg
        }
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        // ---- The facts, verbatim -------------------------------------------
        Label {
            Layout.fillWidth: true
            text: root.actionText
            font: Typography.titleMedium
            color: Theme.color("onSurface")
            wrapMode: Text.WordWrap
        }

        Label {
            Layout.fillWidth: true
            visible: root.affectedText.length > 0
            text: qsTr("This affects: %1").arg(root.affectedText)
            font: Typography.bodyMedium
            color: Theme.color("onSurface")
            wrapMode: Text.WordWrap
        }

        Label {
            Layout.fillWidth: true
            visible: root.consequenceText.length > 0
            text: root.consequenceText
            font: Typography.bodyMedium
            color: Theme.color("error")
            wrapMode: Text.WordWrap
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("This cannot be undone.")
            font: Typography.labelMedium
            color: Theme.color("error")
            wrapMode: Text.WordWrap
        }

        MenuSeparator { Layout.fillWidth: true }

        // ---- Two independent keys ------------------------------------------
        Label {
            text: qsTr("Turn both keys to arm the confirmation.")
            font: Typography.labelMedium
            color: Theme.color("onSurfaceVariant")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Spacing.lg

            Switch {
                id: keyOne
                text: qsTr("First key")
                Accessible.name: qsTr("First key, %1")
                    .arg(checked ? qsTr("turned") : qsTr("not turned"))
                // Turning a key back off disarms the slider immediately.
                onCheckedChanged: if (!checked) confirmSlider.value = 0
            }

            Switch {
                id: keyTwo
                text: qsTr("Second key")
                Accessible.name: qsTr("Second key, %1")
                    .arg(checked ? qsTr("turned") : qsTr("not turned"))
                onCheckedChanged: if (!checked) confirmSlider.value = 0
            }
        }

        // ---- The full-range slider -----------------------------------------
        Label {
            Layout.fillWidth: true
            text: root.bothKeysTurned
                ? root.confirmLabel
                : qsTr("Both keys are required before this can be confirmed.")
            font: Typography.bodyMedium
            color: root.bothKeysTurned
                ? Theme.color("onSurface") : Theme.color("onSurfaceVariant")
            wrapMode: Text.WordWrap
        }

        Slider {
            id: confirmSlider
            Layout.fillWidth: true
            from: 0
            to: 1
            enabled: root.bothKeysTurned && !completion.done
            Accessible.name: qsTr("%1. Slide fully to the right to confirm.")
                .arg(root.confirmLabel)

            // A slider released before the end springs back: a partial slide is
            // not a decision, and leaving it parked near the end would let the
            // next stray click finish an irreversible action.
            onPressedChanged: {
                if (pressed || completion.done)
                    return
                if (value < to)
                    value = 0
                else
                    root._authorize()
            }
        }

        // Dramatic while it moves, but never blocking, and replaced by its end
        // state when the user has asked for reduced motion.
        ProgressBar {
            id: slideProgress
            Layout.fillWidth: true
            from: 0
            to: 1
            value: confirmSlider.value
            visible: root.bothKeysTurned

            Behavior on value {
                enabled: !root.reducedMotion
                NumberAnimation { duration: Spacing.motionFast }
            }
        }

        Label {
            id: completion
            property bool done: false
            Layout.fillWidth: true
            visible: done
            text: qsTr("Authorized.")
            font: Typography.titleMedium
            color: Theme.color("success")
            horizontalAlignment: Text.AlignHCenter
            opacity: done ? 1 : 0

            Behavior on opacity {
                enabled: !root.reducedMotion
                NumberAnimation { duration: Spacing.motionBase }
            }
        }
    }

    function _authorize() {
        completion.done = true
        Log.info("ui", "SuperConfirmDialog authorized: " + root.actionText)
        // Let the completion state render before the dialog goes away; with
        // reduced motion this is immediate.
        if (root.reducedMotion) {
            root._finish()
        } else {
            finishTimer.start()
        }
    }

    function _finish() {
        root.authorized()
        root.close()
        root._reset()
        root._restoreFocus()
    }

    Timer {
        id: finishTimer
        interval: Spacing.motionBase
        onTriggered: root._finish()
    }

    footer: DialogButtonBox {
        spacing: Spacing.sm
        padding: Spacing.lg
        topPadding: Spacing.sm

        // Always available, including mid-slide.
        Button {
            id: emergencyExit
            text: qsTr("Emergency exit")
            flat: true
            Accessible.name: qsTr("Emergency exit. Cancels without doing anything.")
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
            onClicked: root.reject()
        }
    }
}
