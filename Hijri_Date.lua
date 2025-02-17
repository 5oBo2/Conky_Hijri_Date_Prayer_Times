-- Lua Script
require("cairo")
require("cairo_xlib")
local http = require("socket.http") -- Ensure LuaSocket is installed
local ltn12 = require("ltn12") -- Required for response sink
local json = require("dkjson") -- JSON parsing library

function TimeToMinutes(timeStr)
	local hours, minutes = timeStr:match("(%d+):(%d+)")
	return tonumber(hours) * 60 + tonumber(minutes)
end

function GetCurrentTime()
    local os_time = os.time()
    local current_time = os.date("%H:%M", os_time)
    return current_time
end


AfterMaghribCall = false
-- Function to fetch Hijri date
function fetch_hijri_date(AfterMaghribCall)

    local month_name = {[1]="Muharram",[2]="Safar",[3]="Rabi Al Awwal",[4]="Rabi Al Thani",[5]="Jumada Al Oula",[6]="Jumada Al-Akhira",[7]="Rajab",[8]="Shaban",[9]="Ramadan", [10]="Shawwal", [11]="Dhul Qidah", [12]="Dhul Hijjah"}

    local latitude = 30.0444
    local longitude = 31.23575
    local date = os.date("%d-%m-%Y", os.time() + (AfterMaghribCall and 86400 or 0))
    print('date', date)
    local url = "https://api.aladhan.com/v1/timings/" .. date .. "?latitude=" .. latitude .. "&longitude=" .. longitude
    local response_body = {}
    local res, code = http.request{
        url = url,
        sink = ltn12.sink.table(response_body)
    }

    if code == 200 then
        local response = table.concat(response_body)
        local data, _, err = json.decode(response, 1, nil)
        if not err then
            Day = data.data.date.hijri.day
            local month = data.data.date.hijri.month.number
            Month = month_name[month]
            Year = data.data.date.hijri.year
            Maghrib = TimeToMinutes(data.data.timings.Maghrib)
        else
            print("Error fetching date")
        end
    else
        print("HTTP Error: " .. tostring(code))
    end
end

-- Fetch the Hijri date 
fetch_hijri_date(AfterMaghribCall)

-- Function to draw text with color
function draw_colored_text(cr, text, xpos, ypos, red, green, blue, alpha)

    cairo_set_source_rgba(cr, red, green, blue, alpha)
    cairo_move_to(cr, xpos, ypos)
    cairo_show_text(cr, text)
    cairo_stroke(cr)
end

-- Main function for drawing with Conky
function conky_main()
    if conky_window == nil then
        return
    end

    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height
    )
    

    local font = "ITC Avant Garde Pro XLt"
    local font_size_time = 1000
    local font_size_date = 300
    local x_margin = font_size_date/2.5
    local y_margin = font_size_date / 1.5
    local ypos_date = font_size_time + font_size_date + y_margin
    local ypos_hijri = ypos_date + font_size_date + y_margin / 2
    -- print('min window height: ' .. ypos_hijri)
    local alpha = 200/255

    cr = cairo_create(cs)
    cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, font_size_time)
    local extents = cairo_text_extents_t:create()

    local date = os.date("%A |  %d %B %Y")
    local time = os.date("%H%M")
    local current_time = TimeToMinutes(GetCurrentTime())

    if not AfterMaghribCall and  Maghrib < current_time then
        AfterMaghribCall=true
        fetch_hijri_date(AfterMaghribCall)
    elseif AfterMaghribCall and Maghrib > current_time then
        AfterMaghribCall=false
    end

    cairo_text_extents(cr, time, extents)
    local time_width = extents.width
    local xpos_time = (conky_window.width - time_width) / 2 
    draw_colored_text(cr, time, xpos_time, font_size_time, 1, 1, 1, alpha)  

    cairo_set_font_size(cr, font_size_date)
    cairo_text_extents(cr, date, extents)
    local date_width = extents.width
    local xpos_date = (conky_window.width - date_width) / 2 
    draw_colored_text(cr, date, xpos_date, ypos_date, 1, 1, 1, alpha)  

    -- Ensure valid split
    if Day and Month and Year then
        Day = tonumber(Day) -- Convert day to number for comparison
        StringDay = string.format("%02d", Day)
        -- Choose colors for the day
        local day_red, day_green, day_blue, day_alpha = 1, 1, 1, alpha -- Default color: white
        if Day > 11 and Day < 16 then
            day_red, day_green, day_blue, day_alpha = 200/255, 55/255, 55/255, alpha -- Highlight color: red
        end        

        cairo_text_extents(cr, StringDay, extents)
        local day_width = extents.width
        cairo_text_extents(cr, Month, extents)
        local month_width = extents.width
        cairo_text_extents(cr, Year, extents)
        local year_width = extents.width

        local total_width = day_width + month_width + year_width + (x_margin*2)
        local xpos = (conky_window.width - total_width) / 2 

        -- Draw the day with conditional color
        draw_colored_text(cr, StringDay, xpos, ypos_hijri, day_red, day_green, day_blue, day_alpha)

        -- Draw the month in default color
        xpos = xpos + day_width + x_margin
        draw_colored_text(cr, Month, xpos, ypos_hijri, 1, 1, 1, alpha)        
        
        -- Draw the year in default color
        xpos = xpos + month_width + x_margin
        draw_colored_text(cr, tostring(Year), xpos, ypos_hijri, 1, 1, 1, alpha)        
  

    end

    -- Clean up
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
    cr = nil
end
