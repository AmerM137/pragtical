---@meta

---
---Core functionality to render or draw elements into the screen.
---@class renderer
renderer = {}

---
---Array of bytes that represents a color used by the rendering functions.
---@class renderer.color
---@field public [1] number Red
---@field public [2] number Green
---@field public [3] number Blue
---@field public [4] number Alpha

---
---Represent options that affect a font's rendering.
---@class renderer.fontoptions
---@field public antialiasing "none" | "grayscale" | "subpixel"
---@field public hinting "slight" | "none" | "full"
---@field public bold boolean
---@field public italic boolean
---@field public underline boolean
---@field public smoothing boolean
---@field public strikethrough boolean

---
---@class renderer.font
renderer.font = {}

---
---Create a new font object.
---
---@param path string
---@param size number
---@param options? renderer.fontoptions
---
---@return renderer.font
function renderer.font.load(path, size, options) end

---
---Combines an array of fonts into a single one for broader charset support,
---the order of the list determines the fonts precedence when retrieving
---a symbol from it.
---
---@param fonts renderer.font[]
---
---@return renderer.font
function renderer.font.group(fonts) end

---
---Representation of a font metadata.
---
---@class renderer.font.metadata
---@field public id string?
---@field public fullname string?
---@field public version string?
---@field public sampletext string?
---@field public psname string?
---@field public family string?
---@field public subfamily string?
---@field public tfamily string?
---@field public tsubfamily string?
---@field public wwsfamily string?
---@field public wwssubfamily string?
---Some monospace fonts do not set it to true, do not rely on it too much.
---@field public monospace boolean

---
---Get a font file metadata. In case of a font group it will return an array
---of metadata results for each font on the group.
---
---@param font_or_path renderer.font | string
---
---@return renderer.font.metadata | renderer.font.metadata[] | nil
---@return string? errmsg
function renderer.font.get_metadata(font_or_path) end

---
---Clones a font object into a new one.
---
---@param size? number Optional new size for cloned font.
---@param options? renderer.fontoptions
---
---@return renderer.font
function renderer.font:copy(size, options) end

---
---Set the amount of characters that represent a tab.
---
---@param chars integer Also known as tab width.
function renderer.font:set_tab_size(chars) end

---
---Get the width in pixels of the given text when
---rendered with this font.
---
---@param text string
---
---@return number
function renderer.font:get_width(text) end

---
---Get the height in pixels that occupies a single character
---when rendered with this font.
---
---@return number
function renderer.font:get_height() end

---
---Get the current size of the font.
---
---@return number
function renderer.font:get_size() end

---
---Set a new size for the font.
---
---@param size number
function renderer.font:set_size(size) end

---
---Get the current path of the font as a string if a single font or as an
---array of strings if a group font.
---
---@return string | table<integer, string>
function renderer.font:get_path() end

---
---Toggles drawing debugging rectangles on the currently rendered sections
---of the window to help troubleshoot the renderer.
---
---@param enable boolean
function renderer.show_debug(enable) end

---
---Get the size of the screen area been rendered.
---
---@return number width
---@return number height
function renderer.get_size() end

---
---Tell the rendering system that we want to build a new frame to render.
---
---@param window renwindow
function renderer.begin_frame(window) end

---
---Tell the rendering system that we finished building the frame.
---
function renderer.end_frame() end

---
---Set the region of the screen where draw operations will take effect.
---
---@param x number
---@param y number
---@param width number
---@param height number
function renderer.set_clip_rect(x, y, width, height) end

---
---Draw a rectangle.
---
---@param x number
---@param y number
---@param width number
---@param height number
---@param color renderer.color
function renderer.draw_rect(x, y, width, height, color) end

---
---Draw text and return the x coordinate where the text finished drawing.
---
---@param font renderer.font
---@param text string
---@param x number
---@param y number
---@param color renderer.color
---
---@return number x
function renderer.draw_text(font, text, x, y, color) end


return renderer
