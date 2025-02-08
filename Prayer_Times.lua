-- Lua Script
require("cairo")
require("cairo_xlib")
local http = require("socket.http") -- Ensure LuaSocket is installed
local ltn12 = require("ltn12") -- Required for response sink
local json = require("dkjson") -- JSON parsing library

Prayers= {"Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"}

function TimeToMinutes(timeStr)
	local hours, minutes = timeStr:match("(%d+):(%d+)")
	return tonumber(hours) * 60 + tonumber(minutes)
end

function GetCurrentTime()
    local os_time = os.time()
    local current_time = os.date("%H:%M", os_time)
    return current_time
end

-- Function to fetch Prayer times
function fetch_prayer_times()
    local latitude = 30.0444
    local longitude = 31.23575
    local today_date = os.date("%d-%m-%Y")
    local url = "https://api.aladhan.com/v1/timings/" .. today_date .. "?latitude=" .. latitude .. "&longitude=" .. longitude .. "&midnightMode=1"
    local response_body = {}
    print('Fetching Prayer Times...')
    local res, code = http.request{
        url = url,
        sink = ltn12.sink.table(response_body)
    }
    if code == 200 then
        local response = table.concat(response_body)
        local data, _, err = json.decode(response, 1, nil)
        if not err then
            Fajr = data.data.timings.Fajr
            Sunrise = data.data.timings.Sunrise
            Dhuhr = data.data.timings.Dhuhr
            Asr = data.data.timings.Asr
            Maghrib = data.data.timings.Maghrib
            Isha = data.data.timings.Isha
            Midnight = data.data.timings.Midnight

            Prayer_times_table={Fajr=TimeToMinutes(Fajr), Sunrise=TimeToMinutes(Sunrise), Dhuhr=TimeToMinutes(Dhuhr), Asr=TimeToMinutes(Asr), Maghrib=TimeToMinutes(Maghrib), Isha=TimeToMinutes(Isha), Midnight=TimeToMinutes(Midnight)}

            print('Done Extracting Prayer Times')
        else
            print("Error fetching date")
        end
    else
        print("HTTP Error: " .. tostring(code))
    end
end

function GetCurrentPrayerAndTimeRemaining(prayer_times_table, current_time)
	for _, prayer in ipairs(Prayers) do
		local prayer_time = prayer_times_table[prayer]
        if prayer_time >= current_time and prayer ~= 'Midnight' and prayer ~= 'Sunrise' then			
            local remainingMinutes = prayer_time - current_time
            local hours = math.floor(remainingMinutes / 60)
            local minutes = remainingMinutes % 60
			return prayer, string.format("%02d", hours), string.format("%02d", minutes), remainingMinutes

        end
    end

    -- If no prayer time is found (past last prayer), return to Fajr		
	local remainingMinutes = (24 * 60) + prayer_times_table['Fajr'] - current_time
	local hours = math.floor(remainingMinutes / 60)
	local minutes = remainingMinutes % 60	
	return 'Fajr', string.format("%02d", hours), string.format("%02d", minutes), remainingMinutes

	
end


function GetPreviousPrayerAndTimeElapsed(Prayer_times_table, current_time)
	
	for i = #Prayers, 1, -1 do
		local prayer = Prayers[i]
		local prayer_time = Prayer_times_table[prayer]
        if prayer_time < current_time and prayer ~= 'Midnight' and prayer ~= 'Sunrise' then	
            local elapsedMinutes = current_time - prayer_time
            local hours = math.floor(elapsedMinutes / 60)
            local minutes = elapsedMinutes % 60
			return prayer, string.format("%02d", hours), string.format("%02d", minutes), elapsedMinutes

        end
    end

    -- If no prayer time is found (past last prayer), return to Isha		
	local elapsedMinutes = current_time + (24 * 60) - Prayer_times_table['Isha'] 
	local hours = math.floor(elapsedMinutes / 60)
	local minutes = elapsedMinutes % 60	
	return 'Isha', string.format("%02d", hours), string.format("%02d", minutes), elapsedMinutes

	
end


-- Fetch Prayer times once
fetch_prayer_times()

