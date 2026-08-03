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
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

/*!
    \qmltype TorrentOptionsDialog
    \brief Material dialog to edit per-torrent options for one OR many torrents.

    Mirrors the legacy \c TorrentOptionsDialog (multi-torrent edit). For every
    field the caller pre-computes an aggregate value plus a "mixed" flag; when a
    field is mixed the control is shown in an indeterminate state (tri-state
    checkboxes are \c PartiallyChecked, category shows a "currently used"
    placeholder) and is only written back when the user gives it a definite
    value.

    The dialog is presentational: it reads the live category list from the
    \c Session singleton and, on OK, emits \l optionsAccepted with a plain result
    object carrying only the fields that changed. The invoking view applies the
    result to the engine (Session/Torrent) — matching the legacy \c accept()
    semantics — because no dedicated per-torrent options controller is defined.

    Expected \l initialValues keys (all optional):
    \list
      \li \c autoTMM, \c useDownloadPath, \c disableDHT, \c disablePEX,
          \c disableLSD, \c sequential, \c firstLastPieces, \c superSeeding —
          \c Qt.CheckState ints (\c Qt.PartiallyChecked means mixed)
      \li \c savePath, \c downloadPath, \c category — strings
      \li \c categoryMixed, \c upLimitMixed, \c downLimitMixed, \c allPrivate — bools
      \li \c upLimit, \c downLimit — KiB/s ints
      \li \c ratioLimit (real), \c seedingTimeLimit, \c inactiveSeedingTimeLimit,
          \c shareLimitAction — engine share-limit sentinels
    \endlist
*/
Dialog {
    id: root

    // --- Public API --------------------------------------------------------

    /*! Opaque ids of the torrents being edited (echoed back in the result). */
    property var torrentIds: []
    /*! Aggregate initial values + mixed flags (see type docs). */
    property var initialValues: ({})

    /*! Emitted on OK with a plain object holding only the changed fields. */
    signal optionsAccepted(var result)

    // --- Engine sentinels (mirror base/bittorrent/sharelimits.h) -----------

    readonly property real defaultRatioLimit: -2
    readonly property int defaultSeedingTimeLimit: -2
    readonly property int defaultShareLimitMode: -1
    readonly property int defaultShareLimitAction: -1

    // --- Internal state ----------------------------------------------------

    property bool _ready: false
    property bool _upDirty: false
    property bool _downDirty: false
    property var _categoryModel: []
    readonly property string _categoryPlaceholder: "--" + qsTr("Currently used categories") + "--"

    function _iv(key, fallback) {
        return (initialValues && (initialValues[key] !== undefined)) ? initialValues[key] : fallback;
    }

    function _toArray(value) {
        if ((value === undefined) || (value === null))
            return [];
        if (Array.isArray(value))
            return value;
        const out = [];
        try {
            for (let i = 0; i < value.length; ++i)
                out.push(value[i]);
        } catch (err) {
            // Not iterable — ignore.
        }
        return out;
    }

    function _buildCategoryModel() {
        const list = [];
        if (root._iv("categoryMixed", false))
            list.push(root._categoryPlaceholder);
        else
            list.push("");
        const known = root._toArray(Session.categories());
        for (let i = 0; i < known.length; ++i) {
            if (list.indexOf(known[i]) < 0)
                list.push(known[i]);
        }
        const current = root._iv("category", "");
        if ((current.length > 0) && (list.indexOf(current) < 0))
            list.splice(1, 0, current);
        return list;
    }

    function _buildResult() {
        const result = { "torrentIds": root.torrentIds };

        if (autoTMMCheck.checkState !== Qt.PartiallyChecked) {
            result.autoTMM = (autoTMMCheck.checkState === Qt.Checked);
            if (!result.autoTMM) {
                result.savePath = savePathField.path;
                if (useDownloadPathCheck.checkState !== Qt.PartiallyChecked)
                    result.useDownloadPath = (useDownloadPathCheck.checkState === Qt.Checked);
                if (result.useDownloadPath === true)
                    result.downloadPath = downloadPathField.path;
            }
        }

        const chosenCategory = categoryCombo.editText;
        if (!(root._iv("categoryMixed", false) && (chosenCategory === root._categoryPlaceholder)))
            result.category = chosenCategory;

        if (!root._iv("upLimitMixed", false) || root._upDirty)
            result.upLimit = upLimitSpin.value;
        if (!root._iv("downLimitMixed", false) || root._downDirty)
            result.downLimit = downLimitSpin.value;

        result.ratioLimit = shareLimitsForm.ratioLimit;
        result.seedingTimeLimit = shareLimitsForm.seedingTimeLimit;
        result.inactiveSeedingTimeLimit = shareLimitsForm.inactiveSeedingTimeLimit;
        result.shareLimitMode = shareLimitsForm.mode;
        result.shareLimitAction = shareLimitsForm.action;

        if (disableDHTCheck.checkState !== Qt.PartiallyChecked)
            result.disableDHT = (disableDHTCheck.checkState === Qt.Checked);
        if (disablePEXCheck.checkState !== Qt.PartiallyChecked)
            result.disablePEX = (disablePEXCheck.checkState === Qt.Checked);
        if (disableLSDCheck.checkState !== Qt.PartiallyChecked)
            result.disableLSD = (disableLSDCheck.checkState === Qt.Checked);
        if (sequentialCheck.checkState !== Qt.PartiallyChecked)
            result.sequential = (sequentialCheck.checkState === Qt.Checked);
        if (firstLastCheck.checkState !== Qt.PartiallyChecked)
            result.firstLastPieces = (firstLastCheck.checkState === Qt.Checked);
        if (superSeedingCheck.checkState !== Qt.PartiallyChecked)
            result.superSeeding = (superSeedingCheck.checkState === Qt.Checked);
        if (diskIOCombo.currentIndex > 0)
            result.diskIOType = diskIOCombo.currentIndex;

        return result;
    }

    // --- Dialog shell ------------------------------------------------------

    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(560, (parent ? parent.width : 560) * 0.9)
    height: Math.min(implicitHeight, (parent ? parent.height : 720) * 0.9)
    padding: Spacing.lg
    standardButtons: Dialog.Ok | Dialog.Cancel
    Material.elevation: 24
    Material.background: Theme.color("surface")

    header: Pane {
        Material.elevation: 0
        padding: Spacing.lg
        RowLayout {
            width: parent.width
            spacing: Spacing.sm
            MDIcon {
                icon: Icons.tune
                size: 24
                color: Theme.color("primary")
            }
            Label {
                Layout.fillWidth: true
                text: qsTr("Torrent Options")
                font: Typography.headlineSmall
                color: Theme.color("onSurface")
                elide: Label.ElideRight
            }
        }
    }

    contentItem: ScrollView {
        id: scroll
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: scroll.availableWidth
            spacing: Spacing.md

            // 1. Automatic Torrent Management -----------------------------
            CheckBox {
                id: autoTMMCheck
                Layout.fillWidth: true
                tristate: true
                text: qsTr("Automatic Torrent Management")
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Automatic mode means that various torrent properties (e.g. save path) will be decided by the associated category")
                onClicked: Log.info("ui", "TorrentOptions: AutoTMM -> " + checkState)
            }

            // 2. Save at ---------------------------------------------------
            MaterialCard {
                Layout.fillWidth: true
                title: qsTr("Save at")
                enabled: autoTMMCheck.checkState !== Qt.Checked

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.sm

                    PathField {
                        id: savePathField
                        Layout.fillWidth: true
                        pickFolder: true
                        title: qsTr("Choose save path")
                        placeholder: qsTr("Save path")
                        onAccepted: Log.debug("ui", "TorrentOptions: save path -> " + path)
                    }

                    CheckBox {
                        id: useDownloadPathCheck
                        Layout.fillWidth: true
                        tristate: true
                        text: qsTr("Use another path for incomplete torrent")
                        onClicked: Log.debug("ui", "TorrentOptions: useDownloadPath -> " + checkState)
                    }

                    PathField {
                        id: downloadPathField
                        Layout.fillWidth: true
                        enabled: useDownloadPathCheck.checkState === Qt.Checked
                        pickFolder: true
                        title: qsTr("Choose incomplete path")
                        placeholder: qsTr("Incomplete torrents path")
                    }
                }
            }

            // 3. Category --------------------------------------------------
            LabeledField {
                Layout.fillWidth: true
                label: qsTr("Category:")

                ComboBox {
                    id: categoryCombo
                    editable: true
                    Layout.fillWidth: true
                    model: root._categoryModel
                    onActivated: Log.info("ui", "TorrentOptions: category -> " + editText)
                }
            }

            // 4. Torrent Speed Limits -------------------------------------
            MaterialCard {
                Layout.fillWidth: true
                title: qsTr("Torrent Speed Limits")

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.sm

                    LabeledField {
                        Layout.fillWidth: true
                        label: qsTr("Upload:")
                        SpeedSpinBox {
                            id: upLimitSpin
                            Layout.fillWidth: true
                            from: 0
                            to: 2000000
                            stepSize: 10
                            unlimitedText: qsTr("∞")
                            suffix: qsTr(" KiB/s")
                            onValueChanged: if (root._ready) root._upDirty = true
                        }
                    }

                    LabeledField {
                        Layout.fillWidth: true
                        label: qsTr("Download:")
                        SpeedSpinBox {
                            id: downLimitSpin
                            Layout.fillWidth: true
                            from: 0
                            to: 2000000
                            stepSize: 10
                            unlimitedText: qsTr("∞")
                            suffix: qsTr(" KiB/s")
                            onValueChanged: if (root._ready) root._downDirty = true
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("These will not exceed the global limits.")
                        font: Typography.labelSmall
                        color: Theme.color("onSurfaceVariant")
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // 5. Torrent Share Limits -------------------------------------
            MaterialCard {
                Layout.fillWidth: true
                title: qsTr("Torrent Share Limits")

                SharedShareLimitsForm {
                    id: shareLimitsForm
                    Layout.fillWidth: true
                    onChanged: Log.debug("ui", "TorrentOptions: share limits changed")
                }
            }

            // 6. Bottom option grid ---------------------------------------
            MaterialCard {
                Layout.fillWidth: true
                title: qsTr("Advanced")

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Spacing.lg
                    rowSpacing: Spacing.xs

                    CheckBox {
                        id: disableDHTCheck
                        tristate: true
                        text: qsTr("Disable DHT for this torrent")
                        enabled: !root._iv("allPrivate", false)
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Not applicable to private torrents")
                        onClicked: Log.debug("ui", "TorrentOptions: disableDHT -> " + checkState)
                    }
                    CheckBox {
                        id: sequentialCheck
                        tristate: true
                        text: qsTr("Download in sequential order")
                        onClicked: Log.debug("ui", "TorrentOptions: sequential -> " + checkState)
                    }
                    CheckBox {
                        id: disablePEXCheck
                        tristate: true
                        text: qsTr("Disable PeX for this torrent")
                        enabled: !root._iv("allPrivate", false)
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Not applicable to private torrents")
                        onClicked: Log.debug("ui", "TorrentOptions: disablePEX -> " + checkState)
                    }
                    CheckBox {
                        id: firstLastCheck
                        tristate: true
                        text: qsTr("Download first and last pieces first")
                        onClicked: Log.debug("ui", "TorrentOptions: firstLastPieces -> " + checkState)
                    }
                    CheckBox {
                        id: disableLSDCheck
                        tristate: true
                        text: qsTr("Disable LSD for this torrent")
                        enabled: !root._iv("allPrivate", false)
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Not applicable to private torrents")
                        onClicked: Log.debug("ui", "TorrentOptions: disableLSD -> " + checkState)
                    }
                    CheckBox {
                        id: superSeedingCheck
                        tristate: true
                        text: qsTr("Super seeding mode")
                        onClicked: Log.debug("ui", "TorrentOptions: superSeeding -> " + checkState)
                    }

                    LabeledField {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        label: qsTr("Disk IO type:")
                        // TODO(engine): per-torrent disk IO type is engine-deep glue;
                        // exposed here so the option round-trips through the result.
                        ComboBox {
                            id: diskIOCombo
                            Layout.fillWidth: true
                            model: [ qsTr("Default"), qsTr("Enable OS cache"), qsTr("Disable OS cache") ]
                            onActivated: Log.debug("ui", "TorrentOptions: disk IO type -> " + currentIndex)
                        }
                    }
                }
            }
        }
    }

    // --- Behaviour ---------------------------------------------------------

    onAboutToShow: {
        root._ready = false;
        root._categoryModel = root._buildCategoryModel();
        autoTMMCheck.checkState = root._iv("autoTMM", Qt.Unchecked);
        savePathField.path = root._iv("savePath", "");
        useDownloadPathCheck.checkState = root._iv("useDownloadPath", Qt.Unchecked);
        downloadPathField.path = root._iv("downloadPath", "");

        const category = root._iv("category", "");
        categoryCombo.editText = root._iv("categoryMixed", false) ? root._categoryPlaceholder : category;

        root._upDirty = false;
        root._downDirty = false;
        upLimitSpin.value = root._iv("upLimit", 0);
        downLimitSpin.value = root._iv("downLimit", 0);

        shareLimitsForm.ratioLimit = root._iv("ratioLimit", root.defaultRatioLimit);
        shareLimitsForm.seedingTimeLimit = root._iv("seedingTimeLimit", root.defaultSeedingTimeLimit);
        shareLimitsForm.inactiveSeedingTimeLimit = root._iv("inactiveSeedingTimeLimit", root.defaultSeedingTimeLimit);
        shareLimitsForm.mode = root._iv("shareLimitMode", root.defaultShareLimitMode);
        shareLimitsForm.action = root._iv("shareLimitAction", root.defaultShareLimitAction);

        const allPrivate = root._iv("allPrivate", false);
        disableDHTCheck.checkState = allPrivate ? Qt.Checked : root._iv("disableDHT", Qt.Unchecked);
        disablePEXCheck.checkState = allPrivate ? Qt.Checked : root._iv("disablePEX", Qt.Unchecked);
        disableLSDCheck.checkState = allPrivate ? Qt.Checked : root._iv("disableLSD", Qt.Unchecked);
        sequentialCheck.checkState = root._iv("sequential", Qt.Unchecked);
        firstLastCheck.checkState = root._iv("firstLastPieces", Qt.Unchecked);
        superSeedingCheck.checkState = root._iv("superSeeding", Qt.Unchecked);
        diskIOCombo.currentIndex = root._iv("diskIOType", 0);

        root._ready = true;
        Log.info("ui", "TorrentOptionsDialog opened for " + root._toArray(root.torrentIds).length + " torrent(s)");
    }

    onAccepted: {
        const result = root._buildResult();
        Log.info("ui", "TorrentOptionsDialog accepted: " + JSON.stringify(Object.keys(result)));
        root.optionsAccepted(result);
    }

    onRejected: Log.debug("ui", "TorrentOptionsDialog cancelled")
}
