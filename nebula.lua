local pui = require 'gamesense/pui'
local vector = require 'vector'
local base64 = require 'gamesense/base64'
local json = require 'json'
local bit = require 'bit'
local trace = require 'gamesense/trace'
local screen = {client.screen_size()}
local center = {screen[1]/2, screen[2]/2}
local effects = {
    stars = {},
    welcome_active = true,
    welcome_alpha = 255
}
-- Speedhack Variables (Часть 1: вставлено после screen и center)
local speed_enabled = false
local base_speed = 1.0
local current_speed = base_speed
local target_speed = base_speed
local speed_multiplier = 2.0
local lerp_rate = 0.1
local anti_detect_enabled = true
local fake_lag_enabled = false
local fake_lag_amount = 6
local speed_boost_key = false
local speed_indicator_enabled = true
local indicator_x, indicator_y = center[1], center[2] + 100
local indicator_r, indicator_g, indicator_b, indicator_alpha = 135, 206, 235, 255



-- [[ PUI Groups and Accent ]]
local lua_group = pui.group("AA", "Anti-aimbot angles")
local config_group = pui.group("AA", "Fake lag")
local other_group = pui.group("AA", "Other")
pui.accent = "1E90FFFF" -- Cosmic blue accent

-- [[ Helper Functions ]]
local function rgba_to_hex(b, c, d, e)
    return string.format('%02x%02x%02x%02x', b, c, d, e)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function clamp(x, minval, maxval)
    return x < minval and minval or x > maxval and maxval or x
end

local function text_fade_animation(x, y, speed, color1, color2, text, flag)
    local final_text = ''
    local curtime = globals.curtime()
    for i = 0, #text do
        local wave = math.sin(speed * curtime + i / 5)
        local color = rgba_to_hex(
            lerp(color1.r, color2.r, clamp(wave, 0, 1)),
            lerp(color1.g, color2.g, clamp(wave, 0, 1)),
            lerp(color1.b, color2.b, clamp(wave, 0, 1)),
            color1.a
        )
        final_text = final_text .. '\a' .. color .. text:sub(i, i)
    end
    renderer.text(x, y, color1.r, color1.g, color1.b, color1.a, flag, nil, final_text)
end

local function toticks(time)
    return math.floor(time / globals.tickinterval() + 0.5)
end
-- [[ Effects Storage ]]
local effects = {
    menu_open = false,
    menu_fade_alpha = 0,
    welcome_active = true,
    welcome_alpha = 255,
    stars = {}
}

-- [[ Generate Cosmic Stars for Effects ]]
local function generate_stars()
    effects.stars = {}
    for i = 1, 50 do
        table.insert(effects.stars, {
            x = math.random(0, screen[1]),
            y = math.random(0, screen[2]),
            size = math.random(1, 3),
            alpha = math.random(50, 255),
            speed = math.random(1, 3)
        })
    end
end

-- [[ Cosmic Effect for Menu Opening ]]
local function render_cosmic_menu_effect()
    if not effects.menu_open then
        effects.menu_fade_alpha = lerp(effects.menu_fade_alpha, 0, globals.frametime() * 5)
    else
        effects.menu_fade_alpha = lerp(effects.menu_fade_alpha, 150, globals.frametime() * 5)
    end

    renderer.rectangle(0, 0, screen[1], screen[2], 10, 20, 40, effects.menu_fade_alpha)

    for _, star in ipairs(effects.stars) do
        star.y = star.y + star.speed * globals.frametime() * 60
        if star.y > screen[2] then star.y = -star.size end
        renderer.circle(star.x, star.y, 255, 255, 255, star.alpha, star.size, 1, 1)
    end
end

-- [[ Welcome Screen Effect ]]
local function render_welcome_effect()
    if not effects.welcome_active then return end

    effects.welcome_alpha = lerp(effects.welcome_alpha, 0, globals.frametime() * 2)
    if effects.welcome_alpha < 1 then effects.welcome_active = false return end

    renderer.rectangle(0, 0, screen[1], screen[2], 10, 20, 40, effects.welcome_alpha)

    for _, star in ipairs(effects.stars) do
        star.x = star.x + math.sin(globals.curtime() + star.speed) * 2
        star.y = star.y + math.cos(globals.curtime() + star.speed) * 2
        if star.x < 0 or star.x > screen[1] or star.y < 0 or star.y > screen[2] then
            star.x, star.y = math.random(0, screen[1]), math.random(0, screen[2])
        end
        renderer.circle(star.x, star.y, 135, 206, 235, effects.welcome_alpha * (star.alpha / 255), star.size, 1, 1)
    end

    text_fade_animation(center[1], center[2] - 20, -1.5, {r=135, g=206, b=235, a=effects.welcome_alpha}, {r=30, g=144, b=255, a=effects.welcome_alpha}, "Welcome to Nebula Overlord", "cdb")
end

-- [[ Initial Star Generation ]]
generate_stars()

-- [[ Anti-Aim Conditions ]]
local antiaim_cond = { '\vGlobal\r', '\vStand\r', '\vWalking\r', '\vRunning\r', '\vAir\r', '\vAir+Duck\r', '\vDuck\r', '\vDuck+Move\r' }
local short_cond = { '\vG ·\r', '\vS ·\r', '\vW ·\r', '\vR ·\r', '\vA ·\r', '\vAD ·\r', '\vD ·\r', '\vDM ·\r' }

-- [[ UI References ]]
local ref = {
    enabled = ui.reference('AA', 'Anti-aimbot angles', 'Enabled'),
    yawbase = ui.reference('AA', 'Anti-aimbot angles', 'Yaw base'),
    fsbodyyaw = ui.reference('AA', 'Anti-aimbot angles', 'Freestanding body yaw'),
    edgeyaw = ui.reference('AA', 'Anti-aimbot angles', 'Edge yaw'),
    fakeduck = ui.reference('RAGE', 'Other', 'Duck peek assist'),
    forcebaim = ui.reference('RAGE', 'Aimbot', 'Force body aim'),
    safepoint = ui.reference('RAGE', 'Aimbot', 'Force safe point'),
    roll = { ui.reference('AA', 'Anti-aimbot angles', 'Roll') },
    clantag = ui.reference('Misc', 'Miscellaneous', 'Clan tag spammer'),
    pitch = { ui.reference('AA', 'Anti-aimbot angles', 'Pitch') },
    rage = { ui.reference('RAGE', 'Aimbot', 'Enabled') },
    yaw = { ui.reference('AA', 'Anti-aimbot angles', 'Yaw') },
    yawjitter = { ui.reference('AA', 'Anti-aimbot angles', 'Yaw jitter') },
    bodyyaw = { ui.reference('AA', 'Anti-aimbot angles', 'Body yaw') },
    freestand = { ui.reference('AA', 'Anti-aimbot angles', 'Freestanding') },
    slow = { ui.reference('AA', 'Other', 'Slow motion') },
    os = { ui.reference('AA', 'Other', 'On shot anti-aim') },
    dt = { ui.reference('RAGE', 'Aimbot', 'Double tap') },
    minimum_damage = ui.reference("RAGE", "Aimbot", "Minimum damage"),
    minimum_damage_override = { ui.reference("RAGE", "Aimbot", "Minimum damage override") },
    quick_peek_assist = { ui.reference("RAGE", "Other", "Quick peek assist") },
    quick_peek_assist_mode = { ui.reference("RAGE", "Other", "Quick peek assist mode") }
}
-- [[ Nebula Overlord Menu ]]
local lua_menu = {
    main = {
        enable = lua_group:label("Nebula Overlord"),
        tab = lua_group:combobox('\vN · \rMain Tab', {"Anti-Aim", "Visuals", "Misc", "Exploits", "Configs"}), -- Добавлена вкладка Configs
    },
    antiaim = {
        tab = lua_group:combobox("\vN · \rAnti-Aim Tab", {"Settings", "Conditions"}),
        addons = lua_group:multiselect('\vN · \rEnhancements', {'Warmup Protection', 'Knife Defense', 'Head Safety'}),
        safe_head = lua_group:multiselect('\vN · \rHead Safety', {'Air+Duck Knife', 'Air+Duck Zeus', 'Long Range'}),
        yaw_direction = lua_group:multiselect('\vN · \rYaw Control', {'Freestanding', 'Manual'}),
        key_freestand = lua_group:hotkey('\vN · \rFreestanding Key'),
        key_left = lua_group:hotkey('\vN · \rManual Left'),
        key_right = lua_group:hotkey('\vN · \rManual Right'),
        key_forward = lua_group:hotkey('\vN · \rManual Forward'),
        yaw_base = lua_group:combobox("\vN · \rYaw Base", {"Local View", "At Targets"}),
        condition = lua_group:combobox('\vN · \rCurrent Condition', antiaim_cond),
    },
    misc = {
        cross_ind = lua_group:checkbox("\vN · \rCrosshair HUD", {30, 144, 255}),
        cross_ind_type = lua_group:combobox("  \vN · \rHUD Style", {"Cosmic", "Minimal", "Orbit", "Nebula"}),
        cross_color = lua_group:checkbox("  \vN · \rHUD Color", {135, 206, 235}),
        key_color = lua_group:checkbox("  \vN · \rKeybind Color", {255, 255, 255}),
        info_panel = lua_group:checkbox("\vN · \rNebula Panel"),
        defensive_window = lua_group:checkbox("\vN · \rDefensive Bar", {30, 144, 255}),
        defensive_style = lua_group:combobox("  \vN · \rBar Style", {"Gradient", "Solid"}),
        velocity_window = lua_group:checkbox("\vN · \rVelocity Bar", {30, 144, 255}),
        velocity_style = lua_group:combobox("  \vN · \rBar Style", {"Gradient", "Solid"}),
        fast_ladder = lua_group:checkbox("\vN · \rFast Ladder"),
        log = lua_group:checkbox("\vN · \rRagebot Logs"),
        log_type = lua_group:multiselect("  \vN · \rLog Output", {"Console", "Screen"}),
        screen_type = lua_group:combobox("  \vN · \rLog Style", {"Cosmic", "Minimal"}),
        animation = lua_group:checkbox("\vN · \rAnimation Tweaks"),
        animation_ground = lua_group:combobox("  \vN · \rGround Anim", {"Static", "Pulse", "Random", "Walk Static", "Walk Pulse"}),
        animation_value = lua_group:slider("  \vN · \rAnim Intensity", 0, 10, 5),
        animation_air = lua_group:combobox("  \vN · \rAir Anim", {"Off", "Static", "Random", "Walk Static", "Walk Pulse"}),
        third_person = lua_group:checkbox("\vN · \rThird Person Zoom"),
        third_person_value = lua_group:slider("  \vN · \rZoom Distance", 30, 200, 50),
        aspectratio = lua_group:checkbox("\vN · \rAspect Ratio"),
        aspectratio_value = lua_group:slider("  \vN · \rAspect Value", 0, 200, 133),
        teleport = lua_group:checkbox("\vN · \rLC Teleport"),
        teleport_key = lua_group:hotkey("\vN · \rTeleport Key", true),
        resolver = lua_group:checkbox("\vN · \rCustom Resolver"),
        resolver_type = lua_group:combobox("  \vN · \rResolver Mode", {"Safe", "Advanced", "Defensive"}),
        clantag = lua_group:checkbox("\vN · \rCosmic Clantag"),
        clantag_animation = lua_group:combobox("  \vN · \rClantag Animation", {"Fade", "Scroll", "Blink", "Wave"}),
        clantag_speed = lua_group:slider("  \vN · \rClantag Speed", 0.1, 2.0, 0.5, true, "s", 0.1),
        trashtalk = lua_group:checkbox("\vN · \rTrashtalk"),
        trashtalk_language = lua_group:combobox("  \vN · \rTrashtalk Language", {"English", "Russian", "Spanish", "Chinese"})
    },
    visuals = {
        bullet_tracers = lua_group:checkbox("\vN · \rBullet Tracers", {93, 240, 235, 255}),
        bullet_tracers_color = lua_group:color_picker("  \vN · \rTracer Color", 93, 240, 235, 255),
        bullet_tracers_animation = lua_group:combobox("  \vN · \rTracer Animation", {"Fade", "Pulse", "Static", "Stars"}),
        bullet_tracers_lifetime = lua_group:slider("  \vN · \rTracer Lifetime", 1, 10, 2, true, "s")
    },
    exploits = {
        exploits_enabled = lua_group:checkbox("\vN · \rEnable Exploits"),
        unlimited_bt = lua_group:checkbox("\vN · \rUnlimited Backtrack"),
        unlimited_bt_key = lua_group:hotkey("  \vN · \rUnlimited BT Key", true),
        unlimited_bt_ticks = lua_group:slider("  \vN · \rBT Ticks", 1, 12, 12, true, "t"),
        unlimited_bt_choke = lua_group:slider("  \vN · \rBT Choke Amount", 1, 14, 14, true, "t"),
        unlimited_bt_priority = lua_group:checkbox("  \vN · \rHigh Priority Targets", true),
        phantom_reload = lua_group:checkbox("\vN · \rPhantom Reload"),
        phantom_reload_key = lua_group:hotkey("  \vN · \rPhantom Reload Key", true),
        phantom_reload_interval = lua_group:slider("  \vN · \rReload Interval", 5, 50, 20, true, "t"),
        ai_peek = lua_group:checkbox("\vN · \rAI Peek"),
        ai_peek_key = lua_group:hotkey("  \vN · \rPeek Bot Key", true, 0),
        ai_peek_mode = lua_group:combobox("  \vN · \rDetection Mode", {"Risky", "Safest"}),
        ai_peek_target = lua_group:combobox("  \vN · \rDetection Target", {"Current", "All target"}),
        ai_peek_hitbox = lua_group:multiselect("  \vN · \rDetection Hitbox", {"Head", "Neck", "Chest", "Stomach", "Arms", "Legs", "Feet"}),
        ai_peek_tick = lua_group:slider("  \vN · \rReserve Extrapolate Tick", 0, 5, 0),
        ai_peek_unlock = lua_group:checkbox("  \vN · \rUnlock Camera"),
        ai_peek_segament = lua_group:slider("  \vN · \rSegament", 2, 60, 2),
        ai_peek_radius = lua_group:slider("  \vN · \rRadius", 0, 250, 50),
        ai_peek_depart = lua_group:slider("  \vN · \rDepartment", 1, 12, 2),
        ai_peek_middle = lua_group:checkbox("  \vN · \rMiddle Point"),
        ai_peek_limit = lua_group:checkbox("  \vN · \rMax Prediction Point Limit"),
        ai_peek_limit_num = lua_group:slider("  \vN · \rLimit Num", 0, 20, 5),
        ai_peek_debugger = lua_group:multiselect("  \vN · \rDebugger", {"Line player-predict", "Line predict-target", "Fraction detection", "Base"}),
        ai_peek_color = lua_group:color_picker("  \vN · \rDebugger Color", 255, 255, 255, 255)
    },
    configs = {
        import_button = lua_group:button("\vN · \rImport Config"),
        export_button = lua_group:button("\vN · \rExport Config"),
        reset_button = lua_group:button("\vN · \rReset Config")
    }
}

