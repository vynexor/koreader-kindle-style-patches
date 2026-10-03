-- 2-mimic-kindle-ui-patch.lua
-- Combined Kindle-style footer and centered clock header for KOReader
-- To customize: Edit only HEADER_CONFIG and FOOTER_CONFIG sections


-- ============ FOOTER SECTION ============


-- === helpers.lua ===

local CONSTANTS = {
	MINUTES_IN_HOUR = 60,
	NO_MINUTES = 0,
	ONE_MINUTE = 1,
}

local TEXT = {
   	LESS_THAN_A_MINUTE_TEXT = "less than a minute",
	ONE_MINUTE_TEXT = "1 minute",
	MINUTES_TEXT = " minutes",
}

local function getMinutes(time_string)
	if not time_string or time_string == "" then
		return CONSTANTS.NO_MINUTES
	end

	-- Format: "01:45" (hours:minutes)
	local hours, minutes = time_string:match("(%d+):(%d+)")
	if hours and minutes then
		return tonumber(hours) * CONSTANTS.MINUTES_IN_HOUR + tonumber(minutes)
	end

	-- Format: "1h 10m" or "10m" or "1h"
	hours = time_string:match("(%d+)h")
	minutes = time_string:match("(%d+)m")

	if hours or minutes then
		-- Convert hours to minutes, or use 0 if no hours found
		local hoursInMinutes = CONSTANTS.NO_MINUTES
		if hours then
			hoursInMinutes = tonumber(hours) * CONSTANTS.MINUTES_IN_HOUR
		end

		-- Get minutes value, or use 0 if no minutes found
		local minutesValue = CONSTANTS.NO_MINUTES
		if minutes then
			minutesValue = tonumber(minutes) or CONSTANTS.NO_MINUTES
		end

		return hoursInMinutes + minutesValue
	end

	return CONSTANTS.NO_MINUTES
end

local function formatTime(minutes)
	if minutes <= CONSTANTS.ONE_MINUTE then
		return "1 min"
	elseif minutes < CONSTANTS.MINUTES_IN_HOUR then
		return minutes .. " mins"
	end

	local hours = math.floor(minutes / CONSTANTS.MINUTES_IN_HOUR)
	local rest = minutes % CONSTANTS.MINUTES_IN_HOUR
	local text = hours .. (hours == 1 and " hr" or " hrs")
	if rest == 1 then
		text = text .. " 1 min"
	elseif rest > 1 then
		text = text .. " " .. rest .. " mins"
	end
	return text
end

-- (face, isRegistered) -> bold face file, or nil when nothing should change.
local function resolveBoldFontFace(face, isRegistered)
	if type(face) ~= "string" or face == "" then
		return nil
	end
	if type(isRegistered) ~= "function" then
		return nil
	end

	local stem, extension = face:match("^(.*)%-Regular(%.[%a%d]+)$")
	if not stem then
		return nil
	end

	local bold_face = stem .. "-Bold" .. extension
	if not isRegistered(bold_face) then
		return nil
	end

	return bold_face
end

local function getTimeString(footer, pages_left)
	-- Method 1: Works on Emulator
	if footer.ui.statistics and footer.ui.statistics.getTimeForPages then
		local ok, time_string = pcall(function()
			return footer.ui.statistics:getTimeForPages(pages_left)
		end)

		if ok and time_string then
			return time_string
		end
	end

	-- Method 2: Works on Kindle
	if footer.getDataFromStatistics then
		local ok, time_string = pcall(function()
			return footer:getDataFromStatistics("", pages_left)
		end)
		if ok and time_string and time_string ~= "" then
			return time_string
		end
	end

	return nil
end

local helpers = {
	resolveBoldFontFace = resolveBoldFontFace,
	getMinutes = getMinutes,
	formatTime = formatTime,
	getTimeString = getTimeString,
}

-- === footer.lua ===

local ReaderFooter = require("apps/reader/modules/readerfooter")
local userpatch = require("userpatch")

