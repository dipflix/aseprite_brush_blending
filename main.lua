---@diagnostic disable: unnecessary-if
local dlg = Dialog { id = "cm_d", title = "Dipflix - Brush blending", visible = false }
local state = {
    enabled = false,
    mode = "Normal",
    base_color = nil,
    tickRate = 0.05,
}

function colorToInt(color)
    return (color.red << 16) + (color.green << 8) + (color.blue)
end

function colorFromInt(color)
    return Color {
        red = (color >> 16) & 255,
        green = (color >> 8) & 255,
        blue = color & 255
    }
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function clamp01(v)
    return clamp(v, 0.0, 1.0)
end

local function to01(v)
    return clamp01(v / 255.0)
end

local function from01(v)
    return math.floor(clamp01(v) * 255.0 + 0.5)
end

local function normalize_rgb(color)
    local c = Color(color)
    return c.red, c.green, c.blue, c.alpha or 255
end

local function blend_channel(base, blend, mode)
    if mode == "Normal" then
        return blend
    elseif mode == "Multiply" then
        return base * blend
    elseif mode == "Screen" then
        return 1.0 - (1.0 - base) * (1.0 - blend)
    elseif mode == "Overlay" then
        if base <= 0.5 then
            return 2.0 * base * blend
        end
        return 1.0 - 2.0 * (1.0 - base) * (1.0 - blend)
    elseif mode == "Darken" then
        return math.min(base, blend)
    elseif mode == "Lighten" then
        return math.max(base, blend)
    elseif mode == "Color Dodge" then
        if blend >= 1.0 then return 1.0 end
        return math.min(1.0, base / (1.0 - blend))
    elseif mode == "Color Burn" then
        if blend <= 0.0 then return 0.0 end
        return 1.0 - math.min(1.0, (1.0 - base) / blend)
    elseif mode == "Hard Light" then
        if blend <= 0.5 then
            return 2.0 * base * blend
        end
        return 1.0 - 2.0 * (1.0 - base) * (1.0 - blend)
    elseif mode == "Soft Light" then
        if blend <= 0.5 then
            return base - (1.0 - 2.0 * blend) * base * (1.0 - base)
        end
        local d
        if base <= 0.25 then
            d = ((16.0 * base - 12.0) * base + 4.0) * base
        else
            d = math.sqrt(base)
        end
        return base + (2.0 * blend - 1.0) * (d - base)
    elseif mode == "Difference" then
        return math.abs(base - blend)
    elseif mode == "Exclusion" then
        return base + blend - 2.0 * base * blend
    elseif mode == "Addition" then
        return math.min(1.0, base + blend)
    elseif mode == "Subtract" then
        return math.max(0.0, base - blend)
    elseif mode == "Divide" then
        if blend <= 0.0 then return 1.0 end
        return math.min(1.0, base / blend)
    end
    return blend
end

local function blend_hsl(baseColor, blendColor, mode)
    local b = Color(baseColor)
    local s = Color(blendColor)
    local out = Color { red = b.red, green = b.green, blue = b.blue, alpha = b.alpha }

    if mode == "Hue" then
        out.hue = s.hue
        out.saturation = b.saturation
        out.lightness = b.lightness
    elseif mode == "Saturation" then
        out.hue = b.hue
        out.saturation = s.saturation
        out.lightness = b.lightness
    elseif mode == "Color" then
        out.hue = s.hue
        out.saturation = s.saturation
        out.lightness = b.lightness
    elseif mode == "Luminosity" then
        out.hue = b.hue
        out.saturation = b.saturation
        out.lightness = s.lightness
    end

    return out
end

local function blend_colors(baseColor, blendColor, mode)
    if mode == "Hue" or mode == "Saturation" or mode == "Color" or mode == "Luminosity" then
        return blend_hsl(baseColor, blendColor, mode)
    end

    local br, bg, bb, ba = normalize_rgb(baseColor)
    local sr, sg, sb = normalize_rgb(blendColor)

    local r = blend_channel(to01(br), to01(sr), mode)
    local g = blend_channel(to01(bg), to01(sg), mode)
    local b = blend_channel(to01(bb), to01(sb), mode)


    return Color { red = from01(r), green = from01(g), blue = from01(b), alpha = ba }