local function update_menu()
    local cosmic_colors = {
        {30, 144, 255, 255 * math.abs(math.cos(2 * math.pi * globals.curtime() / 4))},
        {135, 206, 235, 255 * math.abs(math.cos(2 * math.pi * globals.curtime() / 4 + 0.5))}
    }
    local label_text = string.format("­ NEBULA OVERLORD \a%s%s­", rgba_to_hex(unpack(cosmic_colors[1])), rgba_to_hex(unpack(cosmic_colors[2])))
    lua_menu.main.enable:set(label_text)
end

-- [[ Anti-Aim Condition System ]]
local antiaim_system = {}
for i = 1, #antiaim_cond do
    antiaim_system[i] = {
        label = lua_group:label(' · Nebula \vCondition\r Setup ~ '),
        enable = lua_group:checkbox('Enable · '..antiaim_cond[i]),
        yaw_type = lua_group:combobox(short_cond[i]..'Yaw Mode', {"Default", "Delayed"}),
        yaw_delay = lua_group:slider(short_cond[i]..'Delay Ticks', 1, 10, 4, true, 't', 1),
        yaw_left = lua_group:slider(short_cond[i]..'Yaw Left', -180, 180, 0, true, '°', 1),
        yaw_right = lua_group:slider(short_cond[i]..'Yaw Right', -180, 180, 0, true, '°', 1),
        yaw_random = lua_group:slider(short_cond[i]..'Random Factor', 0, 100, 0, true, '%', 1),
        mod_type = lua_group:combobox(short_cond[i]..'Jitter Mode', {'Off', 'Offset', 'Center', 'Random', 'Pulse'}),
        mod_dm = lua_group:slider(short_cond[i]..'Jitter Range', -180, 180, 0, true, '°', 1),
        body_yaw_type = lua_group:combobox(short_cond[i]..'Body Yaw', {'Off', 'Opposite', 'Pulse', 'Static'}),
        body_slider = lua_group:slider(short_cond[i]..'Body Yaw Degree', -180, 180, 0, true, '°', 1),
        force_def = lua_group:checkbox(short_cond[i]..'Force Defensive'),
        peek_def = lua_group:checkbox(short_cond[i]..'Defensive Peek'),
        defensive = lua_group:checkbox(short_cond[i]..'Defensive AA'),
        defensive_type = lua_group:combobox(short_cond[i]..'Defensive Style', {'Default', 'Custom'}),
        defensive_yaw = lua_group:combobox(short_cond[i]..'Defensive Yaw', {'Off', 'Spin', 'Cosmic', 'Random'}),
        yaw_value = lua_group:slider(short_cond[i]..'Yaw Degree', -180, 180, 0, true, '°', 1),
        def_yaw_value = lua_group:slider(short_cond[i]..'[DEF] Yaw Degree', -180, 180, 0, true, '°', 1),
        def_mod_type = lua_group:combobox(short_cond[i]..'[DEF] Jitter Mode', {'Off', 'Offset', 'Center', 'Random', 'Pulse'}),
        def_mod_dm = lua_group:slider(short_cond[i]..'[DEF] Jitter Range', -180, 180, 0, true, '°', 1),
        def_body_yaw_type = lua_group:combobox(short_cond[i]..'[DEF] Body Yaw', {'Off', 'Opposite', 'Pulse', 'Static'}),
        def_body_slider = lua_group:slider(short_cond[i]..'[DEF] Body Yaw Degree', -180, 180, 0, true, '°', 1),
        defensive_pitch = lua_group:combobox(short_cond[i]..'Defensive Pitch', {'Off', 'Custom', 'Cosmic', 'Random'}),
        pitch_value = lua_group:slider(short_cond[i]..'Pitch Degree', -89, 89, 0, true, '°', 1)
    }
end

-- [[ Menu Dependencies ]]
local aa_tab = {lua_menu.main.tab, "Anti-Aim"}
local misc_tab = {lua_menu.main.tab, "Misc"}
local visual_tab = {lua_menu.main.tab, "Visuals"}
local exploits_tab = {lua_menu.main.tab, "Exploits"}
local configs_tab = {lua_menu.main.tab, "Configs"}
local aa_cond_tab = {lua_menu.antiaim.tab, "Conditions"}
local aa_settings = {lua_menu.antiaim.tab, "Settings"}

lua_menu.antiaim.tab:depend(aa_tab)
lua_menu.antiaim.addons:depend(aa_tab, aa_settings)
lua_menu.antiaim.safe_head:depend(aa_tab, {lua_menu.antiaim.addons, "Head Safety"}, aa_settings)
lua_menu.antiaim.yaw_base:depend(aa_tab, aa_settings)
lua_menu.antiaim.condition:depend(aa_tab, aa_cond_tab)
lua_menu.antiaim.yaw_direction:depend(aa_tab, aa_settings)
lua_menu.antiaim.key_freestand:depend(aa_tab, {lua_menu.antiaim.yaw_direction, "Freestanding"}, aa_settings)
lua_menu.antiaim.key_left:depend(aa_tab, {lua_menu.antiaim.yaw_direction, "Manual"}, aa_settings)
lua_menu.antiaim.key_right:depend(aa_tab, {lua_menu.antiaim.yaw_direction, "Manual"}, aa_settings)
lua_menu.antiaim.key_forward:depend(aa_tab, {lua_menu.antiaim.yaw_direction, "Manual"}, aa_settings)
lua_menu.misc.cross_ind:depend(visual_tab)
lua_menu.misc.cross_ind_type:depend(visual_tab, {lua_menu.misc.cross_ind, true})
lua_menu.misc.info_panel:depend(visual_tab)
lua_menu.misc.defensive_window:depend(visual_tab)
lua_menu.misc.defensive_style:depend(visual_tab, {lua_menu.misc.defensive_window, true})
lua_menu.misc.velocity_window:depend(visual_tab)
lua_menu.misc.velocity_style:depend(visual_tab, {lua_menu.misc.velocity_window, true})
lua_menu.misc.cross_color:depend(visual_tab, {lua_menu.misc.cross_ind, true})
lua_menu.misc.key_color:depend(visual_tab, {lua_menu.misc.cross_ind, true})
lua_menu.misc.log:depend(visual_tab)
lua_menu.misc.log_type:depend(visual_tab, {lua_menu.misc.log, true})
lua_menu.misc.screen_type:depend(visual_tab, {lua_menu.misc.log, true}, {lua_menu.misc.log_type, "Screen"})
lua_menu.misc.fast_ladder:depend(misc_tab)
lua_menu.misc.animation:depend(misc_tab)
lua_menu.misc.animation_ground:depend(misc_tab, {lua_menu.misc.animation, true})
lua_menu.misc.animation_value:depend(misc_tab, {lua_menu.misc.animation, true})
lua_menu.misc.animation_air:depend(misc_tab, {lua_menu.misc.animation, true})
lua_menu.misc.third_person:depend(misc_tab)
lua_menu.misc.third_person_value:depend(misc_tab, {lua_menu.misc.third_person, true})
lua_menu.misc.aspectratio:depend(misc_tab)
lua_menu.misc.aspectratio_value:depend(misc_tab, {lua_menu.misc.aspectratio, true})
lua_menu.misc.teleport:depend(misc_tab)
lua_menu.misc.teleport_key:depend(misc_tab)
lua_menu.misc.resolver:depend(misc_tab)
lua_menu.misc.resolver_type:depend(misc_tab, {lua_menu.misc.resolver, true})
lua_menu.misc.clantag:depend(misc_tab)
lua_menu.misc.clantag_animation:depend(misc_tab, {lua_menu.misc.clantag, true})
lua_menu.misc.clantag_speed:depend(misc_tab, {lua_menu.misc.clantag, true})
lua_menu.misc.trashtalk:depend(misc_tab)
lua_menu.misc.trashtalk_language:depend(misc_tab, {lua_menu.misc.trashtalk, true})
lua_menu.visuals.bullet_tracers:depend(visual_tab)
lua_menu.visuals.bullet_tracers_color:depend(visual_tab, {lua_menu.visuals.bullet_tracers, true})
lua_menu.visuals.bullet_tracers_animation:depend(visual_tab, {lua_menu.visuals.bullet_tracers, true})
lua_menu.visuals.bullet_tracers_lifetime:depend(visual_tab, {lua_menu.visuals.bullet_tracers, true})
lua_menu.exploits.exploits_enabled:depend(exploits_tab)
lua_menu.exploits.unlimited_bt:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true})
lua_menu.exploits.unlimited_bt_key:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.unlimited_bt, true})
lua_menu.exploits.unlimited_bt_ticks:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.unlimited_bt, true})
lua_menu.exploits.unlimited_bt_choke:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.unlimited_bt, true})
lua_menu.exploits.unlimited_bt_priority:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.unlimited_bt, true})
lua_menu.exploits.phantom_reload:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true})
lua_menu.exploits.phantom_reload_key:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.phantom_reload, true})
lua_menu.exploits.phantom_reload_interval:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.phantom_reload, true})
lua_menu.exploits.speedhack:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true})
lua_menu.exploits.speedhack_key:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.speedhack, true})
lua_menu.exploits.speed_multiplier:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.speedhack, true})
lua_menu.exploits.speed_lerp:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.speedhack, true})
lua_menu.exploits.speed_anti_detect:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.speedhack, true})
lua_menu.exploits.speed_fake_lag:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.speedhack, true})
lua_menu.exploits.speed_fake_lag_amount:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.speedhack, true}, {lua_menu.exploits.speed_fake_lag, true})
lua_menu.exploits.ai_peek:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true})
lua_menu.exploits.ai_peek_key:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true})
lua_menu.exploits.ai_peek_mode:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true})
lua_menu.exploits.ai_peek_target:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true})
lua_menu.exploits.ai_peek_hitbox:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true})
lua_menu.exploits.ai_peek_tick:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true})
lua_menu.exploits.ai_peek_unlock:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true})
lua_menu.exploits.ai_peek_segament:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true})
lua_menu.exploits.ai_peek_radius:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true})
lua_menu.exploits.ai_peek_depart:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true})
lua_menu.exploits.ai_peek_middle:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true})
lua_menu.exploits.ai_peek_limit:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true})
lua_menu.exploits.ai_peek_limit_num:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true}, {lua_menu.exploits.ai_peek_limit, true})
lua_menu.exploits.ai_peek_debugger:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true})
lua_menu.exploits.ai_peek_color:depend(exploits_tab, {lua_menu.exploits.exploits_enabled, true}, {lua_menu.exploits.ai_peek, true})
lua_menu.configs.import_button:depend(configs_tab)
lua_menu.configs.export_button:depend(configs_tab)
lua_menu.configs.reset_button:depend(configs_tab)

