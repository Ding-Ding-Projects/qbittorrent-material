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
import QtQuick.Window
import qBittorrent

/*!
    \qmltype SearchableMenu
    \brief The base every context menu derives from: its own search field, its
           own anchored regex builder, and a width that cannot clip a shortcut.

    Every context menu carries a keyboard-accessible search field that filters
    only that menu's visible items, without changing what any item does. The
    field is a \l FilterTextField, so each menu also gets the anchored regex
    builder that belongs to that specific field — plain text stays the default
    and regex is an explicit opt-in.

    Deriving menus declare their items normally and gate visibility on
    \l matches():

    \qml
    SearchableMenu {
        id: root
        MenuItem {
            text: qsTr("Start")
            visible: root.matches(text)
            height: visible ? implicitHeight : 0
        }
    }
    \endqml

    \section2 Width

    Menu items render their keyboard shortcut in a right-anchored Label. An
    anchored child contributes nothing to \c implicitWidth, so a menu sized
    purely from its content collapses to the label width and paints the shortcut
    over the text. \l minimumMenuWidth establishes a floor wide enough for a
    label and its shortcut, and the menu still grows past it for longer content.

    \section2 Height

    The menu is bounded by the window and scrolls inside that bound. Capping the
    height and clipping instead would delete the last items with no scrollbar to
    say anything is missing.
*/
Menu {
    id: root

    /*! The live query. Empty means "show everything". */
    property string filterText: ""
    /*! Whether \l filterText is a regular expression rather than plain text. */
    property bool regexEnabled: false
    /*! Flags applied when \l regexEnabled is true. */
    property string regexFlags: "iu"

    /*! Placeholder for the search field. */
    property string searchPlaceholder: qsTr("Search actions")
    /*! Screen-reader name for the search field. */
    property string searchAccessibleName: qsTr("Search menu actions")

    /*! Floor for the menu width; see the type documentation. */
    property int minimumMenuWidth: Math.round(360 * Spacing.density)

    /*! Set false for a menu whose items genuinely cannot be filtered. */
    property bool searchEnabled: true

    modal: false
    Material.elevation: Spacing.elevationMenu

    // Grow past the floor for longer content, never below it.
    implicitWidth: Math.max(root.minimumMenuWidth,
        root.implicitContentWidth + root.leftPadding + root.rightPadding)

    readonly property int maxMenuHeight: root.Window.window
        ? Math.round(root.Window.window.height * 0.85) : 640
    height: Math.min(implicitHeight, root.maxMenuHeight)

    /*!
        True when \a label should stay visible under the current query.

        Regex matching runs through the application's own engine
        (\c QRegularExpression) rather than JavaScript's, so a pattern behaves
        here exactly as it does in every other search surface. An invalid
        pattern matches nothing rather than throwing.
    */
    function matches(label) {
        if (root.filterText.length === 0)
            return true

        const text = String(label)
        if (!root.regexEnabled) {
            return text.toLocaleLowerCase().includes(
                root.filterText.toLocaleLowerCase())
        }

        // The result map's match tally is "count" — reading a wrong key yields
        // undefined, `undefined > 0` is false, and every item silently vanishes
        // the moment regex mode is switched on.
        const evaluation = WorkspaceManager.evaluateRegularExpression(
            root.filterText, root.regexFlags, text)
        return (evaluation.valid === true) && (evaluation.count > 0)
    }

    // Via Connections, not `onAboutToShow:`/`onOpened:` handlers: a handler
    // declared here is replaced outright when a deriving menu declares its own,
    // which would silently cost that menu its reset and its keyboard focus.
    Connections {
        target: root

        function onAboutToShow() {
            root.filterText = ""
        }

        function onOpened() {
            if (root.searchEnabled)
                Qt.callLater(menuSearchField.forceActiveFocus)
        }
    }

    // The search field is the menu's first item so it is the first thing the
    // keyboard reaches, and Escape closes the whole menu from inside it.
    MenuItem {
        id: menuSearchItem
        visible: root.searchEnabled
        height: visible ? implicitHeight : 0
        focusPolicy: Qt.NoFocus
        implicitHeight: Spacing.controlHeight + (Spacing.sm * 2)
        leftPadding: Spacing.sm
        rightPadding: Spacing.sm

        contentItem: FilterTextField {
            id: menuSearchField
            enabled: true
            placeholder: root.searchPlaceholder
            text: root.filterText
            regexEnabled: root.regexEnabled
            regexFlags: root.regexFlags
            builderTitle: qsTr("Regex Builder")
            Accessible.name: root.searchAccessibleName

            onTextChanged: root.filterText = text
            onRegexEnabledChanged: root.regexEnabled = regexEnabled
            onRegexApplied: (pattern, flags) => {
                root.regexEnabled = true
                root.regexFlags = flags
                root.filterText = pattern
            }
            Keys.onEscapePressed: root.close()
        }
    }

    MenuSeparator { visible: root.searchEnabled }
}