local FOOTER_CONFIG = {
	CHAPTER_COMPLETED_TEXT = "Chapter completed",
	CHAPTER_SUFFIX = "left in chapter",
	BOOK_SUFFIX = "left in book",
	PAGE_TEXT = "Page %s", -- use "Page %s of %s" to also show the total
	SEPARATOR = " \u{00B7} ", -- middle dot between items
	FOOTER_LEFT_MARGIN = 1, -- Character spaces on left
	FOOTER_RIGHT_MARGIN = 2, -- Character spaces on right
}

local footerTextGeneratorMap = userpatch.getUpValue(ReaderFooter.applyFooterMode, "footerTextGeneratorMap")
local original_chapter_time_to_read = footerTextGeneratorMap.chapter_time_to_read

local function canCalculateCustomTime(footer)
	local result = footer.ui.statistics and footer.ui.statistics.is_doc
	return result
end

local function getPagesLeftInChapter(footer)
	local result = footer.ui.toc:getChapterPagesLeft(footer.pageno)
		or footer.ui.document:getTotalPagesLeft(footer.pageno)
	return result
end

local function calculateReadingTime(footer, pages_left)
	local timeString = helpers.getTimeString(footer, pages_left)

	if not timeString then
		return nil
	end

	local minutes = helpers.getMinutes(timeString)

	local formattedTime = helpers.formatTime(minutes)

	return formattedTime
end

-- KOReader's "compact" status bar squeezes every normal space into a hair
-- space. No-break spaces are left alone, so the words keep their gaps.
local function keepSpaces(text)
	return (text:gsub(" ", "\u{00A0}"))
end

local function getPageText(footer)
	local ok, text = pcall(function()
		if footer.ui.pagemap and footer.ui.pagemap:wantsPageLabels() then
			return FOOTER_CONFIG.PAGE_TEXT:format(
				tostring(footer.ui.pagemap:getCurrentPageLabel(true)),
				tostring(footer.ui.pagemap:getLastPageLabel(true))
			)
		end
		if footer.ui.document:hasHiddenFlows() then
			local flow = footer.ui.document:getPageFlow(footer.pageno)
			return FOOTER_CONFIG.PAGE_TEXT:format(
				tostring(footer.ui.document:getPageNumberInFlow(footer.pageno)),
				tostring(footer.ui.document:getTotalPagesInFlow(flow))
			)
		end
		return FOOTER_CONFIG.PAGE_TEXT:format(tostring(footer.pageno), tostring(footer.pages))
	end)
	if ok and text then
		return text
	end
	return nil
end

local function getChapterText(footer)
	local fallback = original_chapter_time_to_read(footer)

	if not canCalculateCustomTime(footer) then
		return fallback
	end

	local pagesLeft = getPagesLeftInChapter(footer)
	if not pagesLeft then
		return fallback
	end

	if pagesLeft == 0 then
		return FOOTER_CONFIG.CHAPTER_COMPLETED_TEXT
	end

	local readingTime = calculateReadingTime(footer, pagesLeft)
	if not readingTime then
		return fallback
	end

	return readingTime .. " " .. FOOTER_CONFIG.CHAPTER_SUFFIX
end

local function getBookText(footer)
	if not canCalculateCustomTime(footer) then
		return nil
	end

	local ok, pagesLeft = pcall(function()
		return footer.ui.document:getTotalPagesLeft(footer.pageno)
	end)
	if not ok or not pagesLeft or pagesLeft <= 0 then
		return nil
	end

	local readingTime = calculateReadingTime(footer, pagesLeft)
	if not readingTime then
		return nil
	end

	return readingTime .. " " .. FOOTER_CONFIG.BOOK_SUFFIX
end

-- What the bottom-left corner shows. A tap on the status bar moves to the
-- next entry, like the Kindle's own reader does.
local LEFT_MODES = { "page", "chapter", "book", "none" }
local LEFT_MODE_SETTING = "kindle_ui_left_mode"

local function getLeftMode()
	local mode = G_reader_settings:readSetting(LEFT_MODE_SETTING)
	for _, name in ipairs(LEFT_MODES) do
		if name == mode then
			return mode
		end
	end
	return "chapter"