for i = 1, #antiaim_cond do
    local cond_check = {lua_menu.antiaim.condition, function() return (i ~= 1) end}
    local tab_cond = {lua_menu.antiaim.condition, antiaim_cond[i]}
    local cnd_en = {antiaim_system[i].enable, function() if i == 1 then return true else return antiaim_system[i].enable:get() end end}
    local jit_ch = {antiaim_system[i].mod_type, function() return antiaim_system[i].mod_type:get() ~= "Off" end}
    local def_jit_ch = {antiaim_system[i].def_mod_type, function() return antiaim_system[i].def_mod_type:get() ~= "Off" end}
    local def_ch = {antiaim_system[i].defensive, true}
    local body_ch = {antiaim_system[i].body_yaw_type, function() return antiaim_system[i].body_yaw_type:get() ~= "Off" end}
    local def_body_ch = {antiaim_system[i].def_body_yaw_type, function() return antiaim_system[i].def_body_yaw_type:get() ~= "Off" end}
    local delay_ch = {antiaim_system[i].yaw_type, "Delayed"}
    local yaw_ch = {antiaim_system[i].defensive_yaw, "Spin"}
    local def_yaw_ch = {antiaim_system[i].defensive_type, "Custom"}
    local def_def = {antiaim_system[i].defensive_type, "Default"}
    local def_custom = {antiaim_system[i].defensive_type, "Custom"}
    local pitch_ch = {antiaim_system[i].defensive_pitch, "Custom"}

    antiaim_system[i].label:depend(tab_cond, aa_tab, aa_cond_tab)
    antiaim_system[i].enable:depend(cond_check, tab_cond, aa_tab, aa_cond_tab)
    antiaim_system[i].yaw_type:depend(cnd_en, tab_cond, aa_tab, aa_cond_tab)
    antiaim_system[i].yaw_delay:depend(cnd_en, tab_cond, aa_tab, delay_ch, aa_cond_tab)
    antiaim_system[i].yaw_left:depend(cnd_en, tab_cond, aa_tab, aa_cond_tab)
    antiaim_system[i].yaw_right:depend(cnd_en, tab_cond, aa_tab, aa_cond_tab)
    antiaim_system[i].yaw_random:depend(cnd_en, tab_cond, aa_tab, aa_cond_tab)
    antiaim_system[i].mod_type:depend(cnd_en, tab_cond, aa_tab, aa_cond_tab)
    antiaim_system[i].mod_dm:depend(cnd_en, tab_cond, aa_tab, jit_ch, aa_cond_tab)
    antiaim_system[i].body_yaw_type:depend(cnd_en, tab_cond, aa_tab, aa_cond_tab)
    antiaim_system[i].body_slider:depend(cnd_en, tab_cond, aa_tab, body_ch, aa_cond_tab)
    antiaim_system[i].force_def:depend(cnd_en, tab_cond, aa_tab, aa_cond_tab)
    antiaim_system[i].peek_def:depend(cnd_en, tab_cond, aa_tab, {antiaim_system[i].force_def, false}, aa_cond_tab)
    antiaim_system[i].defensive:depend(cnd_en, tab_cond, aa_tab, aa_cond_tab)
    antiaim_system[i].defensive_type:depend(cnd_en, tab_cond, aa_tab, def_ch, aa_cond_tab)
    antiaim_system[i].defensive_yaw:depend(cnd_en, tab_cond, aa_tab, def_ch, def_def, aa_cond_tab)
    antiaim_system[i].yaw_value:depend(cnd_en, tab_cond, aa_tab, def_ch, yaw_ch, def_def, aa_cond_tab)
    antiaim_system[i].def_yaw_value:depend(cnd_en, tab_cond, aa_tab, def_ch, def_yaw_ch, aa_cond_tab)
    antiaim_system[i].def_mod_type:depend(cnd_en, tab_cond, aa_tab, def_ch, def_custom, aa_cond_tab)
    antiaim_system[i].def_mod_dm:depend(cnd_en, tab_cond, aa_tab, def_ch, def_custom, def_jit_ch, aa_cond_tab)
    antiaim_system[i].def_body_yaw_type:depend(cnd_en, tab_cond, aa_tab, def_ch, def_custom, aa_cond_tab)
    antiaim_system[i].def_body_slider:depend(cnd_en, tab_cond, aa_tab, def_ch, def_custom, def_body_ch, aa_cond_tab)
    antiaim_system[i].defensive_pitch:depend(cnd_en, tab_cond, aa_tab, def_ch, aa_cond_tab)
    antiaim_system[i].pitch_value:depend(cnd_en, tab_cond, aa_tab, def_ch, pitch_ch, aa_cond_tab)
end
-- [[ Helper Functions ]]
local function hide_original_menu(state)
    ui.set_visible(ref.enabled, state)
    ui.set_visible(ref.pitch[1], state)
    ui.set_visible(ref.pitch[2], state)
    ui.set_visible(ref.yawbase, state)
    ui.set_visible(ref.yaw[1], state)
    ui.set_visible(ref.yaw[2], state)
    ui.set_visible(ref.yawjitter[1], state)
    ui.set_visible(ref.yawjitter[2], state)
    ui.set_visible(ref.bodyyaw[1], state)
    ui.set_visible(ref.bodyyaw[2], state)
    ui.set_visible(ref.fsbodyyaw, state)
    ui.set_visible(ref.edgeyaw, state)
    ui.set_visible(ref.freestand[1], state)
    ui.set_visible(ref.freestand[2], state)
    ui.set_visible(ref.roll[1], state)
end

local function randomize_value(original_value, percent)
    local min_range = original_value - (original_value * percent / 100)
    local max_range = original_value + (original_value * percent / 100)
    return math.random(min_range, max_range)
end

-- [[ Defensive Detection ]]
local last_sim_time = 0
local native_GetClientEntity = vtable_bind('client.dll', 'VClientEntityList003', 3, 'void*(__thiscall*)(void*, int)')

function is_defensive_active(lp)
    if globals.chokedcommands() > 1 then return false end
    if lp == nil or not entity.is_alive(lp) then return end
    local m_flOldSimulationTime = ffi.cast("float*", ffi.cast("uintptr_t", native_GetClientEntity(lp)) + 0x26C)[0]
    local m_flSimulationTime = entity.get_prop(lp, "m_flSimulationTime")
    local delta = toticks(m_flOldSimulationTime - m_flSimulationTime)
    if delta > 0 then
        last_sim_time = globals.tickcount() + delta - toticks(client.real_latency())
    end
    return last_sim_time > globals.tickcount()
end

function is_defensive_resolver(lp)
    if lp == nil or not entity.is_alive(lp) then return end
    local m_flOldSimulationTime = ffi.cast("float*", ffi.cast("uintptr_t", native_GetClientEntity(lp)) + 0x26C)[0]
    local m_flSimulationTime = entity.get_prop(lp, "m_flSimulationTime")
    local delta = toticks(m_flOldSimulationTime - m_flSimulationTime)
    if delta > 0 then
        last_sim_time = globals.tickcount() + delta - toticks(client.real_latency())
    end
    return last_sim_time > globals.tickcount()
end

-- [[ Player State Detection ]]
local id = 1
local function player_state(cmd)
    local lp = entity.get_local_player()
    if lp == nil then return end

    local vecvelocity = { entity.get_prop(lp, 'm_vecVelocity') }
    local flags = entity.get_prop(lp, 'm_fFlags')
    local velocity = math.sqrt(vecvelocity[1]^2 + vecvelocity[2]^2)
    local groundcheck = bit.band(flags, 1) == 1
    local jumpcheck = bit.band(flags, 1) == 0 or cmd.in_jump == 1
    local ducked = entity.get_prop(lp, 'm_flDuckAmount') > 0.7
    local duckcheck = ducked or ui.get(ref.fakeduck)
    local slowwalk_key = ui.get(ref.slow[1]) and ui.get(ref.slow[2])

    if jumpcheck and duckcheck then return "Air+Duck"
    elseif jumpcheck then return "Air"
    elseif duckcheck and velocity > 10 then return "Duck+Move"
    elseif duckcheck and velocity < 10 then return "Duck"
    elseif groundcheck and slowwalk_key and velocity > 10 then return "Walking"
    elseif groundcheck and velocity > 5 then return "Running"
    elseif groundcheck and velocity < 5 then return "Stand"
    else return "Global" end
end

-- [[ Yaw Direction Control ]]
local yaw_direction = 0
local last_press_t_dir = 0

local function run_direction()
    ui.set(ref.freestand[1], lua_menu.antiaim.yaw_direction:get("Freestanding"))
    ui.set(ref.freestand[2], lua_menu.antiaim.key_freestand:get() and 'Always on' or 'On hotkey')

    if yaw_direction ~= 0 then
        ui.set(ref.freestand[1], false)
    end

    if lua_menu.antiaim.yaw_direction:get("Manual") then
        if lua_menu.antiaim.key_right:get() and last_press_t_dir + 0.2 < globals.curtime() then
            yaw_direction = yaw_direction == 90 and 0 or 90
            last_press_t_dir = globals.curtime()
        elseif lua_menu.antiaim.key_left:get() and last_press_t_dir + 0.2 < globals.curtime() then
            yaw_direction = yaw_direction == -90 and 0 or -90
            last_press_t_dir = globals.curtime()
        elseif lua_menu.antiaim.key_forward:get() and last_press_t_dir + 0.2 < globals.curtime() then
            yaw_direction = yaw_direction == 180 and 0 or 180
            last_press_t_dir = globals.curtime()
        elseif last_press_t_dir > globals.curtime() then
            last_press_t_dir = globals.curtime()
        end
    end
end

-- [[ Distance Calculation for Anti-Knife ]]
local function anti_knife_dist(x1, y1, z1, x2, y2, z2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2 + (z2 - z1)^2)
end

-- [[ Vulnerability Check ]]
local function is_vulnerable()
    for _, v in ipairs(entity.get_players(true)) do
        local flags = (entity.get_esp_data(v)).flags
        if bit.band(flags, bit.lshift(1, 11)) ~= 0 then
            return true
        end
    end
    return false
end

-- [[ Safe Head Function ]]
local function safe_func()
    ui.set(ref.yawjitter[1], "Off")
    ui.set(ref.yaw[1], '180')
    ui.set(ref.bodyyaw[1], "Static")
    ui.set(ref.bodyyaw[2], 1)
    ui.set(ref.yaw[2], 14)
    ui.set(ref.pitch[2], 89)
end

-- [[ Anti-Aim Setup ]]
local current_tickcount = 0
local to_jitter = false
local to_defensive = true
local first_execution = true
local yaw_amount = 0

local function defensive_peek()
    to_defensive = false
end

local function defensive_disabler()
    to_defensive = true
end

local function aa_setup(cmd)
    local lp = entity.get_local_player()
    if lp == nil then return end

    local state = player_state(cmd)
    if state == "Duck+Move" and antiaim_system[8].enable:get() then id = 8
    elseif state == "Duck" and antiaim_system[7].enable:get() then id = 7
    elseif state == "Air+Duck" and antiaim_system[6].enable:get() then id = 6
    elseif state == "Air" and antiaim_system[5].enable:get() then id = 5
    elseif state == "Running" and antiaim_system[4].enable:get() then id = 4
    elseif state == "Walking" and antiaim_system[3].enable:get() then id = 3
    elseif state == "Stand" and antiaim_system[2].enable:get() then id = 2
    else id = 1 end

    ui.set(ref.roll[1], 0)
    run_direction()

    if globals.tickcount() > current_tickcount + antiaim_system[id].yaw_delay:get() then
        if cmd.chokedcommands == 0 then
            to_jitter = not to_jitter
            current_tickcount = globals.tickcount()
        end
    elseif globals.tickcount() < current_tickcount then
        current_tickcount = globals.tickcount()
    end

    if is_vulnerable() then
        if first_execution then
            first_execution = false
            to_defensive = true
            client.set_event_callback("setup_command", defensive_disabler)
        end
        if globals.tickcount() % 10 == 9 then
            defensive_peek()
            client.unset_event_callback("setup_command", defensive_disabler)
        end
    else
        first_execution = true
        to_defensive = false
    end

    ui.set(ref.fsbodyyaw, false)
    ui.set(ref.pitch[1], "Custom")
    ui.set(ref.yawbase, lua_menu.antiaim.yaw_base:get())

    local selected_builder_def = antiaim_system[id].defensive:get() and antiaim_system[id].defensive_type:get() == "Custom" and is_defensive_active(lp)

    if selected_builder_def then
        ui.set(ref.yawjitter[1], antiaim_system[id].def_mod_type:get())
        ui.set(ref.yawjitter[2], antiaim_system[id].def_mod_dm:get())
        ui.set(ref.bodyyaw[1], antiaim_system[id].def_body_yaw_type:get())
        ui.set(ref.bodyyaw[2], antiaim_system[id].def_body_slider:get())
        yaw_amount = yaw_direction == 0 and antiaim_system[id].def_yaw_value:get() or yaw_direction
    else
        ui.set(ref.yawjitter[1], antiaim_system[id].mod_type:get())
        ui.set(ref.yawjitter[2], antiaim_system[id].mod_dm:get())
        if antiaim_system[id].yaw_type:get() == "Delayed" then
            ui.set(ref.bodyyaw[1], "Static")
            ui.set(ref.bodyyaw[2], to_jitter and 1 or -1)
        else
            ui.set(ref.bodyyaw[1], antiaim_system[id].body_yaw_type:get())
            ui.set(ref.bodyyaw[2], antiaim_system[id].body_slider:get())
        end
    end

    if is_defensive_active(lp) and antiaim_system[id].defensive:get() and antiaim_system[id].defensive_type:get() == "Default" and antiaim_system[id].defensive_yaw:get() == "Spin" then
        ui.set(ref.yaw[1], 'Spin')
    else
        ui.set(ref.yaw[1], '180')
    end

    cmd.force_defensive = antiaim_system[id].force_def:get() or antiaim_system[id].peek_def:get() and to_defensive

    local desync_type = entity.get_prop(lp, 'm_flPoseParameter', 11) * 120 - 60
    local desync_side = desync_type > 0

    if is_defensive_active(lp) and antiaim_system[id].defensive:get() and antiaim_system[id].defensive_type:get() == "Default" then
        if antiaim_system[id].defensive_yaw:get() == "Spin" then
            yaw_amount = antiaim_system[id].yaw_value:get()
        elseif antiaim_system[id].defensive_yaw:get() == "Cosmic" then
            yaw_amount = desync_side and 90 or -90
        elseif antiaim_system[id].defensive_yaw:get() == "Random" then
            yaw_amount = math.random(-180, 180)
        else
            yaw_amount = desync_side and randomize_value(antiaim_system[id].yaw_left:get(), antiaim_system[id].yaw_random:get()) or randomize_value(antiaim_system[id].yaw_right:get(), antiaim_system[id].yaw_random:get())
        end
    elseif not selected_builder_def then
        yaw_amount = desync_side and randomize_value(antiaim_system[id].yaw_left:get(), antiaim_system[id].yaw_random:get()) or randomize_value(antiaim_system[id].yaw_right:get(), antiaim_system[id].yaw_random:get())
        ui.set(ref.pitch[2], 89)
    end

    if is_defensive_active(lp) and antiaim_system[id].defensive:get() then
        if antiaim_system[id].defensive_pitch:get() == "Custom" then
            ui.set(ref.pitch[2], antiaim_system[id].pitch_value:get())
        elseif antiaim_system[id].defensive_pitch:get() == "Cosmic" then
            ui.set(ref.pitch[2], desync_side and 49 or -49)
        elseif antiaim_system[id].defensive_pitch:get() == "Random" then
            ui.set(ref.pitch[2], math.random(-89, 89))
        else
            ui.set(ref.pitch[2], 89)
        end
    end

    ui.set(ref.yaw[2], yaw_direction == 0 and yaw_amount or yaw_direction)

    local players = entity.get_players(true)
    if lua_menu.antiaim.addons:get("Warmup Protection") then
        if entity.get_prop(entity.get_game_rules(), "m_bWarmupPeriod") == 1 then
            ui.set(ref.yaw[2], math.random(-180, 180))
            ui.set(ref.yawjitter[2], math.random(-180, 180))
            ui.set(ref.bodyyaw[2], math.random(-180, 180))
            ui.set(ref.pitch[1], "Custom")
            ui.set(ref.pitch[2], math.random(-89, 89))
        end
    end

    local threat = client.current_threat()
    local lp_weapon = entity.get_player_weapon(lp)
    local lp_orig_x, lp_orig_y, lp_orig_z = entity.get_prop(lp, "m_vecOrigin")
    local flags = entity.get_prop(lp, 'm_fFlags')
    local jumpcheck = bit.band(flags, 1) == 0 or cmd.in_jump == 1
    local ducked = entity.get_prop(lp, 'm_flDuckAmount') > 0.7

    if lua_menu.antiaim.addons:get("Head Safety") then
        if lp_weapon ~= nil then
            if lua_menu.antiaim.safe_head:get("Air+Duck Knife") then
                if jumpcheck and ducked and entity.get_classname(lp_weapon) == "CKnife" then
                    safe_func()
                end
            end
            if lua_menu.antiaim.safe_head:get("Air+Duck Zeus") then
                if jumpcheck and ducked and entity.get_classname(lp_weapon) == "CWeaponTaser" then
                    safe_func()
                end
            end
            if lua_menu.antiaim.safe_head:get("Long Range") then
                if threat ~= nil then
                    local threat_x, threat_y, threat_z = entity.get_prop(threat, "m_vecOrigin")
                    local threat_dist = anti_knife_dist(lp_orig_x, lp_orig_y, lp_orig_z, threat_x, threat_y, threat_z)
                    if threat_dist > 900 then
                        safe_func()
                    end
                end
            end
        end
    end

    if lua_menu.antiaim.addons:get("Knife Defense") then
        for i = 1, #players do
            if players == nil then return end
            local enemy_orig_x, enemy_orig_y, enemy_orig_z = entity.get_prop(players[i], "m_vecOrigin")
            local distance_to = anti_knife_dist(lp_orig_x, lp_orig_y, lp_orig_z, enemy_orig_x, enemy_orig_y, enemy_orig_z)
            local weapon = entity.get_player_weapon(players[i])
            if weapon == nil then return end
            if entity.get_classname(weapon) == "CKnife" and distance_to <= 250 then
                ui.set(ref.yaw[2], 180)
                ui.set(ref.yawbase, "At targets")
            end
        end
    end
