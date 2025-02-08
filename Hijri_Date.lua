-- Lua Script
require("cairo")
require("cairo_xlib")
local http = require("socket.http") -- Ensure LuaSocket is installed
local ltn12 = require("ltn12") -- Required for response sink
local json = require("dkjson") -- JSON parsing library


-- Function to fetch Hijri date
function fetch_hijri_date()
    local month_name = {[1]="Muharram",[2]="Safar",[3]="Rabi Al Awwal",[4]="Rabi Al Thani",[5]="Jumada Al Oula",[6]="Jumada Al-Akhira",[7]="Rajab",[8]="Shaban",[9]="Ramadan", [10]="Shawwal", [11]="Dhul Qidah", [12]="Dhul Hijjah"}
    local today_date = os.date("%d-%m-%Y")
    local url = "https://api.aladhan.com/v1/gToH/" .. today_date
    local response_body = {}
    local res, code = http.request{
        url = url,
        sink = ltn12.sink.table(response_body)
    }

    if code == 200 then
        local response = table.concat(response_body)
        local data, _, err = json.decode(response, 1, nil)
        if not err then
            Day = data.data.hijri.day
            local month = data.data.hijri.month.number
            Month = month_name[month]
            Year = data.data.hijri.year
        else
            print("Error fetching date")
        end
    else
        print("HTTP Error: " .. tostring(code))
    end
end

-- Fetch the Hijri date 
fetch_hijri_date()

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
    local font_size = 500
    local ypos = font_size
    local margin = font_size/2.5
    local alpha = 200/255

    cr = cairo_create(cs)
    cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, font_size)

    -- Ensure valid split
    if Day and Month and Year then
        Day = tonumber(Day) -- Convert day to number for comparison
        StringDay = string.format("%02d", Day)
        -- Choose colors for the day
        local day_red, day_green, day_blue, day_alpha = 1, 1, 1, alpha -- Default color: white
        if Day > 11 and Day < 16 then
            day_red, day_green, day_blue, day_alpha = 200/255, 55/255, 55/255, alpha -- Highlight color: red
        end
        
        local extents = cairo_text_extents_t:create()
        cairo_text_extents(cr, StringDay, extents)
        local day_width = extents.width
        cairo_text_extents(cr, Month, extents)
        local month_width = extents.width
        cairo_text_extents(cr, Year, extents)
        local year_width = extents.width

        local total_width = day_width + month_width + year_width + (margin*2)
        local xpos = (conky_window.width - total_width) / 2 

        -- Draw the day with conditional color
        draw_colored_text(cr, StringDay, xpos, ypos, day_red, day_green, day_blue, day_alpha)

        -- Draw the month in default color
        xpos = xpos + day_width + margin
        draw_colored_text(cr, Month, xpos, ypos, 1, 1, 1, alpha)        
        
        -- Draw the year in default color
        xpos = xpos + month_width + margin
        draw_colored_text(cr, tostring(Year), xpos, ypos, 1, 1, 1, alpha)        
  

    end

    -- Clean up
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
    cr = nil
end