end

local function get_color_under_cursor()
    local editor = app.editor
    if not editor or not editor.sprite then
        return nil
    end

    local pos = editor.spritePos
    if not pos then
        return nil
    end
    local sprite = editor.sprite

    if pos.x < 0 or pos.y < 0 or pos.x >= sprite.width or pos.y >= sprite.height then
        return nil
    end

    local frame = (app.site and (app.site.frame or app.site.frameNumber)) or 1
    local sample = Image(1, 1, sprite.colorMode)
    sample:drawSprite(sprite, frame, Point(-pos.x, -pos.y))

    local pixel = sample:getPixel(0, 0)
    local pc = app.pixelColor
    local mode = sprite.colorMode

    if mode == ColorMode.RGB then
        return Color {
            r = pc.rgbaR(pixel),
            g = pc.rgbaG(pixel),
            b = pc.rgbaB(pixel),
            a = pc.rgbaA(pixel)
        }
    elseif mode == ColorMode.GRAY then
        return Color {
            gray = pc.grayaV(pixel),
            alpha = pc.grayaA(pixel)
        }
    elseif mode == ColorMode.INDEXED then
        return Color { index = pixel }
    end

    return nil
end



local function sample_and_apply()
    local mod_color = get_color_under_cursor()
    if not mod_color then
        return false
    end

    local base = state.base_color
    if not base then
        return false
    end

    local result = blend_colors(base, mod_color, state.mode)
    if result then
        app.fgColor = result
        return true
    end

    return false
end

local live_timer
live_timer = Timer {
    interval = state.tickRate,
    ontick = function()
        sample_and_apply()
    end
}

local function toggle_live_enabled()
    state.enabled = dlg.data.live_blend_enabled
    if state.enabled then
        live_timer:start()
    else
        live_timer:stop()
    end
end

local function update_live_button()
    local text = state.enabled and "Stop" or "Start"
    dlg:modify { id = "live_toggle", text = text }
end


local function pickBaseColorByCursorPosition()
    local sampled = get_color_under_cursor()
    if sampled then
        state.base_color = sampled
        dlg:modify { id = "base_color", color = sampled }
    end
end



function init(plugin)
    main(plugin)
end

function main(plugin)
    dlg
        :color {
            id = "base_color",
            label = "Base",
            color = app.fgColor,
            onchange = function()
                state.base_color = dlg.data.base_color
            end
        }
        :combobox {
            id = "live_blend_mode",
            label = "Mode",
            option = "Normal",
            options = {
                "Normal",
                "Darken",
                "Multiply",
                "Color Burn",
                "Lighten",
                "Screen",
                "Color Dodge",
                "Addition",
                "Overlay",
                "Soft Light",
                "Hard Light",
                "Difference",
                "Exclusion",
                "Subtract",
                "Divide",
                "Hue",
                "Saturation",
                "Color",
                "Luminosity"
            },
            onchange = function(ev)
                state.mode = dlg.data.live_blend_mode
            end
        }
        :button {
            id = "live_toggle",
            text = "Start",
            onclick = function()
                state.enabled = not state.enabled
                if state.enabled then
                    live_timer:start()
                else
                    live_timer:stop()
                end
                update_live_button()
            end
        }
        :newrow()
        :label { text = "Alt+A - to select color" }

    plugin:newCommand {
        id = "bs_open",
        title = "Brush blending",
        group = "help_readme",
        onclick = function()
            dlg:show { wait = false }
        end
    }

    plugin:newCommand {
        id = "bs_pick_color",
        title = "Brush blending - pick color",
        onclick = pickBaseColorByCursorPosition
    }
end

function exit(plugin)
    if live_timer then
        live_timer:stop()
    end
end