end
-- [[ Bullet Impact Handler ]]
local lastmiss = 0
local function GetClosestPoint(A, B, P)
    local a_to_p = { P[1] - A[1], P[2] - A[2] }
    local a_to_b = { B[1] - A[1], B[2] - A[2] }
    local atb2 = a_to_b[1]^2 + a_to_b[2]^2
    local atp_dot_atb = a_to_p[1]*a_to_b[1] + a_to_p[2]*a_to_b[2]
    local t = atp_dot_atb / atb2
    return { A[1] + a_to_b[1]*t, A[2] + a_to_b[2]*t }
end

client.set_event_callback("bullet_impact", function(e)
    if not entity.is_alive(entity.get_local_player()) then return end
    local ent = client.userid_to_entindex(e.userid)
    if ent ~= client.current_threat() then return end
    if entity.is_dormant(ent) or not entity.is_enemy(ent) then return end

    local ent_origin = { entity.get_prop(ent, "m_vecOrigin") }
    ent_origin[3] = ent_origin[3] + entity.get_prop(ent, "m_vecViewOffset[2]")
    local local_head = { entity.hitbox_position(entity.get_local_player(), 0) }
    local closest = GetClosestPoint(ent_origin, { e.x, e.y, e.z }, local_head)
    local delta = { local_head[1]-closest[1], local_head[2]-closest[2] }
    local delta_2d = math.sqrt(delta[1]^2 + delta[2]^2)
    if math.abs(delta_2d) <= 60 and globals.curtime() - lastmiss > 0.015 then
        lastmiss = globals.curtime()
        if lua_menu.misc.log_type:get("Screen") then
            renderer.log(entity.get_player_name(ent).." Fired at You")
        end
    end
end)

-- [[ Animation Breaker ]]
local function anim_breaker()
    local lp = entity.get_local_player()
    if not lp or not entity.is_alive(lp) then return end

    local self_index = c_entity.new(lp)
    local self_anim_state = self_index:get_anim_state()
    if not self_anim_state then return end

    local self_anim_overlay = self_index:get_anim_overlay(12) -- Слой анимации для ног
    if not self_anim_overlay then return end

    local ground_anim = lua_menu.misc.animation_ground:get()
    local air_anim = lua_menu.misc.animation_air:get()
    local flags = entity.get_prop(lp, "m_fFlags")
    local on_ground = bit.band(flags, 1) == 1

    -- Управление весом анимации для плавности
    local x_velocity = entity.get_prop(lp, "m_vecVelocity[0]")
    self_anim_overlay.weight = math.abs(x_velocity) >= 3 and 1 or 0

    -- Ground Animation
    if on_ground then
        if ground_anim == "Static" then
            entity.set_prop(lp, "m_flPoseParameter", lua_menu.misc.animation_value:get()/10, 0)
        elseif ground_anim == "Pulse" then
            entity.set_prop(lp, "m_flPoseParameter", globals.tickcount() % 4 > 1 and lua_menu.misc.animation_value:get()/10 or 0, 0)
        elseif ground_anim == "Random" then
            entity.set_prop(lp, "m_flPoseParameter", math.random(lua_menu.misc.animation_value:get(), 10)/10, 0)
        elseif ground_anim == "Walk Static" then
            -- Имитация ходьбы на земле
            entity.set_prop(lp, "m_flPoseParameter", 0.5, 1) -- Поза ходьбы (ноги)
            entity.set_prop(lp, "m_flCycle", 0.5, 12) -- Постоянный цикл шага
        elseif ground_anim == "Walk Pulse" then
            -- Пульсирующая ходьба на земле
            entity.set_prop(lp, "m_flPoseParameter", 0.5, 1)
            entity.set_prop(lp, "m_flCycle", math.sin(globals.curtime() * 2) * 0.5 + 0.5, 12)
        end
    elseif not on_ground then
        if air_anim == "Static" then
            entity.set_prop(lp, "m_flPoseParameter", 1, 1)
        elseif air_anim == "Random" then
            entity.set_prop(lp, "m_flPoseParameter", math.random(0, 10)/10, 1)
        elseif air_anim == "Walk Static" then
            -- Имитация ходьбы в воздухе
            entity.set_prop(lp, "m_flPoseParameter", 0.5, 1)
            entity.set_prop(lp, "m_flCycle", 0.5, 12)
        elseif air_anim == "Walk Pulse" then
            -- Пульсирующая ходьба в воздухе
            entity.set_prop(lp, "m_flPoseParameter", 0.5, 1)
            entity.set_prop(lp, "m_flCycle", math.sin(globals.curtime() * 2) * 0.5 + 0.5, 12)
        end
    end
end

-- [[ Auto Teleport ]]
local function auto_tp(cmd)
    local lp = entity.get_local_player()
    if lp == nil then return end
    local flags = entity.get_prop(lp, 'm_fFlags')
    local jumpcheck = bit.band(flags, 1) == 0
    if is_vulnerable() and jumpcheck then
        cmd.force_defensive = true
        cmd.discharge_pending = true
    end
end

