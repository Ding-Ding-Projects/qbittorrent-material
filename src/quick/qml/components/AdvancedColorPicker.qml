/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import qBittorrent

/*!
    \qmltype AdvancedColorPicker
    \brief Bounded, app-painted continuous color picker and translator.

    The conversion formulas intentionally match the Infinite color studio in
    WorkspaceTabSettingsDialog. This reusable surface adds transactional
    Apply/Cancel behavior, viewport collision handling, persisted recent/custom
    colors, keyboard operation, contrast evidence, and explicit output-alpha
    policy for callers such as the Material seed-color editor.
*/
Popup {
    id: root
    objectName: "advancedColorPicker"

    signal colorPreviewed(color value)
    signal colorAccepted(color value)
    signal colorCanceled(color originalValue)

    property string title: qsTr("Advanced color picker")
    property color selectedColor: "#FF6750A4"
    property color originalColor: "#FF6750A4"
    property color contrastAgainst: Theme.color("surface")
    property bool forceOpaque: false
    property var returnFocusItem: null
    property var anchorItem: null
    property bool acceptedThisOpen: false
    property bool updatingColor: false
    property bool parsingClipped: false
    property bool pendingClip: false
    property color pendingClippedColor: "transparent"
    property real pickerHue: 0
    property real pickerSaturation: 0
    property real pickerValue: 0
    property real pickerAlpha: 1
    property var recentColors: []
    property real dragOriginX: 0
    property real dragOriginY: 0
    property bool userPositioned: false

    readonly property int viewportMargin: Spacing.md
    readonly property int horizontalViewportMargin: parent && parent.width >= viewportMargin * 2
        ? viewportMargin : 0
    readonly property int verticalViewportMargin: parent && parent.height >= viewportMargin * 2
        ? viewportMargin : 0
    readonly property int preferredWidth: 820
    readonly property int preferredHeight: 720
    readonly property string strictNumberPattern:
        "[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?"
    readonly property var colorSpaceModel: [
        { label: qsTr("HEX / HEX8"), hint: qsTr("#RRGGBB or Qt #AARRGGBB") },
        { label: qsTr("RGB / RGBA"), hint: qsTr("rgba(0–255, 0–255, 0–255, 0–1)") },
        { label: qsTr("HSL / HSLA"), hint: qsTr("hsla(deg, %, %, 0–1)") },
        { label: qsTr("HSV / HSB"), hint: qsTr("hsva(deg, %, %, 0–1)") },
        { label: qsTr("HWB"), hint: qsTr("hwb(deg % % / 0–1)") },
        { label: qsTr("CIELAB"), hint: qsTr("lab(L a b / 0–1)") },
        { label: qsTr("LCH"), hint: qsTr("lch(L C deg / 0–1)") },
        { label: qsTr("OKLab"), hint: qsTr("oklab(L a b / 0–1)") },
        { label: qsTr("OKLCH"), hint: qsTr("oklch(L C deg / 0–1)") },
        { label: qsTr("CMYK"), hint: qsTr("cmyka(%, %, %, %, 0–1)") },
        { label: qsTr("Named color"), hint: qsTr("A Qt/SVG named color, when defined") }
    ]
    readonly property var customPalette: [
        "#FF000000", "#FFFFFFFF", "#FF6750A4", "#FFFF0000",
        "#FFFFA500", "#FFFFFF00", "#FF00AA55", "#FF0088FF",
        "#FF0000FF", "#FF800080", "#FFFF00FF", "#00000000"
    ]
    readonly property string pickerPropertyCorpus: qsTr(
        "Saturation value brightness hue alpha opacity transparency HEX HEX8 RGB RGBA HSL HSLA HSV HSB HWB CIELAB LCH OKLab OKLCH CMYK named color translation gamut clipping contrast copy preview custom palette recent saved colors")
    readonly property bool showSaturationValue: propertyMatches(qsTr(
        "Saturation value brightness two-dimensional continuous color field"))
    readonly property bool showHue: propertyMatches(qsTr("Hue degrees color wheel"))
    readonly property bool showAlpha: propertyMatches(qsTr("Alpha opacity transparency"))
    readonly property bool showTranslator: propertyMatches(qsTr(
        "HEX HEX8 RGB RGBA HSL HSLA HSV HSB HWB CIELAB LCH OKLab OKLCH CMYK named color translation gamut clipping contrast copy preview"))
    readonly property bool showCustomPalette: propertyMatches(qsTr(
        "Custom palette swatches save color"))
    readonly property bool showRecentColors: propertyMatches(qsTr(
        "Recent saved custom colors"))
    readonly property bool hasPropertyMatch: showSaturationValue || showHue || showAlpha
        || showTranslator || showCustomPalette || showRecentColors

    parent: Overlay.overlay
    width: parent
        ? Math.min(preferredWidth, Math.max(0, parent.width - horizontalViewportMargin * 2))
        : preferredWidth
    height: parent
        ? Math.min(preferredHeight, Math.max(0, parent.height - verticalViewportMargin * 2))
        : preferredHeight
    modal: false
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value))
    }

    function propertyMatches(corpus) {
        var query = pickerPropertySearch.text.trim()
        if (!query.length)
            return true
        if (pickerPropertySearch.regexEnabled) {
            var result = WorkspaceManager.evaluateRegularExpression(query,
                pickerPropertySearch.regexFlags, corpus)
            return result.valid && result.count > 0
        }
        return corpus.toLocaleLowerCase().indexOf(query.toLocaleLowerCase()) >= 0
    }

    function moveWithinViewport(candidateX, candidateY) {
        if (!parent)
            return
        var maximumX = Math.max(horizontalViewportMargin,
            parent.width - width - horizontalViewportMargin)
        var maximumY = Math.max(verticalViewportMargin,
            parent.height - height - verticalViewportMargin)
        x = clamp(candidateX, horizontalViewportMargin, maximumX)
        y = clamp(candidateY, verticalViewportMargin, maximumY)
    }

    function placeAtAnchor() {
        if (!parent)
            return
        if (!anchorItem || !anchorItem.mapToItem) {
            moveWithinViewport((parent.width - width) / 2, (parent.height - height) / 2)
            return
        }
        var topLeft = anchorItem.mapToItem(parent, 0, 0)
        var below = topLeft.y + anchorItem.height + Spacing.xs
        var above = topLeft.y - height - Spacing.xs
        var candidateY = below + height + verticalViewportMargin <= parent.height ? below : above
        moveWithinViewport(topLeft.x + anchorItem.width - width, candidateY)
    }

    function settleAfterGeometryChange() {
        if (!opened)
            return
        Qt.callLater(function() {
            if (root.userPositioned)
                root.moveWithinViewport(root.x, root.y)
            else
                root.placeAtAnchor()
        })
    }

    function openFor(anchor, value, backgroundColor) {
        anchorItem = anchor
        returnFocusItem = anchor
        originalColor = colorValue(value, Theme.color("primary"))
        contrastAgainst = colorValue(backgroundColor, Theme.color("surface"))
        acceptedThisOpen = false
        userPositioned = false
        pendingClip = false
        colorError.text = ""
        loadRecentColors()
        setPickerColor(originalColor, false)
        open()
    }

    function cancelPicker() {
        acceptedThisOpen = false
        close()
    }

    function acceptPicker() {
        // The translator field is editable independently from selectedColor.
        // Parse it first so the footer cannot silently accept the previous
        // selection when a user clicks Apply without pressing Enter or Preview.
        if (!acceptFormattedColor())
            return
        acceptedThisOpen = true
        var output = outputColor()
        addRecentColor(output)
        colorAccepted(output)
        close()
    }

    onOpened: {
        placeAtAnchor()
        Qt.callLater(function() { saturationValueField.forceActiveFocus(Qt.PopupFocusReason) })
    }
    onClosed: {
        if (!acceptedThisOpen)
            colorCanceled(originalColor)
        var focusTarget = returnFocusItem
        if (focusTarget && focusTarget.forceActiveFocus)
            Qt.callLater(function() { focusTarget.forceActiveFocus(Qt.PopupFocusReason) })
    }
    onWidthChanged: settleAfterGeometryChange()
    onHeightChanged: settleAfterGeometryChange()

    function twoHex(value) {
        var result = Math.round(clamp(value, 0, 1) * 255).toString(16).toUpperCase()
        return result.length < 2 ? "0" + result : result
    }

    function colorHex8(colorValue) {
        var color = colorValue || selectedColor
        return "#" + twoHex(color.a) + twoHex(color.r) + twoHex(color.g) + twoHex(color.b)
    }

    function colorHex(colorValue) {
        var color = colorValue || selectedColor
        if (color.a < 0.999999)
            return colorHex8(color)
        return "#" + twoHex(color.r) + twoHex(color.g) + twoHex(color.b)
    }

    function parseHex(value) {
        var text = String(value).trim().toUpperCase()
        if (/^#[0-9A-F]{3}$/.test(text)) {
            return Qt.rgba(parseInt(text[1] + text[1], 16) / 255,
                parseInt(text[2] + text[2], 16) / 255,
                parseInt(text[3] + text[3], 16) / 255, 1)
        }
        if (/^#[0-9A-F]{6}$/.test(text))
            text = "#FF" + text.substring(1)
        if (!/^#[0-9A-F]{8}$/.test(text))
            return null
        return Qt.rgba(parseInt(text.substring(3, 5), 16) / 255,
            parseInt(text.substring(5, 7), 16) / 255,
            parseInt(text.substring(7, 9), 16) / 255,
            parseInt(text.substring(1, 3), 16) / 255)
    }

    function colorValue(value, fallback) {
        if (value && value.r !== undefined)
            return value
        var parsed = parseHex(value)
        if (parsed !== null)
            return parsed
        if (ThemeManager.isValidColor(String(value)))
            return ThemeManager.parseColorValue(String(value))
        if (fallback && fallback.r !== undefined)
            return fallback
        parsed = parseHex(fallback)
        if (parsed !== null)
            return parsed
        if (ThemeManager.isValidColor(String(fallback)))
            return ThemeManager.parseColorValue(String(fallback))
        return Qt.rgba(0, 0, 0, 1)
    }

    function rgbToHsv(color) {
        var maximum = Math.max(color.r, color.g, color.b)
        var minimum = Math.min(color.r, color.g, color.b)
        var delta = maximum - minimum
        var hue = 0
        if (delta > 0) {
            if (maximum === color.r)
                hue = ((color.g - color.b) / delta) % 6
            else if (maximum === color.g)
                hue = (color.b - color.r) / delta + 2
            else
                hue = (color.r - color.g) / delta + 4
            hue = ((hue * 60) + 360) % 360
        }
        return { h: hue, s: maximum === 0 ? 0 : delta / maximum,
            v: maximum, a: color.a }
    }

    function rgbToHsl(color) {
        var maximum = Math.max(color.r, color.g, color.b)
        var minimum = Math.min(color.r, color.g, color.b)
        var delta = maximum - minimum
        var lightness = (maximum + minimum) / 2
        var hue = 0
        if (delta > 0) {
            if (maximum === color.r)
                hue = ((color.g - color.b) / delta) % 6
            else if (maximum === color.g)
                hue = (color.b - color.r) / delta + 2
            else
                hue = (color.r - color.g) / delta + 4
            hue = ((hue * 60) + 360) % 360
        }
        var saturation = delta === 0 ? 0 : delta / (1 - Math.abs(2 * lightness - 1))
        return { h: hue, s: saturation, l: lightness, a: color.a }
    }

    function srgbToLinear(value) {
        return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
    }

    function linearToSrgb(value) {
        return value <= 0.0031308 ? value * 12.92 : 1.055 * Math.pow(value, 1 / 2.4) - 0.055
    }

    function rgbToLab(color) {
        var r = srgbToLinear(color.r)
        var g = srgbToLinear(color.g)
        var b = srgbToLinear(color.b)
        var x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        var y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        var z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        var epsilon = 216 / 24389
        var kappa = 24389 / 27
        function f(t) { return t > epsilon ? Math.pow(t, 1 / 3) : (kappa * t + 16) / 116 }
        var fx = f(x), fy = f(y), fz = f(z)
        return { l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz), alpha: color.a }
    }

    function signedCubeRoot(value) {
        return value < 0 ? -Math.pow(-value, 1 / 3) : Math.pow(value, 1 / 3)
    }

    function rgbToOklab(color) {
        var r = srgbToLinear(color.r), g = srgbToLinear(color.g), b = srgbToLinear(color.b)
        var l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        var m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        var s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        l = signedCubeRoot(l); m = signedCubeRoot(m); s = signedCubeRoot(s)
        return {
            l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
            alpha: color.a
        }
    }

    function makeRgb(red, green, blue, alpha) {
        if (!Number.isFinite(red)) {
            parsingClipped = true
            red = red > 0 ? 1 : 0
        }
        if (!Number.isFinite(green)) {
            parsingClipped = true
            green = green > 0 ? 1 : 0
        }
        if (!Number.isFinite(blue)) {
            parsingClipped = true
            blue = blue > 0 ? 1 : 0
        }
        if (!Number.isFinite(alpha)) {
            parsingClipped = true
            alpha = alpha > 0 ? 1 : 0
        }
        return Qt.rgba(boundedGamutUnit(red), boundedGamutUnit(green),
            boundedGamutUnit(blue),
            boundedUnit(alpha))
    }

    function labToRgb(lightness, greenRed, blueYellow, alpha) {
        var fy = (lightness + 16) / 116
        var fx = greenRed / 500 + fy
        var fz = fy - blueYellow / 200
        var epsilon = 216 / 24389
        var kappa = 24389 / 27
        function finv(t) {
            var cube = t * t * t
            return cube > epsilon ? cube : (116 * t - 16) / kappa
        }
        var x = 0.95047 * finv(fx)
        var y = finv(fy)
        var z = 1.08883 * finv(fz)
        var r = linearToSrgb(3.2404542 * x - 1.5371385 * y - 0.4985314 * z)
        var g = linearToSrgb(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z)
        var b = linearToSrgb(0.0556434 * x - 0.2040259 * y + 1.0572252 * z)
        return makeRgb(r, g, b, alpha)
    }

    function oklabToRgb(lightness, greenRed, blueYellow, alpha) {
        var l = lightness + 0.3963377774 * greenRed + 0.2158037573 * blueYellow
        var m = lightness - 0.1055613458 * greenRed - 0.0638541728 * blueYellow
        var s = lightness - 0.0894841775 * greenRed - 1.2914855480 * blueYellow
        l = l * l * l; m = m * m * m; s = s * s * s
        var r = linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)
        var g = linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)
        var b = linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        return makeRgb(r, g, b, alpha)
    }

    function strictNumbers(value, expression, count) {
        // Every color-space parser supplies a complete anchored grammar. This
        // prevents friendly-looking junk such as "rgb(1,2,3) surprise 4" from
        // being reduced to whichever numbers happen to occur in it.
        if (expression.charAt(0) !== "^"
                || expression.charAt(expression.length - 1) !== "$")
            return null
        var match = new RegExp(expression, "i").exec(String(value).trim())
        if (match === null || match.length !== count + 1)
            return null
        var result = []
        for (var i = 1; i <= count; ++i) {
            var number = Number(match[i])
            if (!Number.isFinite(number))
                return null
            result.push(number)
        }
        return result
    }

    function fixed(value, digits) {
        var result = Number(value).toFixed(digits)
        return result.replace(/\.0+$|(?:(\.\d*?[1-9]))0+$/, "$1")
    }

    function nameForColor(color) {
        return ThemeManager.nameForColor(color)
    }

    function formattedColor(index, color) {
        var hsv = rgbToHsv(color)
        var hsl = rgbToHsl(color)
        if (index === 0)
            return colorHex(color)
        if (index === 1)
            return "rgba(" + Math.round(color.r * 255) + ", " + Math.round(color.g * 255)
                + ", " + Math.round(color.b * 255) + ", " + fixed(color.a, 3) + ")"
        if (index === 2)
            return "hsla(" + fixed(hsl.h, 2) + ", " + fixed(hsl.s * 100, 2) + "%, "
                + fixed(hsl.l * 100, 2) + "%, " + fixed(color.a, 3) + ")"
        if (index === 3)
            return "hsva(" + fixed(hsv.h, 2) + ", " + fixed(hsv.s * 100, 2) + "%, "
                + fixed(hsv.v * 100, 2) + "%, " + fixed(color.a, 3) + ")"
        if (index === 4) {
            var white = Math.min(color.r, color.g, color.b)
            var black = 1 - Math.max(color.r, color.g, color.b)
            return "hwb(" + fixed(hsv.h, 2) + " " + fixed(white * 100, 2) + "% "
                + fixed(black * 100, 2) + "% / " + fixed(color.a, 3) + ")"
        }
        if (index === 5) {
            var lab = rgbToLab(color)
            return "lab(" + fixed(lab.l, 3) + " " + fixed(lab.a, 3) + " "
                + fixed(lab.b, 3) + " / " + fixed(color.a, 3) + ")"
        }
        if (index === 6) {
            lab = rgbToLab(color)
            var chroma = Math.sqrt(lab.a * lab.a + lab.b * lab.b)
            var angle = (Math.atan2(lab.b, lab.a) * 180 / Math.PI + 360) % 360
            return "lch(" + fixed(lab.l, 3) + " " + fixed(chroma, 3) + " "
                + fixed(angle, 3) + " / " + fixed(color.a, 3) + ")"
        }
        var oklab = rgbToOklab(color)
        if (index === 7)
            return "oklab(" + fixed(oklab.l, 5) + " " + fixed(oklab.a, 5) + " "
                + fixed(oklab.b, 5) + " / " + fixed(color.a, 3) + ")"
        if (index === 8) {
            chroma = Math.sqrt(oklab.a * oklab.a + oklab.b * oklab.b)
            angle = (Math.atan2(oklab.b, oklab.a) * 180 / Math.PI + 360) % 360
            return "oklch(" + fixed(oklab.l, 5) + " " + fixed(chroma, 5) + " "
                + fixed(angle, 3) + " / " + fixed(color.a, 3) + ")"
        }
        if (index === 9) {
            var k = 1 - Math.max(color.r, color.g, color.b)
            var c = k >= 0.999999 ? 0 : (1 - color.r - k) / (1 - k)
            var m = k >= 0.999999 ? 0 : (1 - color.g - k) / (1 - k)
            var y = k >= 0.999999 ? 0 : (1 - color.b - k) / (1 - k)
            return "cmyka(" + fixed(c * 100, 2) + "%, " + fixed(m * 100, 2) + "%, "
                + fixed(y * 100, 2) + "%, " + fixed(k * 100, 2) + "%, "
                + fixed(color.a, 3) + ")"
        }
        var name = nameForColor(color)
        // QColor only has names for a finite set of opaque colors. An exact
        // ARGB fallback keeps the Named Color page round-trippable for every
        // other color instead of emitting an unparseable "custom (...)" label.
        return name.length ? name : colorHex8(color)
    }

    function boundedRange(value, minimum, maximum) {
        if (!Number.isFinite(value)) {
            parsingClipped = true
            return value > 0 ? maximum : minimum
        }
        if (value < minimum || value > maximum)
            parsingClipped = true
        return clamp(value, minimum, maximum)
    }

    function boundedUnit(value) {
        return boundedRange(value, 0, 1)
    }

    function boundedGamutUnit(value) {
        // Perceptual conversions can land a few floating-point ulps beyond the
        // sRGB boundary. Clamp that numerical dust silently, but require an
        // explicit clipping decision for a real out-of-gamut channel.
        var epsilon = 0.000001
        if (!Number.isFinite(value)) {
            parsingClipped = true
            return value > 0 ? 1 : 0
        }
        if (value < -epsilon || value > 1 + epsilon)
            parsingClipped = true
        return clamp(value, 0, 1)
    }

    function parsedFormattedColor(index, value) {
        parsingClipped = false
        var n = strictNumberPattern
        var values = null
        if (index === 0)
            return parseHex(value)
        if (index === 10) {
            var namedValue = String(value).trim()
            var fallbackHex = parseHex(namedValue)
            if (fallbackHex !== null)
                return fallbackHex
            if (!ThemeManager.isValidColor(namedValue))
                return null
            return ThemeManager.parseColorValue(namedValue)
        }

        if (index === 1) {
            values = strictNumbers(value,
                "^rgb\\(\\s*(" + n + ")\\s*,\\s*(" + n + ")\\s*,\\s*("
                    + n + ")\\s*\\)$", 3)
            if (values === null)
                values = strictNumbers(value,
                    "^rgba\\(\\s*(" + n + ")\\s*,\\s*(" + n + ")\\s*,\\s*("
                        + n + ")\\s*,\\s*(" + n + ")\\s*\\)$", 4)
            if (values === null)
                return null
            return makeRgb(values[0] / 255, values[1] / 255, values[2] / 255,
                values.length === 4 ? values[3] : 1)
        }

        if (index === 2) {
            values = strictNumbers(value,
                "^hsl\\(\\s*(" + n + ")\\s*,\\s*(" + n + ")%\\s*,\\s*("
                    + n + ")%\\s*\\)$", 3)
            if (values === null)
                values = strictNumbers(value,
                    "^hsla\\(\\s*(" + n + ")\\s*,\\s*(" + n + ")%\\s*,\\s*("
                        + n + ")%\\s*,\\s*(" + n + ")\\s*\\)$", 4)
            if (values === null)
                return null
            var hslHue = boundedRange(values[0], 0, 360)
            return Qt.hsla((hslHue % 360) / 360,
                boundedUnit(values[1] / 100), boundedUnit(values[2] / 100),
                boundedUnit(values.length === 4 ? values[3] : 1))
        }

        if (index === 3) {
            values = strictNumbers(value,
                "^(?:hsv|hsb)\\(\\s*(" + n + ")\\s*,\\s*(" + n
                    + ")%\\s*,\\s*(" + n + ")%\\s*\\)$", 3)
            if (values === null)
                values = strictNumbers(value,
                    "^(?:hsva|hsba)\\(\\s*(" + n + ")\\s*,\\s*(" + n
                        + ")%\\s*,\\s*(" + n + ")%\\s*,\\s*(" + n
                        + ")\\s*\\)$", 4)
            if (values === null)
                return null
            var hsvHue = boundedRange(values[0], 0, 360)
            return Qt.hsva((hsvHue % 360) / 360,
                boundedUnit(values[1] / 100), boundedUnit(values[2] / 100),
                boundedUnit(values.length === 4 ? values[3] : 1))
        }

        if (index === 4) {
            values = strictNumbers(value,
                "^hwb\\(\\s*(" + n + ")\\s+(" + n + ")%\\s+(" + n
                    + ")%\\s*\\)$", 3)
            if (values === null)
                values = strictNumbers(value,
                    "^hwb\\(\\s*(" + n + ")\\s+(" + n + ")%\\s+(" + n
                        + ")%\\s*\\/\\s*(" + n + ")\\s*\\)$", 4)
            if (values === null)
                return null
            var hue = (boundedRange(values[0], 0, 360) % 360) / 360
            var white = boundedUnit(values[1] / 100)
            var black = boundedUnit(values[2] / 100)
            var sum = white + black
            if (sum > 1) { white /= sum; black /= sum; parsingClipped = true }
            var pure = Qt.hsva(hue, 1, 1, 1)
            var factor = 1 - white - black
            return makeRgb(pure.r * factor + white, pure.g * factor + white,
                pure.b * factor + white, boundedUnit(values.length === 4 ? values[3] : 1))
        }

        if (index === 5) {
            values = strictNumbers(value,
                "^lab\\(\\s*(" + n + ")\\s+(" + n + ")\\s+(" + n
                    + ")\\s*\\)$", 3)
            if (values === null)
                values = strictNumbers(value,
                    "^lab\\(\\s*(" + n + ")\\s+(" + n + ")\\s+(" + n
                        + ")\\s*\\/\\s*(" + n + ")\\s*\\)$", 4)
            if (values === null)
                return null
            return labToRgb(boundedRange(values[0], 0, 100), values[1], values[2],
                boundedUnit(values.length === 4 ? values[3] : 1))
        }

        if (index === 6) {
            values = strictNumbers(value,
                "^lch\\(\\s*(" + n + ")\\s+(" + n + ")\\s+(" + n
                    + ")\\s*\\)$", 3)
            if (values === null)
                values = strictNumbers(value,
                    "^lch\\(\\s*(" + n + ")\\s+(" + n + ")\\s+(" + n
                        + ")\\s*\\/\\s*(" + n + ")\\s*\\)$", 4)
            if (values === null)
                return null
            var lchChroma = values[1]
            if (lchChroma < 0) {
                parsingClipped = true
                lchChroma = 0
            }
            var radians = boundedRange(values[2], 0, 360) * Math.PI / 180
            return labToRgb(boundedRange(values[0], 0, 100),
                lchChroma * Math.cos(radians), lchChroma * Math.sin(radians),
                boundedUnit(values.length === 4 ? values[3] : 1))
        }

        if (index === 7) {
            values = strictNumbers(value,
                "^oklab\\(\\s*(" + n + ")\\s+(" + n + ")\\s+(" + n
                    + ")\\s*\\)$", 3)
            if (values === null)
                values = strictNumbers(value,
                    "^oklab\\(\\s*(" + n + ")\\s+(" + n + ")\\s+(" + n
                        + ")\\s*\\/\\s*(" + n + ")\\s*\\)$", 4)
            if (values === null)
                return null
            return oklabToRgb(boundedUnit(values[0]), values[1], values[2],
                boundedUnit(values.length === 4 ? values[3] : 1))
        }

        if (index === 8) {
            values = strictNumbers(value,
                "^oklch\\(\\s*(" + n + ")\\s+(" + n + ")\\s+(" + n
                    + ")\\s*\\)$", 3)
            if (values === null)
                values = strictNumbers(value,
                    "^oklch\\(\\s*(" + n + ")\\s+(" + n + ")\\s+(" + n
                        + ")\\s*\\/\\s*(" + n + ")\\s*\\)$", 4)
            if (values === null)
                return null
            var oklchChroma = values[1]
            if (oklchChroma < 0) {
                parsingClipped = true
                oklchChroma = 0
            }
            radians = boundedRange(values[2], 0, 360) * Math.PI / 180
            return oklabToRgb(boundedUnit(values[0]),
                oklchChroma * Math.cos(radians), oklchChroma * Math.sin(radians),
                boundedUnit(values.length === 4 ? values[3] : 1))
        }

        if (index === 9) {
            values = strictNumbers(value,
                "^cmyk\\(\\s*(" + n + ")%\\s*,\\s*(" + n + ")%\\s*,\\s*("
                    + n + ")%\\s*,\\s*(" + n + ")%\\s*\\)$", 4)
            if (values === null)
                values = strictNumbers(value,
                    "^cmyka\\(\\s*(" + n + ")%\\s*,\\s*(" + n
                        + ")%\\s*,\\s*(" + n + ")%\\s*,\\s*(" + n
                        + ")%\\s*,\\s*(" + n + ")\\s*\\)$", 5)
            if (values === null)
                return null
            var c = boundedUnit(values[0] / 100)
            var m = boundedUnit(values[1] / 100)
            var y = boundedUnit(values[2] / 100)
            var k = boundedUnit(values[3] / 100)
            return makeRgb((1 - c) * (1 - k), (1 - m) * (1 - k),
                (1 - y) * (1 - k), boundedUnit(values.length === 5 ? values[4] : 1))
        }
        return null
    }

    function outputColor() {
        return forceOpaque
            ? Qt.rgba(selectedColor.r, selectedColor.g, selectedColor.b, 1)
            : selectedColor
    }

    function syncColorText() {
        if (!colorFormatField)
            return
        updatingColor = true
        colorFormatField.text = formattedColor(colorSpaceCombo.currentIndex, selectedColor)
        updatingColor = false
    }

    function setPickerColor(color, notifyPreview, preserveValidationMessage) {
        if (!preserveValidationMessage) {
            pendingClip = false
            colorError.text = ""
        }
        updatingColor = true
        selectedColor = color
        var hsv = rgbToHsv(color)
        if (hsv.s > 0)
            pickerHue = hsv.h / 360
        pickerSaturation = hsv.s
        pickerValue = hsv.v
        pickerAlpha = color.a
        updatingColor = false
        syncColorText()
        if (notifyPreview)
            colorPreviewed(outputColor())
    }

    function setPickerHsva(hue, saturation, value, alpha, notifyPreview) {
        pickerHue = ((hue % 1) + 1) % 1
        pickerSaturation = clamp(saturation, 0, 1)
        pickerValue = clamp(value, 0, 1)
        pickerAlpha = clamp(alpha, 0, 1)
        setPickerColor(Qt.hsva(pickerHue, pickerSaturation, pickerValue, pickerAlpha),
            notifyPreview)
    }

    function adjustSaturationValue(deltaSaturation, deltaValue) {
        setPickerHsva(pickerHue, pickerSaturation + deltaSaturation,
            pickerValue + deltaValue, pickerAlpha, true)
    }

    function acceptFormattedColor() {
        if (updatingColor)
            return true
        var parsed = parsedFormattedColor(colorSpaceCombo.currentIndex, colorFormatField.text)
        if (parsed === null) {
            pendingClip = false
            colorError.text = qsTr("That value is not valid in the selected color space.")
            return false
        }
        if (parsingClipped) {
            pendingClippedColor = parsed
            pendingClip = true
            colorError.text = qsTr(
                "This value is outside the supported range or sRGB gamut. Review it before clipping.")
            return false
        }
        pendingClip = false
        colorError.text = ""
        setPickerColor(parsed, true)
        return true
    }

    function acceptClippedColor() {
        if (!pendingClip)
            return
        pendingClip = false
        colorError.text = qsTr("The out-of-gamut channels were clipped to sRGB.")
        setPickerColor(pendingClippedColor, true, true)
    }

    function loadRecentColors() {
        var stored = Preferences.value("GUI/Appearance/RecentSeedColors", [])
        var result = []
        if (stored && stored.length !== undefined) {
            for (var i = 0; i < stored.length && result.length < 12; ++i) {
                var value = String(stored[i])
                if (parseHex(value) !== null && result.indexOf(value) < 0)
                    result.push(value)
            }
        }
        recentColors = result
    }

    function addRecentColor(color) {
        var hex = colorHex8(forceOpaque
            ? Qt.rgba(color.r, color.g, color.b, 1) : color)
        var next = [hex]
        for (var i = 0; i < recentColors.length && next.length < 12; ++i)
            if (recentColors[i] !== hex) next.push(recentColors[i])
        recentColors = next
        Preferences.setValue("GUI/Appearance/RecentSeedColors", next)
        Preferences.apply()
    }

    function relativeLuminance(color) {
        return 0.2126 * srgbToLinear(color.r) + 0.7152 * srgbToLinear(color.g)
            + 0.0722 * srgbToLinear(color.b)
    }

    function contrastRatio() {
        var background = contrastAgainst
        var foreground = outputColor()
        var composite = Qt.rgba(foreground.r * foreground.a + background.r * (1 - foreground.a),
            foreground.g * foreground.a + background.g * (1 - foreground.a),
            foreground.b * foreground.a + background.b * (1 - foreground.a), 1)
        var first = relativeLuminance(composite)
        var second = relativeLuminance(background)
        return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05)
    }

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
        border.width: 1
        border.color: Theme.color("outlineVariant")
    }

    contentItem: ColumnLayout {
        spacing: 0
        Accessible.role: Accessible.Dialog
        Accessible.name: root.title
        Accessible.description: root.forceOpaque
            ? qsTr("Continuous color picker. Material seed output is normalized to fully opaque.")
            : qsTr("Continuous color picker with alpha-preserving output.")

        RowLayout {
            id: pickerHeader
            Layout.fillWidth: true
            Layout.margins: Spacing.md
            spacing: Spacing.sm
            Accessible.name: qsTr("Drag advanced color picker")
            Accessible.description: qsTr("Drag this header to move the color picker")

            DragHandler {
                target: null
                cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onActiveChanged: {
                    if (active) {
                        root.userPositioned = true
                        root.dragOriginX = root.x
                        root.dragOriginY = root.y
                    }
                }
                onTranslationChanged: {
                    if (active)
                        root.moveWithinViewport(root.dragOriginX + translation.x,
                            root.dragOriginY + translation.y)
                }
            }

            MDIcon { icon: Icons.palette; size: 22; color: Theme.color("primary") }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    text: root.title
                    font: Typography.titleLarge
                    color: Theme.color("onSurface")
                }
                Label {
                    Layout.fillWidth: true
                    text: qsTr("Continuous sRGB selection · local bidirectional translation")
                    font: Typography.bodySmall
                    color: Theme.color("onSurfaceVariant")
                    wrapMode: Text.WordWrap
                }
            }
            Button {
                text: qsTr("Close")
                flat: true
                Accessible.description: qsTr("Cancel changes and return to the seed color control")
                onClicked: root.cancelPicker()
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.color("outlineVariant") }

        FilterTextField {
            id: pickerPropertySearch
            objectName: "advancedColorPickerPropertySearch"
            Layout.fillWidth: true
            Layout.leftMargin: Spacing.lg
            Layout.rightMargin: Spacing.lg
            Layout.topMargin: Spacing.sm
            Layout.bottomMargin: Spacing.sm
            placeholder: qsTr("Search color controls")
            builderTitle: qsTr("Color controls Regex Builder")
            builderSampleText: root.pickerPropertyCorpus
            Accessible.name: qsTr("Search advanced color picker controls and properties")
        }

        ScrollView {
            id: pickerScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: Math.max(0, pickerScroll.availableWidth)
                spacing: Spacing.md

                GridLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Spacing.lg
                    Layout.rightMargin: Spacing.lg
                    Layout.topMargin: Spacing.lg
                    columns: root.width >= 700 ? 2 : 1
                    columnSpacing: Spacing.lg
                    rowSpacing: Spacing.md

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 390
                        spacing: Spacing.sm
                        visible: root.showSaturationValue || root.showHue || root.showAlpha

                        Rectangle {
                            id: saturationValueField
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.width >= 520 ? 240 : 190
                            color: Qt.hsva(root.pickerHue, 1, 1, 1)
                            radius: Spacing.radiusControl
                            clip: true
                            border.width: activeFocus ? 3 : 1
                            border.color: activeFocus ? Theme.color("primary") : Theme.color("outline")
                            activeFocusOnTab: true
                            visible: root.showSaturationValue
                            Accessible.role: Accessible.Slider
                            Accessible.focusable: true
                            Accessible.focused: activeFocus
                            Accessible.name: qsTr("Two-dimensional saturation and value picker")
                            Accessible.description: qsTr(
                                "Saturation %1 percent, value %2 percent. Left and right change saturation. Up and down change brightness. Hold Shift for fine steps.")
                                .arg(Math.round(root.pickerSaturation * 100))
                                .arg(Math.round(root.pickerValue * 100))

                            Keys.onPressed: function(event) {
                                var step = (event.modifiers & Qt.ShiftModifier) ? 0.01 : 0.05
                                if (event.key === Qt.Key_Left) {
                                    root.adjustSaturationValue(-step, 0); event.accepted = true
                                } else if (event.key === Qt.Key_Right) {
                                    root.adjustSaturationValue(step, 0); event.accepted = true
                                } else if (event.key === Qt.Key_Up) {
                                    root.adjustSaturationValue(0, step); event.accepted = true
                                } else if (event.key === Qt.Key_Down) {
                                    root.adjustSaturationValue(0, -step); event.accepted = true
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: "white" }
                                    GradientStop { position: 1; color: "transparent" }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    GradientStop { position: 0; color: "transparent" }
                                    GradientStop { position: 1; color: "black" }
                                }
                            }
                            Rectangle {
                                width: 18
                                height: 18
                                radius: 9
                                x: root.clamp(root.pickerSaturation * saturationValueField.width
                                    - width / 2, 0, saturationValueField.width - width)
                                y: root.clamp((1 - root.pickerValue) * saturationValueField.height
                                    - height / 2, 0, saturationValueField.height - height)
                                color: "transparent"
                                border.width: 3
                                border.color: root.contrastRatio() >= 3 ? "white" : "black"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.CrossCursor
                                function selectAt(mouse) {
                                    root.setPickerHsva(root.pickerHue,
                                        root.clamp(mouse.x / width, 0, 1),
                                        1 - root.clamp(mouse.y / height, 0, 1),
                                        root.pickerAlpha, true)
                                }
                                onPressed: function(mouse) {
                                    saturationValueField.forceActiveFocus(Qt.MouseFocusReason)
                                    selectAt(mouse)
                                }
                                onPositionChanged: function(mouse) { if (pressed) selectAt(mouse) }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: root.showSaturationValue
                            text: qsTr("Saturation %1% · value %2%")
                                .arg(Math.round(root.pickerSaturation * 100))
                                .arg(Math.round(root.pickerValue * 100))
                            font: Typography.bodySmall
                            color: Theme.color("onSurfaceVariant")
                            Accessible.name: text
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.showHue
                            Label { text: qsTr("Hue"); font: Typography.labelMedium }
                            Slider {
                                id: hueSlider
                                Layout.fillWidth: true
                                from: 0
                                to: 360
                                value: root.pickerHue * 360
                                Accessible.name: qsTr("Hue in degrees")
                                onMoved: root.setPickerHsva(value / 360, root.pickerSaturation,
                                    root.pickerValue, root.pickerAlpha, true)
                                background: Rectangle {
                                    x: hueSlider.leftPadding
                                    y: hueSlider.topPadding + hueSlider.availableHeight / 2 - height / 2
                                    width: hueSlider.availableWidth
                                    height: 8
                                    radius: 4
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.00; color: "#FFFF0000" }
                                        GradientStop { position: 0.17; color: "#FFFFFF00" }
                                        GradientStop { position: 0.33; color: "#FF00FF00" }
                                        GradientStop { position: 0.50; color: "#FF00FFFF" }
                                        GradientStop { position: 0.67; color: "#FF0000FF" }
                                        GradientStop { position: 0.83; color: "#FFFF00FF" }
                                        GradientStop { position: 1.00; color: "#FFFF0000" }
                                    }
                                }
                            }
                            Label { text: Math.round(hueSlider.value) + "°"; font: Typography.labelMedium }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.showAlpha
                            Label { text: qsTr("Alpha"); font: Typography.labelMedium }
                            Slider {
                                id: alphaSlider
                                Layout.fillWidth: true
                                from: 0
                                to: 100
                                value: root.pickerAlpha * 100
                                Accessible.name: qsTr("Alpha opacity percentage")
                                onMoved: root.setPickerHsva(root.pickerHue, root.pickerSaturation,
                                    root.pickerValue, value / 100, true)
                            }
                            Label { text: Math.round(alphaSlider.value) + "%"; font: Typography.labelMedium }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 350
                        spacing: Spacing.sm
                        visible: root.showTranslator

                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 52
                                radius: Spacing.radiusChip
                                color: root.selectedColor
                                border.width: 1
                                border.color: Theme.color("outline")
                                Accessible.name: qsTr("Selected color %1").arg(root.colorHex8(root.selectedColor))
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Label {
                                    text: root.forceOpaque
                                        ? qsTr("sRGB gamut · output alpha 100%")
                                        : qsTr("sRGB gamut · alpha preserved")
                                    font: Typography.titleSmall
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: root.forceOpaque
                                        ? qsTr("Alpha remains available for translation and preview, but Material seed derivation applies an opaque color.")
                                        : qsTr("The selected alpha channel is preserved on Apply.")
                                    font: Typography.bodySmall
                                    color: Theme.color("onSurfaceVariant")
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        ComboBox {
                            id: colorSpaceCombo
                            Layout.fillWidth: true
                            model: root.colorSpaceModel
                            textRole: "label"
                            Accessible.name: qsTr("Color translation space")
                            onActivated: {
                                root.pendingClip = false
                                colorError.text = ""
                                root.syncColorText()
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: root.colorSpaceModel[colorSpaceCombo.currentIndex]
                                ? root.colorSpaceModel[colorSpaceCombo.currentIndex].hint : ""
                            font: Typography.bodySmall
                            color: Theme.color("onSurfaceVariant")
                            wrapMode: Text.WordWrap
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            TextField {
                                id: colorFormatField
                                objectName: "advancedColorValueField"
                                Layout.fillWidth: true
                                selectByMouse: true
                                maximumLength: 160
                                Accessible.name: qsTr("Editable color value in the selected color space")
                                onTextEdited: {
                                    root.pendingClip = false
                                    colorError.text = ""
                                }
                                onAccepted: root.acceptFormattedColor()
                            }
                            Button {
                                text: qsTr("Copy")
                                Accessible.name: qsTr("Copy this color representation")
                                onClicked: {
                                    clipboardHelper.text = colorFormatField.text
                                    clipboardHelper.selectAll()
                                    clipboardHelper.copy()
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Button {
                                text: qsTr("Preview translated value")
                                enabled: !root.pendingClip
                                onClicked: root.acceptFormattedColor()
                            }
                            Button {
                                visible: root.pendingClip
                                text: qsTr("Clip to sRGB and preview")
                                highlighted: true
                                onClicked: root.acceptClippedColor()
                            }
                        }
                        Label {
                            id: colorError
                            Layout.fillWidth: true
                            visible: text.length > 0
                            wrapMode: Text.WordWrap
                            color: root.pendingClip ? Theme.color("error") : Theme.color("onSurfaceVariant")
                            font: Typography.bodySmall
                            Accessible.role: Accessible.AlertMessage
                            Accessible.name: text
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: contrastColumn.implicitHeight + Spacing.md * 2
                            radius: Spacing.radiusControl
                            color: Theme.color("surfaceVariant")
                            border.width: 1
                            border.color: root.contrastRatio() >= 4.5
                                ? Theme.color("primary") : Theme.color("error")
                            ColumnLayout {
                                id: contrastColumn
                                anchors.fill: parent
                                anchors.margins: Spacing.md
                                Label {
                                    text: qsTr("Applied contrast %1:1 · %2")
                                        .arg(root.fixed(root.contrastRatio(), 2))
                                        .arg(root.contrastRatio() >= 7 ? qsTr("AAA")
                                            : (root.contrastRatio() >= 4.5 ? qsTr("AA")
                                                : qsTr("below AA for normal text")))
                                    font: Typography.labelLarge
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("Measured against the relevant surface after alpha policy is applied. Out-of-gamut translated input requires explicit clipping.")
                                    wrapMode: Text.WordWrap
                                    font: Typography.bodySmall
                                    color: Theme.color("onSurfaceVariant")
                                }
                            }
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Spacing.lg
                    Layout.rightMargin: Spacing.lg
                    visible: !root.hasPropertyMatch
                    text: qsTr("No color controls match this search.")
                    font: Typography.bodyMedium
                    color: Theme.color("onSurfaceVariant")
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Spacing.lg
                    Layout.rightMargin: Spacing.lg
                    visible: root.showCustomPalette
                    text: qsTr("Custom palette")
                    font: Typography.titleSmall
                    color: Theme.color("onSurface")
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: Spacing.lg
                    Layout.rightMargin: Spacing.lg
                    visible: root.showCustomPalette
                    spacing: Spacing.xs
                    Repeater {
                        model: root.customPalette
                        delegate: Button {
                            required property string modelData
                            width: 38
                            height: 38
                            padding: 0
                            Accessible.name: qsTr("Custom color %1").arg(modelData)
                            background: Rectangle {
                                radius: width / 2
                                color: modelData
                                border.width: 1
                                border.color: Theme.color("outline")
                            }
                            onClicked: {
                                var parsed = root.parseHex(modelData)
                                root.setPickerColor(parsed, true)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Spacing.lg
                    Layout.rightMargin: Spacing.lg
                    visible: root.showRecentColors
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Recent and saved custom colors")
                        font: Typography.titleSmall
                        color: Theme.color("onSurface")
                    }
                    Button {
                        text: qsTr("Save current custom color")
                        flat: true
                        onClicked: root.addRecentColor(root.outputColor())
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: Spacing.lg
                    Layout.rightMargin: Spacing.lg
                    Layout.bottomMargin: Spacing.lg
                    visible: root.showRecentColors
                    spacing: Spacing.xs
                    Label {
                        visible: root.recentColors.length === 0
                        text: qsTr("No saved colors yet.")
                        color: Theme.color("onSurfaceVariant")
                    }
                    Repeater {
                        model: root.recentColors
                        delegate: Button {
                            required property string modelData
                            width: 38
                            height: 38
                            padding: 0
                            Accessible.name: qsTr("Recent color %1").arg(modelData)
                            background: Rectangle {
                                radius: Spacing.radiusChip
                                color: modelData
                                border.width: 2
                                border.color: Theme.color("primary")
                            }
                            onClicked: root.setPickerColor(root.parseHex(modelData), true)
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.color("outlineVariant") }
        GridLayout {
            id: pickerActions
            Layout.fillWidth: true
            Layout.margins: Spacing.md
            rowSpacing: Spacing.sm
            columnSpacing: Spacing.sm
            columns: root.width >= 560 ? 3 : 1
            Label {
                Layout.fillWidth: true
                text: root.forceOpaque
                    ? qsTr("Apply writes an opaque Material seed; Cancel restores the previous seed.")
                    : qsTr("Apply writes the selected color; Cancel restores the previous color.")
                font: Typography.bodySmall
                color: Theme.color("onSurfaceVariant")
                wrapMode: Text.WordWrap
            }
            Button {
                Layout.fillWidth: pickerActions.columns === 1
                text: qsTr("Cancel")
                onClicked: root.cancelPicker()
            }
            Button {
                Layout.fillWidth: pickerActions.columns === 1
                text: qsTr("Apply color")
                highlighted: true
                onClicked: root.acceptPicker()
            }
        }
    }

    TextInput {
        id: clipboardHelper
        visible: false
        width: 0
        height: 0
    }
}