-- Function to draw text with color
function draw_colored_text(cr, text, font_size, xpos, ypos, red, green, blue, alpha)

    cairo_set_font_size(cr, font_size)
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
    local current_time = TimeToMinutes(GetCurrentTime())
    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height
    )
    

    local font = "ITC Avant Garde Pro XLt"
    local font_size = 250
    local font_small = 100
    local ypos = (font_size + (font_size/2)) * 2
    local xmargin = font_size/2
    local ymargin = font_size/5
    local alpha = 200/255

    cr = cairo_create(cs)
    cairo_set_font_size(cr, font_size)
    cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    

    local prayer, hours_till, minutes_till, remainingMinutes = GetCurrentPrayerAndTimeRemaining(Prayer_times_table, current_time)

    local prev_prayer, hours_since, minutes_since, elapsedMinutes = GetPreviousPrayerAndTimeElapsed(Prayer_times_table, current_time)

    local min_r, min_g, min_b, min_alpha = 1, 1, 1, alpha -- Default color: white
    local e_min_r, e_min_g, e_min_b, e_min_alpha = 1, 1, 1, alpha -- Default color: white

    if remainingMinutes < 16 then
        min_r, min_g, min_b, min_alpha = 200/255, 55/255, 55/255, alpha -- Highlight color: red
    end
    if elapsedMinutes > 5 and elapsedMinutes < 20 then
        e_min_r, e_min_g, e_min_b, e_min_alpha = 200/255, 55/255, 55/255, alpha -- Highlight color: red
    end
    
    local extents = cairo_text_extents_t:create()

    cairo_text_extents(cr, Fajr, extents)
    local fajr_width = extents.width
    
    local total_width = (fajr_width * 7) + (xmargin*6)

    local xpos = (conky_window.width - total_width) / 2 
    local name_margin_x = ymargin
    local name_margin_y = font_size


    draw_colored_text(cr, 'Since ' .. prev_prayer, font_small, xpos - name_margin_x, 0 + font_small, 1, 1, 1, alpha)
    draw_colored_text(cr, hours_since, font_size, xpos, 0 + font_size + font_small, 1, 1, 1, alpha) 
    draw_colored_text(cr, minutes_since, font_size, xpos + font_size + xmargin/2 , 0 + font_size + font_small, e_min_r, e_min_g, e_min_b, e_min_alpha) 

    draw_colored_text(cr, 'Fajr', font_small, xpos - name_margin_x, ypos - name_margin_y, 1, 1, 1, alpha)
    draw_colored_text(cr, Fajr, font_size, xpos, ypos, 1, 1, 1, alpha)

    draw_colored_text(cr, 'Till ' .. prayer, font_small, xpos - name_margin_x, ypos + font_small + ymargin, 1, 1, 1, alpha)
    draw_colored_text(cr, hours_till, font_size, xpos, ypos + font_size + font_small + ymargin, 1, 1, 1, alpha) 
    draw_colored_text(cr, minutes_till, font_size, xpos + font_size + xmargin/2 , ypos + font_size + font_small + ymargin, min_r, min_g, min_b, min_alpha) 

    xpos = xpos + fajr_width + xmargin
    draw_colored_text(cr, 'Sunrise', font_small, xpos - name_margin_x, ypos - name_margin_y, 1, 1, 1, alpha)
    draw_colored_text(cr, Sunrise, font_size, xpos, ypos, 1, 1, 1, alpha)
    if Prayer_times_table['Isha'] < current_time and Prayer_times_table['Midnight'] > current_time then
		local remainingMinutes_Midnight = Prayer_times_table['Midnight'] - current_time
		local hours_Midnight = string.format("%02d", math.floor(remainingMinutes_Midnight / 60))
		local minutes_Midnight = string.format("%02d", remainingMinutes_Midnight % 60)

        local min_r, min_g, min_b, min_alpha = 1, 1, 1, alpha -- Default color: white
        if remainingMinutes_Midnight <= 15 then
            min_r, min_g, min_b, min_alpha = 200/255, 55/255, 55/255, alpha		
		end

        draw_colored_text(cr, 'Till Midnight', font_small, xpos - name_margin_x, ypos + font_small + ymargin, 1, 1, 1, alpha)
        draw_colored_text(cr, hours_Midnight, font_size, xpos, ypos + font_size + font_small + ymargin, 1, 1, 1, alpha)
        draw_colored_text(cr, minutes_Midnight, font_size, xpos + font_size + xmargin/2, ypos + font_size + font_small + ymargin, min_r, min_g, min_b, min_alpha)
		
		
	
	elseif Prayer_times_table['Fajr'] < current_time and Prayer_times_table['Sunrise'] > current_time then

		local remainingMinutes_Sunrise = Prayer_times_table['Sunrise'] - current_time
        local hours_Sunrise = string.format("%02d", math.floor(remainingMinutes_Sunrise / 60))
		local minutes_Sunrise = string.format("%02d", remainingMinutes_Sunrise % 60)
        local min_r, min_g, min_b, min_alpha = 1, 1, 1, alpha -- Default color: white
        if remainingMinutes_Sunrise <= 15 then
            min_r, min_g, min_b, min_alpha = 200/255, 55/255, 55/255, alpha		
		end


        draw_colored_text(cr, 'Till Sunrise', font_small, xpos - name_margin_x, ypos + font_small + ymargin, 1, 1, 1, alpha)
        draw_colored_text(cr, hours_Sunrise, font_size, xpos, ypos + font_size + font_small + ymargin, 1, 1, 1, alpha)
        draw_colored_text(cr, minutes_Sunrise, font_size, xpos + font_size + xmargin/2, ypos + font_size + font_small + ymargin, min_r, min_g, min_b, min_alpha)


	end    
    
    xpos = xpos + fajr_width + xmargin
    draw_colored_text(cr, 'Dhuhr', font_small, xpos - name_margin_x, ypos - name_margin_y, 1, 1, 1, alpha)
    draw_colored_text(cr, Dhuhr, font_size, xpos, ypos, 1, 1, 1, alpha)        
    
    xpos = xpos + fajr_width + xmargin
    draw_colored_text(cr, 'Asr', font_small, xpos - name_margin_x, ypos - name_margin_y, 1, 1, 1, alpha)
    draw_colored_text(cr, Asr, font_size, xpos, ypos, 1, 1, 1, alpha)        
    
    xpos = xpos + fajr_width + xmargin
    draw_colored_text(cr, 'Maghrib', font_small, xpos - name_margin_x, ypos - name_margin_y, 1, 1, 1, alpha)
    draw_colored_text(cr, Maghrib, font_size, xpos, ypos, 1, 1, 1, alpha)        
    
    xpos = xpos + fajr_width + xmargin
    draw_colored_text(cr, 'Isha', font_small, xpos - name_margin_x, ypos - name_margin_y, 1, 1, 1, alpha)
    draw_colored_text(cr, Isha, font_size, xpos, ypos, 1, 1, 1, alpha)        
    
    xpos = xpos + fajr_width + xmargin
    draw_colored_text(cr, 'Midnight', font_small, xpos - name_margin_x, ypos - name_margin_y, 1, 1, 1, alpha)
    draw_colored_text(cr, Midnight, font_size, xpos, ypos, 1, 1, 1, alpha)        
         


    -- Clean up
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
    cr = nil
end