-- [[ Ragebot Logs ]]
local logs = {}
local function ragebot_logs()
    local offset, x, y = 0, screen[1] / 2, screen[2] / 1.4
    for idx, data in ipairs(logs) do
        if (((globals.curtime()/2) * 2.0) - data[3]) < 4.0 and not (#logs > 5 and idx < #logs - 5) then
            data[2] = lerp(data[2], 255, globals.frametime() * 10)
        else
            data[2] = lerp(data[2], 0, globals.frametime() * 10)
        end
        offset = offset - 40 * (data[2] / 255)

        local text_size_x, text_size_y = renderer.measure_text("", data[1])
        if lua_menu.misc.screen_type:get() == "Cosmic" then
            renderer.rectangle(x - 7 - text_size_x / 2, y - offset - 8, text_size_x + 13, 26, 10, 20, 40, (data[2] / 255) * 150)
            renderer.gradient(x - 7 - text_size_x / 2, y - offset - 8, text_size_x + 13, 26, 30, 144, 255, (data[2] / 255) * 100, 135, 206, 235, (data[2] / 255) * 100, true)
            renderer.text(x - 1 - text_size_x / 2, y - offset, 255, 255, 255, data[2], "c", 0, data[1])
        else
            renderer.rectangle(x - 7 - text_size_x / 2, y - offset - 5, text_size_x + 13, 20, 20, 30, 50, (data[2] / 255) * 200)
            renderer.text(x - 1 - text_size_x / 2, y - offset, 135, 206, 235, data[2], "c", 0, data[1])
        end
        if data[2] < 0.1 or not entity.get_local_player() then table.remove(logs, idx) end
    end
end

renderer.log = function(text)
    table.insert(logs, { text, 0, ((globals.curtime() / 2) * 2.0)})
end

local hitgroup_names = {'generic', 'head', 'chest', 'stomach', 'left arm', 'right arm', 'left leg', 'right leg', 'neck', '?', 'gear'}

local function aim_hit(e)
    if not lua_menu.misc.log:get() then return end
    local group = hitgroup_names[e.hitgroup + 1] or '?'
    if lua_menu.misc.log_type:get("Screen") then
        renderer.log(string.format('Hit %s in %s for %d dmg', entity.get_player_name(e.target), group, e.damage))
    end
    if lua_menu.misc.log_type:get("Console") then
        print(string.format('Hit %s in %s for %d damage', entity.get_player_name(e.target), group, e.damage))
    end
end

local function aim_miss(e)
    if not lua_menu.misc.log:get() then return end
    local group = hitgroup_names[e.hitgroup + 1] or '?'
    if lua_menu.misc.log_type:get("Screen") then
        renderer.log(string.format('Missed %s in %s due to %s', entity.get_player_name(e.target), group, e.reason))
    end
    if lua_menu.misc.log_type:get("Console") then
        print(string.format('Missed %s in %s due to %s', entity.get_player_name(e.target), group, e.reason))
    end
end

client.set_event_callback('aim_hit', aim_hit)
client.set_event_callback('aim_miss', aim_miss)

local function doubletap_charged()
    if not ui.get(ref.dt[1]) or not ui.get(ref.dt[2]) or ui.get(ref.fakeduck) then return false end
    local lp = entity.get_local_player()
    if not entity.is_alive(lp) or lp == nil then return end
    local weapon = entity.get_prop(lp, "m_hActiveWeapon")
    if weapon == nil then return false end
    local next_attack = entity.get_prop(lp, "m_flNextAttack") + 0.01
    local check = entity.get_prop(weapon, "m_flNextPrimaryAttack")
    if check == nil then return end
    local next_primary_attack = check + 0.01
    return next_attack - globals.curtime() < 0 and next_primary_attack - globals.curtime() < 0
end

-- [[ Visual Indicators ]]
local scoped_space = 0
local main_font = "c-b"
local key_font = "c"

local function screen_indicator()
    local lp = entity.get_local_player()
    if lp == nil then return end
    local ind_size = renderer.measure_text("cb", "Nebula Overlord")
    local scpd = entity.get_prop(lp, "m_bIsScoped") == 1
    scoped_space = lerp(scoped_space, scpd and 50 or 0, globals.frametime() * 20)
    local condition = "global"
    if id == 1 then condition = "global"
    elseif id == 2 then condition = "stand"
    elseif id == 3 then condition = "walk"
    elseif id == 4 then condition = "run"
    elseif id == 5 then condition = "air"
    elseif id == 6 then condition = "air+duck"
    elseif id == 7 then condition = "duck"
    elseif id == 8 then condition = "duck+move" end
    local spaceind = 10

    if lua_menu.misc.cross_ind_type:get() == "Cosmic" then
        main_font, key_font = "c-b", "c"
    elseif lua_menu.misc.cross_ind_type:get() == "Minimal" then
        main_font, key_font = "c", "c"
    elseif lua_menu.misc.cross_ind_type:get() == "Orbit" then
        main_font, key_font = "c-b", "c-b"
    else
        main_font, key_font = "c-d", "c-d" -- Nebula style
    end

    local new_check = lua_menu.misc.cross_ind_type:get() == "Cosmic"
    lua_menu.misc.cross_color:override(true)
    lua_menu.misc.key_color:override(true)
    local r1, g1, b1, a1 = lua_menu.misc.cross_ind:get_color()
    local r2, g2, b2, a2 = lua_menu.misc.cross_color:get_color()
    local r3, g3, b3, a3 = lua_menu.misc.key_color:get_color()

    if new_check then
        renderer.gradient(center[1] - ind_size / 2 + scoped_space, center[2] + 25, ind_size, 20, 30, 144, 255, 150, 135, 206, 235, 150, true)
    end

    text_fade_animation(center[1] + scoped_space, center[2] + 30, -2, {r=r1, g=g1, b=b1, a=255}, {r=r2, g=g2, b=b2, a=255}, new_check and "NEBULA" or "nebula", main_font)
    renderer.text(center[1] + scoped_space, center[2] + 40, r2, g2, b2, 255, main_font, 0, condition)

    if ui.get(ref.forcebaim) then
        renderer.text(center[1] + scoped_space, center[2] + 40 + spaceind, r3, g3, b3, 255, key_font, 0, new_check and "BAIM" or "baim")
        spaceind = spaceind + 10
    end
    if ui.get(ref.os[2]) then
        renderer.text(center[1] + scoped_space, center[2] + 40 + spaceind, r3, g3, b3, 255, key_font, 0, new_check and "OSAA" or "osaa")
        spaceind = spaceind + 10
    end
    if ui.get(ref.minimum_damage_override[2]) then
        renderer.text(center[1] + scoped_space, center[2] + 40 + spaceind, r3, g3, b3, 255, key_font, 0, new_check and "DMG" or "dmg")
        spaceind = spaceind + 10
    end
    if ui.get(ref.dt[1]) and ui.get(ref.dt[2]) then
        renderer.text(center[1] + scoped_space, center[2] + 40 + spaceind, doubletap_charged() and r3 or 255, doubletap_charged() and g3 or 0, doubletap_charged() and b3 or 0, 255, key_font, 0, new_check and "DT" or "dt")
        spaceind = spaceind + 10
    end
    if ui.get(ref.freestand[1]) and ui.get(ref.freestand[2]) then
        renderer.text(center[1] + scoped_space, center[2] + 40 + spaceind, r3, g3, b3, 255, key_font, 0, new_check and "FS" or "fs")
    end
end

-- [[ Bullet Tracers Logic ]]
local bullet_tracers = {}
local function add_bullet_tracer(e)
    if not lua_menu.visuals.bullet_tracers:get() then return end
    local shooter = client.userid_to_entindex(e.userid)
    if not entity.is_alive(shooter) then return end

    local start_x, start_y, start_z = entity.get_prop(shooter, "m_vecOrigin")
    start_z = start_z + entity.get_prop(shooter, "m_vecViewOffset[2]")
    local end_x, end_y, end_z = e.x, e.y, e.z

    table.insert(bullet_tracers, {
        start_x = start_x,
        start_y = start_y,
        start_z = start_z,
        end_x = end_x,
        end_y = end_y,
        end_z = end_z,
        time = globals.curtime(),
        alpha = 255
    })
end

local function draw_bullet_tracers()
    if not lua_menu.visuals.bullet_tracers:get() then
        bullet_tracers = {}
        return
    end

    local r, g, b, a = lua_menu.visuals.bullet_tracers_color:get()
    local animation_type = lua_menu.visuals.bullet_tracers_animation:get()
    local lifetime = lua_menu.visuals.bullet_tracers_lifetime:get()

    for i, tracer in ipairs(bullet_tracers) do
        local elapsed = globals.curtime() - tracer.time
        if elapsed > lifetime then
            table.remove(bullet_tracers, i)
        else
            local start_x, start_y = renderer.world_to_screen(tracer.start_x, tracer.start_y, tracer.start_z)
            local end_x, end_y = renderer.world_to_screen(tracer.end_x, tracer.end_y, tracer.end_z)

            if start_x and start_y and end_x and end_y then
                local alpha = tracer.alpha
                if animation_type == "Fade" then
                    alpha = lerp(tracer.alpha, 0, elapsed / lifetime)
                elseif animation_type == "Pulse" then
                    alpha = 255 * math.abs(math.sin(globals.curtime() * 5))
                elseif animation_type == "Static" then
                    alpha = 255
                elseif animation_type == "Stars" then
                    local dx = end_x - start_x
                    local dy = end_y - start_y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    local step = 20
                    local num_stars = math.floor(dist / step)
                    alpha = lerp(tracer.alpha, 0, elapsed / lifetime)
                    for j = 0, num_stars do
                        local t = j / num_stars
                        local star_x = start_x + dx * t
                        local star_y = start_y + dy * t
                        renderer.text(star_x, star_y, r, g, b, alpha, "c", 0, "*")
                    end
                end

                if animation_type ~= "Stars" then
                    renderer.line(start_x, start_y, end_x, end_y, r, g, b, alpha)
                end
                tracer.alpha = alpha
            end
        end
    end
end

client.set_event_callback("bullet_impact", add_bullet_tracer)
local defensive_alpha = 0
local defensive_amount = 0
local velocity_alpha = 0
local velocity_amount = 0

local function velocity_ind()
    local lp = entity.get_local_player()
    if lp == nil then return end
    local r, g, b, a = lua_menu.misc.velocity_window:get_color()
    local vel_mod = entity.get_prop(lp, 'm_flVelocityModifier')
    if not ui.is_menu_open() then
        velocity_alpha = lerp(velocity_alpha, vel_mod < 1 and 255 or 0, globals.frametime() * 10)
        velocity_amount = lerp(velocity_amount, vel_mod, globals.frametime() * 10)
    else
        velocity_alpha = lerp(velocity_alpha, 255, globals.frametime() * 10)
        velocity_amount = globals.tickcount() % 50 / 100 * 2
    end

    renderer.text(center[1], screen[2] / 3 - 10, 255, 255, 255, velocity_alpha, "c", 0, "Velocity")
    if lua_menu.misc.velocity_style:get() == "Gradient" then
        renderer.gradient(center[1] - 50 * velocity_amount, screen[2] / 3, 50 * velocity_amount, 4, r, g, b, velocity_alpha / 3, r, g, b, velocity_alpha, true)
        renderer.gradient(center[1], screen[2] / 3, 50 * velocity_amount, 4, r, g, b, velocity_alpha, r, g, b, velocity_alpha / 3, true)
    else
        renderer.rectangle(center[1] - 50, screen[2] / 3, 100, 4, 10, 20, 40, velocity_alpha)
        renderer.rectangle(center[1] - 50, screen[2] / 3, 100 * velocity_amount, 4, r, g, b, velocity_alpha)
    end
end

local function defensive_ind()
    local lp = entity.get_local_player()
    if lp == nil then return end
    local charged = doubletap_charged()
    local active = is_defensive_active(lp)
    local r, g, b, a = lua_menu.misc.defensive_window:get_color()
    if not ui.is_menu_open() then
        if ui.get(ref.dt[1]) and ui.get(ref.dt[2]) and not ui.get(ref.fakeduck) then
            if charged and active then
                defensive_alpha = lerp(defensive_alpha, 255, globals.frametime() * 10)
                defensive_amount = lerp(defensive_amount, 1, globals.frametime() * 10)
            elseif charged and not active then
                defensive_alpha = lerp(defensive_alpha, 0, globals.frametime() * 10)
                defensive_amount = lerp(defensive_amount, 0.5, globals.frametime() * 10)
            else
                defensive_alpha = lerp(defensive_alpha, 255, globals.frametime() * 10)
                defensive_amount = lerp(defensive_amount, 0, globals.frametime() * 10)
            end
        else
            defensive_alpha = lerp(defensive_alpha, 0, globals.frametime() * 10)
            defensive_amount = lerp(defensive_amount, 0, globals.frametime() * 10)
        end
    else
        defensive_alpha = lerp(defensive_alpha, 255, globals.frametime() * 10)
        defensive_amount = globals.tickcount() % 50 / 100 * 2
    end

    renderer.text(center[1], screen[2] / 4 - 10, 255, 255, 255, defensive_alpha, "c", 0, "Defensive")
    if lua_menu.misc.defensive_style:get() == "Gradient" then
        renderer.gradient(center[1] - 50 * defensive_amount, screen[2] / 4, 50 * defensive_amount, 4, r, g, b, defensive_alpha / 3, r, g, b, defensive_alpha, true)
        renderer.gradient(center[1], screen[2] / 4, 50 * defensive_amount, 4, r, g, b, defensive_alpha, r, g, b, defensive_alpha / 3, true)
    else
        renderer.rectangle(center[1] - 50, screen[2] / 4, 100, 4, 10, 20, 40, defensive_alpha)
        renderer.rectangle(center[1] - 50, screen[2] / 4, 100 * defensive_amount, 4, r, g, b, defensive_alpha)
    end
end

local function info_panel()
    local lp = entity.get_local_player()
    if lp == nil then return end
    local condition = id == 1 and "global" or id == 2 and "stand" or id == 3 and "walk" or id == 4 and "run" or id == 5 and "air" or id == 6 and "air+duck" or id == 7 and "duck" or "duck+move"
    local threat = client.current_threat()
    local name = threat and entity.get_player_name(threat):sub(1, 12) or "nil"
    local threat_desync = threat and math.floor(entity.get_prop(threat, 'm_flPoseParameter', 11) * 120 - 60) or 0
    local desync_amount = math.floor(entity.get_prop(lp, 'm_flPoseParameter', 11) * 120 - 60)

    local textsize = renderer.measure_text("d", "Nebula Overlord")
    renderer.gradient(20, center[2], textsize / 2, 2, 30, 144, 255, 255, 135, 206, 235, 255, true)
    renderer.gradient(20 + textsize / 2, center[2], textsize / 2, 2, 135, 206, 235, 255, 30, 144, 255, 255, true)
    text_fade_animation(20, center[2] - 5, -1.5, {r=135, g=206, b=235, a=255}, {r=30, g=144, b=255, a=255}, "NEBULA", "d")
    renderer.text(20, center[2] + 10, 255, 255, 255, 255, "d", 0, "State: " .. condition .. " " .. math.abs(desync_amount) .. "°")
    renderer.text(20, center[2] + 20, 255, 255, 255, 255, "d", 0, "Target: " .. string.lower(name) .. " " .. math.abs(threat_desync) .. "°")
    if lua_menu.misc.resolver:get() then
        renderer.text(20, center[2] + 30, 255, 255, 255, 255, "d", 0, "Resolver: " .. string.lower(lua_menu.misc.resolver_type:get()))
    end
end

-- [[ Exploits ]]
local function unlimited_backtrack_exploit(cmd)
    if not lua_menu.exploits.exploits_enabled:get() or not lua_menu.exploits.unlimited_bt:get() or not lua_menu.exploits.unlimited_bt_key:get() then return end
    local lp = entity.get_local_player()
    if lp and entity.is_alive(lp) then
        local bt_ticks = lua_menu.exploits.unlimited_bt_ticks:get()
        local choke_amount = math.min(lua_menu.exploits.unlimited_bt_choke:get(), 12)
        local use_priority = lua_menu.exploits.unlimited_bt_priority:get()

        for i, enemy in ipairs(entity.get_players(true)) do
            plist.set(enemy, "Override backtrack", true)
            plist.set(enemy, "Override backtrack ticks", bt_ticks)
            plist.set(enemy, "High priority", use_priority)
        end

        if globals.chokedcommands() < choke_amount and math.random(0, 1) == 0 then
            cmd.allow_send_packet = false
        else
            cmd.allow_send_packet = true
        end
    end
end

local function phantom_reload_exploit(cmd)
    if not lua_menu.exploits.exploits_enabled:get() or not lua_menu.exploits.phantom_reload:get() or not lua_menu.exploits.phantom_reload_key:get() then return end
    local lp = entity.get_local_player()
    if lp and entity.is_alive(lp) then
        local weapon = entity.get_player_weapon(lp)
        if weapon and cmd.in_reload == 0 then
            local interval = lua_menu.exploits.phantom_reload_interval:get()
            if globals.tickcount() % interval == 0 then
                client.exec("reload")
                cmd.allow_send_packet = false
            else
                cmd.allow_send_packet = true
            end
        end
    end
end

-- [[ AI Peek Exploit (полностью скопировано из CloniuSense) ]]
local function includes(table, key)
    for i=1, #table do
        if table[i] == key then
            return true
        end
    end
    return false
end

local function extrapolate(player, ticks, x, y, z)
    local xv, yv, zv = entity.get_prop(player, "m_vecVelocity")
    local new_x = x + globals.tickinterval() * xv * ticks
    local new_y = y + globals.tickinterval() * yv * ticks
    local new_z = z + globals.tickinterval() * zv * ticks
    return new_x, new_y, new_z
end

local function is_in_air(player)
    return bit.band(entity.get_prop(player, "m_fFlags"), 1) == 0
end

local r, g, b, a = 255, 255, 255, 255
local my_old_view = vector(0, 0, 0)
local my_old_vec = vector(0, 0, 0)

local function init_old()
    local me = entity.get_local_player()
    if me == nil then
        return
    end
    local pitch, yaw = client.camera_angles()
    my_old_view = vector(pitch, yaw, 0)
    local x, y, z = entity.hitbox_position(me, 3)
    my_old_vec = vector(x, y, z)
end

local IS_WORKING = false
local WORKING_VEC = my_old_vec

local function vector_angles(x1, y1, z1, x2, y2, z2)
    local origin_x, origin_y, origin_z
    local target_x, target_y, target_z
    if x2 == nil then
        target_x, target_y, target_z = x1, y1, z1
        origin_x, origin_y, origin_z = client.eye_position()
        if origin_x == nil then
            return
        end
    else
        origin_x, origin_y, origin_z = x1, y1, z1
        target_x, target_y, target_z = x2, y2, z2
    end

    local delta_x, delta_y, delta_z = target_x - origin_x, target_y - origin_y, target_z - origin_z
    if delta_x == 0 and delta_y == 0 then
        return (delta_z > 0 and 270 or 90), 0
    else
        local yaw = math.deg(math.atan2(delta_y, delta_x))
        local hyp = math.sqrt(delta_x * delta_x + delta_y * delta_y)
        local pitch = math.deg(math.atan2(-delta_z, hyp))
        return pitch, yaw
    end
end

local function get_view_point(radius, v, vec)
    local me = entity.get_local_player()
    local eye_pos = vec
    local viewangle = my_old_view
    local a_vec = eye_pos + vector(0, 0, 0):init_from_angles(0, (90 + viewangle.y + radius), 0) * v
    return a_vec
end

local function get_predict_point(radius, segament, vec)
    local points = {}
    local me = entity.get_local_player()
    local my_vec = vec
    segament = math.max(2, math.floor(segament))
    local angles_pre_point = 360 / segament
    for i = 0, 360, angles_pre_point do
        local m_p = get_view_point(i, radius, my_vec)
        table.insert(points, m_p)
    end
    return points
end

local function get_depart_point(vec, my_vec, department, limit_vec)
    local vec_1 = vector(vec.x, vec.y, 0)
    local vec_2 = vector(my_vec.x, my_vec.y, 0)
    local vec_3 = vector(limit_vec.x, limit_vec.y, 0)

    local each_plus = (vec_1 - vec_2) / department
    local limit_vec_cal = (vec_3 - vec_2):length()

    local points = {}

    for i = 1, department do
        local add_vec = each_plus * i
        if add_vec:length() < limit_vec_cal then
            table.insert(points, my_vec + add_vec)
        end
    end

    return points
end

local function endpos(origin, dest)
    local local_player = entity.get_local_player()
    local tr = trace.line(origin, dest, { skip = local_player })
    local endpos = tr.end_pos
    return endpos, tr.fraction
end

local function draw_circle_3d(x, y, z, radius, r, g, b, a, accuracy, width, outline, start_degrees, percentage, fill_r, fill_g, fill_b, fill_a)
    local accuracy = accuracy ~= nil and accuracy or 3
    local width = width ~= nil and width or 1
    local outline = outline ~= nil and outline or false
    local start_degrees = start_degrees ~= nil and start_degrees or 0
    local percentage = percentage ~= nil and percentage or 1

    local center_x, center_y
    if fill_a then
        center_x, center_y = renderer.world_to_screen(x, y, z)
    end

    local screen_x_line_old, screen_y_line_old
    for rot = start_degrees, percentage * 360, accuracy do
        local rot_temp = math.rad(rot)
        local lineX, lineY, lineZ = radius * math.cos(rot_temp) + x, radius * math.sin(rot_temp) + y, z
        local screen_x_line, screen_y_line = renderer.world_to_screen(lineX, lineY, lineZ)
        if screen_x_line ~= nil and screen_x_line_old ~= nil then
            if fill_a and center_x ~= nil then
                renderer.triangle(screen_x_line, screen_y_line, screen_x_line_old, screen_y_line_old, center_x, center_y, fill_r, fill_g, fill_b, fill_a)
            end
            for i = 1, width do
                local i = i - 1
                renderer.line(screen_x_line, screen_y_line - i, screen_x_line_old, screen_y_line_old - i, r, g, b, a)
                renderer.line(screen_x_line - 1, screen_y_line, screen_x_line_old - i, screen_y_line_old, r, g, b, a)
            end
            if outline then
                local outline_a = a / 255 * 160
                renderer.line(screen_x_line, screen_y_line - width, screen_x_line_old, screen_y_line_old - width, 16, 16, 16, outline_a)
                renderer.line(screen_x_line, screen_y_line + 1, screen_x_line_old, screen_y_line_old + 1, 16, 16, 16, outline_a)
            end
        end
        screen_x_line_old, screen_y_line_old = screen_x_line, screen_y_line
    end
end

local function calculate_end_pos(draw_line, draw_circle, debug_fraction, vec, my_vec)
    local me = entity.get_local_player()
    local dx, dy, dz = entity.get_origin(me)
    local debug_vec = vector(my_vec.x, my_vec.y, dz + 5)
    local debug_vec_2 = vector(vec.x, vec.y, dz + 5)
    local pos_1, fraction_1 = endpos(my_vec, vec)
    local pos_2, fraction_2 = endpos(debug_vec, debug_vec_2)

    local end_Pos = vector(pos_2.x, pos_2.y, vec.z)

    if draw_line then
        local x1, y1 = renderer.world_to_screen(pos_2.x, pos_2.y, pos_2.z)
        local x2, y2 = renderer.world_to_screen(debug_vec.x, debug_vec.y, debug_vec.z)
        renderer.line(x1, y1, x2, y2, r, g, b, a)
    end

    if debug_fraction then
        local debug_text = tostring(math.floor(fraction_1) * 100)
        local x3, y3 = renderer.world_to_screen(debug_vec_2.x, debug_vec_2.y, debug_vec_2.z)
        renderer.text(x3, y3, r, g, b, a, 'c', 0, debug_text)
    end

    return end_Pos
end

local function calculate_real_point(draw_line, draw_circle, debug_fraction, vec)
    local points_list = {}
    local me = entity.get_local_player()
    local my_vec = vec
    local points = get_predict_point(lua_menu.exploits.ai_peek_radius:get(), lua_menu.exploits.ai_peek_segament:get(), my_vec)

    for i, o in pairs(points) do
        if lua_menu.exploits.ai_peek_middle:get() then
            local halfone = points[i + 1]
            halfone = halfone == nil and points[1] or halfone
            local halfpoint = vector((halfone.x + o.x) / 2, (halfone.y + o.y) / 2, o.z)
            local end_pos = calculate_end_pos(draw_line, draw_circle, debug_fraction, halfpoint, my_vec)
            table.insert(points_list, {
                endpos = end_pos,
                ideal = halfpoint
            })
        end
        local end_pos = calculate_end_pos(draw_line, draw_circle, debug_fraction, o, my_vec)
        table.insert(points_list, {
            endpos = end_pos,
            ideal = o
        })
    end

    return points_list
end

local function run_all_Point(debug_line, debug_cir, debug_fraction, department, vec)
    local me = entity.get_local_player()
    local m_points = calculate_real_point(debug_line, debug_cir, debug_fraction, vec)
    local dx, dy, dz = entity.get_origin(me)
    local points = {}
    for i, o in pairs(m_points) do
        local calculate_vec = o.ideal
        local limit_vec = o.endpos
        table.insert(points, limit_vec)
        if debug_cir then
            draw_circle_3d(limit_vec.x, limit_vec.y, dz + 5, 5, r, g, b, a)
        end

        if department ~= 1 then
            for _, depart_vec in pairs(get_depart_point(calculate_vec, vec, department, limit_vec)) do
                table.insert(points, depart_vec)
                if debug_cir then
                    draw_circle_3d(depart_vec.x, depart_vec.y, dz + 5, 5, r, g, b, a)
                end
            end
        end
    end

    return points
end

local function get_peek_hitbox(content)
    local hitbox = {}
    if includes(content, 'Head') then
        table.insert(hitbox, 0)
    end

    if includes(content, 'Neck') then
        table.insert(hitbox, 1)
    end

    if includes(content, 'Chest') then
        table.insert(hitbox, 4)
        table.insert(hitbox, 5)
        table.insert(hitbox, 6)
    end

    if includes(content, 'Stomach') then
        table.insert(hitbox, 2)
        table.insert(hitbox, 3)
    end

    if includes(content, 'Arms') then
        table.insert(hitbox, 13)
        table.insert(hitbox, 14)
        table.insert(hitbox, 15)
        table.insert(hitbox, 16)
        table.insert(hitbox, 17)
        table.insert(hitbox, 18)
    end

    if includes(content, 'Legs') then
        table.insert(hitbox, 7)
        table.insert(hitbox, 8)
        table.insert(hitbox, 9)
        table.insert(hitbox, 10)
    end

    if includes(content, 'Feet') then
        table.insert(hitbox, 11)
        table.insert(hitbox, 12)
    end

    return hitbox
end

local function using_auto_peek()
    return (ui.get(ref.quick_peek_assist[1]) and ui.get(ref.quick_peek_assist[2]))
end

local function ai_peek_runner()
    if not lua_menu.exploits.exploits_enabled:get() or not lua_menu.exploits.ai_peek:get() then return end

    local predict_tick = lua_menu.exploits.ai_peek_tick:get()
    local me = entity.get_local_player()
    if me == nil then return end

    if not entity.is_alive(me) then
        return
    end

    if not lua_menu.exploits.ai_peek_key:get() then
        return
    end

    local m_x, m_y, m_z = entity.hitbox_position(me, 3)
    local my_vec = vector(m_x, m_y, m_z)

    local mpitch, myaw = client.camera_angles()

    local debugger = lua_menu.exploits.ai_peek_debugger:get()
    local m_points = run_all_Point(
        includes(debugger, 'Line player-predict'),
        includes(debugger, 'Base'),
        includes(debugger, 'Fraction detection'),
        lua_menu.exploits.ai_peek_depart:get(),
        my_old_vec
    )
    local sort_type = lua_menu.exploits.ai_peek_mode:get()
    local p_Hitbox = get_peek_hitbox(lua_menu.exploits.ai_peek_hitbox:get())
    local p_List = {}
    if not (lua_menu.exploits.ai_peek_target:get() == 'Current') then
        local players = entity.get_players(true)
        if #players == 0 then
            WORKING_VEC = nil
            IS_WORKING = false
            return
        end
        for i, o in pairs(m_points) do
            for _, player in pairs(players) do
                local best_target = player
                for _, v in pairs(p_Hitbox) do
                    local ex, ey, ez = entity.hitbox_position(best_target, v)
                    local new_x, new_y, new_z = extrapolate(best_target, predict_tick, ex, ey, ez)
                    local e_vec = vector(new_x, new_y, new_z)
                    local _, dmg = client.trace_bullet(me, o.x, o.y, o.z, e_vec.x, e_vec.y, e_vec.z)
                    if dmg >= math.min(ui.get(ref.minimum_damage), entity.get_prop(best_target, 'm_iHealth')) then
                        table.insert(p_List, {
                            TARGET = best_target,
                            damage = dmg,
                            vec = o,
                            enemy_vec = e_vec
                        })
                    end
                end
            end

            if lua_menu.exploits.ai_peek_limit:get() and #p_List >= lua_menu.exploits.ai_peek_limit_num:get() then
                break
            end
        end
    else
        local best_target = client.current_threat()
        if best_target == nil then
            WORKING_VEC = nil
            IS_WORKING = false
            return
        end
        for i, o in pairs(m_points) do
            for k, v in pairs(p_Hitbox) do
                local ex, ey, ez = entity.hitbox_position(best_target, v)
                local new_x, new_y, new_z = extrapolate(best_target, predict_tick, ex, ey, ez)
                local e_vec = vector(new_x, new_y, new_z)
                local _, dmg = client.trace_bullet(me, o.x, o.y, o.z, e_vec.x, e_vec.y, e_vec.z)
                if dmg > math.min(ui.get(ref.minimum_damage), entity.get_prop(best_target, 'm_iHealth')) then
                    table.insert(p_List, {
                        TARGET = best_target,
                        damage = dmg,
                        vec = o,
                        enemy_vec = e_vec
                    })
                end
            end

            if lua_menu.exploits.ai_peek_limit:get() and #p_List >= lua_menu.exploits.ai_peek_limit_num:get() then
                break
            end
        end
    end

    table.sort(p_List, function(a, b)
        if sort_type == 'Risky' then
            return a.damage > b.damage
        else
            return a.damage < b.damage
        end
    end)

    for i, o in pairs(p_List) do
        if not entity.is_alive(o.TARGET) then
            table.remove(p_List, i)
        end
    end

    local _, _, debug_point = entity.get_origin(me)
    if #p_List >= 1 then
        local lib = p_List[1]
        local vec = lib.vec
        local damage = lib.damage
        local e_vec = lib.enemy_vec
        local new_debug = vector(vec.x, vec.y, debug_point + 5)
        local x1, y1 = renderer.world_to_screen(new_debug.x, new_debug.y, new_debug.z)
        if includes(debugger, 'Line predict-target') then
            local x2, y2 = renderer.world_to_screen(e_vec.x, e_vec.y, e_vec.z)
            renderer.line(x1, y1, x2, y2, r, g, b, a)
        end

        if y1 ~= nil then
            y1 = y1 - 12
        end

        local render_text = tostring(math.floor(damage))
        renderer.text(x1, y1, r, g, b, a, 0, render_text)
        IS_WORKING = true
        WORKING_VEC = vec
    else
        WORKING_VEC = nil
        IS_WORKING = false
    end
end

local RUN_MOVEMENT = false
local function ai_peek_ragebot()
    if not lua_menu.exploits.exploits_enabled:get() or not lua_menu.exploits.ai_peek:get() then return end
    RUN_MOVEMENT = false
end

local function set_movement(cmd, desired_pos)
    local local_player = entity.get_local_player()
    local x, y, z = entity.get_prop(local_player, "m_vecAbsOrigin")
    local pitch, yaw = vector_angles(x, y, z, desired_pos.x, desired_pos.y, desired_pos.z)
    cmd.in_forward = 1
    cmd.in_back = 0
    cmd.in_moveleft = 0
    cmd.in_moveright = 0
    cmd.in_speed = 0

    cmd.forwardmove = 800
    cmd.sidemove = 0

    cmd.move_yaw = yaw
end

local indr, indg, indb, inda = 255, 255, 255, 255

local function ai_peek_retreat(cmd)
    if not lua_menu.exploits.exploits_enabled:get() or not lua_menu.exploits.ai_peek:get() then return end

    local me = entity.get_local_player()
    if me == nil then return end

    if not entity.is_alive(me) then return end

    local is_forward = cmd.in_forward == 1
    local is_backward = cmd.in_back == 1
    local is_left = cmd.in_moveleft == 1
    local is_right = cmd.in_moveright == 1

    if lua_menu.exploits.ai_peek_key:get() then
        local my_weapon = entity.get_player_weapon(me)
        if my_weapon == nil then return end

        local in_air = is_in_air(me)
        local timer = globals.curtime()
        local can_Fire = (entity.get_prop(me, "m_flNextAttack") <= timer and entity.get_prop(my_weapon, "m_flNextPrimaryAttack") <= timer)
        local x, y, z = entity.get_origin(me)

        if math.abs(x - my_old_vec.x) <= 10 then
            RUN_MOVEMENT = true
        end

        if not can_Fire then
            RUN_MOVEMENT = false
        end
        indr, indg, indb, inda = 255, 255, 0, 255
        if IS_WORKING and RUN_MOVEMENT and not in_air and WORKING_VEC ~= nil then
            set_movement(cmd, WORKING_VEC)
            indr, indg, indb, inda = 0, 255, 0, 255
        elseif not RUN_MOVEMENT and not in_air and not is_forward and not is_backward and not is_left and not is_right then
            set_movement(cmd, my_old_vec)
        end
    else
        indr, indg, indb, inda = 0, 255, 0, 255
    end
end

local function ai_peek_exploit(cmd)
    if not lua_menu.exploits.exploits_enabled:get() or not lua_menu.exploits.ai_peek:get() then return end
    ai_peek_retreat(cmd)
end

init_old()
-- [[ Cosmic Tag Spammer ]]
local cosmic_tag = "Nebula Overlord"
local last_clantag_update = 0
local clantag_frame = 0

local function clantag_en()
    if not lua_menu.misc.clantag:get() then
        ui.set(ref.clantag, false)
        client.set_clan_tag("")
        return
    end

    ui.set(ref.clantag, false) -- Отключаем встроенный клантэг
    local animation = lua_menu.misc.clantag_animation:get()
    local speed = lua_menu.misc.clantag_speed:get()
    local curtime = globals.curtime()

    if curtime - last_clantag_update < speed then return end
    last_clantag_update = curtime
    clantag_frame = clantag_frame + 1

    local tag = ""
    if animation == "Fade" then
        local len = #cosmic_tag
        local step = math.floor(clantag_frame % (len * 2))
        if step < len then
            tag = cosmic_tag:sub(1, step + 1)
        else
            tag = cosmic_tag:sub(1, len * 2 - step - 1)
        end
    elseif animation == "Scroll" then
        local len = #cosmic_tag
        local pos = (clantag_frame % (len + 1))
        tag = cosmic_tag:sub(pos + 1) .. cosmic_tag:sub(1, pos)
    elseif animation == "Blink" then
        tag = (clantag_frame % 2 == 0) and cosmic_tag or ""
    elseif animation == "Wave" then
        tag = ""
        for i = 1, #cosmic_tag do
            local wave = math.sin((curtime * 2 + i) * 0.5)
            tag = tag .. (wave > 0 and cosmic_tag:sub(i, i):upper() or cosmic_tag:sub(i, i):lower())
        end
    end

    client.set_clan_tag(tag)
end

-- [[ Fast Ladder ]]
local function fastladder(e)
    local lp = entity.get_local_player()
    local pitch, yaw = client.camera_angles()
    if entity.get_prop(lp, "m_MoveType") == 9 then
        e.yaw = math.floor(e.yaw + 0.5)
        e.roll = 0
        if e.forwardmove == 0 then
            if e.sidemove ~= 0 then
                e.pitch = 89
                e.yaw = e.yaw + 180
                if e.sidemove < 0 then e.in_moveleft, e.in_moveright = 0, 1 end
                if e.sidemove > 0 then e.in_moveleft, e.in_moveright = 1, 0 end
            end
        elseif e.forwardmove > 0 and pitch < 45 then
            e.pitch = 89
            e.in_moveright, e.in_moveleft, e.in_forward, e.in_back = 1, 0, 0, 1
            e.yaw = e.yaw + (e.sidemove == 0 and 90 or e.sidemove < 0 and 150 or 30)
        elseif e.forwardmove < 0 then
            e.pitch = 89
            e.in_moveleft, e.in_moveright, e.in_forward, e.in_back = 1, 0, 1, 0
            e.yaw = e.yaw + (e.sidemove == 0 and 90 or e.sidemove > 0 and 150 or 30)
        end
    end
end

-- [[ Third Person and Aspect Ratio ]]
local function thirdperson(value)
    if value ~= nil then cvar.cam_idealdist:set_int(value) end
end

local function aspectratio(value)
    if value then cvar.r_aspectratio:set_float(value / 100) end
end

-- [[ Resolver Logic ]]
local expres = {}
expres.get_prev_simtime = function(ent)
    local ent_ptr = native_GetClientEntity(ent)
    return ent_ptr and ffi.cast('float*', ffi.cast('uintptr_t', ent_ptr) + 0x26C)[0] or nil
end

expres.restore = function()
    for i = 1, 64 do plist.set(i, "Force body yaw", false) end
end

expres.body_yaw, expres.eye_angles = {}, {}

expres.get_max_desync = function(animstate)
    local speedfactor = clamp(animstate.feet_speed_forwards_or_sideways, 0, 1)
    local avg_speedfactor = (animstate.stop_to_full_running_fraction * -0.3 - 0.2) * speedfactor + 1
    local duck_amount = animstate.duck_amount
    if duck_amount > 0 then
        avg_speedfactor = avg_speedfactor + (duck_amount * speedfactor * (0.5 - avg_speedfactor))
    end
    return clamp(avg_speedfactor, 0.5, 1)
end

expres.handle = function(current_threat)
    if not current_threat or not entity.is_alive(current_threat) or entity.is_dormant(current_threat) then
        expres.restore()
        return
    end

    if not expres.body_yaw[current_threat] then
        expres.body_yaw[current_threat], expres.eye_angles[current_threat] = {}, {}
    end

    local simtime = toticks(entity.get_prop(current_threat, 'm_flSimulationTime'))
    local prev_simtime = toticks(expres.get_prev_simtime(current_threat))
    expres.body_yaw[current_threat][simtime] = entity.get_prop(current_threat, 'm_flPoseParameter', 11) * 120 - 60
    expres.eye_angles[current_threat][simtime] = select(2, entity.get_prop(current_threat, "m_angEyeAngles"))

    if expres.body_yaw[current_threat][prev_simtime] then
        local ent = c_entity.new(current_threat)
        local animstate = ent:get_anim_state()
        local max_desync = expres.get_max_desync(animstate)
        local Pitch = entity.get_prop(current_threat, "m_angEyeAngles[0]")
        local pitch_e = Pitch > -30 and Pitch < 49
        local curr_side = globals.tickcount() % 4 > 1 and 1 or -1

        if lua_menu.misc.resolver_type:get() == "Safe" then
            local should_correct = (simtime - prev_simtime >= 1) and math.abs(max_desync) < 45 and expres.body_yaw[current_threat][prev_simtime] ~= 0
            if should_correct then
                local value = math.random(0, expres.body_yaw[current_threat][prev_simtime] * math.random(-1, 1)) * 0.25
                plist.set(current_threat, 'Force body yaw', true)
                plist.set(current_threat, 'Force body yaw value', value)
            else
                plist.set(current_threat, 'Force body yaw', false)
            end
        elseif lua_menu.misc.resolver_type:get() == "Advanced" then
            local value_body = pitch_e and 0 or curr_side * (max_desync * math.random(0, 58))
            plist.set(current_threat, 'Force body yaw', true)
            plist.set(current_threat, 'Force body yaw value', value_body)
        else -- Defensive
            if not is_defensive_resolver(current_threat) then return end
            local value_body = pitch_e and 0 or math.random(0, expres.body_yaw[current_threat][prev_simtime] * math.random(-1, 1)) * 0.25
            plist.set(current_threat, 'Force body yaw', true)
            plist.set(current_threat, 'Force body yaw value', value_body)
        end
    end
    plist.set(current_threat, 'Correction active', true)
end

local function resolver_update()
    local lp = entity.get_local_player()
    if not lp then return end
    local entities = entity.get_players(true)
    if not entities then return end

    for i = 1, #entities do
        local target = entities[i]
        if target and entity.is_alive(target) then
            expres.handle(target)
        end
    end
end

-- [[ Trashtalk ]]
local trashtalk_phrases = {
    English = {
        "Nebula Overlord owns you!",
        "Orbiting your skill level!",
        "Cosmic precision, trash aim!",
        "Lost in my nebula hacks!",
        "Stargazing at your defeat!",
        "Nebula dominates all!",
        "Interstellar superiority!",
        "You're cosmic dust!"
    },
    Russian = {
        "Nebula Overlord раздавит тебя!",
        "Кручусь вокруг твоего скилла!",
        "Космическая точность, мусорный аим!",
        "Заблудился в моих хаках!",
        "Смотри на звезды своего поражения!",
        "Nebula властвует над всеми!",
        "Межзвездное превосходство!",
        "Ты космический мусор!"
    },
    Spanish = {
        "¡Nebula Overlord te posee!",
        "¡Orbitando tu nivel de habilidad!",
        "¡Precisión cósmica, puntería basura!",
        "¡Perdido en mis hacks de nebulosa!",
        "¡Mirando las estrellas de tu derrota!",
        "¡Nebula domina todo!",
        "¡Superioridad interestelar!",
        "¡Eres polvo cósmico!"
    },
    Chinese = {
        "星云霸主拥有你！",
        "围绕你的技能水平旋转！",
        "宇宙精度，垃圾瞄准！",
        "迷失在我的星云外挂中！",
        "凝视你失败的星星！",
        "星云统治一切！",
        "星际优势！",
        "你是宇宙尘埃！"
    }
}

local function on_player_death(e)
    if not lua_menu.misc.trashtalk:get() then return end
    if not lua_menu.main.enable:get() then return end

    local victim_userid, attacker_userid = e.userid, e.attacker
    if not victim_userid or not attacker_userid then return end

    local victim_entindex = client.userid_to_entindex(victim_userid)
    local attacker_entindex = client.userid_to_entindex(attacker_userid)

    if attacker_entindex == entity.get_local_player() and entity.is_enemy(victim_entindex) then
        local language = lua_menu.misc.trashtalk_language:get()
        local phrases = trashtalk_phrases[language]
        client.delay_call(2, function() client.exec("say ", phrases[math.random(1, #phrases)]) end)
    end
end
client.set_event_callback("player_death", on_player_death)

-- [[ Config System ]]
local config_items = {lua_menu, antiaim_system}
local package = pui.setup(config_items)
local config = {}

config.export = function()
    local data = package:save()
    local encrypted = base64.encode(json.stringify(data))
    clipboard.set(encrypted)
    print("Config exported to clipboard")
end

config.import = function(input)
    local decrypted = json.parse(base64.decode(input or clipboard.get()))
    package:load(decrypted)
    print("Config imported")
end

lua_menu.configs.import_button:set_callback(function() config.import() end)
lua_menu.configs.export_button:set_callback(function() config.export() end)
lua_menu.configs.reset_button:set_callback(function()
    config.import("W251bGwsW3siZW5hYmxlIjpmYWxzZSwieWF3X3R5cGUiOiJEZWZhdWx0IiwibW9kX3R5cGUiOiJPZmYiLCJkZWZfeWF3X3ZhbHVlIjo5LCJkZWZlbnNpdmVfcGl0Y2giOiJPZmYiLCJib2R5X3NsaWRlciI6LTEsInlhd19yYW5kb20iOjAsInBlZWtfZGVmIjpmYWxzZSwiZGVmZW5zaXZlIjp0cnVlLCJmb3JjZV9kZWYiOnRydWUsInlhd19kZWxheSI6NCwiZGVmX2JvZHlfeWF3X3R5cGUiOiJQdWxzZSIsInBpdGNoX3ZhbHVlIjozOCwiZGVmX21vZF90eXBlIjoiQ2VudGVyIiwieWF3X3ZhbHVlIjowLCJkZWZfYm9keV9zbGlkZXIiOjEsImRlZl9tb2RfZG0iOjUwLCJib2R5X3lhd190eXBlIjoiUHVsc2UiLCJ5YXdfdmFsdWUiOjksInlhd19yaWdodCI6OSwibW9kX2RtIjowLCJ5YXdfbGVmdCI6OSwiZGVmZW5zaXZlX3R5cGUiOiJDdXN0b20iLCJkZWZlbnNpdmVfeWF3IjoiT2ZmIn0seyJlbmFibGUiOnRydWUsInlhd190eXBlIjoiRGVsYXllZCIsIm1vZF90eXBlIjoiT2ZmIiwiZGVmX3lhd192YWx1ZSI6MywiZGVmZW5zaXZlX3BpdGNoIjoiQ29zbWljIiwiYm9keV9zbGlkZXIiOi0xLCJ5YXdfcmFuZG9tIjowLCJwZWVrX2RlZiI6ZmFsc2UsImRlZmVuc2l2ZSI6dHJ1ZSwiZm9yY2VfZGVmIjp0cnVlLCJ5YXdfZGVsYXkiOjQsImRlZl9ib2R5X3lhd190eXBlIjoiUHVsc2UiLCJwaXRjaF92YWx1ZSI6MCwiZGVmX21vZF90eXBlIjoiQ2VudGVyIiwieWF3X3ZhbHVlIjowLCJkZWZfYm9keV9zbGlkZXIiOi0xLCJkZWZfbW9kX2RtIjo2MCwiYm9keV95YXdfdHlwZSI6IlB1bHNlIiwieWF3X3JpZ2h0Ijo0LCJtb2RfZG0iOjAsInlhd19sZWZ0Ijo0LCJkZWZlbnNpdmVfdHlwZSI6IkN1c3RvbSIsImRlZmVuc2l2ZV95YXciOiJTcGluIn0seyJlbmFibGUiOmZhbHNlLCJ5YXdfdHlwZSI6IkRlZmF1bHQiLCJtb2RfdHlwZSI6Ik9mZiIsImRlZl95YXdfdmFsdWUiOjAsImRlZmVuc2l2ZV9waXRjaCI6Ik9mZiIsImJvZHlfc2xpZGVyIjowLCJ5YXdfcmFuZG9tIjowLCJwZWVrX2RlZiI6ZmFsc2UsImRlZmVuc2l2ZSI6ZmFsc2UsImZvcmNlX2RlZiI6ZmFsc2UsInlhd19kZWxheSI6NCwiZGVmX2JvZHlfeWF3X3R5cGUiOiJPZmYiLCJwaXRjaF92YWx1ZSI6MCwiZGVmX21vZF90eXBlIjoiT2ZmIiwieWF3X3ZhbHVlIjowLCJkZWZfYm9keV9zbGlkZXIiOjAsImRlZl9tb2RfZG0iOjAsImJvZHlfeWF3X3R5cGUiOiJPZmYiLCJ5YXdfcmFuZG9tIjo0LCJ5YXdfcmFuZG9tIjowLCJ5YXdfcmFuZG9tIjowLCJkZWZlbnNpdmVfdHlwZSI6IkRlZmF1bHQiLCJkZWZlbnNpdmVfeWF3IjoiT2ZmIn0seyJlbmFibGUiOnRydWUsInlhd190eXBlIjoiRGVsYXllZCIsIm1vZF90eXBlIjoiT2ZmIiwiZGVmX3lhd192YWx1ZSI6MCwiZGVmZW5zaXZlX3BpdGNoIjoiUmFuZG9tIiwiYm9keV9zbGlkZXIiOjEsInlhd19yYW5kb20iOjE1LCJwZWVrX2RlZiI6dHJ1ZSwiZGVmZW5zaXZlIjp0cnVlLCJmb3JjZV9kZWYiOmZhbHNlLCJ5YXdfZGVsYXkiOjUsImRlZl9ib2R5X3lhd190eXBlIjoiUHVsc2UiLCJwaXRjaF92YWx1ZSI6MCwiZGVmX21vZF90eXBlIjoiQ2VudGVyIiwieWF3X3ZhbHVlIjozMCwiZGVmX2JvZHlfc2xpZGVyIjoxLCJkZWZfbW9kX2RtIjo3NywiYm9keV95YXdfdHlwZSI6IlN0YXRpYyIsInlhd19yaWdodCI6MzQsIm1vZF9kbSI6MCwieWF3X2xlZnQiOi0zNCwiZGVmZW5zaXZlX3R5cGUiOiJEZWZhdWx0IiwiZGVmZW5zaXZlX3lhdyI6IlNwaW4ifV0=")
end)

-- [[ Event Callbacks ]]
client.set_event_callback("setup_command", function(cmd)
    if not lua_menu.main.enable:get() then return end
    aa_setup(cmd)
    if lua_menu.misc.fast_ladder:get() then fastladder(cmd) end
    if lua_menu.misc.teleport:get() and lua_menu.misc.teleport_key:get() then auto_tp(cmd) end
    if lua_menu.misc.resolver:get() then resolver_update() end
    unlimited_backtrack_exploit(cmd)
    phantom_reload_exploit(cmd)
    ai_peek_exploit(cmd)
    speedhack(cmd)
end)
-- Speedhack Cleanup
client.set_event_callback("shutdown", function()
    local lp = entity.get_local_player()
    if lp then
        entity.set_prop(lp, "m_flVelocityModifier", 1.0)
    end
end)
-- Speedhack Functions
local function clamp(value, min, max) return math.min(math.max(value, min), max) end

local function speedhack(cmd)
    if not lua_menu.exploits.exploits_enabled:get() or not lua_menu.exploits.speedhack:get() then
        speed_enabled = false
        current_speed = base_speed
        return
    end

    speed_enabled = lua_menu.exploits.speedhack_key:get()
    speed_multiplier = lua_menu.exploits.speed_multiplier:get()
    lerp_rate = lua_menu.exploits.speed_lerp:get()
    anti_detect_enabled = lua_menu.exploits.speed_anti_detect:get()
    fake_lag_enabled = lua_menu.exploits.speed_fake_lag:get()
    fake_lag_amount = lua_menu.exploits.speed_fake_lag_amount:get()

    local lp = entity.get_local_player()
    if not lp or not entity.is_alive(lp) then
        speed_enabled = false
        current_speed = base_speed
        return
    end

    if speed_enabled then
        target_speed = speed_multiplier
    else
        target_speed = base_speed
    end

    -- Плавный переход скорости
    current_speed = lerp(current_speed, target_speed, globals.frametime() * lerp_rate * 20)

    -- Применение скорости через m_flVelocityModifier
    entity.set_prop(lp, "m_flVelocityModifier", clamp(current_speed, 0.1, 5.0))

    -- Антидетект: маскировка через фейк-лаги
    if anti_detect_enabled and fake_lag_enabled then
        ui.set(ref.fakelag_limit, fake_lag_amount)
        ui.set(ref.fakelag_enabled, true)
    else
        ui.set(ref.fakelag_enabled, false)
    end

    -- Ускорение движения через cmd
    if speed_enabled then
        cmd.forwardmove = cmd.forwardmove * current_speed
        cmd.sidemove = cmd.sidemove * current_speed
    end
end

local function draw_speed_indicator()
    if not lua_menu.exploits.exploits_enabled:get() or not lua_menu.exploits.speedhack:get() or not speed_enabled then return end
    local r1, g1, b1 = 135, 206, 235
    local r2, g2, b2 = 30, 144, 255
    local alpha = 255 * (1 + math.sin(globals.curtime() * 3)) / 2 -- Пульсация
    text_fade_animation(indicator_x, indicator_y, -1.5, {r=r1, g=g1, b=b1, a=alpha}, {r=r2, g=g2, b=b2, a=alpha}, string.format("Speed: %.1fx", current_speed), "c")
end

client.set_event_callback('pre_render', function()
    if not lua_menu.main.enable:get() then return end
    if lua_menu.misc.animation:get() then anim_breaker() end
end)

client.set_event_callback('paint_ui', function()
    hide_original_menu(not lua_menu.main.enable:get())
    update_menu()
end)

client.set_event_callback('paint', function()
    if not lua_menu.main.enable:get() then return end
    clantag_en() -- Обновленный вызов клантэга
    if not entity.is_alive(entity.get_local_player()) then return end
    if lua_menu.misc.cross_ind:get() then screen_indicator() end
    thirdperson(lua_menu.misc.third_person:get() and lua_menu.misc.third_person_value:get() or nil)
    aspectratio(lua_menu.misc.aspectratio:get() and lua_menu.misc.aspectratio_value:get() or nil)
    if lua_menu.misc.velocity_window:get() then velocity_ind() end
    if lua_menu.misc.defensive_window:get() then defensive_ind() end
    ragebot_logs()
    if lua_menu.misc.info_panel:get() then info_panel() end
    draw_bullet_tracers()
    if lua_menu.exploits.ai_peek:get() then
        renderer.indicator(indr, indg, indb, inda, 'AI PEEK')
        ai_peek_runner()
    end
    text_fade_animation(screen[1]/2, screen[2] - 20, -1.5, {r=135, g=206, b=235, a=255}, {r=30, g=144, b=255, a=255}, "Nebula Overlord", "cdb")
    effects.menu_open = ui.is_menu_open()
    render_cosmic_menu_effect()
    if effects.welcome_active then render_welcome_effect() end
end)

lua_menu.misc.resolver:set_callback(function(self)
    if not self:get() then expres.restore() end
end, true)

client.set_event_callback('shutdown', function()
    hide_original_menu(true)
    thirdperson(150)
    aspectratio(0)
    expres.restore()
    client.set_clan_tag("") -- Сброс клантэга при выключении
end)

client.set_event_callback('round_prestart', function()
    logs = {}
    if lua_menu.misc.log_type:get("Screen") then renderer.log("Nebula Overlord Reset") end
end)

client.set_event_callback("player_connect_full", function(e)
    if client.userid_to_entindex(e.userid) == entity.get_local_player() then
        effects.welcome_active = true
        effects.welcome_alpha = 255
        generate_stars()
    end
end)

-- Дополнительные callbacks для AI Peek
client.set_event_callback("aim_fire", ai_peek_ragebot)
client.set_event_callback("run_command", function()
    local me = entity.get_local_player()
    if me == nil then return end

    if not entity.is_alive(me) then return end

    local m_x, m_y, m_z = entity.hitbox_position(me, 3)
    local my_vec = vector(m_x, m_y, m_z)
    local mpitch, myaw = client.camera_angles()

    if not lua_menu.exploits.ai_peek_key:get() or lua_menu.exploits.ai_peek_unlock:get() then
        my_old_view = vector(mpitch, myaw, 0)
    end

    if not lua_menu.exploits.ai_peek_key:get() then
        my_old_vec = my_vec
    end
end)

-- Обработчик видимости меню AI Peek
local function ai_peek_menu_handler()
    local enabled = lua_menu.exploits.exploits_enabled:get()
    local ai_peek_enabled = enabled and lua_menu.exploits.ai_peek:get()

    lua_menu.exploits.ai_peek_key:set_visible(ai_peek_enabled)
    lua_menu.exploits.ai_peek_mode:set_visible(ai_peek_enabled)
    lua_menu.exploits.ai_peek_target:set_visible(ai_peek_enabled)
    lua_menu.exploits.ai_peek_hitbox:set_visible(ai_peek_enabled)
    lua_menu.exploits.ai_peek_tick:set_visible(ai_peek_enabled)
    lua_menu.exploits.ai_peek_unlock:set_visible(ai_peek_enabled)
    lua_menu.exploits.ai_peek_segament:set_visible(ai_peek_enabled)
    lua_menu.exploits.ai_peek_radius:set_visible(ai_peek_enabled)
    lua_menu.exploits.ai_peek_depart:set_visible(ai_peek_enabled)
    lua_menu.exploits.ai_peek_middle:set_visible(ai_peek_enabled)
    lua_menu.exploits.ai_peek_limit:set_visible(ai_peek_enabled)
    lua_menu.exploits.ai_peek_limit_num:set_visible(ai_peek_enabled and lua_menu.exploits.ai_peek_limit:get())
    lua_menu.exploits.ai_peek_debugger:set_visible(ai_peek_enabled)
    lua_menu.exploits.ai_peek_color:set_visible(ai_peek_enabled)

    lua_menu.exploits.unlimited_bt:set_visible(enabled)
    lua_menu.exploits.unlimited_bt_key:set_visible(enabled and lua_menu.exploits.unlimited_bt:get())
    lua_menu.exploits.unlimited_bt_ticks:set_visible(enabled and lua_menu.exploits.unlimited_bt:get())
    lua_menu.exploits.unlimited_bt_choke:set_visible(enabled and lua_menu.exploits.unlimited_bt:get())
    lua_menu.exploits.unlimited_bt_priority:set_visible(enabled and lua_menu.exploits.unlimited_bt:get())
    lua_menu.exploits.phantom_reload:set_visible(enabled)
    lua_menu.exploits.phantom_reload_key:set_visible(enabled and lua_menu.exploits.phantom_reload:get())
    lua_menu.exploits.phantom_reload_interval:set_visible(enabled and lua_menu.exploits.phantom_reload:get())
    -- Speedhack UI
lua_menu.exploits.speedhack = lua_group:checkbox("\vN · \rSpeedhack")
lua_menu.exploits.speedhack_key = lua_group:hotkey("\vN · \rSpeedhack Key", true)
lua_menu.exploits.speed_multiplier = lua_group:slider("\vN · \rSpeed Multiplier", 1.0, 5.0, 2.0, true, "x", 0.1)
lua_menu.exploits.speed_lerp = lua_group:slider("\vN · \rLerp Rate", 0.01, 0.5, 0.1, true, "", 0.01)
lua_menu.exploits.speed_anti_detect = lua_group:checkbox("\vN · \rAnti-Detect")
lua_menu.exploits.speed_fake_lag = lua_group:checkbox("\vN · \rFake Lag")
lua_menu.exploits.speed_fake_lag_amount = lua_group:slider("\vN · \rFake Lag Amount", 1, 14, 6, true, "t")
end

ai_peek_menu_handler()
for i, o in pairs(lua_menu.exploits) do
    o:set_callback(ai_peek_menu_handler)
end