end

local function getNextLeftMode(mode)
	for i, name in ipairs(LEFT_MODES) do
		if name == mode then
			return LEFT_MODES[i % #LEFT_MODES + 1]
		end
	end
	return LEFT_MODES[1]
end

function footerTextGeneratorMap.chapter_time_to_read(footer)
	local mode = getLeftMode()
	local text

	-- "none": the whole bar is blank, like the Kindle's empty state.
	if mode == "none" then
		return ""
	end

	if mode == "page" then
		text = getPageText(footer)
	elseif mode == "book" then
		text = getBookText(footer)
	end

	if not text then
		text = getChapterText(footer)
	end

	return string.rep("\u{00A0}", FOOTER_CONFIG.FOOTER_LEFT_MARGIN) .. keepSpaces(text)
end

local orig_TapFooter = ReaderFooter.TapFooter

function ReaderFooter:TapFooter(ges)
	if self.view.flipping_visible or self.settings.lock_tap then
		return orig_TapFooter(self, ges)
	end

	G_reader_settings:saveSetting(LEFT_MODE_SETTING, getNextLeftMode(getLeftMode()))
	self:onUpdateFooter(true)
	return true
end

-- Side margins are added to the items themselves (as no-break spaces), so
-- KOReader measures and draws exactly the same text and never cuts off the
-- percentage.
local original_percentage = footerTextGeneratorMap.percentage

function footerTextGeneratorMap.percentage(footer)
	if getLeftMode() == "none" then
		return ""
	end

	local text = original_percentage(footer)
	if not text or text == "" then
		return text
	end
	return text .. string.rep("\u{00A0}", FOOTER_CONFIG.FOOTER_RIGHT_MARGIN)
end

-- Keep the percentage at exactly the same spot whatever is shown on the left.
-- KOReader fills the gap between left and right with whole spaces, so the
-- right-hand item shifted by up to one space width depending on how wide the
-- left text was. The left text is therefore padded with hair spaces until its
-- width is an exact multiple of one space.
local FooterTextWidget = require("ui/widget/textwidget")

local function measureText(footer, text)
	local widget = FooterTextWidget:new{
		text = text,
		face = footer.footer_text_face,
		bold = footer.settings.text_font_bold,
	}
	local width = widget:getSize().w
	widget:free()
	return width
end

-- Try the left text with 0, 1, 2... hair spaces appended, build the whole
-- line each time, and keep the version whose total width is closest to the
-- full bar width. The line then always ends at the same pixel.
local measuring = false
local candidate_hairs = 0
local HAIR = "\u{200A}"

local unpadded_chapter_time_to_read = footerTextGeneratorMap.chapter_time_to_read

function footerTextGeneratorMap.chapter_time_to_read(footer)
	local text = unpadded_chapter_time_to_read(footer)
	if not text or text == "" then
		return text
	end
	if measuring then
		return text .. HAIR:rep(candidate_hairs)
	end
	if not footer.footer_text_face or not footer._saved_screen_width or not footer.horizontal_margin then
		return text
	end

	local best = 0
	local ok = pcall(function()
		local target = math.floor(footer._saved_screen_width - 2 * footer.horizontal_margin)
		local space_w = measureText(footer, string.rep(" ", 20)) / 20
		local hair_w = measureText(footer, HAIR:rep(20)) / 20
		if space_w <= 0 or hair_w <= 0 then
			return
		end
		local best_gap = math.huge
		measuring = true
		for hairs = 0, math.ceil(space_w / hair_w) + 1 do
			candidate_hairs = hairs
			local width = measureText(footer, (footer:genAllFooterText()))
			local gap = target - width
			if gap >= 0 and gap < best_gap then
				best, best_gap = hairs, gap
			end
			if gap == 0 then
				break
			end
		end
	end)
	measuring = false
	if not ok then
		best = 0
	end
	return text .. HAIR:rep(best)
end

-- === main.lua ===

local UIManager = require("ui/uimanager")
local ReaderFooter = require("apps/reader/modules/readerfooter")
local FontChooser = require("ui/widget/fontchooser")

local orig_init = ReaderFooter.init

-- KOReader >= 2025 stores text_font_face as a path, which never gets promoted to
-- the real bold file: text_font_bold then renders as light synthesized bold.
local function useRealBoldFontFace(footer)
	if footer.settings.text_font_bold ~= true then
		return false
	end

	local isRegistered = FontChooser and FontChooser.isFontRegistered
	local bold_face = helpers.resolveBoldFontFace(footer.settings.text_font_face, isRegistered)
	if not bold_face then
		return false
	end

	footer.settings.text_font_face = bold_face
	footer.settings.text_font_bold = false
	return true
end

local function rebuildFooterModeState(footer)
	footer:set_mode_index()
	footer.mode_list = {}
	for i = 0, #footer.mode_index do
		footer.mode_list[footer.mode_index[i]] = i
	end
	footer:set_has_no_mode()
end

local function getFirstEnabledMode(footer)
	for i, mode_name in ipairs(footer.mode_index) do
		if footer.settings[mode_name] and mode_name ~= "dynamic_filler" then
			return i
		end
	end
	return footer.mode_list.page_progress or footer.mode_list.off or 0
end

local function recoverInvalidMode(footer)
	local mode = footer.mode
	if mode == nil or footer.mode_index[mode] == nil then
		return getFirstEnabledMode(footer)
	end

	if not footer.settings.all_at_once and footer.settings.disable_progress_bar then
		local mode_name = footer.mode_index[mode]
		if not mode_name or not footer.settings[mode_name] or mode_name == "dynamic_filler" then
			return getFirstEnabledMode(footer)
		end
	end

	return nil
end

function ReaderFooter:init(...)
	orig_init(self, ...)

	UIManager:tickAfterNext(function()
		local kindle_ui_applied = G_reader_settings:readSetting("kindle_ui_applied", false)
		local should_refresh_layout = false
		local should_flush = false
		local should_repaint = false

		if not kindle_ui_applied then
			-- Apply Kindle UI settings (first run only)
			self.settings.all_at_once = true
			self.settings.disable_progress_bar = true
			self.settings.percentage = true
			self.settings.chapter_time_to_read = true
			self.settings.dynamic_filler = true

			self.settings.page_progress = false
			self.settings.pages_left_book = false
			self.settings.time = false
			self.settings.chapter_progress = false
			self.settings.pages_left = false
			self.settings.battery = false
			self.settings.book_time_to_read = false
			self.settings.bookmark_count = false
			self.settings.mem_usage = false
			self.settings.wifi_status = false
			self.settings.page_turning_inverted = false
			self.settings.book_author = false
			self.settings.book_title = false
			self.settings.book_chapter = false
			self.settings.custom_text = false

			-- Keep KOReader's expected 0-based order format (off at index 0).
			self.settings.order = {
				[0] = "off",
				"chapter_time_to_read",
				"dynamic_filler",
				"percentage",
			}
			self.settings.items_separator = "none"
			self.settings.item_prefix = "compact_items"
			self.settings.align = "left"
			self.settings.container_height = 20
			self.settings.container_bottom_padding = 5
			self.settings.text_font_bold = true

			G_reader_settings:saveSetting("kindle_ui_applied", true)
			G_reader_settings:saveSetting("footer", self.settings)
			should_refresh_layout = true
			should_flush = true
		end

		if useRealBoldFontFace(self) then
			if self.updateFooterFont then
				self:updateFooterFont()
			end
			G_reader_settings:saveSetting("footer", self.settings)
			should_flush = true
			-- Without this the footer keeps the old face until the user taps it.
			should_repaint = self.refreshFooter ~= nil
		end

		-- Migration for older patch versions that saved a 1-based order table.
		if self.settings.order
			and self.settings.order[0] == nil
			and self.settings.order[1] == "chapter_time_to_read"
			and self.settings.order[2] == "dynamic_filler"
			and self.settings.order[3] == "percentage" then
			self.settings.order[0] = "off"
			G_reader_settings:saveSetting("footer", self.settings)
			should_refresh_layout = true
			should_flush = true
		end

		if should_refresh_layout then
			rebuildFooterModeState(self)
		end

		local recovered_mode = recoverInvalidMode(self)
		if recovered_mode ~= nil and recovered_mode ~= self.mode then
			self.mode = recovered_mode
			G_reader_settings:saveSetting("reader_footer_mode", self.mode)
			should_refresh_layout = true
			should_flush = true
		end

		if should_refresh_layout then
			self:updateFooterTextGenerator()
			self:applyFooterMode()
			self:resetLayout()
		end

		if should_repaint then
			self:refreshFooter(true, true)
		end

		if should_flush and G_reader_settings.flush then
			G_reader_settings:flush()
		end
	end)
end

-- ============ HEADER SECTION ============


-- === header.lua ===

-- Modify these values to customize the header appearance
local HEADER_CONFIG = {
    -- Spacing
    top_padding = 24,          -- Top margin in pixels (original 12)
    -- Font
    font_face = "ffont",       -- Font name
    font_size = 16,            -- Font size in pixels
    font_bold = false,        --  Use bold font? (original: true)
    font_color = nil,          -- Font color (nil = COLOR_BLACK)
    -- Margins
    use_book_margins = true,   -- Use same margins as book for header
    margin = nil,              -- Fallback margin if book margins disabled (nil = Size.padding.large)
    max_width_pct = 100,       -- Maximum width % before truncating (default: 100)
    -- Behavior
    show_for_pdf = false,      -- Show header for PDF/CBZ files?
}

-- ==========================================
-- Implementation - No need to modify below
-- ==========================================
local Blitbuffer = require("ffi/blitbuffer")
local TextWidget = require("ui/widget/textwidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local BD = require("ui/bidi")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local datetime = require("datetime")
local Device = require("device")
local Screen = Device.screen
local ReaderView = require("apps/reader/modules/readerview")

local orig_paintTo = ReaderView.paintTo

-- While the sleep screen is up, the clock and the bottom bar are hidden so a
-- transparent wallpaper sits on plain text only.
local hidden_for_sleep = false

local Screensaver = require("ui/screensaver")
local orig_screensaver_show = Screensaver.show
local orig_screensaver_cleanup = Screensaver.cleanup

local function repaintReader(refresh_mode)
    local ReaderUI = require("apps/reader/readerui")
    local reader = ReaderUI.instance
    if reader and reader.dialog then
        UIManager:setDirty(reader.dialog, refresh_mode)
        return true
    end
    return false
end

-- Close the top menu and the bottom font/layout menu, so they are not left
-- on screen under the wallpaper.
local function closeReaderMenus()
    local ReaderUI = require("apps/reader/readerui")
    local reader = ReaderUI.instance
    if not reader then return end
    if reader.menu and reader.menu.menu_container then
        pcall(reader.menu.onCloseReaderMenu, reader.menu)
    end
    if reader.config and reader.config.config_dialog then
        pcall(reader.config.onCloseConfigMenu, reader.config)
    end

    -- Anything else still open on top of the book (dictionary window,
    -- selection menu, other pop-ups) is closed too.
    local stack = UIManager._window_stack
    if type(stack) == "table" then
        local above, found = {}, false
        for _, window in ipairs(stack) do
            if found then
                table.insert(above, window.widget)
            elseif window.widget == reader then
                found = true
            end
        end
        for i = #above, 1, -1 do
            pcall(UIManager.close, UIManager, above[i])
        end
    end

    -- Remove a text selection that is still marked on the page.
    if reader.highlight and reader.highlight.clear then
        pcall(reader.highlight.clear, reader.highlight)
    end
end

function Screensaver:show()
    if self.ui and self.screensaver_background == "none" then
        closeReaderMenus()
        hidden_for_sleep = true
        if repaintReader("ui") then
            UIManager:forceRePaint()
        end
    end
    return orig_screensaver_show(self)
end

function Screensaver:cleanup()
    if hidden_for_sleep then
        hidden_for_sleep = false
        repaintReader("ui")
    end
    return orig_screensaver_cleanup(self)
end

-- Keep the clock current while a page stays open: once a minute, right
-- after the minute changes, redraw just the strip at the top of the page.
-- Nothing runs while the device sleeps or when no book is open.
local clock_timer_running = false
local last_clock_height = nil

local function refreshClock()
    local ReaderUI = require("apps/reader/readerui")
    local reader = ReaderUI.instance
    if not reader or not reader.dialog then
        clock_timer_running = false
        return
    end

    if not hidden_for_sleep and not Device.screen_saver_mode then
        local height = (last_clock_height or Screen:scaleBySize(40)) + Screen:scaleBySize(4)
        UIManager:setDirty(reader.dialog, function()
            return "ui", Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = height }
        end)
    end

    UIManager:scheduleIn(61 - tonumber(os.date("%S")), refreshClock)
end

local function startClockTimer()
    if clock_timer_running then
        return
    end
    clock_timer_running = true
    UIManager:scheduleIn(61 - tonumber(os.date("%S")), refreshClock)
end

function ReaderView:paintTo(bb, x, y)
    if hidden_for_sleep then
        local footer_visible = self.footer_visible
        self.footer_visible = false
        orig_paintTo(self, bb, x, y)
        self.footer_visible = footer_visible
        return
    end

    orig_paintTo(self, bb, x, y)

	if self.render_mode ~= nil and not HEADER_CONFIG.show_for_pdf then
		return
	end

	-- Get configuration values with defaults
	local font_color = HEADER_CONFIG.font_color or Blitbuffer.COLOR_BLACK
	local fallback_margin = HEADER_CONFIG.margin or Size.padding.large

	-- Calculate margins
	local screen_width = Screen:getWidth()
	local left_margin = fallback_margin
	local right_margin = fallback_margin

	if HEADER_CONFIG.use_book_margins and self.document and self.document.getPageMargins then
		local doc_margins = self.document:getPageMargins()
		left_margin = doc_margins.left or fallback_margin
		right_margin = doc_margins.right or fallback_margin
	end

	local margins = left_margin + right_margin
	local avail_width = screen_width - margins

	local time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))

	local function getFittedText(text, max_width_pct)
		if text == nil or text == "" then
			return ""
		end
		local text_widget = TextWidget:new{
			text = text:gsub(" ", "\u{00A0}"), -- no-break-space
			max_width = avail_width * max_width_pct * (1/100),
			face = Font:getFace(HEADER_CONFIG.font_face, HEADER_CONFIG.font_size),
			bold = HEADER_CONFIG.font_bold,
			padding = 0,
		}
		local fitted_text, add_ellipsis = text_widget:getFittedText()
		text_widget:free()
		if add_ellipsis then
			fitted_text = fitted_text .. "…"
		end
		return BD.auto(fitted_text)
	end

	local header_content = getFittedText(time, HEADER_CONFIG.max_width_pct)

	local header_text = TextWidget:new{
		text = header_content,
		face = Font:getFace(HEADER_CONFIG.font_face, HEADER_CONFIG.font_size),
		bold = HEADER_CONFIG.font_bold,
		fgcolor = font_color,
		padding = 0,
	}

	local header_height = header_text:getSize().h + HEADER_CONFIG.top_padding
	last_clock_height = header_height
	startClockTimer()

	local header = CenterContainer:new{
		dimen = Geom:new{ w = screen_width, h = header_height },
		VerticalGroup:new{
			VerticalSpan:new{ width = HEADER_CONFIG.top_padding },
			HorizontalGroup:new{
				HorizontalSpan:new{ width = left_margin },
				header_text,
				HorizontalSpan:new{ width = right_margin },
			},
		},
	}

	header:paintTo(bb, x, y)
	-- Slightly heavier than regular, lighter than bold: draw the text
	-- again one and two pixels to the right.
	header:paintTo(bb, x + 1, y)
	header:paintTo(bb, x + 2, y)
end
