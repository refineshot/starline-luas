local ffi = ffi

local ASSET_REPO_URL = "https://raw.githubusercontent.com/refineshot/starline-luas/main/data/scaleform/art/"

local menu = ui.Group("Scaleform HUD")
local ui_enabled = menu.Checkbox("Enable Scaleform", true)

ffi.cdef[[
    typedef void (__fastcall *fnParseImageUrl)(void* out, const char* url);
    uint64_t GetTickCount64(void);
    void* CreateFileA(const char*, uint32_t, uint32_t, void*, uint32_t, uint32_t, void*);
    int ReadFile(void*, void*, uint32_t, uint32_t*, void*);
    uint32_t GetFileSize(void*, uint32_t*);
    int CloseHandle(void*);
]]

local pGetTickCount64 = cheat.FindExport("kernel32.dll", "GetTickCount64")
local fnGetTickCount64 = pGetTickCount64 and ffi.cast("uint64_t (__stdcall*)()", pGetTickCount64) or function() return os.clock() * 1000 end
local pCreateFileA = cheat.FindExport("kernel32.dll", "CreateFileA")
local pReadFile = cheat.FindExport("kernel32.dll", "ReadFile")
local pGetFileSize = cheat.FindExport("kernel32.dll", "GetFileSize")
local pCloseHandle = cheat.FindExport("kernel32.dll", "CloseHandle")
local fnCreateFileA = pCreateFileA and ffi.cast("void* (__stdcall*)(const char*, uint32_t, uint32_t, void*, uint32_t, uint32_t, void*)", pCreateFileA)
local fnReadFile = pReadFile and ffi.cast("int (__stdcall*)(void*, void*, uint32_t, uint32_t*, void*)", pReadFile)
local fnGetFileSize = pGetFileSize and ffi.cast("uint32_t (__stdcall*)(void*, uint32_t*)", pGetFileSize)
local fnCloseHandle = pCloseHandle and ffi.cast("int (__stdcall*)(void*)", pCloseHandle)

local function read_local_disk_file(filepath)
    if not fnCreateFileA or not fnReadFile or not fnGetFileSize or not fnCloseHandle then return nil end
    local handle = fnCreateFileA(filepath, 0x80000000, 1, nil, 3, 0x80, nil)
    local invalid = ffi.cast("void*", ffi.cast("intptr_t", -1))
    if handle == invalid or handle == nil then return nil end
    local size = fnGetFileSize(handle, nil)
    if size == 0 or size == 0xFFFFFFFF then fnCloseHandle(handle) return nil end
    local buf = ffi.new("char[?]", size + 1)
    local bytesRead = ffi.new("uint32_t[1]")
    local ok = fnReadFile(handle, buf, size, bytesRead, nil)
    fnCloseHandle(handle)
    if ok ~= 0 and bytesRead[0] > 0 then return ffi.string(buf, bytesRead[0]) end
    return nil
end

local function get_art_dir()
    if file and file.Dir then
        local d = file.Dir()
        if d and #d > 0 then return d:gsub("/", "\\") .. "\\scaleform\\art" end
    end
    return "C:\\Users\\" .. (os.getenv("USERNAME") or "User") .. "\\Documents\\Starline\\scripts\\data\\scaleform\\art"
end

local kImageUrlPattern = "40 53 57 41 56 48 81 EC 40 04 00 00"
local pParseImageUrl = cheat.FindPattern("panorama.dll", kImageUrlPattern)
local oParseImageUrl = nil
local rewritten_buf = ffi.new("char[1024]")

if pParseImageUrl then
    oParseImageUrl = hooks.Add(pParseImageUrl, ffi.typeof("fnParseImageUrl"), function(out, url)
        if url ~= nil then
            local u = ffi.string(url)
            local scheme = "file://{hud}/"
            if u:sub(1, #scheme) == scheme then
                local name = u:sub(#scheme + 1)
                local q = name:find("?", 1, true)
                if q then name = name:sub(1, q - 1) end
                local rewritten = "raw://" .. get_art_dir() .. "\\" .. name
                ffi.copy(rewritten_buf, rewritten)
                return oParseImageUrl(out, rewritten_buf)
            end
        end
        return oParseImageUrl(out, url)
    end)
end

local ART_FILES = {
    "alert_icon.png",
    "alive_ct.png",
    "alive_skull.png",
    "alive_t.png",
    "ammo_plate.png",
    "armor_icon.png",
    "armor_plate.png",
    "defuse_icon.png",
    "fade.png",
    "gotv_ct.png",
    "gotv_t.png",
    "helmet_icon.png",
    "hp_icon.png",
    "hp_plate.png",
    "hp_red.png",
    "icon.ico",
    "kill_badge.png",
    "logo.png",
    "notice_bar.png",
    "novote.png",
    "team_ct.png",
    "team_t.png",
    "topleft.png",
    "weapon_plate.png",
    "win_ct.png",
    "win_t.png",
    "yesvote.png",
}

local is_downloading = false
local assets_ready = false

local function ensure_assets(on_finish)
    if is_downloading then return end
    local missing = {}
    for _, name in ipairs(ART_FILES) do
        if not file.Exists("scaleform/art/" .. name) then
            local local_bytes = read_local_disk_file("C:\\Users\\catgirl\\Documents\\project\\art\\" .. name)
            if local_bytes and #local_bytes > 0 then
                file.Write("scaleform/art/" .. name, local_bytes)
            else
                table.insert(missing, name)
            end
        end
    end

    if #missing == 0 then
        assets_ready = true
        if on_finish then on_finish() end
        return
    end

    assets_ready = false
    is_downloading = true
    local queue = {}
    for _, f in ipairs(missing) do table.insert(queue, f) end
    local total = #queue
    local done = 0

    local function download_next()
        if #queue == 0 then
            is_downloading = false
            assets_ready = true
            print("[Scaleform] Assets downloaded")
            if on_finish then on_finish() end
            return
        end
        local filename = table.remove(queue, 1)
        local base = ASSET_REPO_URL
        if base:sub(-1) ~= "/" then base = base .. "/" end
        local url = base .. filename
        http.Get(url, function(res)
            if res.ok and res.status == 200 and res.body and #res.body > 0 then
                file.Write("scaleform/art/" .. filename, res.body)
                done = done + 1
            else
                print(string.format("[Scaleform] Failed to download %s", filename))
            end
            download_next()
        end)
    end
    download_next()
end

local BUNDLED_SCRIPTS = {
    ["alerts.js"] = [===[var Al = {
	width: 700,
	height: 41,
	top: 300,
	bg: 'gradient( linear, 0% 0%, 100% 0%, from( #77777700 ), color-stop( 0.20, #00000099 ),'
		+ ' color-stop( 0.40, #00000099 ), color-stop( 0.60, #00000099 ),'
		+ ' color-stop( 0.80, #00000099 ), to( #00000000 ) )',

	fontSize: 32,
	textTop: 1,
	color: '#FFFFFF',
	matchStartColor: '#e10000',
	replayColor: '#c9c9c9',
	fade: 0.3,
	hideDuration: 1.0,
	hide: [
		{at: 0.00, opacity: '0.65', lit: false},
		{at: 0.21, opacity: '1.0', lit: true},
		{at: 0.42, opacity: '0.65', lit: false},
		{at: 1.00, opacity: '0.0', lit: false},
	],
	flashBrightness: '2.0',
	restBrightness: '1.0',
	park: -3000,
};

var AlOwner = contextPanel.FindChildTraverse('HudAlerts');

var AlPark = function (owner) {
	if (!owner)
		return false;
	if (owner.BHasClass('alert-parked')) {
		var held = true;
		try {
			var y = owner.style.y;
			if (typeof y === 'string' && y !== '')
				held = (y === Al.park + 'px');
		} catch (error) {
			held = true;
		}
		if (held)
			return false;
	}
	owner.AddClass('alert-parked');
	owner.style.y = Al.park + 'px';
	return true;
};

if (AlOwner)
	AlPark(AlOwner);

var AlOld = contextPanel.FindChildTraverse('Alert');
if (AlOld)
	AlOld.DeleteAsync(0);

var AlBar = $.CreatePanel('Panel', contextPanel, 'Alert');
AlBar.hittest = false;
AlBar.style.width = Al.width + 'px';
AlBar.style.height = Al.height + 'px';
AlBar.style.horizontalAlign = 'center';
AlBar.style.verticalAlign = 'top';
AlBar.style.marginTop = Al.top + 'px';
AlBar.style.backgroundColor = Al.bg;
AlBar.style.zIndex = '20';
AlBar.style.opacity = '0.0';
AlBar.style.brightness = Al.restBrightness;
AlBar.style.transitionProperty = 'opacity, brightness';
AlBar.style.transitionDuration = Al.fade + 's, ' + Al.fade + 's';
AlBar.style.transitionTimingFunction = 'linear';

var AlLabel = $.CreatePanel('Label', AlBar, 'AlertBarText');
AlLabel.hittest = false;
AlLabel.style.width = '100%';
AlLabel.style.horizontalAlign = 'center';
AlLabel.style.verticalAlign = 'center';
AlLabel.style.marginTop = Al.textTop + 'px';
AlLabel.style.textAlign = 'center';
AlLabel.style.fontFamily = 'Stratum2';
AlLabel.style.fontWeight = 'bold';
AlLabel.style.fontSize = Al.fontSize + 'px';
AlLabel.style.letterSpacing = '0px';
AlLabel.style.color = Al.color;
AlLabel.style.lineHeight = Al.fontSize + 'px';
AlLabel.style.textOverflow = 'shrink';

var AlShow = function (label, text) {
	var want = String(text).toUpperCase();
	if (label.Text === want)
		return;
	label.Text = want;
	label.text = want;
};

var AlDress = function (label, src) {
	var wanted = src.BHasClass('MatchStartAlert') ? Al.matchStartColor
		: (src.BHasClass('ReplayAlert') ? Al.replayColor : Al.color);
	if (label.Color !== wanted) {
		label.Color = wanted;
		label.style.color = wanted;
	}
	var mono = src.BHasClass('MatchAlertTimer');
	if (label.Mono !== mono) {
		label.Mono = mono;
		label.style.fontFamily = mono ? 'Stratum2 Bold Monodigit' : 'Stratum2';
	}
};

var AlHideSerial = (typeof AlHideSerial === 'undefined' ? 0 : AlHideSerial);

var AlLeg = function (bar, mine, span, stop) {
	try {
		if (mine !== AlHideSerial || !bar || !bar.IsValid())
			return;
		bar.style.transitionDuration = span + 's, ' + span + 's';
		bar.style.opacity = stop.opacity;
		bar.style.brightness = stop.lit ? Al.flashBrightness : Al.restBrightness;
	} catch (error) {
			}
};

var AlPlayHide = function (bar) {
	AlHideSerial = AlHideSerial + 1;
	var mine = AlHideSerial;
	var stops = Al.hide;

	AlLeg(bar, mine, 0, stops[0]);
	for (var at = 1; at < stops.length; ++at) {
		(function (index) {
			var from = stops[index - 1];
			var stop = stops[index];
			var span = (stop.at - from.at) * Al.hideDuration;
			$.Schedule(from.at * Al.hideDuration, function () {
				AlLeg(bar, mine, span, stop);
			});
		})(at);
	}
};

var AlRaise = function (bar) {
	AlHideSerial = AlHideSerial + 1;
	bar.style.transitionDuration = Al.fade + 's, ' + Al.fade + 's';
	bar.style.brightness = Al.restBrightness;
	bar.style.opacity = '1.0';
};

	var AlSaidRepark = false;

var AlWatch = function () {
	var owner = contextPanel.FindChildTraverse('HudAlerts');
	if (owner && AlPark(owner) && !AlSaidRepark) {
		AlSaidRepark = true;
	}
	var src = owner ? owner.FindChildTraverse('AlertText') : null;
	var bar = contextPanel.FindChildTraverse('Alert');
	var label = bar ? bar.FindChildTraverse('AlertBarText') : null;
	if (!owner || !src || !bar || !label)
		return;

	var up = (owner.BHasClass('AlertVisible') || owner.BHasClass('FlashAnim'))
		&& !owner.BHasClass('HideFlash');
	if (up) {
		var text = '';
		try {
			text = src.text || '';
		} catch (error) {
			text = '';
		}
		if (!text) {
			up = false;
		} else {
			AlDress(label, src);
			AlShow(label, text);
		}
	}

	var state = up ? 'up' : 'down';
	if (bar.State === state)
		return;
	var was = bar.State;
	bar.State = state;

	if (state === 'up') {
		AlRaise(bar);
	} else if (was === 'up') {
		AlPlayHide(bar);
	} else {
		return;
	}
};

var AlGeneration = (typeof AlGeneration === 'undefined' ? 0 : AlGeneration) + 1;

var AlTick = function (generation) {
	if (generation !== AlGeneration)
		return;
	try {
		AlWatch();
	} catch (error) {
			}
	$.Schedule(0.1, function () {
		AlTick(generation);
	});
};

$.Schedule(0.0, (function (generation) {
	return function () {
		AlTick(generation);
	};
})(AlGeneration));
]===],
    ["art.js"] = [===[var ArtFiles = {
	noticebar: 'notice_bar.png', topleft: 'topleft.png',
	alivect: 'alive_ct.png', alivet: 'alive_t.png', aliveskull: 'alive_skull.png',
	teamct: 'team_ct.png', teamt: 'team_t.png',
	weaponplate: 'weapon_plate.png', ammoplate: 'ammo_plate.png',
	hpplate: 'hp_plate.png', hpredplate: 'hp_red.png', armorplate: 'armor_plate.png',
	hpicon: 'hp_icon.png', armoricon: 'armor_icon.png', helmeticon: 'helmet_icon.png',
	killbadge: 'kill_badge.png', winpanelct: 'win_ct.png', winpanelt: 'win_t.png',
	alerticon: 'alert_icon.png', yesvote: 'yesvote.png', novote: 'novote.png',
	defuseicon: 'defuse_icon.png', joinplate: 'fade.png',
	gotvct: 'gotv_ct.png', gotvt: 'gotv_t.png'
};

var ArtNonce = (typeof ArtNonce === 'undefined' ? 1 : ArtNonce);
var ArtPainted = (typeof ArtPainted === 'undefined' ? [] : ArtPainted);

var ArtUrl = function (token) {
	return 'file://{hud}/' + (ArtFiles[token] || token);
};

var ArtCss = function (token) {
	return 'url("' + ArtUrl(token) + '")';
};

var ArtStamp = function (token, extra) {
	return token + '|' + ArtNonce
		+ '|' + ((extra && extra.size) || '')
		+ '|' + ((extra && extra.position) || '')
		+ '|' + ((extra && extra.opacity) || '');
};

var PaintArt = function (panel, token, extra) {
	if (!panel)
		return false;

	var stamp = ArtStamp(token, extra);
	if (panel.ArtStamp === stamp)
		return true;
	panel.ArtStamp = stamp;

	panel.style.backgroundColor = '#00000000';
	panel.style.backgroundImage = ArtCss(token);
	panel.style.backgroundSize = (extra && extra.size) || '100% 100%';
	panel.style.backgroundRepeat = 'no-repeat';
	panel.style.backgroundImgOpacity = (extra && extra.opacity) || '1.0';
	if (extra && extra.position)
		panel.style.backgroundPosition = extra.position;

	var slot = panel.ArtSlot;
	if (typeof slot === 'number' && ArtPainted[slot] && ArtPainted[slot].panel === panel) {
		ArtPainted[slot] = {panel: panel, id: panel.id, token: token, extra: extra};
		return true;
	}
	panel.ArtSlot = ArtPainted.length;
	ArtPainted.push({panel: panel, id: panel.id, token: token, extra: extra});
	return true;
};

var RearmArt = function (why) {
	CompactArt();
	ArtNonce = ArtNonce + 1;
	var kept = [];
	for (var at = 0; at < ArtPainted.length; ++at) {
		var entry = ArtPainted[at];
		try {
			entry.panel.style.backgroundImage = ArtCss(entry.token);
			entry.panel.style.backgroundImgOpacity = (entry.extra && entry.extra.opacity) || '1.0';
			entry.panel.ArtStamp = ArtStamp(entry.token, entry.extra);
			kept.push(entry);
		} catch (error) {
		}
	}
	ArtPainted = kept;
};

var CompactArt = function () {
	var kept = [];
	for (var at = ArtPainted.length - 1; at >= 0; --at) {
		var entry = ArtPainted[at];
		if (!entry || !entry.panel || entry.panel.ArtSeen)
			continue;
		entry.panel.ArtSeen = true;
		kept.push(entry);
	}
	kept.reverse();
	for (var slot = 0; slot < kept.length; ++slot) {
		kept[slot].panel.ArtSeen = false;
		kept[slot].panel.ArtSlot = slot;
	}
	ArtPainted = kept;
};

CompactArt();

if (typeof ArtEvents === 'undefined') {
	var ArtEvents = true;
	$.RegisterForUnhandledEvent('OnRoundStart', function () {
		RearmArt('round start');
	});
} else {
	RearmArt('reload');
}
]===],
    ["autodisconnect.js"] = [===[var AdGeneration = (typeof AdGeneration === 'undefined' ? 0 : AdGeneration) + 1;

var AdOnce = function (panel, marker) {
	if (!panel || panel.BHasClass(marker))
		return false;
	panel.AddClass(marker);
	return true;
};

var AdSet = function (panel, prop, value) {
	if (!panel)
		return;
	try {
		panel.style[prop] = value;
	} catch (error) {
			}
};

var AdApply = function () {
	var root = contextPanel.FindChildTraverse('HudAutoDisconnect');
	if (!root)
		return;
	var container = root.FindChildrenWithClassTraverse('auto-disconnect-container')[0];
	if (container && AdOnce(container, 'ad-container')) {
		AdSet(container, 'padding', '16px');
		AdSet(container, 'backgroundColor', '#000000CC');
		AdSet(container, 'borderRadius', '0px');
	}
	AdSet(root, 'horizontalAlign', 'right');
	AdSet(root, 'marginRight', '10px');

	var top = root.FindChildTraverse('TopLabel');
	if (top && AdOnce(top, 'ad-top')) {
		AdSet(top, 'fontFamily', 'Stratum2');
		AdSet(top, 'fontWeight', 'medium');
		AdSet(top, 'fontSize', '32px');
		AdSet(top, 'textAlign', 'center');
		AdSet(top, 'padding', '4px');
		AdSet(top, 'color', '#ff3d3d');
		AdSet(top, 'textShadow', '1px 1px 2px #000000AA');
	}

	var bottom = root.FindChildTraverse('BottomLabel');
	if (bottom && AdOnce(bottom, 'ad-bottom')) {
		AdSet(bottom, 'fontFamily', 'Stratum2');
		AdSet(bottom, 'fontWeight', 'medium');
		AdSet(bottom, 'fontSize', '28px');
		AdSet(bottom, 'textAlign', 'center');
		AdSet(bottom, 'padding', '4px');
		AdSet(bottom, 'color', '#ff3d3d');
		AdSet(bottom, 'textShadow', '1px 1px 2px #000000AA');
	}

	var icon = root.FindChildTraverse('TimerIcon');
	if (icon && AdOnce(icon, 'ad-icon'))
		AdSet(icon, 'washColor', '#ff3d3d');
};

var AdTick = function (generation) {
	if (generation !== AdGeneration)
		return;
	try {
		AdApply();
	} catch (error) {
			}
	$.Schedule(0.5, function () {
		AdTick(generation);
	});
};

AdTick(AdGeneration);
]===],
    ["base.js"] = [===[var Child = function (root, id) {
	return root ? root.FindChildTraverse(id) : null;
};

var Paint = function (panel, token, size) {
	return PaintArt(panel, token, {size: size, opacity: PlateImgOpacity});
};

var PlateImgOpacity = '1.0';
var PlateHeight = 46;
var PlateWidth = 410;
var PixelGap = 1;

var Dashboard = Child(contextPanel, 'DashboardLabel');
if (Paint(Dashboard, 'topleft')) {
	Dashboard.RemoveClass('additive');
	Dashboard.style.horizontalAlign = 'left';
	Dashboard.style.verticalAlign = 'top';
	Dashboard.style.marginLeft = PixelGap + 'px';
	Dashboard.style.marginTop = PixelGap + 'px';
	Dashboard.style.width = PlateWidth + 'px';
	Dashboard.style.height = PlateHeight + 'px';
	Dashboard.style.paddingTop = '10px';
	Dashboard.style.paddingLeft = '14px';
	Dashboard.style.textAlign = 'left';
	Dashboard.style.fontFamily = 'Stratum2';
	Dashboard.style.fontWeight = 'bold';
	Dashboard.style.fontSize = '26px';
	Dashboard.style.letterSpacing = '0px';
	Dashboard.style.opacity = '1.0';

	var RadarRoot = Dashboard.GetParent();
	var RadarPanel = Child(contextPanel, 'Radar');

	while (RadarRoot && RadarPanel && RadarRoot.GetParent() !== RadarPanel.GetParent())
		RadarRoot = RadarRoot.GetParent();
	if (RadarRoot && RadarPanel && RadarRoot.GetParent() === RadarPanel.GetParent()) {
		RadarRoot.GetParent().MoveChildBefore(RadarRoot, RadarPanel);
		RadarPanel.style.y = (40 + PlateHeight + PixelGap) + 'px';
	}
}

for (var alert of contextPanel.FindChildrenWithClassTraverse('AlertText')) {
	alert.style.backgroundColor =
		'gradient( linear, 100% 0%, 0% 0%, from( #00000000 ), color-stop( 0.7, #00000077 ), to( #00000077 ) )';
	alert.style.textShadow = '1px 1px 2px #00000055';
	alert.style.fontFamily = 'Stratum2';
	alert.style.fontWeight = 'normal';
	alert.style.fontSize = '21.5px';
	alert.style.letterSpacing = '.43px';
	alert.style.paddingLeft = '28px';
	alert.style.paddingBottom = '0px';
}
]===],
    ["damageindicator.js"] = [===[var DamageSize = '200px';

var DamageRoot = contextPanel.FindChildTraverse('Damage');
if (DamageRoot) {
	try {
		DamageRoot.style.width = DamageSize;
		DamageRoot.style.height = DamageSize;
	} catch (error) {
	}
	var DamageSegments = DamageRoot.FindChildrenWithClassTraverse('Damage__Segment');
	for (var DamageAt = 0; DamageAt < DamageSegments.length; ++DamageAt) {
		try {
			DamageSegments[DamageAt].style.clip = 'radial( 50% 50%, 315deg, 90deg )';
		} catch (clipError) {
			break;
		}
	}
} else {
}
]===],
    ["deathnotices.js"] = [===[var HiddenIcons = ['NoScopeIcon', 'ThroughSmokeIcon', 'AttackerBlindIcon', 'Domination', 'AttackerInAir', 'Revenge'];
var WeaponIconScale = '75%';
var ExtraIconHeight = '26px';
var NoticeFontSize = '20px';
var NoticeLetterSpacing = '0.2px';
var NoticeTextShadow = '1px 1px 0px #000000';
var NoticeGap = '4px';
var VignetteOpacity = '0.76';
var VignetteHeight = '95%';
var KillerBar = '#000000e6';
var VictimBar = '#a81313ff';
var NoticeRoot = null;

var StyleOneNotice = function (notice, force) {
	var isKiller = notice.BHasClass('DeathNotice_Killer');
	var isVictim = notice.BHasClass('DeathNotice_Victim');
	var marker = isKiller ? 'killer' : (isVictim ? 'victim' : 'neutral');
	if (!force && notice.BHasClass(marker))
		return;
	for (var stale of ['killer', 'victim', 'neutral'])
		notice.RemoveClass(stale);
	notice.AddClass(marker);

	for (var iconId of HiddenIcons) {
		var extraIcon = notice.FindChildTraverse(iconId);
		if (extraIcon)
			extraIcon.style.visibility = 'collapse';
	}

	for (var icon of notice.FindChildrenWithClassTraverse('DeathNoticeIcon')) {
		icon.style.verticalAlign = 'top';
		if (icon.id === 'Weapon') {
			icon.style.transform = 'translateY(5px)';
			icon.style.uiScale = WeaponIconScale;
		} else {
			icon.style.height = ExtraIconHeight;
			icon.style.transform = 'translateY(0px)';
			icon.style.uiScale = '100%';
		}
	}

	for (var label of notice.FindChildrenWithClassTraverse('stratum-bold')) {
		label.style.fontSize = NoticeFontSize;
		label.style.fontWeight = 'bold';
		label.style.letterSpacing = NoticeLetterSpacing;
		label.style.textShadow = NoticeTextShadow;
	}

	for (var t of notice.FindChildrenWithClassTraverse('DeathNoticeTColor'))
		t.style.color = '#e8c56f';
	for (var ct of notice.FindChildrenWithClassTraverse('DeathNoticeCTColor'))
		ct.style.color = '#83a5de';

	for (var blurred of notice.FindChildrenWithClassTraverse('DeathNoticeBG'))
		blurred.style.visibility = 'collapse';

	for (var vignette of notice.FindChildrenWithClassTraverse('DeathNoticeBGGradient')) {
		vignette.style.visibility = isKiller ? 'collapse' : 'visible';
		vignette.style.opacity = VignetteOpacity;
		vignette.style.height = VignetteHeight;
		vignette.style.verticalAlign = 'center';
	}

	notice.style.marginTop = NoticeGap;

	for (var border of notice.FindChildrenWithClassTraverse('DeathNoticeBGBorder')) {
		border.style.boxShadow = 'inset #00000000 0px 0px 0px 0px;';
		border.style.backgroundImage = 'none';
		border.style.borderRadius = '5px';
		border.style.border = isKiller ? '1.5px solid #b3070d' : '1.5px solid #00000000';
		if (isKiller) {
			border.style.backgroundColor = KillerBar;
		} else if (isVictim) {
			border.style.backgroundColor = VictimBar;
		} else {
			border.style.backgroundColor = '#00000000';
		}
	}
};

var StyleDeathNotices = function (force) {
	if (!NoticeRoot)
		NoticeRoot = contextPanel.FindChildTraverse('HudDeathNotice');
	if (!NoticeRoot)
		return;

	for (var notice of NoticeRoot.FindChildrenWithClassTraverse('DeathNotice'))
		StyleOneNotice(notice, force);
};

StyleDeathNotices(true);

if (typeof DeathNoticeLoop === 'undefined') {
	var DeathNoticeLoop = function () {
		try {
			StyleDeathNotices(false);
		} catch (error) {
						NoticeRoot = null;
		}
		$.Schedule(0.2, DeathNoticeLoop);
	};
	$.Schedule(0.2, DeathNoticeLoop);
}
]===],
    ["dmbonus.js"] = [===[var DbGeneration = (typeof DbGeneration === 'undefined' ? 0 : DbGeneration) + 1;

var DbOnce = function (panel, marker) {
	if (!panel || panel.BHasClass(marker))
		return false;
	panel.AddClass(marker);
	return true;
};

var DbSet = function (panel, prop, value) {
	if (!panel)
		return;
	try {
		panel.style[prop] = value;
	} catch (error) {
			}
};

var DbShadow = '1px 1px 1px 1.0 #000000';

var DbApply = function () {
	var root = contextPanel.FindChildTraverse('HudDMBonusPanel');
	if (!root)
		return;

	var bg = root.FindChildrenWithClassTraverse('bonuspanel-bg')[0];
	if (bg && DbOnce(bg, 'dm-bg')) {
		DbSet(bg, 'width', '400px');
		DbSet(bg, 'height', '100%');
		DbSet(bg, 'backgroundColor', 'gradient( linear, 0% 0%, 100% 0%,'
			+ ' from( #000000ED ), color-stop( 0.8, #00000020 ), to( #00000000 ) )');
	}

	for (var edge of root.FindChildrenWithClassTraverse('bonuspanel-bkg-TOP'))
		if (DbOnce(edge, 'dm-edge')) {
			DbSet(edge, 'width', '400px');
			DbSet(edge, 'height', '2px');
			DbSet(edge, 'backgroundColor', 'gradient( linear, 100% 0%, 0% 0%,'
				+ ' from( #00000000 ), to( #000000BB ) )');
		}
	for (var edge2 of root.FindChildrenWithClassTraverse('bonuspanel-bkg-BOT'))
		if (DbOnce(edge2, 'dm-edge2')) {
			DbSet(edge2, 'width', '400px');
			DbSet(edge2, 'height', '2px');
			DbSet(edge2, 'verticalAlign', 'bottom');
			DbSet(edge2, 'backgroundColor', 'gradient( linear, 100% 0%, 0% 0%,'
				+ ' from( #00000000 ), to( #000000BB ) )');
		}

	for (var title of root.FindChildrenWithClassTraverse('bonuspanel-title-text'))
		if (DbOnce(title, 'dm-title')) {
			DbSet(title, 'fontFamily', 'Stratum2');
			DbSet(title, 'fontSize', '16px');
			DbSet(title, 'color', '#dddddd');
			DbSet(title, 'textShadow', DbShadow);
		}

	for (var weapon of root.FindChildrenWithClassTraverse('bonuspanel-title-weapon'))
		if (DbOnce(weapon, 'dm-weapon')) {
			DbSet(weapon, 'fontFamily', 'Stratum2');
			DbSet(weapon, 'fontWeight', 'medium');
			DbSet(weapon, 'fontSize', '22px');
			DbSet(weapon, 'color', '#ffffff');
			DbSet(weapon, 'textShadow', DbShadow);
			DbSet(weapon, 'paddingLeft', '4px');
		}

	for (var points of root.FindChildrenWithClassTraverse('bonuspanel-points'))
		if (DbOnce(points, 'dm-points')) {
			DbSet(points, 'fontFamily', 'Stratum2');
			DbSet(points, 'fontWeight', 'medium');
			DbSet(points, 'fontSize', '26px');
			DbSet(points, 'color', '#ffffff');
			DbSet(points, 'textShadow', DbShadow);
			DbSet(points, 'verticalAlign', 'bottom');
			DbSet(points, 'textAlign', 'center');
		}

	for (var timer of root.FindChildrenWithClassTraverse('bonuspanel-timer-text'))
		if (DbOnce(timer, 'dm-timer')) {
			DbSet(timer, 'fontFamily', 'Stratum2 Bold Monodigit');
			DbSet(timer, 'fontWeight', 'bold');
			DbSet(timer, 'fontSize', '50px');
			DbSet(timer, 'color', '#ffffff');
			DbSet(timer, 'horizontalAlign', 'center');
			DbSet(timer, 'verticalAlign', 'middle');
		}

	for (var icon of root.FindChildrenWithClassTraverse('bonuspanel-icon'))
		if (DbOnce(icon, 'dm-icon')) {
			DbSet(icon, 'height', '64px');
			DbSet(icon, 'color', 'white');
			DbSet(icon, 'verticalAlign', 'center');
		}

	for (var killPoints of root.FindChildrenWithClassTraverse('bonuspanel-bonuspoints-points'))
		if (DbOnce(killPoints, 'dm-killpoints')) {
			DbSet(killPoints, 'fontFamily', 'Stratum2');
			DbSet(killPoints, 'fontWeight', 'bold');
			DbSet(killPoints, 'fontSize', '32px');
			DbSet(killPoints, 'color', '#ffffff');
			DbSet(killPoints, 'textShadow', DbShadow);
		}
};

var DbTick = function (generation) {
	if (generation !== DbGeneration)
		return;
	try {
		DbApply();
	} catch (error) {
			}
	$.Schedule(0.5, function () {
		DbTick(generation);
	});
};

DbTick(DbGeneration);
]===],
    ["freezepanel.js"] = [===[var fpFailures = {};

var fpSet = function (panel, property, value) {
	if (!panel)
		return;
	try {
		panel.style[property] = value;
	} catch (error) {
		if (!fpFailures[property]) {
			fpFailures[property] = true;
					}
	}
};

var fpAdd = function (panel, className) {
	if (panel && !panel.BHasClass(className))
		panel.AddClass(className);
};

var fpEach = function (root, className, dress) {
	if (!root)
		return;
	var found = root.FindChildrenWithClassTraverse(className);
	for (var at = 0; at < found.length; ++at)
		dress(found[at]);
};

var fpBox = {
	contentWidth: '510px',
	bg: 'gradient( linear, 0% 0%, 100% 0%, from( #00000000 ), to( #000000cc ) )',
	fillBg: 'gradient( linear, 0% 0%, 100% 0%, from( #000000cc ), color-stop( 0.70, #000000cc ),'
		+ ' to( #00000000 ) )',
	avatarMount: '86px',
	avatar: '80px',
	barWidth: '80px',
	barBorder: '1px solid #c2c5ba80',
	nameColor: '#cccccc',
	nameSize: '30px',
	nameHeight: '40px',
	descColor: '#c93121',
	descSize: '20px',
	damageBg: 'gradient( linear, 0% 0%, 100% 0%, from( #00000088 ), color-stop( 0.60, #00000088 ),'
		+ ' to( #00000000 ) )',
	damageSize: '20px',
	itemBorder: '5px solid #000000',
	itemBg: '#000000cc',
	navColor: '#cccccc',
	navSize: '20px',
	navShadow: '2px 2px 0px #000000',
	ssContentWidth: '650px',
	ssBg: 'gradient( linear, 0% 0%, 100% 0%, from( #00000000 ), color-stop( 0.30, #000000cc ),'
		+ ' to( #000000cc ) )',
	ssAvatarMount: '46px',
	ssAvatar: '40px',
	ssNameColor: '#ffffff',
	ssNameSize: '40px',
	ssDescColor: '#c93121',
	ssDescSize: '25px',
	ssItemWidth: '120px',
};

var fpDress = function () {
	var fpMain = contextPanel.FindChildTraverse('DeathPanel');
	if (fpMain) {
		if (fpMain.BHasClass('DeathPanel__BG-Blur'))
			fpMain.RemoveClass('DeathPanel__BG-Blur');

		fpEach(fpMain, 'death-panel-bg', function (panel) {
			fpSet(panel, 'backgroundImage', 'none');
			fpSet(panel, 'backgroundImgOpacity', '0');
		});

		fpEach(fpMain, 'DeathPanel__Content', function (panel) {
			fpSet(panel, 'width', fpBox.contentWidth);
		});
		fpEach(fpMain, 'DeathPanel__BG', function (panel) {
			fpSet(panel, 'backgroundColor', fpBox.bg);
		});

		var fpAvatar = fpMain.FindChildTraverse('Avatar');
		var fpAvatarRow = fpAvatar && fpAvatar.GetParent() ? fpAvatar.GetParent().GetParent()
			: null;
		if (fpAvatarRow)
			fpSet(fpAvatarRow, 'backgroundColor', fpBox.fillBg);
		fpEach(fpMain, 'DeathPanel_AvatarBG', function (panel) {
			fpSet(panel, 'width', fpBox.avatarMount);
			fpSet(panel, 'height', fpBox.avatarMount);
			fpSet(panel, 'backgroundColor', 'gradient( linear, 0% 0%, 0% 100%, from( #7e7e7e ),'
				+ ' to( #2a2a2a ) )');
		});
		fpEach(fpMain, 'DeathPanel__Avatar', function (panel) {
			fpSet(panel, 'width', fpBox.avatar);
			fpSet(panel, 'height', fpBox.avatar);
		});
		fpEach(fpMain, 'DeathPanel__AvatarHealthBar', function (panel) {
			fpSet(panel, 'width', fpBox.barWidth);
			fpSet(panel, 'height', '5px');
			fpSet(panel, 'border', fpBox.barBorder);
			fpSet(panel, 'margin', '3px');

		});
		fpEach(fpMain, 'DeathPanel__Name', function (panel) {
			fpSet(panel, 'color', fpBox.nameColor);
			fpSet(panel, 'fontSize', fpBox.nameSize);
			fpSet(panel, 'height', fpBox.nameHeight);
			fpSet(panel, 'letterSpacing', '0px');
			fpAdd(panel, 'additive');
		});
		fpEach(fpMain, 'DeathPanel__Desc', function (panel) {
			fpSet(panel, 'color', fpBox.descColor);
			fpSet(panel, 'fontSize', fpBox.descSize);
			fpSet(panel, 'paddingLeft', '20px');
			fpAdd(panel, 'additive');
		});
		fpEach(fpMain, 'DeathPanel__Damage', function (panel) {
			fpSet(panel, 'backgroundColor', fpBox.damageBg);
			fpSet(panel, 'borderTop', '0px solid #00000000');
			var kids = panel.Children();
			for (var kid = 0; kid < kids.length; ++kid)
				if (kids[kid].paneltype === 'Label') {
					fpSet(kids[kid], 'fontSize', fpBox.damageSize);
					fpSet(kids[kid], 'paddingLeft', '10px');
				}
		});
		fpEach(fpMain, 'DeathPanel__ItemContainer', function (panel) {
			fpSet(panel, 'width', '150px');
			fpSet(panel, 'borderLeft', fpBox.itemBorder);
			fpSet(panel, 'backgroundColor', fpBox.itemBg);
		});
		fpEach(fpMain, 'DeathPanel__Navigation', function (panel) {
			fpSet(panel, 'color', fpBox.navColor);
			fpSet(panel, 'fontSize', fpBox.navSize);
			fpSet(panel, 'fontWeight', 'bold');
			fpSet(panel, 'textShadow', fpBox.navShadow);
			fpSet(panel, 'paddingLeft', '10px');
		});
	}

	var fpSS = contextPanel.FindChildTraverse('DeathPanelSS');
	if (fpSS) {
		fpEach(fpSS, 'DeathPanelSS__Content', function (panel) {
			fpSet(panel, 'width', fpBox.ssContentWidth);
		});
		fpEach(fpSS, 'DeathPanelSS__BG', function (panel) {
			fpSet(panel, 'backgroundColor', fpBox.ssBg);
		});
		fpEach(fpSS, 'DeathPanelSS__Logo', function (panel) {
			fpSet(panel, 'width', '650px');
			fpSet(panel, 'padding', '10px');
			fpSet(panel, 'marginLeft', '30px');
			fpSet(panel, 'marginBottom', '30px');
			fpSet(panel, 'backgroundColor', 'gradient( linear, 0% 0%, 100% 0%, from( #00000000 ),'
				+ ' color-stop( 0.30, #00000080 ), to( #00000080 ) )');
		});
		fpEach(fpSS, 'DeathPanelSS__LogoImage', function (panel) {
			fpSet(panel, 'washColor', '#cccccc');
		});
		fpEach(fpSS, 'DeathPanel_AvatarBG', function (panel) {
			fpSet(panel, 'width', fpBox.ssAvatarMount);
			fpSet(panel, 'height', fpBox.ssAvatarMount);
		});
		fpEach(fpSS, 'DeathPanel__Avatar', function (panel) {
			fpSet(panel, 'width', fpBox.ssAvatar);
			fpSet(panel, 'height', fpBox.ssAvatar);
		});
		fpEach(fpSS, 'DeathPanel__AvatarHealthBar', function (panel) {
			fpSet(panel, 'width', fpBox.ssAvatar);
		});
		fpEach(fpSS, 'DeathPanelSS__Name', function (panel) {
			fpSet(panel, 'color', fpBox.ssNameColor);
			fpSet(panel, 'fontSize', fpBox.ssNameSize);
			fpSet(panel, 'fontWeight', 'bold');
			fpSet(panel, 'marginRight', '10px');
		});
		fpEach(fpSS, 'DeathPanelSS__Desc', function (panel) {
			fpSet(panel, 'color', fpBox.ssDescColor);
			fpSet(panel, 'fontSize', fpBox.ssDescSize);
			fpSet(panel, 'fontWeight', 'bold');
		});
		fpEach(fpSS, 'DeathPanel__ItemContainer', function (panel) {
			fpSet(panel, 'width', fpBox.ssItemWidth);
		});
	}

	var fpCancel = contextPanel.FindChildTraverse('DeathCancel');
	if (fpCancel) {
		fpSet(fpCancel, 'color', fpBox.navColor);
		fpSet(fpCancel, 'fontSize', fpBox.navSize);
		fpSet(fpCancel, 'fontWeight', 'bold');
		fpSet(fpCancel, 'textShadow', fpBox.navShadow);
	}
};

var fpGeneration = (typeof fpGeneration === 'undefined' ? 0 : fpGeneration) + 1;
var fpWasHidden = true;

var fpTick = function (generation) {
	if (generation !== fpGeneration)
		return;
	try {
		var root = contextPanel.FindChildTraverse('HudDeathPanel');
		var hidden = true;
		try {
			hidden = root ? !(root.visible === true) : true;
		} catch (visibleError) {
			hidden = root ? root.BHasClass('DeathPanelRoot--Hidden') : true;
		}
	if (fpWasHidden && !hidden) {
		fpDress();
	}
	fpWasHidden = hidden;
	} catch (error) {
			}
	$.Schedule(0.1, function () {
		fpTick(generation);
	});
};

$.Schedule(0.1, (function (generation) {
	return function () {
		fpTick(generation);
	};
})(fpGeneration));
]===],
    ["gamerules_constants.js"] = [===[var dictObjectiveImage = {
	0: 'file://{images}/icons/ui/bomb_c4.svg',
	1: 'file://{images}/icons/ui/bomb.svg',
	2: 'file://{images}/icons/equipment/defuser.svg',
	3: 'file://{images}/icons/ui/time_exp.svg',
};
]===],
    ["healtharmor.js"] = [===[var HaOwner = contextPanel.FindChildTraverse('jsHudHealthArmorAmmoMore');
if (!HaOwner) {
	for (var HaAt = contextPanel.FindChildTraverse('hud-HA-main'); HaAt; HaAt = HaAt.GetParent()) {
		if (HaAt.GetParent() === contextPanel) {
			HaOwner = HaAt;
			break;
		}
	}
}

var HaBox = {
	edgeGap: 0,
	bottomGap: 0,
	iconY: 0,
	textY: 0,
	height: 57,
	hpWidth: 197,
	hpBgSize: '107% 100%',
	armorWidth: 230,

	iconWidth: 22,
	iconHeight: 22,
	iconX: 19,
	iconOpacity: '0.85',
	textWidth: 70,
	textX: 40,
	fontSize: 42,
	letterSpacing: -1,
	textMarginLeft: 5,
	color: '#ffffff',
	textShadow: '0px 0px 3px 0.0 #000000DD',
	criticalShadow: '0px 0px 9px 2.5 #DD0000',
	criticalAt: 25,
	criticalPlateOpacity: '0.92',
	criticalFill: '#ff0000',
	barWidth: 80,
	barHeight: 8,
	barX: 116,
	barY: 6,
	barTrack: '#03030399',
	armorMax: 100,
};

var HaFailures = {};

var HaSet = function (panel, property, value) {
	if (!panel)
		return;
	try {
		panel.style[property] = value;
	} catch (error) {
		if (!HaFailures[property]) {
			HaFailures[property] = true;
					}
	}
};

var HaTint = function () {
	try {
		return (typeof HudTextColor !== 'undefined' && HudTextColor) ? HudTextColor : HaBox.color;
	} catch (error) {
		return HaBox.color;
	}
};

var HaPlateOpacity = function () {
	try {
		return (typeof PlateAlphaValue !== 'undefined' && PlateAlphaValue !== null)
			? String(PlateAlphaValue) : '1.0';
	} catch (error) {
		return '1.0';
	}
};

var HaOldRoot = contextPanel.FindChildTraverse('HA');
if (HaOldRoot)
	HaOldRoot.DeleteAsync(0);

if (HaOwner) {
	var HaRoot = $.CreatePanel('Panel', contextPanel, 'HA');
	HaRoot.hittest = false;
	HaSet(HaRoot, 'width', '100%');
	HaSet(HaRoot, 'height', '100%');
	HaSet(HaRoot, 'zIndex', '20');
	HaSet(HaRoot, 'visibility', 'collapse');

	for (var HaGone of ['hud-HA-bar', 'hud-HA-center', 'hud-HA__stroke']) {
		var HaFound = HaOwner.FindChildrenWithClassTraverse(HaGone);
		for (var HaOne = 0; HaOne < HaFound.length; ++HaOne) {
			HaSet(HaFound[HaOne], 'visibility', 'collapse');
		}
	}

	var HaMain = HaOwner.FindChildTraverse('hud-HA-main');
	var HaSrcHealth = null;
	var HaSrcArmor = null;
	if (HaMain) {
		HaSet(HaMain, 'opacity', '0.0');
		var HaHealthGroup = HaMain.FindChildrenWithClassTraverse('hud-HA-health')[0];
		var HaArmorGroup = HaMain.FindChildrenWithClassTraverse('hud-HA-armor')[0];
		if (HaHealthGroup)
			HaSrcHealth = HaHealthGroup.FindChildrenWithClassTraverse('hud-HA-health_or_ammo-label')[0];
		if (HaArmorGroup)
			HaSrcArmor = HaArmorGroup.FindChildrenWithClassTraverse('hud-HA-armor-label')[0];
	}

	var HaRow = $.CreatePanel('Panel', HaRoot, 'HARow');
	HaRow.hittest = false;
	HaSet(HaRow, 'flowChildren', 'right');
	HaSet(HaRow, 'width', 'fit-children');
	HaSet(HaRow, 'height', HaBox.height + 'px');
	HaSet(HaRow, 'horizontalAlign', 'left');
	HaSet(HaRow, 'verticalAlign', 'bottom');
	HaSet(HaRow, 'marginLeft', HaBox.edgeGap + 'px');
	HaSet(HaRow, 'marginBottom', HaBox.bottomGap + 'px');

	var HaGroup = function (id, token, width, bgSize) {
		var group = $.CreatePanel('Panel', HaRow, id);
		group.hittest = false;
		HaSet(group, 'width', width + 'px');
		HaSet(group, 'height', '100%');
		PaintArt(group, token, bgSize
			? {size: bgSize, opacity: HaPlateOpacity()}
			: {opacity: HaPlateOpacity()});

		var icon = $.CreatePanel('Panel', group, id + 'Icon');
		icon.hittest = false;
		HaSet(icon, 'width', HaBox.iconWidth + 'px');
		HaSet(icon, 'height', HaBox.iconHeight + 'px');
		HaSet(icon, 'x', HaBox.iconX + 'px');
		HaSet(icon, 'y', HaBox.iconY + 'px');
		HaSet(icon, 'horizontalAlign', 'left');
		HaSet(icon, 'verticalAlign', 'center');
		HaSet(icon, 'opacity', HaBox.iconOpacity);

		var label = $.CreatePanel('Label', group, id + 'Text');
		label.hittest = false;
		HaSet(label, 'width', HaBox.textWidth + 'px');
		HaSet(label, 'x', HaBox.textX + 'px');
		HaSet(label, 'y', HaBox.textY + 'px');
		HaSet(label, 'horizontalAlign', 'left');
		HaSet(label, 'verticalAlign', 'center');
		HaSet(label, 'lineHeight', HaBox.fontSize + 'px');
		HaSet(label, 'fontFamily', 'Stratum2');
		HaSet(label, 'fontWeight', 'bold');
		HaSet(label, 'fontSize', HaBox.fontSize + 'px');
		HaSet(label, 'color', HaBox.color);
		HaSet(label, 'letterSpacing', HaBox.letterSpacing + 'px');
		HaSet(label, 'textShadow', HaBox.textShadow);
		HaSet(label, 'marginLeft', HaBox.textMarginLeft + 'px');
		HaSet(label, 'textAlign', 'center');
		HaSet(label, 'textOverflow', 'shrink');
		label.AddClass('hud-colored');

		var bar = $.CreatePanel('Panel', group, id + 'Bar');
		bar.hittest = false;
		HaSet(bar, 'width', HaBox.barWidth + 'px');
		HaSet(bar, 'height', HaBox.barHeight + 'px');
		HaSet(bar, 'x', HaBox.barX + 'px');
		HaSet(bar, 'y', HaBox.barY + 'px');
		HaSet(bar, 'horizontalAlign', 'left');
		HaSet(bar, 'verticalAlign', 'center');
		HaSet(bar, 'backgroundColor', HaBox.barTrack);

		var fill = $.CreatePanel('Panel', bar, id + 'Fill');
		fill.hittest = false;
		HaSet(fill, 'height', '100%');
		HaSet(fill, 'width', '100%');
		HaSet(fill, 'horizontalAlign', 'left');
		HaSet(fill, 'verticalAlign', 'top');
		HaSet(fill, 'backgroundColor', HaTint());

		return {group: group, icon: icon, label: label, fill: fill};
	};

	var HaHealth = HaGroup('HAHealth', 'hpplate', HaBox.hpWidth, HaBox.hpBgSize);
	var HaArmor = HaGroup('HAArmor', 'armorplate', HaBox.armorWidth, null);

	PaintArt(HaHealth.icon, 'hpicon', {size: 'contain'});
	PaintArt(HaArmor.icon, 'armoricon', {size: 'contain'});
}

var HaGeneration = (typeof HaGeneration === 'undefined' ? 0 : HaGeneration) + 1;
var HaSaid = -1;

var HaRead = function (label) {
	if (!label)
		return null;
	try {
		var value = parseInt(label.text, 10);
		return isFinite(value) ? value : null;
	} catch (error) {
		return null;
	}
};

var HaShow = function (parts, value, max, critical) {
	if (!parts || value === null)
		return;
	if (parts.label.Value !== value) {
		parts.label.Value = value;
		parts.label.text = String(value);
		var pct = Math.max(0, Math.min(100, Math.round((value / max) * 100)));
		HaSet(parts.fill, 'width', pct + '%');
		if (critical !== undefined) {
			var lit = value <= HaBox.criticalAt;
			if (parts.label.Critical !== lit) {
				parts.label.Critical = lit;
				HaSet(parts.label, 'textShadow', lit ? HaBox.criticalShadow : HaBox.textShadow);
				HaSet(parts.fill, 'backgroundColor', lit ? HaBox.criticalFill : HaTint());
				parts.fill.SetHasClass('ha-critical', lit);
				if (parts.group) {
					parts.group.SetHasClass('ha-critical', lit);
					PaintArt(parts.group, lit ? 'hpredplate' : 'hpplate', {
						size: HaBox.hpBgSize,
						opacity: lit ? HaBox.criticalPlateOpacity : HaPlateOpacity(),
					});
				}
			}
		}
	}
};

var HaTick = function (generation) {
	if (generation !== HaGeneration)
		return;
		try {
			var owner = contextPanel.FindChildTraverse('jsHudHealthArmorAmmoMore');
			var healthLabel = contextPanel.FindChildTraverse('HAHealthText');
			if (owner && healthLabel) {
			var root = contextPanel.FindChildTraverse('HA');
			if (root) {
				var active = owner.BHasClass('HUD--HA--active');
				if (root.BHasClass('ha-active') !== active) {
					root.SetHasClass('ha-active', active);
					HaSet(root, 'visibility', active ? 'visible' : 'collapse');
				}
			}

			var health = {
				label: healthLabel,
				fill: contextPanel.FindChildTraverse('HAHealthFill'),
				group: contextPanel.FindChildTraverse('HAHealth'),
			};
			var armor = {
				label: contextPanel.FindChildTraverse('HAArmorText'),
				fill: contextPanel.FindChildTraverse('HAArmorFill'),
			};
			if (health.fill)
				HaShow(health, HaRead(HaSrcHealth), 100, true);
			if (armor.label && armor.fill)
				HaShow(armor, HaRead(HaSrcArmor), HaBox.armorMax);

			var main = contextPanel.FindChildTraverse('hud-HA-main');
			var icon = contextPanel.FindChildTraverse('HAArmorIcon');
			if (main && icon) {
				var wanted = main.BHasClass('HUD--has-helmet') ? 'helmeticon' : 'armoricon';
				if (icon.Src !== wanted) {
					icon.Src = wanted;
					PaintArt(icon, wanted, {size: 'contain'});
				}
			}

			if (HaSaid !== generation && owner.actuallayoutwidth > 0 && healthLabel.actuallayoutwidth > 0) {
				HaSaid = generation;
			}
		}
	} catch (error) {
			}
	$.Schedule(0.1, function () {
		HaTick(generation);
	});
};

$.Schedule(0.0, (function (generation) {
	return function () {
		HaTick(generation);
	};
})(HaGeneration));
]===],
    ["icon.js"] = [===[var IconUtil = (function () {

	var FallbackPng = function (elIconPanel, basePath) {
		var tried = false;
		try {
			$.RegisterEventHandler('ImageFailedLoad', elIconPanel, function () {
				if (tried)
					return;
				tried = true;
				elIconPanel.SetImage(basePath + '.png');
			});
		} catch (error) {
		}
	};

	return {
		FallbackPng: FallbackPng,
	};
})();
]===],
    ["joinpanel.js"] = [===[var Jp = {
	width: 700,
	height: 56,
	top: 86,
	inset: 2,
	logoScale: 0.75,
	logoOpacity: '0.95',
	logoTop: 2,
	logoLeft: 0,
	verb: 'Playing on team',
	fontSize: 34,
	fontWeight: 'black',
	textTop: 6,
	textOpacity: '0.85',
	letterSpacing: 0,
	color: '#ffffff',
	logoGap: 8,

	fade: 0.6,
	rise: -35,
	hold: 3.0,
	permanent: false,
};

var JpSides = {
	ct: {
		cls: 'HUD--team--ct',
		logo: 's2r://panorama/images/icons/ct_logo.vsvg',
		side: '#counter-terrorists',
		english: 'Counter-Terrorists',
	},
	t: {
		cls: 'HUD--team--terrorist',
		logo: 's2r://panorama/images/icons/t_logo.vsvg',
		side: '#terrorists',
		english: 'Terrorists',
	},
};

var JpLocalize = function (token) {
	try {
		var text = $.Localize(token);
		return (text && text.length > 1 && text.charAt(0) !== '#') ? text : null;
	} catch (error) {
		return null;
	}
};

var JpTextCache = (typeof JpTextCache === 'undefined' ? {} : JpTextCache);

var JpText = function (which) {
	var key = which + '|' + Jp.verb;
	if (JpTextCache[key])
		return JpTextCache[key];
	var side = JpSides[which];
	var whole = (Jp.verb + ' ' + (JpLocalize(side.side) || side.english)).toUpperCase();
	JpTextCache[key] = whole;
	return whole;
};

var JpTeam = function () {
	try {
		var team = GameStateAPI.GetPlayerTeamNumber(GameStateAPI.GetLocalPlayerXuid());
		if (team === 3)
			return 'ct';
		if (team === 2)
			return 't';
	} catch (error) {
	}
	for (var at = contextPanel; at; at = at.GetParent()) {
		if (at.BHasClass(JpSides.ct.cls))
			return 'ct';
		if (at.BHasClass(JpSides.t.cls))
			return 't';
	}
	for (var cls of [JpSides.ct.cls, JpSides.t.cls]) {
		if (contextPanel.FindChildrenWithClassTraverse(cls).length)
			return cls === JpSides.ct.cls ? 'ct' : 't';
	}
	return null;
};

var JpOld = contextPanel.FindChildTraverse('Join');
if (JpOld)
	JpOld.DeleteAsync(0);

var JpBar = $.CreatePanel('Panel', contextPanel, 'Join');
JpBar.hittest = false;
JpBar.style.width = Jp.width + 'px';
JpBar.style.height = Jp.height + 'px';
JpBar.style.horizontalAlign = 'center';
JpBar.style.verticalAlign = 'top';
JpBar.style.marginTop = Jp.top + 'px';
JpBar.style.zIndex = '21';
JpBar.style.overflow = 'noclip';
JpBar.style.opacity = '0.0';
JpBar.style.transform = 'translateY(' + Jp.rise + 'px)';
JpBar.style.transitionProperty = 'opacity, transform';
JpBar.style.transitionDuration = Jp.fade + 's, ' + Jp.fade + 's';
JpBar.style.transitionTimingFunction = 'linear';
PaintArt(JpBar, 'joinplate');

var JpLogoBox = Math.round(Jp.height * Jp.logoScale);
var JpLogo = $.CreatePanel('Image', JpBar, 'JoinLogo');
JpLogo.hittest = false;
JpLogo.SetImage(JpSides.ct.logo);
JpLogo.style.width = JpLogoBox + 'px';
JpLogo.style.height = JpLogoBox + 'px';
JpLogo.style.horizontalAlign = 'left';
JpLogo.style.verticalAlign = 'top';
JpLogo.style.marginLeft = (Jp.inset + Jp.logoLeft) + 'px';
JpLogo.style.marginTop = (Jp.inset + Jp.logoTop) + 'px';
JpLogo.style.opacity = Jp.logoOpacity;

var JpTextLeft = Jp.inset + JpLogoBox + Jp.logoGap;
var JpTextWidth = Jp.width - JpTextLeft - 12;

var JpTextZone = $.CreatePanel('Panel', JpBar, 'JoinTextZone');
JpTextZone.hittest = false;
JpTextZone.style.width = JpTextWidth + 'px';
JpTextZone.style.height = '100%';
JpTextZone.style.marginLeft = JpTextLeft + 'px';
JpTextZone.style.overflow = 'noclip';

var JpLabel = $.CreatePanel('Label', JpTextZone, 'JoinText');
JpLabel.hittest = false;
JpLabel.style.width = 'fit-children';
JpLabel.style.height = (Jp.fontSize + 4) + 'px';
JpLabel.style.horizontalAlign = 'center';
JpLabel.style.verticalAlign = 'top';
JpLabel.style.marginTop = (Jp.inset + Jp.textTop) + 'px';
JpLabel.style.textAlign = 'center';
JpLabel.style.fontFamily = 'Stratum2';
JpLabel.style.fontWeight = Jp.fontWeight;
JpLabel.style.fontSize = Jp.fontSize + 'px';
JpLabel.style.lineHeight = Jp.fontSize + 'px';
JpLabel.style.letterSpacing = Jp.letterSpacing + 'px';
JpLabel.style.color = Jp.color;
JpLabel.style.opacity = Jp.textOpacity;
JpLabel.style.whiteSpace = 'nowrap';

var JpFitFont = function (label, max) {
	if (!label)
		return;
	var size = Jp.fontSize;
	var tries = 0;
	var step = function () {
		if (!label.IsValid())
			return;
		var scale = label.actualuiscale_x || 1;
		var width = label.actuallayoutwidth / scale;
		if (width > 0 && (width <= max || tries >= 6))
			return;
		if (width > 0)
			tries += 1;
		size -= 2;
		if (size < 18)
			return;
		label.style.fontSize = size + 'px';
		label.style.lineHeight = size + 'px';
		label.style.height = (size + 4) + 'px';
		$.Schedule(0.05, step);
	};
	$.Schedule(0.05, step);
};

var JpHide = function (bar) {
	if (!bar || !bar.IsValid() || !bar.Shown)
		return;
	bar.Shown = false;
	bar.style.opacity = '0.0';
	bar.style.transform = 'translateY(' + Jp.rise + 'px)';
};

var JpSerial = (typeof JpSerial === 'undefined' ? 0 : JpSerial);

var JpShow = function (bar, which) {
	var side = JpSides[which];
	var logo = bar.FindChildTraverse('JoinLogo');
	var label = bar.FindChildTraverse('JoinText');
	if (!logo || !label)
		return;
	logo.SetImage(side.logo);
	label.text = JpText(which);
	label.FitSize = Jp.fontSize;
	label.style.fontSize = Jp.fontSize + 'px';
	label.style.lineHeight = Jp.fontSize + 'px';
	label.style.height = (Jp.fontSize + 4) + 'px';
	JpFitFont(label, JpTextWidth - 8);
	bar.Shown = true;
	bar.style.opacity = '1.0';
	bar.style.transform = 'translateY(0px)';

	JpSerial = JpSerial + 1;
	if (Jp.permanent) {
		return;
	}
	var mine = JpSerial;
	$.Schedule(Jp.fade + Jp.hold, function () {
		try {
			if (mine === JpSerial)
				JpHide(bar);
		} catch (error) {
					}
	});
};

var JpGates = {
	live: 'HUD--HA--active',
	intro: 'HUD--team-preview-camera',
};

var JpGamephase = function () {
	try {
		var data = GameStateAPI.GetTimeDataJSO();
		return data ? Number(data.gamephase) : -1;
	} catch (error) {
		return -1;
	}
};

var JpReady = function () {
	if (JpGamephase() !== 2 && JpGamephase() !== 3)
		return false;
	for (var at = contextPanel; at; at = at.GetParent())
		if (at.BHasClass(JpGates.intro))
			return false;
	var owner = contextPanel.FindChildTraverse('jsHudHealthArmorAmmoMore');
	return !!owner && owner.BHasClass(JpGates.live);
};

var JpWatch = function () {
	var bar = contextPanel.FindChildTraverse('Join');
	if (!bar)
		return;
	var team = JpTeam();
	var ready = JpReady();

	if (typeof bar.Seed === 'undefined') {
		bar.Seed = team;

		bar.Owed = !!team;
		return;
	}

	if (bar.Seed !== team) {
		bar.Seed = team;
		bar.Owed = !!team;
	}

	if (!bar.Owed || !team || !ready)
		return;
	bar.Owed = false;
	JpShow(bar, team);
};

var JpGeneration = (typeof JpGeneration === 'undefined' ? 0 : JpGeneration) + 1;

var JpTick = function (generation) {
	if (generation !== JpGeneration)
		return;
	try {
		JpWatch();
	} catch (error) {
			}
	$.Schedule(0.25, function () {
		JpTick(generation);
	});
};

$.Schedule(0.0, (function (generation) {
	return function () {
		JpTick(generation);
	};
})(JpGeneration));
]===],
    ["killcount.js"] = [===[var Kc = {

	badgeWidth: 23,
	badgeHeight: 23,
	pitch: 26,
	slots: 5,
	firstX: 1619,
	anchorRight: 1694,
	fxPark: -3000,
	bottom: 1080 - 1050,
	skullBox: 17,
	skullSrc: '',
	skullY: -1,
	skullX: 0,
	countSize: '17px',
	countColor: '#e8e4d2',
};

var KcRowRight = 1920 - Kc.anchorRight - (Kc.pitch - Kc.badgeWidth);
var KcHiddenIds = ['hud-HA__kills', 'hud-HA__kills--fx', 'hud-HA__Specialkills--fx'];

var KcHideStock = function () {
	var cards = null;
	for (var at = 0; at < KcHiddenIds.length; ++at) {
		var panel = contextPanel.FindChildTraverse(KcHiddenIds[at]);
		if (!panel)
			continue;
		panel.style.visibility = 'collapse';
		if (at === 0)
			cards = panel;
	}
	return cards;
};

var KcParkFx = function () {
	var parked = 0;
	for (var at = 1; at < KcHiddenIds.length; ++at) {
		var fx = contextPanel.FindChildTraverse(KcHiddenIds[at]);
		if (fx && !fx.BHasClass('fx-parked')) {
			fx.AddClass('fx-parked');
			fx.style.y = Kc.fxPark + 'px';
			++parked;
		}
	}
	return parked;
};

var KcListeners = ['HUD--on-kill--listener', 'HUD--health--on-damage--listener',
	'HUD--has-armor--on-pickup--listener', 'HUD--on-reload--listener',
	'HUD--weapon--on-change--listener', 'HUD--weapon--on-fired--listener'];

var KcGlowNoted = false;

var KcNoGlow = function (cards) {
	var owner = cards.GetParent();
	if (!owner)
		return;

	var stripped = 0;
	for (var at = 0; at < KcListeners.length; ++at) {
		var listener = KcListeners[at];
		var trigger = listener.substring(0, listener.length - '--listener'.length);
		var hits = owner.FindChildrenWithClassTraverse(listener);
		for (var one = 0; one < hits.length; ++one) {
			hits[one].RemoveClass(listener);
			++stripped;
		}
		var lit = owner.FindChildrenWithClassTraverse(trigger);
		for (var two = 0; two < lit.length; ++two) {
			lit[two].RemoveClass(trigger);
			++stripped;
		}
	}

	if (stripped && !KcGlowNoted) {
		KcGlowNoted = true;
	}
};

var KcCount = function (cards) {
	for (var at = cards; at; at = at.GetParent()) {
		if (at.BHasClass('HUD--NumKills--extra'))
			return Kc.slots + 1;
		for (var n = Kc.slots; n >= 1; --n)
			if (at.BHasClass('HUD--NumKills--' + n))
				return n;
	}
	return 0;
};

var KcOldRow = contextPanel.FindChildTraverse('Kills');
if (KcOldRow) {
	KcOldRow.DeleteAsync(0);
}

var KcBuild = function () {
	var row = $.CreatePanel('Panel', contextPanel, 'Kills');
	row.hittest = false;
	row.style.horizontalAlign = 'right';
	row.style.verticalAlign = 'bottom';
	row.style.marginRight = KcRowRight + 'px';
	row.style.marginBottom = Kc.bottom + 'px';
	row.style.width = 'fit-children';
	row.style.height = Kc.badgeHeight + 'px';
	row.style.flowChildren = 'right';
	row.style.zIndex = '21';
	var more = $.CreatePanel('Label', row, 'KillMore');
	more.hittest = false;
	more.style.fontFamily = 'Stratum2';
	more.style.fontWeight = 'bold';
	more.style.fontSize = Kc.countSize;
	more.style.color = Kc.countColor;
	more.style.verticalAlign = 'center';
	more.style.textShadow = '1px 1px 0px #000000';
	more.style.marginRight = '2px';
	more.style.visibility = 'collapse';
	more.text = '+';

	for (var at = 0; at < Kc.slots; ++at) {
		var badge = $.CreatePanel('Panel', row, 'Kill' + at);
		badge.hittest = false;
		badge.style.width = Kc.badgeWidth + 'px';
		badge.style.height = Kc.badgeHeight + 'px';
		badge.style.marginRight = (Kc.pitch - Kc.badgeWidth) + 'px';
		badge.style.visibility = 'collapse';
		PaintArt(badge, 'killbadge');
		var skull = $.CreatePanel('Panel', badge, 'KillSkull' + at);
		skull.hittest = false;
		skull.style.width = Kc.skullBox + 'px';
		skull.style.height = Kc.skullBox + 'px';
		skull.style.horizontalAlign = 'center';
		skull.style.verticalAlign = 'center';
		skull.style.x = Kc.skullX + 'px';
		skull.style.y = Kc.skullY + 'px';
		if (Kc.skullSrc) {
			skull.style.backgroundImage = 'url("' + Kc.skullSrc + '")';
			skull.style.backgroundSize = 'contain';
			skull.style.backgroundRepeat = 'no-repeat';
			skull.style.backgroundPosition = 'center center';
			skull.style.washColor = '#ffffff';
		} else {
			PaintArt(skull, 'aliveskull', {size: 'contain'});
		}
	}

	return row;
};

var KcApply = function () {
	var cards = KcHideStock();
	if (!cards)
		return false;
	KcNoGlow(cards);

	var row = contextPanel.FindChildTraverse('Kills');
	if (!row)
		return false;
	var kills = KcCount(cards);
	var marker = 'kills-' + kills;
	if (row.BHasClass(marker))
		return true;

	for (var stale = 0; stale <= Kc.slots + 1; ++stale)
		row.RemoveClass('kills-' + stale);
	row.AddClass(marker);

	var shown = Math.min(kills, Kc.slots);
	for (var at = 0; at < Kc.slots; ++at) {
		var badge = row.FindChildTraverse('Kill' + at);
		if (badge)
			badge.style.visibility = at < shown ? 'visible' : 'collapse';
	}
	var more = row.FindChildTraverse('KillMore');
	if (more)
		more.style.visibility = kills > Kc.slots ? 'visible' : 'collapse';

	return true;
};

KcBuild();

KcParkFx();
KcApply();
var KcGeneration = (typeof KcGeneration === 'undefined' ? 0 : KcGeneration) + 1;

var KcTick = function (generation) {
	if (generation !== KcGeneration)
		return;
	try {
		KcApply();
	} catch (error) {
			}
	$.Schedule(0.25, function () {
		KcTick(generation);
	});
};

$.Schedule(0.25, (function (generation) {
	return function () {
		KcTick(generation);
	};
})(KcGeneration));
]===],
    ["messages.js"] = [===[var Msg = {
	width: 440,
	height: 107,
	nudge: 130,
	raise: 173,
	fade: '0.2s',
	park: -3000,
	bg: 'gradient( linear, 0% 0%, 100% 0%, from( #000000BB ), color-stop( 0.7, #000000BB ), to( #00000000 ) )',
	bgStart: 'gradient( linear, 0% 0%, 100% 0%, from( #000000BB ), color-stop( 0.2, #00000000 ), to( #00000000 ) )',

	icon: 108,
	iconLeft: -54,
	iconEdge: -2,
	textLeft: 7,

	alertColor: '#ff5454',
	alertSize: 24,
	textSize: 22,
	textLine: 23,
	textMax: 340,
	textOpacity: '0.9',
	textTop: 9,
	textBottom: 8,

	chatBottom: 54,
	chatBg: '#00000099',
};

var MsgOnce = function (panel, marker, write) {
	if (!panel || panel.BHasClass(marker))
		return false;
	panel.AddClass(marker);
	write(panel);
	return true;
};

var MsgAlive = function (panel) {
	try {
		return !!(panel && panel.IsValid());
	} catch (error) {
		return false;
	}
};

var MsgAlertText = function () {
	var text = $.Localize('#UI_Alert');
	return (!text || text.charAt(0) === '#') ? 'ALERT' : text;
};

var MsgSources = [];
for (var MsgFound of contextPanel.FindChildrenWithClassTraverse('hud-hint')) {
	MsgSources.push({
		root: MsgFound,
		label: MsgFound.FindChildTraverse('JsHintLabel'),
		high: MsgFound.BHasClass('high-priority'),
	});
	MsgOnce(MsgFound, 'msg-parked', function (panel) {
		panel.style.y = Msg.park + 'px';
	});
}

MsgSources.sort(function (a, b) {
	return (b.high ? 1 : 0) - (a.high ? 1 : 0);
});

var MsgOldBar = contextPanel.FindChildTraverse('Hint');
if (MsgOldBar)
	MsgOldBar.DeleteAsync(0);

var MsgBar = $.CreatePanel('Panel', contextPanel, 'Hint');
MsgBar.hittest = false;
MsgBar.style.width = Msg.width + 'px';
MsgBar.style.height = Msg.height + 'px';
MsgBar.style.flowChildren = 'right';
MsgBar.style.horizontalAlign = 'center';
MsgBar.style.verticalAlign = 'bottom';
MsgBar.style.marginBottom = Msg.raise + 'px';
MsgBar.style.marginLeft = Msg.nudge + 'px';
MsgBar.style.backgroundColor = Msg.bgStart;
MsgBar.style.overflow = 'noclip';
MsgBar.style.opacity = '0.0';

MsgBar.style.transitionProperty = 'background-color';
MsgBar.style.transitionDuration = Msg.fade;
MsgBar.style.transitionTimingFunction = 'ease-in-out';

var MsgIcon = $.CreatePanel('Panel', MsgBar, 'HintIcon');
MsgIcon.hittest = false;
MsgIcon.style.width = Msg.icon + 'px';
MsgIcon.style.height = Msg.icon + 'px';
MsgIcon.style.marginLeft = Msg.iconLeft + 'px';
MsgIcon.style.marginTop = Msg.iconEdge + 'px';
MsgIcon.style.marginBottom = Msg.iconEdge + 'px';
MsgIcon.style.verticalAlign = 'center';
PaintArt(MsgIcon, 'alerticon', {size: 'contain'});

var MsgColumn = $.CreatePanel('Panel', MsgBar, 'HintText');
MsgColumn.hittest = false;
MsgColumn.style.flowChildren = 'down';
MsgColumn.style.verticalAlign = 'top';
MsgColumn.style.horizontalAlign = 'left';
MsgColumn.style.height = 'fit-children';
MsgColumn.style.marginLeft = Msg.textLeft + 'px';
MsgColumn.style.paddingTop = Msg.textTop + 'px';
MsgColumn.style.paddingBottom = Msg.textBottom + 'px';

var MsgAlert = $.CreatePanel('Label', MsgColumn, 'HintAlert');
MsgAlert.hittest = false;
MsgAlert.text = MsgAlertText();
MsgAlert.style.color = Msg.alertColor;
MsgAlert.style.fontFamily = 'Stratum2';
MsgAlert.style.fontWeight = 'medium';
MsgAlert.style.fontSize = Msg.alertSize + 'px';
MsgAlert.style.letterSpacing = '0px';
MsgAlert.style.paddingBottom = '1px';
MsgAlert.style.horizontalAlign = 'left';
MsgAlert.style.textAlign = 'left';

var MsgLabel = $.CreatePanel('Label', MsgColumn, 'HintLabel');
MsgLabel.hittest = false;
MsgLabel.style.color = '#ffffff';
MsgLabel.style.opacity = Msg.textOpacity;
MsgLabel.style.fontFamily = 'Stratum2';
MsgLabel.style.fontWeight = 'medium';
MsgLabel.style.fontSize = Msg.textSize + 'px';
MsgLabel.style.lineHeight = Msg.textLine + 'px';
MsgLabel.style.maxWidth = Msg.textMax + 'px';
MsgLabel.style.letterSpacing = '0px';
MsgLabel.style.horizontalAlign = 'left';
MsgLabel.style.textAlign = 'left';

var MsgPlain = function (text) {
	return text.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]*>/g, '');
};

var MsgWatch = function () {
	for (var at = MsgSources.length - 1; at >= 0; --at) {
		var parked = MsgSources[at];
		if (!MsgAlive(parked.root)) {
			MsgSources.splice(at, 1);
			continue;
		}
		try {
			MsgOnce(parked.root, 'msg-parked', function (panel) {
				panel.style.y = Msg.park + 'px';
			});
		} catch (error) {
		}
	}

	if (!MsgSources.length) {
		for (var fresh of contextPanel.FindChildrenWithClassTraverse('hud-hint')) {
			var freshLabel = null;
			var freshHigh = false;
			try {
				freshLabel = fresh.FindChildTraverse('JsHintLabel');
				freshHigh = fresh.BHasClass('high-priority');
			} catch (error) {
				continue;
			}
			try {
				fresh.style.y = Msg.park + 'px';
				fresh.AddClass('msg-parked');
			} catch (error) {
			}
			MsgSources.push({root: fresh, label: freshLabel, high: freshHigh});
		}
		MsgSources.sort(function (a, b) {
			return (b.high ? 1 : 0) - (a.high ? 1 : 0);
		});
	}

	var live = null;
	var text = '';
	for (var src of MsgSources) {
		if (!MsgAlive(src.root))
			continue;
		var visible = false;
		try {
			visible = src.root.BHasClass('hud-hint--visible');
		} catch (error) {
			continue;
		}
		if (!visible)
			continue;

		var found = '';
		try {
			found = (src.label && src.label.text) || '';
		} catch (error) {
			found = '';
		}
		if (!found)
			continue;
		live = src;
		text = MsgPlain(found);
		break;
	}

	var shown = live ? 1 : 0;
	if (MsgBar.Shown !== shown) {
		MsgBar.Shown = shown;
		MsgBar.style.opacity = shown ? '1.0' : '0.0';
		MsgBar.style.backgroundColor = shown ? Msg.bg : Msg.bgStart;
	}
	if (!live)
		return;

	if (MsgLabel.Text !== text) {
		MsgLabel.Text = text;
		MsgLabel.text = text;
	}
};

var MsgRadioDress = function () {
	var root = contextPanel.FindChildTraverse('HudRadio');
	if (!root)
		return;
	MsgOnce(root.FindChildTraverse('RadioPanelBG'), 'msg-radio-bg', function (panel) {
		panel.style.width = '100%';
		panel.style.height = '100%';
		panel.style.backgroundColor = '#000000';
		panel.style.opacity = '0.45';
	});
	MsgOnce(root.FindChildTraverse('RadioPanel'), 'msg-radio-box', function (panel) {
		panel.style.fontFamily = 'Stratum2';
		panel.style.fontWeight = 'normal';
		panel.style.backgroundColor = '#000000b3';
		panel.style.paddingBottom = '12px';
		panel.style.margin = '8px';
	});
	for (var opts of root.FindChildrenWithClassTraverse('RadioTextOptions'))
		MsgOnce(opts, 'msg-radio-opt', function (panel) {
			panel.style.fontSize = '18px';
			panel.style.color = '#CCCCCC';
			panel.style.margin = '0px 0px 0px 12px';
		});
};

var MsgRadioHeads = function () {
	var root = contextPanel.FindChildTraverse('HudRadio');
	if (!root)
		return;
	for (var head of root.FindChildrenWithClassTraverse('RadioTextHeading'))
		MsgOnce(head, 'msg-radio-head', function (panel) {
			panel.style.fontWeight = 'bold';
			panel.style.fontSize = '24px';
			panel.style.color = '#999999';
			panel.style.textTransform = 'uppercase';
			panel.style.letterSpacing = '0.5px';
			panel.style.textShadow = '1px 1px 1px 1.0 #000000';
		});
};

var MsgGeneration = (typeof MsgGeneration === 'undefined' ? 0 : MsgGeneration) + 1;

var MsgTick = function (generation) {
	if (generation !== MsgGeneration)
		return;
	try {
		MsgWatch();
	} catch (error) {
			}
	try {
		MsgRadioHeads();
	} catch (error) {
			}
	try {
		MsgRadioDress();
	} catch (error) {
			}
	$.Schedule(0.1, function () {
		MsgTick(generation);
	});
};

$.Schedule(0.1, (function (generation) {
	return function () {
		MsgTick(generation);
	};
})(MsgGeneration));
]===],
    ["money.js"] = [===[var OldRoot = contextPanel.FindChildTraverse('MoneyRoot');
if (OldRoot)
	OldRoot.DeleteAsync(0);

var Root = $.CreatePanel('Panel', contextPanel, 'MoneyRoot');
Root.style.width = '100%';
Root.style.height = '100%';
Root.style.zIndex = '20';
Root.hittest = false;

var MoneyBase = {
	left: 0,
	top: 385,
	width: 250,
	height: 39,
	fontSize: 31,
	rowLeft: 9,
	iconSize: 28,
	iconGap: 26,
};

var PlateAlpha = 'f6';
var PlateGradient = 'gradient( linear, 100% 0%, 0% 0%, from( #00000000 ), color-stop( 0.25, #000000' + PlateAlpha + ' ), to( #000000' + PlateAlpha + ' ) )';
var MoneyPlate = $.CreatePanel('Panel', Root, 'Money');

MoneyPlate.style.horizontalAlign = 'left';
MoneyPlate.style.verticalAlign = 'top';
MoneyPlate.style.marginLeft = MoneyBase.left + 'px';
MoneyPlate.style.marginTop = MoneyBase.top + 'px';
MoneyPlate.style.width = MoneyBase.width + 'px';
MoneyPlate.style.height = MoneyBase.height + 'px';
MoneyPlate.style.backgroundColor = PlateGradient;
MoneyPlate.style.visibility = 'collapse';

var MoneyApplyAlpha = function (alpha) {
	if (typeof alpha !== 'number' || !isFinite(alpha) || !MoneyPlate)
		return false;
	alpha = Math.max(0, Math.min(1, alpha));
	var scaled = Math.round(parseInt(PlateAlpha, 16) * alpha);
	var hex = ('0' + scaled.toString(16)).slice(-2);
	var gradient = 'gradient( linear, 100% 0%, 0% 0%, from( #00000000 ), color-stop( 0.25, #000000'
		+ hex + ' ), to( #000000' + hex + ' ) )';
	if (MoneyPlate.Gradient === gradient)
		return true;
	MoneyPlate.Gradient = gradient;
	MoneyPlate.style.backgroundColor = gradient;
	return true;
};

var MoneyRow = $.CreatePanel('Panel', MoneyPlate, 'MoneyRow');
MoneyRow.style.flowChildren = 'right';
MoneyRow.style.width = 'fit-children';
MoneyRow.style.height = '100%';
MoneyRow.style.horizontalAlign = 'left';
MoneyRow.style.marginLeft = MoneyBase.rowLeft + 'px';

var MoneyBuyIcon = $.CreatePanel('Image', MoneyRow, 'MoneyBuyIcon');
MoneyBuyIcon.SetImage('s2r://panorama/images/icons/ui/buyzone.vsvg');
MoneyBuyIcon.AddClass('additive');
MoneyBuyIcon.style.width = MoneyBase.iconSize + 'px';
MoneyBuyIcon.style.height = MoneyBase.iconSize + 'px';
MoneyBuyIcon.style.marginRight = MoneyBase.iconGap + 'px';
MoneyBuyIcon.style.verticalAlign = 'center';
MoneyBuyIcon.style.washColor = '#7CC213';
MoneyBuyIcon.style.opacity = '0.0';

var MoneyText = $.CreatePanel('Label', MoneyRow, 'MoneyText');
MoneyText.style.verticalAlign = 'center';
MoneyText.style.fontFamily = 'Stratum2 Bold Monodigit';
MoneyText.style.fontSize = MoneyBase.fontSize + 'px';
MoneyText.style.color = '#ffffffff';
MoneyText.style.textShadow = '2px 1px 2px 1.0 #000000cc';

var Cs2Money = contextPanel.FindChildTraverse('HudMoney');
if (!Cs2Money) {
} else {
	var ReadMoney = function () {
		try {
			return $.Localize('#buymenu_money', Cs2Money);
		} catch (error) {
			return null;
		}
	};

	var ShowMoney = function (amount) {
		if (typeof amount === 'number') {
			MoneyText.text = '$' + amount;
			return;
		}
		var formatted = ReadMoney();
		if (formatted && formatted.length > 1)
			MoneyText.text = formatted;
	};

	ShowMoney(null);

	if (typeof MoneyHandler !== 'undefined' && MoneyHandler !== null)
		$.UnregisterEventHandler('UpdateHudMoney', Cs2Money, MoneyHandler);

	var MoneyHandler = $.RegisterEventHandler('UpdateHudMoney', Cs2Money, function (amount) {
		ShowMoney(amount);
	});

	for (var drawn of Cs2Money.FindChildrenWithClassTraverse('money-text'))
		drawn.style.visibility = 'collapse';
}

var HideBuyMenuMoney = function () {
	for (var id of ['BuyMenuMoney', 'buymenu-info-money']) {
		var panel = contextPanel.FindChildTraverse(id);
		if (!panel || panel.BHasClass('money-hidden'))
			continue;
		var parts = panel.FindChildrenWithClassTraverse('money-text');
		if (!parts.length)
			continue;
		for (var at = 0; at < parts.length; ++at)
			parts[at].style.visibility = 'collapse';
		panel.AddClass('money-hidden');
	}
};
var MoneyDrawn = function () {
	var panel = contextPanel.FindChildTraverse('HudMoney');
	if (!panel)
		return false;
	for (var at = panel; at && at !== contextPanel; at = at.GetParent()) {
		if (!at.visible || at.BIsTransparent())
			return false;
	}
	return true;
};

var MarkState = function (panel, marker, on) {
	if (panel.BHasClass(marker) === on)
		return false;
	if (on)
		panel.AddClass(marker);
	else
		panel.RemoveClass(marker);
	return true;
};

var HudTick = function () {
	try {
		HideBuyMenuMoney();

		var plate = contextPanel.FindChildTraverse('Money');
		var icon = contextPanel.FindChildTraverse('MoneyBuyIcon');
		var owner = contextPanel.FindChildTraverse('HudMoney');
		if (plate && icon && owner) {
			var drawn = MoneyDrawn();
			if (MarkState(plate, 'money-drawn', drawn)) {
				plate.style.visibility = drawn ? 'visible' : 'collapse';
			}
			var inBuyZone = owner.BHasClass('money__in-buy-zone');
			if (MarkState(icon, 'buy-shown', inBuyZone)) {
				icon.style.opacity = inBuyZone ? '0.8' : '0.0';
			}
		}
	} catch (error) {
			}
	$.Schedule(0.25, function () {
		HudTick();
	});
};

if (typeof HudStarted === 'undefined') {
	var HudStarted = true;
	$.Schedule(0.25, function () {
		HudTick();
	});
}
]===],
    ["progressbar.js"] = [===[var Pb = {
	width: 475,
	marginLeft: 130,
	marginTop: 32,

	anchorHeight: '50%',
	bg: 'gradient( linear, 0% 0%, 100% 0%, from( #000000BB ),' + ' color-stop( 0.7, #000000BB ), to( #00000000 ) )',

	iconSize: 114,
	iconMargin: -56,

	rowMarginLeft: 8,
	rowMarginTop: 11,

	titleFont: 24,
	titleColor: '#FFFFFF',
	timeFont: 24,
	timeColor: '#ff6060',

	textWidth: 360,
	trackWidth: 230,
	trackHeight: 13,
	trackMarginLeft: 0,
	trackBg: 'gradient( linear, 0% 0%, 100% 0%, from( #26262676 ),' + ' color-stop( 0.5, #26262676 ), to( #00000000 ) )',

	fillHeight: 9,
	fillColor: '#ff2222FF',

	infoFont: 22,
	infoColor: '#ffffff',
	infoOpacity: '0.9',
	infoMarginLeft: 8,
	infoMarginTop: 3,

	fade: 0.2,
	park: -3000,
	titleFallback: 'Defuse Time:',
};

var PbFailures = {};

var PbSet = function (panel, property, value) {
	if (!panel)
		return;
	try {
		panel.style[property] = value;
	} catch (error) {
		if (!PbFailures[property]) {
			PbFailures[property] = true;
					}
	}
};

var PbLocalize = function (token) {
	var text = $.Localize(token);
	return (text && text.length > 1 && text.charAt(0) !== '#') ? text : null;
};

var PbTitleCache = (typeof PbTitleCache === 'undefined' ? null : PbTitleCache);

var PbTitleText = function () {
	if (!PbTitleCache)
		PbTitleCache = PbLocalize('#SFUIHUD_InfoPanel_DefuseTitle') || Pb.titleFallback;
	return PbTitleCache;
};

var PbSeconds = function (text) {
	var raw = String(text === undefined || text === null ? '' : text).trim();
	if (!raw)
		return null;
	var parts = raw.split(':');
	var total = 0;
	for (var at = 0; at < parts.length; ++at) {
		var piece = parseFloat(parts[at]);
		if (!isFinite(piece) || piece < 0)
			return null;
		total = total * 60 + piece;
	}
	return total;
};

var PbFraction = function (remaining, total) {
	if (!(total > 0) || remaining === null || remaining === undefined)
		return null;
	var fraction = remaining / total;
	return fraction < 0 ? 0 : (fraction > 1 ? 1 : fraction);
};

var PbAdvance = function (shown, fraction) {
	if (fraction === null)
		return null;
	return (shown === undefined || fraction <= shown) ? fraction : null;
};

var PbPark = function (owner) {
	if (!owner || owner.BHasClass('progress-parked'))
		return;
	owner.AddClass('progress-parked');
	PbSet(owner, 'y', Pb.park + 'px');
};

var PbOld = contextPanel.FindChildTraverse('ProgressAnchor');
if (PbOld)
	PbOld.DeleteAsync(0);

var PbAnchor = $.CreatePanel('Panel', contextPanel, 'ProgressAnchor');
PbAnchor.hittest = false;
PbAnchor.hittestchildren = false;
PbSet(PbAnchor, 'width', '100%');
PbSet(PbAnchor, 'height', Pb.anchorHeight);
PbSet(PbAnchor, 'horizontalAlign', 'center');
PbSet(PbAnchor, 'verticalAlign', 'bottom');
PbSet(PbAnchor, 'overflow', 'noclip');
PbSet(PbAnchor, 'zIndex', '20');

var PbBar = $.CreatePanel('Panel', PbAnchor, 'Progress');
PbBar.hittest = false;
PbSet(PbBar, 'width', Pb.width + 'px');
PbSet(PbBar, 'height', 'fit-children');
PbSet(PbBar, 'horizontalAlign', 'center');
PbSet(PbBar, 'verticalAlign', 'top');
PbSet(PbBar, 'marginTop', Pb.marginTop + 'px');
PbSet(PbBar, 'marginLeft', Pb.marginLeft + 'px');
PbSet(PbBar, 'backgroundColor', Pb.bg);
PbSet(PbBar, 'flowChildren', 'right');
PbSet(PbBar, 'overflow', 'noclip');
PbSet(PbBar, 'opacity', '0.0');
PbSet(PbBar, 'transitionProperty', 'opacity');
PbSet(PbBar, 'transitionDuration', Pb.fade + 's');
PbSet(PbBar, 'transitionTimingFunction', 'linear');

var PbIcon = $.CreatePanel('Panel', PbBar, 'ProgressIcon');
PbIcon.hittest = false;
PbSet(PbIcon, 'width', Pb.iconSize + 'px');
PbSet(PbIcon, 'height', Pb.iconSize + 'px');
PbSet(PbIcon, 'marginLeft', Pb.iconMargin + 'px');
PbSet(PbIcon, 'verticalAlign', 'center');
PbSet(PbIcon, 'zIndex', '1');
PaintArt(PbIcon, 'alerticon', {size: 'contain'});

var PbWarmOld = contextPanel.FindChildTraverse('ProgressWarm');
if (PbWarmOld)
	PbWarmOld.DeleteAsync(0);

var PbWarm = $.CreatePanel('Panel', contextPanel, 'ProgressWarm');
PbWarm.hittest = false;
PbWarm.hittestchildren = false;
PbSet(PbWarm, 'width', Pb.iconSize + 'px');
PbSet(PbWarm, 'height', Pb.iconSize + 'px');
PbSet(PbWarm, 'y', Pb.park + 'px');

for (var PbToken of ['defuseicon', 'alerticon']) {
	var PbWarmPanel = $.CreatePanel('Panel', PbWarm, 'ProgressWarm_' + PbToken);
	PbWarmPanel.hittest = false;
	PbSet(PbWarmPanel, 'width', Pb.iconSize + 'px');
	PbSet(PbWarmPanel, 'height', Pb.iconSize + 'px');
	PaintArt(PbWarmPanel, PbToken, {size: 'contain'});
}

var PbCol = $.CreatePanel('Panel', PbBar, 'ProgressCol');
PbCol.hittest = false;
PbSet(PbCol, 'flowChildren', 'down');
PbSet(PbCol, 'width', Pb.textWidth + 'px');
PbSet(PbCol, 'height', 'fit-children');
PbSet(PbCol, 'marginLeft', Pb.rowMarginLeft + 'px');
PbSet(PbCol, 'marginTop', Pb.rowMarginTop + 'px');

var PbRow = $.CreatePanel('Panel', PbCol, 'ProgressRow');
PbRow.hittest = false;
PbSet(PbRow, 'width', '100%');
PbSet(PbRow, 'height', Pb.titleFont + 'px');

var PbTitle = $.CreatePanel('Label', PbRow, 'ProgressTitle');
PbTitle.hittest = false;
PbSet(PbTitle, 'horizontalAlign', 'left');
PbSet(PbTitle, 'verticalAlign', 'center');
PbSet(PbTitle, 'fontFamily', 'Stratum2');
PbSet(PbTitle, 'fontWeight', 'bold');
PbSet(PbTitle, 'fontSize', Pb.titleFont + 'px');
PbSet(PbTitle, 'lineHeight', Pb.titleFont + 'px');
PbSet(PbTitle, 'letterSpacing', '0px');
PbSet(PbTitle, 'color', Pb.titleColor);
PbTitle.text = PbTitleText();

var PbTime = $.CreatePanel('Label', PbRow, 'ProgressTime');
PbTime.hittest = false;
PbSet(PbTime, 'horizontalAlign', 'right');
PbSet(PbTime, 'verticalAlign', 'center');
PbSet(PbTime, 'textAlign', 'right');
PbSet(PbTime, 'fontFamily', 'Stratum2');
PbSet(PbTime, 'fontWeight', 'bold');
PbSet(PbTime, 'fontSize', Pb.timeFont + 'px');
PbSet(PbTime, 'lineHeight', Pb.timeFont + 'px');
PbSet(PbTime, 'color', Pb.timeColor);

var PbTrack = $.CreatePanel('Panel', PbCol, 'ProgressTrack');
PbTrack.hittest = false;
PbSet(PbTrack, 'width', Pb.trackWidth + 'px');
PbSet(PbTrack, 'height', Pb.trackHeight + 'px');
PbSet(PbTrack, 'marginLeft', Pb.trackMarginLeft + 'px');
PbSet(PbTrack, 'horizontalAlign', 'left');
PbSet(PbTrack, 'backgroundColor', Pb.trackBg);

var PbFill = $.CreatePanel('Panel', PbTrack, 'ProgressFill');
PbFill.hittest = false;
PbSet(PbFill, 'width', '100%');
PbSet(PbFill, 'height', Pb.fillHeight + 'px');
PbSet(PbFill, 'horizontalAlign', 'left');
PbSet(PbFill, 'verticalAlign', 'center');
PbSet(PbFill, 'backgroundColor', Pb.fillColor);

var PbInfo = $.CreatePanel('Label', PbCol, 'ProgressInfo');
PbInfo.hittest = false;
PbSet(PbInfo, 'width', '100%');
PbSet(PbInfo, 'horizontalAlign', 'left');
PbSet(PbInfo, 'textAlign', 'left');
PbSet(PbInfo, 'marginLeft', Pb.infoMarginLeft + 'px');
PbSet(PbInfo, 'marginTop', Pb.infoMarginTop + 'px');
PbSet(PbInfo, 'fontFamily', 'Stratum2');
PbSet(PbInfo, 'fontWeight', 'medium');
PbSet(PbInfo, 'fontSize', Pb.infoFont + 'px');
PbSet(PbInfo, 'lineHeight', '24px');
PbSet(PbInfo, 'letterSpacing', '0px');
PbSet(PbInfo, 'color', Pb.infoColor);
PbSet(PbInfo, 'opacity', Pb.infoOpacity);
PbSet(PbInfo, 'textOverflow', 'shrink');

var PbCountdown = function (owner) {
	var found = owner.FindChildrenWithClassTraverse('hud-progress-bar-info-countdown-text');
	return (found && found.length) ? found[0] : null;
};

var PbRead = function (panel) {
	if (!panel)
		return '';
	try {
		return String(panel.text === undefined || panel.text === null ? '' : panel.text);
	} catch (error) {
		return '';
	}
};

var PbWrite = function (panel, text) {
	if (!panel || panel.Text === text)
		return;
	panel.Text = text;
	panel.text = text;
};

var PbWatch = function () {
	var owner = contextPanel.FindChildTraverse('HudProgressBar');
	var bar = contextPanel.FindChildTraverse('Progress');
	if (!owner || !bar)
		return;
	PbPark(owner);
	var icon = bar.FindChildTraverse('ProgressIcon');
	var time = bar.FindChildTraverse('ProgressTime');
	var fill = bar.FindChildTraverse('ProgressFill');
	var info = bar.FindChildTraverse('ProgressInfo');
	if (!icon || !time || !fill || !info)
		return;

	var up = owner.BHasClass('hud-progress-bar--visible');

	if (up) {
		var raw = PbRead(PbCountdown(owner));
		var remaining = PbSeconds(raw);

		if (remaining !== null && remaining > 0 && !(bar.Total > 0))
			bar.Total = remaining;

		if (owner.BHasClass('hud-progress-bar--switched')) {
			if (!bar.Switched) {
				bar.Switched = true;
				if (remaining !== null && remaining > 0)
					bar.Total = remaining;
				bar.Shown = undefined;
			}
		} else {
			bar.Switched = false;
		}

		var fraction = PbAdvance(bar.Shown, PbFraction(remaining, bar.Total));
		if (fraction !== null) {
			bar.Shown = fraction;
			PbSet(fill, 'width', (fraction * 100) + '%');
		}

		PbWrite(time, raw);
		PbWrite(info, PbRead(owner.FindChildTraverse('ActionLabel')));
		PaintArt(icon, owner.BHasClass('hud-progress-bar__defuse') ? 'defuseicon' : 'alerticon',
			{size: 'contain'});
	}

	var state = up ? 'up' : 'down';
	if (bar.State === state)
		return;
	var was = bar.State;
	bar.State = state;

	if (state === 'up') {
		PbSet(bar, 'opacity', '1.0');
	} else if (was === 'up') {
		PbSet(bar, 'opacity', '0.0');
		bar.Total = null;
		bar.Shown = undefined;
		bar.Switched = false;
		PbSet(fill, 'width', '100%');
	} else {
		return;
	}
};

var PbGeneration = (typeof PbGeneration === 'undefined' ? 0 : PbGeneration) + 1;

var PbTick = function (generation) {
	if (generation !== PbGeneration)
		return;
	try {
		PbWatch();
	} catch (error) {
			}
	$.Schedule(0.1, function () {
		PbTick(generation);
	});
};

$.Schedule(0.0, (function (generation) {
	return function () {
		PbTick(generation);
	};
})(PbGeneration));
]===],
    ["radar.js"] = [===[var RadBox = {
	inner: '#000000',
	square: '280px',
	squareInner: '270px',
	round: '260px',
	roundInner: '250px',
	vignette: '274px',
	vignettePaint: 'gradient( radial, 50% 50%, 0px 0px, 125px 125px, from( #00000000 ),'
		+ ' to( #00000044 ) )',
	onMap: '10px',
	offMap: '16px',
	death: '17px',
};

var RadFailures = {};

var RadSet = function (panel, property, value) {
	if (!panel)
		return;
	try {
		panel.style[property] = value;
	} catch (error) {
		if (!RadFailures[property]) {
			RadFailures[property] = true;
					}
	}
};

var RadDressFrame = function (radar) {
	radar.AddClass('radar-dressed');

	var square = radar.FindChildTraverse('Radar__Square');
	if (square) {
		RadSet(square, 'width', RadBox.square);
		RadSet(square, 'height', RadBox.square);
		RadSet(square, 'backgroundColor', RadBox.inner);

		var inner = square.FindChildTraverse('Radar__Square--Inner');
		if (inner) {
			RadSet(inner, 'width', RadBox.squareInner);
			RadSet(inner, 'height', RadBox.squareInner);
			RadSet(inner, 'backgroundColor', RadBox.inner);
			RadSet(inner, 'worldBlur', 'none');
		}
		var map = square.FindChildTraverse('Radar__Square--InnerTransform');
		if (map && map.BHasClass('additive'))
			map.RemoveClass('additive');

		var border = square.FindChildTraverse('Radar__Square--Border');
		if (border) {
			RadSet(border, 'width', RadBox.square);
			RadSet(border, 'height', RadBox.square);
			if (!square.FindChildTraverse('RadarVignette')) {
				var vignette = $.CreatePanel('Panel', square, 'RadarVignette');
				RadSet(vignette, 'width', RadBox.vignette);
				RadSet(vignette, 'height', RadBox.vignette);
				RadSet(vignette, 'horizontalAlign', 'center');
				RadSet(vignette, 'verticalAlign', 'center');
				RadSet(vignette, 'backgroundColor', RadBox.vignettePaint);
				square.MoveChildBefore(vignette, border);
			}
		}
	}

	var round = radar.FindChildTraverse('Radar__Round');
	if (round) {
		RadSet(round, 'width', RadBox.round);
		RadSet(round, 'height', RadBox.round);
		var roundInner = round.FindChildTraverse('Radar__Round--Inner');
		if (roundInner) {
			RadSet(roundInner, 'width', RadBox.roundInner);
			RadSet(roundInner, 'height', RadBox.roundInner);
			RadSet(roundInner, 'backgroundColor', RadBox.inner);
			RadSet(roundInner, 'worldBlur', 'none');
		}
		var roundMap = round.FindChildTraverse('Radar__Round--InnerTransform');
		if (roundMap && roundMap.BHasClass('additive'))
			roundMap.RemoveClass('additive');
		var roundBorder = round.FindChildTraverse('Radar__Round--Border');
		if (roundBorder) {
			RadSet(roundBorder, 'width', RadBox.round);
			RadSet(roundBorder, 'height', RadBox.round);
		}
	}
};

var RadDressIcons = function (icons) {
	icons.AddClass('radar-dressed');
	var each = function (id, dress) {
		var found = icons.FindChildTraverse(id);
		if (found)
			dress(found);
	};
	each('CTOnMap', function (panel) {
		RadSet(panel, 'width', RadBox.onMap);
		RadSet(panel, 'height', RadBox.onMap);
	});
	each('TOnMap', function (panel) {
		RadSet(panel, 'width', RadBox.onMap);
		RadSet(panel, 'height', RadBox.onMap);
	});
	each('CTOffMap', function (panel) {
		RadSet(panel, 'width', RadBox.offMap);
		RadSet(panel, 'height', RadBox.offMap);
	});
	each('TOffMap', function (panel) {
		RadSet(panel, 'width', RadBox.offMap);
		RadSet(panel, 'height', RadBox.offMap);
	});
	each('EnemyOffMap', function (panel) {
		RadSet(panel, 'width', RadBox.offMap);
		RadSet(panel, 'height', RadBox.offMap);
	});
	each('EnemyOnMap', function (panel) {
		RadSet(panel, 'imgShadow', 'none');
	});
	each('CTDeath', function (panel) {
		RadSet(panel, 'width', RadBox.death);
		RadSet(panel, 'height', RadBox.death);
	});
	each('TDeath', function (panel) {
		RadSet(panel, 'width', RadBox.death);
		RadSet(panel, 'height', RadBox.death);
	});
	each('EnemyDeath', function (panel) {
		RadSet(panel, 'width', RadBox.death);
		RadSet(panel, 'height', RadBox.death);
	});
};

var RadGeneration = (typeof RadGeneration === 'undefined' ? 0 : RadGeneration) + 1;

var RadTick = function (generation) {
	if (generation !== RadGeneration)
		return;
	try {
		var radar = contextPanel.FindChildTraverse('Radar');
		if (radar && !radar.BHasClass('radar-dressed'))
			RadDressFrame(radar);
		if (radar) {
			var rows = radar.FindChildrenWithClassTraverse('PlayerIcons');
			for (var at = 0; at < rows.length; ++at)
				if (!rows[at].BHasClass('radar-dressed'))
					RadDressIcons(rows[at]);
		}
	} catch (error) {
			}
	$.Schedule(0.5, function () {
		RadTick(generation);
	});
};

$.Schedule(0.5, (function (generation) {
	return function () {
		RadTick(generation);
	};
})(RadGeneration));
]===],
    ["reticle.js"] = [===[var ReticleGeneration = (typeof ReticleGeneration === 'undefined' ? 0 : ReticleGeneration) + 1;

var ReticleDress = function (content) {
	if (!content.BHasClass('additive'))
		content.AddClass('additive');

	var names = content.FindChildrenWithClassTraverse('playerid__name');
	for (var at = 0; at < names.length; ++at) {
		try {
			names[at].style.fontSize = '26px';
			names[at].style.padding = '0px 2px 0px 2px';
			names[at].style.letterSpacing = '0px';
		} catch (error) {
						return;
		}
	}
};

var ReticleTick = function (generation) {
	if (generation !== ReticleGeneration)
		return;
	try {
		var host = contextPanel.FindChildTraverse('VisiblePlayerIDs');
		if (host) {
			var cards = host.FindChildrenWithClassTraverse('playerid__content');
			for (var at = 0; at < cards.length; ++at) {
				if (!cards[at].BHasClass('dressed')) {
					cards[at].AddClass('dressed');
					ReticleDress(cards[at]);
				}
			}
		}
	} catch (error) {
			}
	$.Schedule(0.25, function () {
		ReticleTick(generation);
	});
};

$.Schedule(0.25, (function (generation) {
	return function () {
		ReticleTick(generation);
	};
})(ReticleGeneration));
]===],
    ["ris.js"] = [===[var RisCfg = {
	width: 750,
	canvasW: 750,
	canvasH: 75,
	marginX: 50,
	rowY: 292,
	reveal: 5,
	line: 4,
	bg: '#333333d0',
	stripBg: 'rgba(40,40,40,0.9)',
	graphBg: 'rgba(40,40,40,0.8)',
	guide: '1px solid rgba(200,200,200,0.1)',
	ct: '#B5D4EE',
	t: '#EAD18A',
	dot: 32,
	fade: 0.2,
};

var RisState = {
	root: null, plot: null, beams: null, segs: null, damage: null,
	plaque: null, plaqueText: null, plaqueLogo: null, headLogo: null, guides: null,
	living: null, map: {},
	xRange: 1, slice: 1, prev: 50, perspective: 2, localTeam: 0, local: '',
	winner: '', gen: 0, listening: false,
};

var RisValues = function (data) {
	if (!data)
		return [];
	if (data.length === Number(data.length))
		return data;
	var out = [];
	for (var key in data)
		if (data.hasOwnProperty(key))
			out.push(data[key]);
	return out;
};

var RisLoc = function (token, fallback) {
	var text = null;
	try {
		text = $.Localize(token, RisState.root || contextPanel);
	} catch (error) {
		text = null;
	}
	return (text && text.length > 1 && text.charAt(0) !== '#') ? text : fallback;
};

var RisSfx = function (name) {
	try {
		if (typeof UiToolkitAPI !== 'undefined' && UiToolkitAPI.PlaySoundEvent)
			UiToolkitAPI.PlaySoundEvent(name);
	} catch (error) {
	}
};

var RisSetting = function (name) {
	try {
		return GameInterfaceAPI.GetSettingString(name);
	} catch (error) {
		return '';
	}
};

var RisTeamClan = function (isCT) {
	try {
		return GameStateAPI.GetTeamClanName(isCT ? 'CT' : 'TERRORIST') || (isCT ? 'CT' : 'T');
	} catch (error) {
		return isCT ? 'CT' : 'T';
	}
};

var RisXuid = function () {
	try {
		var team = GameStateAPI.GetAssociatedTeamNumber(RisState.local);
		if (GameStateAPI.IsDemoOrHltv() || (team !== 2 && team !== 3))
			return GameStateAPI.GetHudPlayerXuid();
		return GameStateAPI.GetLocalPlayerXuid();
	} catch (error) {
		try {
			return GameStateAPI.GetLocalPlayerXuid();
		} catch (inner) {
			return RisState.local;
		}
	}
};

var RisTeamOf = function (xuid) {
	try {
		var team = GameStateAPI.GetAssociatedTeamNumber(xuid);
		if (team === 2 || team === 3)
			return team;
	} catch (error) {
	}
	return 2;
};

var RisPalette = ['199,187,139', '168,122,224', '116,172,87', '103,167,244', '234,124,68'];

var RisVictimColor = function (index) {
	try {
		if (typeof TeamColor !== 'undefined' && TeamColor.GetTeamColorCss)
			return TeamColor.GetTeamColorCss(index);
	} catch (error) {
	}
	return 'rgb(' + (RisPalette[Number(index) % 5] || '160,160,160') + ')';
};

var RisOdds = function (terroristOdds) {
	return RisState.perspective === 2 ? terroristOdds : 100 - terroristOdds;
};

var RisPlot = function (point) {
	return [
		RisCfg.canvasW / RisState.xRange * point[0],
		RisCfg.canvasH - (RisCfg.canvasH / 100 * point[1]),
	];
};

var RisPanel = function (parent, id) {
	var panel = $.CreatePanel('Panel', parent, id);
	panel.hittest = false;
	return panel;
};

var RisDress = function (panel, prop, value) {
	try {
		panel.style[prop] = value;
	} catch (error) {
			}
};

var RisBuild = function () {
	var host = contextPanel.FindChildTraverse('HudWinPanel') || contextPanel;
	var root = RisPanel(host, 'RisRoot');
	RisDress(root, 'width', RisCfg.width + 'px');
	RisDress(root, 'y', RisCfg.rowY + 'px');
	RisDress(root, 'horizontalAlign', 'center');
	RisDress(root, 'flowChildren', 'down');
	RisDress(root, 'visibility', 'collapse');
	RisState.root = root;

	var plaque = RisPanel(root, 'RisWinnerPlaque');
	RisDress(plaque, 'width', RisCfg.width + 'px');
	RisDress(plaque, 'height', '40px');
	RisDress(plaque, 'opacity', '0.0');
	RisDress(plaque, 'transitionProperty', 'opacity');
	RisDress(plaque, 'transitionDuration', RisCfg.fade + 's');
	RisDress(plaque, 'backgroundColor', 'gradient( linear, 0% 0%, 100% 0%,'
		+ ' from( #00000000 ), color-stop( 0.2, #333333f0 ),'
		+ ' color-stop( 0.8, #333333f0 ), to( #00000000 ) )');
	var plaqueLogo = RisPanel(plaque, 'RisWinnerLogo');
	RisDress(plaqueLogo, 'width', '100px');
	RisDress(plaqueLogo, 'height', '100px');
	RisDress(plaqueLogo, 'horizontalAlign', 'center');
	RisDress(plaqueLogo, 'y', '14px');
	RisDress(plaqueLogo, 'opacity', '0.1');
	var plaqueText = $.CreatePanel('Label', plaque, 'RisWinnerText');
	plaqueText.hittest = false;
	RisDress(plaqueText, 'width', '100%');
	RisDress(plaqueText, 'height', '40px');
	RisDress(plaqueText, 'horizontalAlign', 'center');
	RisDress(plaqueText, 'verticalAlign', 'center');
	RisDress(plaqueText, 'textAlign', 'center');
	RisDress(plaqueText, 'fontFamily', 'Stratum2');
	RisDress(plaqueText, 'fontWeight', 'bold');
	RisDress(plaqueText, 'fontSize', '22px');
	RisDress(plaqueText, 'letterSpacing', '1px');
	RisDress(plaqueText, 'textTransform', 'uppercase');
	RisDress(plaqueText, 'color', '#ffffff');
	RisState.plaque = plaque;
	RisState.plaqueText = plaqueText;
	RisState.plaqueLogo = plaqueLogo;

	var main = RisPanel(root, 'RisMain');
	RisDress(main, 'width', RisCfg.width + 'px');
	RisDress(main, 'marginTop', '5px');
	RisDress(main, 'backgroundColor', RisCfg.bg);

	var head = RisPanel(main, 'RisHeader');
	RisDress(head, 'width', '100%');
	RisDress(head, 'height', '40px');
	RisDress(head, 'backgroundColor', RisCfg.stripBg);
	RisDress(head, 'flowChildren', 'right');
	RisDress(head, 'paddingLeft', '8px');
	var headLogo = RisPanel(head, 'RisHeadLogo');
	RisDress(headLogo, 'width', '20px');
	RisDress(headLogo, 'height', '20px');
	RisDress(headLogo, 'verticalAlign', 'center');
	RisState.headLogo = headLogo;
	var headTitle = $.CreatePanel('Label', head, 'RisHeadTitle');
	headTitle.hittest = false;
	RisDress(headTitle, 'height', '40px');
	RisDress(headTitle, 'verticalAlign', 'center');
	RisDress(headTitle, 'marginLeft', '5px');
	RisDress(headTitle, 'fontFamily', 'Stratum2');
	RisDress(headTitle, 'fontSize', '16px');
	RisDress(headTitle, 'letterSpacing', '1px');
	RisDress(headTitle, 'color', '#ffffff');
	RisState.headTitle = headTitle;

	var center = RisPanel(main, 'RisCenter');
	RisDress(center, 'width', '100%');
	RisDress(center, 'height', RisCfg.canvasH + 'px');
	RisDress(center, 'zIndex', '1');
	var guidesBg = RisPanel(center, 'RisGraphBg');
	RisDress(guidesBg, 'width', '100%');
	RisDress(guidesBg, 'height', '100%');
	RisDress(guidesBg, 'backgroundColor', RisCfg.graphBg);
	var margin = RisPanel(guidesBg, 'RisMargin');
	RisDress(margin, 'width', RisCfg.marginX + 'px');
	RisDress(margin, 'height', '100%');
	RisDress(margin, 'backgroundColor', 'gradient( linear, 100% 0%, 0% 0%,'
		+ ' from( #00000030 ), color-stop( 0.2, #00000000 ), to( #00000000 ) )');
	var guides = RisPanel(guidesBg, 'RisGuides');
	RisDress(guides, 'x', RisCfg.marginX + 'px');
	RisDress(guides, 'width', '700px');
	RisDress(guides, 'height', '100%');
	RisDress(guides, 'flowChildren', 'down');
	for (var half = 0; half < 2; ++half) {
		var interval = RisPanel(guides, 'RisInterval' + half);
		RisDress(interval, 'width', '100%');
		RisDress(interval, 'height', '50%');
		RisDress(interval, 'borderTop', RisCfg.guide);
		RisDress(interval, 'borderBottom', RisCfg.guide);
	}
	var living = RisPanel(guidesBg, 'RisLivingBg');
	RisDress(living, 'height', '100%');
	RisDress(living, 'horizontalAlign', 'right');
	RisDress(living, 'backgroundColor', 'gradient( linear, 0% 0%, 100% 0%,'
		+ ' from( #00000030 ), color-stop( 0.05, #00000000 ), to( #00000000 ) )');
	RisState.guides = guides;
	RisState.living = living;

	var graph = RisPanel(center, 'RisGraph');
	RisDress(graph, 'x', RisCfg.marginX + 'px');
	RisDress(graph, 'width', RisCfg.canvasW + 'px');
	RisDress(graph, 'height', RisCfg.canvasH + 'px');
	RisDress(graph, 'overflow', 'noclip');
	var beams = RisPanel(graph, 'RisBeams');
	RisDress(beams, 'width', RisCfg.canvasW + 'px');
	RisDress(beams, 'height', '100%');
	RisDress(beams, 'zIndex', '-1');
	var segs = RisPanel(graph, 'RisSegments');
	RisDress(segs, 'width', RisCfg.canvasW + 'px');
	RisDress(segs, 'height', '100%');
	var plot = RisPanel(graph, 'RisPlot');
	RisDress(plot, 'width', RisCfg.canvasW + 'px');
	RisDress(plot, 'height', '100%');
	RisState.beams = beams;
	RisState.segs = segs;
	RisState.plot = plot;

	var bottom = RisPanel(main, 'RisBottom');
	RisDress(bottom, 'width', '100%');
	RisDress(bottom, 'height', '67px');
	RisDress(bottom, 'backgroundColor', RisCfg.stripBg);
	var damage = RisPanel(bottom, 'RisDamageRow');
	RisDress(damage, 'width', RisCfg.canvasW + 'px');
	RisDress(damage, 'height', '35px');
	RisDress(damage, 'horizontalAlign', 'center');
	RisDress(damage, 'verticalAlign', 'bottom');
	RisDress(damage, 'transform', 'translateX( ' + RisCfg.marginX + 'px )');
	RisDress(damage, 'overflow', 'noclip');
	RisState.damage = damage;
};

var RisWipe = function (panel) {
	if (!panel)
		return;
	try {
		panel.RemoveAndDeleteChildren();
	} catch (error) {
	}
};

var RisBeam = function (key, teamNumber, plotPoint) {
	var color = teamNumber === 3 ? RisCfg.ct : RisCfg.t;
	var beam = RisPanel(RisState.beams, 'RisBeam-' + key);
	RisDress(beam, 'width', '28px');
	RisDress(beam, 'x', (plotPoint[0] - 14) + 'px');
	RisDress(beam, 'y', plotPoint[1] + 'px');
	RisDress(beam, 'height', (RisCfg.canvasH - plotPoint[1] + 69) + 'px');
	RisDress(beam, 'backgroundColor', 'gradient( linear, 0% 100%, 0% 0%,'
		+ ' from( ' + color + '00 ), color-stop( 0.6, ' + color + '10 ),'
		+ ' to( ' + color + '40 ) )');
};

var RisSegment = function (from, to, color) {
	var dx = to[0] - from[0];
	var dy = to[1] - from[1];
	var len = Math.sqrt(dx * dx + dy * dy);
	if (len < 0.5)
		return;
	var deg = Math.atan2(dy, dx) * 180 / Math.PI;
	var seg = RisPanel(RisState.segs, 'RisSeg' + RisState.segs.GetChildCount());
	RisDress(seg, 'x', from[0] + 'px');
	RisDress(seg, 'y', (from[1] - RisCfg.line / 2) + 'px');
	RisDress(seg, 'width', len + 'px');
	RisDress(seg, 'height', RisCfg.line + 'px');
	RisDress(seg, 'transformOrigin', '0% 50%');
	RisDress(seg, 'transform', 'rotateZ( ' + deg + 'deg )');
	RisDress(seg, 'backgroundColor', color);
	RisDress(seg, 'visibility', 'collapse');
	RisDress(seg, 'opacity', '0.0');
	seg.RisReveal = function () {
		RisDress(seg, 'visibility', 'visible');
		RisDress(seg, 'opacity', '1.0');
	};
};

var RisRevealBox = function (panel) {
	RisDress(panel, 'transitionProperty', 'opacity');
	RisDress(panel, 'transitionDuration', RisCfg.fade + 's');
	RisDress(panel, 'transitionTimingFunction', 'ease-out');
	RisDress(panel, 'opacity', '0.0');
	panel.RisReveal = function () {
		RisDress(panel, 'opacity', '1.0');
	};
};

var RisDotLabel = function (outer, text, color) {
	var label = $.CreatePanel('Label', outer, 'RisChance');
	label.hittest = false;
	RisDress(label, 'width', '100%');
	RisDress(label, 'y', '6px');
	RisDress(label, 'horizontalAlign', 'center');
	RisDress(label, 'textAlign', 'center');
	RisDress(label, 'fontFamily', 'Stratum2 bold');
	RisDress(label, 'fontSize', '12px');
	RisDress(label, 'textTransform', 'uppercase');
	RisDress(label, 'textShadow', '1px 1px black');
	label.text = text;
	RisDress(label, 'color', color || '#8a8a8a');
	return label;
};

var RisChanceColor = function (delta) {
	var frac = Math.min(1, Math.max(0, (delta + 20) / 40));
	return 'rgb(' + Math.round((1 - frac) * 255) + ',' + Math.round(frac * 255) + ',0)';
};

var RisObjectiveSrc = function (type) {
	var at = Number(type);
	return [dictObjectiveImage[at] || dictObjectiveImage[3], at >= 2];
};

var RisDot = function (event, plotPoint, chance) {
	var victim = event.victim_data;
	var objective = event.objective_data;
	var outer = RisPanel(RisState.plot,
		'RisEvent-' + (victim ? 'x' + victim.xuid : 'obj' + objective.type));
	RisDress(outer, 'width', '50px');
	RisDress(outer, 'height', '100px');
	RisDress(outer, 'x', (plotPoint[0] - 25) + 'px');
	RisDress(outer, 'y', (plotPoint[1] - 50) + 'px');
	RisDress(outer, 'overflow', 'noclip');

	var box = RisPanel(outer, 'RisBox');
	RisDress(box, 'width', RisCfg.dot + 'px');
	RisDress(box, 'height', RisCfg.dot + 'px');
	RisDress(box, 'horizontalAlign', 'center');
	RisDress(box, 'verticalAlign', 'center');
	RisDress(box, 'border', '1px solid black');
	RisDress(box, 'borderRadius', '5px');
	RisDress(box, 'backgroundColor', '#777777');
	RisRevealBox(box);

	var reveals = [box];
	var bCT = false;
	if (victim) {
		bCT = victim.team_number === 3;
		if (!victim.is_bot) {
			var avatar = $.CreatePanel('CSGOAvatarImage', box, 'RisAvatar');
			avatar.hittest = false;
			RisDress(avatar, 'width', RisCfg.dot + 'px');
			RisDress(avatar, 'height', RisCfg.dot + 'px');
			RisDress(avatar, 'borderRadius', '3px');
			RisDress(avatar, 'overflow', 'noclip');
			RisDress(avatar, 'horizontalAlign', 'center');
			RisDress(avatar, 'verticalAlign', 'center');
			try {
				avatar.PopulateFromPlayerSlot(GameStateAPI.GetPlayerSlot(String(victim.xuid)));
			} catch (error) {
							}
			var strip = RisPanel(box, 'RisTeamStrip');
			RisDress(strip, 'width', '50%');
			RisDress(strip, 'height', '6px');
			RisDress(strip, 'horizontalAlign', 'center');
			RisDress(strip, 'verticalAlign', 'bottom');
			RisDress(strip, 'backgroundColor', RisVictimColor(victim.color));
		} else {
			RisDress(box, 'backgroundColor', bCT ? '#5d79a8' : '#a8935d');
		}
		RisBeam('x' + victim.xuid, victim.team_number, plotPoint);
	} else {
		var src = RisObjectiveSrc(objective.type);
		bCT = src[1];
		var icon = $.CreatePanel('Image', box, 'RisObjectiveIcon');
		icon.hittest = false;
		RisDress(icon, 'width', '26px');
		RisDress(icon, 'height', '26px');
		RisDress(icon, 'horizontalAlign', 'center');
		RisDress(icon, 'verticalAlign', 'center');
		try {
			icon.SetImage(src[0]);
			IconUtil.FallbackPng(icon, src[0].slice(0, -4));
		} catch (error) {
					}
	}

	if (!victim || victim.is_dead) {
		var delta = chance - RisState.prev;
		var symbol = delta < 0 ? '▼' : delta > 0 ? '▲' : '';
		var text = chance === 100 ? RisLoc('#ris_win', 'WIN')
			: chance === 0 ? RisLoc('#ris_loss', 'LOSS')
			: symbol + chance + '%';
		var color = chance === 100 ? '#00ff00'
			: chance === 0 ? '#ff0000'
			: RisChanceColor(delta);
		RisDotLabel(outer, text, color);
	}

	if (victim && victim.is_dead) {
		var skull = $.CreatePanel('Image', outer, 'RisDeath');
		skull.hittest = false;
		RisDress(skull, 'width', '12px');
		RisDress(skull, 'height', '12px');
		RisDress(skull, 'x', '27px');
		RisDress(skull, 'y', '52px');
		RisDress(skull, 'imgShadow', '1px 1px 1px 3px black');
		PaintArt(skull, 'aliveskull', {size: '100% 100%'});
		RisRevealBox(skull);
		reveals.push(skull);
	}

	outer.RisRevealAll = function () {
		for (var at = 0; at < reveals.length; ++at)
			if (reveals[at] && reveals[at].IsValid() && reveals[at].RisReveal)
				reveals[at].RisReveal();
	};

	RisState.prev = chance;
	return outer;
};

var RisDamageRow = function (key, plotPoint) {
	var outer = RisPanel(RisState.damage, 'RisDamage-' + key);
	RisDress(outer, 'width', '60px');
	RisDress(outer, 'height', '35px');
	RisDress(outer, 'x', (plotPoint[0] - 30) + 'px');
	RisDress(outer, 'verticalAlign', 'bottom');
	RisRevealBox(outer);

	var make = function (id, bottom, tint) {
		var half = RisPanel(outer, id);
		RisDress(half, 'width', '100%');
		RisDress(half, 'height', '16px');
		RisDress(half, 'horizontalAlign', 'center');
		RisDress(half, 'verticalAlign', bottom ? 'bottom' : 'top');
		RisDress(half, 'backgroundColor', tint);
		var text = $.CreatePanel('Label', half, id + 'Text');
		text.hittest = false;
		RisDress(text, 'width', '100%');
		RisDress(text, 'height', '100%');
		RisDress(text, 'horizontalAlign', 'center');
		RisDress(text, 'verticalAlign', 'center');
		RisDress(text, 'textAlign', 'center');
		RisDress(text, 'fontFamily', 'Stratum2 Bold Monodigit');
		RisDress(text, 'fontSize', '12px');
		RisDress(text, 'color', bottom ? '#d87b7b' : '#7bd87b');
		RisDress(text, 'textShadow', '1px 1px black');
		text.text = '';
		return text;
	};

	var row = {
		box: outer,
		given: make('RisGiven', false, 'rgba(0,255,0,0.05)'),
		taken: make('RisTaken', true, 'rgba(255,0,0,0.05)'),
		hp: 0, hits: 0, back: 0, backHits: 0,
	};
	row.write = function () {
		row.given.text = row.hp > 0 ? ('▲' + row.hp + (row.hits > 1 ? ' ·' + row.hits : '')) : '';
		row.taken.text = row.back > 0 ? ('▼' + row.back + (row.backHits > 1 ? ' ·' + row.backHits : '')) : '';
	};
	return row;
};

var RisFindDamage = function (event, xuid) {
	var records = RisValues(event.all_damage_data);
	for (var at = 0; at < records.length; ++at)
		if (String(records[at].other_xuid) === String(xuid))
			return records[at];
	return null;
};

var RisAddDamage = function (event, plotPoint) {
	if (event.objective_data || !event.victim_data)
		return;
	var key = 'x' + event.victim_data.xuid;
	var row = RisState.map[key];
	if (!row) {
		row = RisDamageRow(key, plotPoint);
		RisState.map[key] = row;
	}
	var record = RisFindDamage(event, RisState.local);
	if (record) {
		row.hp = Math.min(100, row.hp + (Number(record.health_removed) || 0));
		row.hits += Number(record.num_hits) || 0;
		row.back = Math.min(100, row.back + (Number(record.return_health_removed) || 0));
		row.backHits += Number(record.return_num_hits) || 0;
		row.write();
	}
};

var RisUpdateDamage = function (xuid, given, taken) {
	var row = RisState.map['x' + xuid];
	if (!row)
		return;
	if (given) {
		row.hp = Math.min(100, row.hp + given);
		row.hits += 1;
	}
	if (taken) {
		row.back = Math.min(100, row.back + taken);
		row.backHits += 1;
	}
	row.write();
	RisDress(row.box, 'opacity', '1.0');
};

var RisSchedule = function (delay, fn) {
	var gen = RisState.gen;
	$.Schedule(delay, function () {
		if (gen === RisState.gen)
			fn();
	});
};

var RisShowWinner = function () {
	if (!RisState.winner)
		return;
	var isCT = RisState.winner === 3;
	RisState.root.SetDialogVariable('ris_team', RisTeamClan(isCT));
	RisState.plaqueText.text = RisLoc('#ris_wins', RisTeamClan(isCT) + ' WINS THE ROUND');
	PaintArt(RisState.plaqueLogo, isCT ? 'teamct' : 'teamt', {size: 'contain'});
	RisDress(RisState.plaque, 'opacity', '1.0');
	RisSfx(RisState.localTeam === RisState.winner
		? 'UIPanorama.round_report_round_won' : 'UIPanorama.round_report_round_lost');
};

var RisShow = function (msg) {
	if (!msg)
		return;
	if (!RisState.root || !RisState.root.IsValid())
		RisBuild();
	if (!RisState.root)
		return;
	RisState.gen += 1;

	RisState.local = RisXuid();
	RisState.localTeam = RisTeamOf(RisState.local);
	RisState.perspective = (RisState.localTeam === 2 || RisState.localTeam === 3)
		? RisState.localTeam : 2;
	RisState.listening = true;
	RisState.map = {};
	RisState.prev = 50;
	RisWipe(RisState.plot);
	RisWipe(RisState.beams);
	RisWipe(RisState.segs);
	RisWipe(RisState.damage);

	var isCT = RisState.perspective === 3;
	var drawColor = isCT ? RisCfg.ct + 'aa' : RisCfg.t + 'aa';
	PaintArt(RisState.headLogo, isCT ? 'teamct' : 'teamt', {size: 'contain'});
	RisState.root.SetDialogVariable('team', RisTeamClan(isCT));
	RisState.headTitle.text = RisLoc('#ris_team-title', 'ROUND REPORT');
	RisDress(RisState.plaque, 'opacity', '0.0');
	RisDress(RisState.root, 'visibility', 'visible');

	var startRaw = Number(msg.init_conditions && msg.init_conditions.terrorist_odds);
	var start = isNaN(startRaw) ? 50 : startRaw;

	var timeline = [];
	var enemies = [];
	var records = RisValues(msg.all_rer_event_data);
	for (var at = 0; at < records.length; ++at) {
		var victim = records[at].victim_data;
		if (!victim || victim.is_dead) {
			timeline.push(records[at]);
			continue;
		}
		var isEnemy = victim.team_number !== RisState.localTeam
			&& (RisState.localTeam === 2 || RisState.localTeam === 3);
		if (isEnemy)
			enemies.push(records[at]);

	}

	RisState.winner = timeline.length
		? (Number(timeline[timeline.length - 1].terrorist_odds) === 100 ? 2
			: Number(timeline[timeline.length - 1].terrorist_odds) === 0 ? 3 : '')
		: '';

	RisState.xRange = timeline.length + enemies.length + 1.5;
	RisState.slice = RisCfg.reveal / RisState.xRange;

	var plots = [RisPlot([0, RisOdds(start)])];
	RisSchedule(0, function () {
		RisStartingDot(plots[0], RisOdds(start));
	});

	for (var step = 0; step < timeline.length; ++step) {
		var chance = RisOdds(Number(timeline[step].terrorist_odds));
		plots.push(RisPlot([step + 1, chance]));
		RisSchedule(step * RisState.slice, function (event, plotPoint, chance) {
			var delta = chance - RisState.prev;
			RisAddDamage(event, plotPoint);
			RisDot(event, plotPoint, chance);
			RisSfx(delta > 0 ? 'UIPanorama.round_report_odds_up'
				: delta < 0 ? 'UIPanorama.round_report_odds_dn'
				: 'UIPanorama.round_report_odds_none');
		}.bind(this, timeline[step], plots[step + 1], chance));
	}

	var tailX = timeline.length;
	for (var extra = 0; extra < enemies.length; ++extra) {
		plots.push(RisPlot([tailX + extra + 1, 50]));
		RisSchedule((tailX + extra) * RisState.slice, function (event, plotPoint) {
			RisAddDamage(event, plotPoint);
			RisDot(event, plotPoint, RisOdds(Number(event.terrorist_odds) || 50));
		}.bind(this, enemies[extra], plots[plots.length - 1]));
	}

	for (var seg = 0; seg + 1 < plots.length; ++seg)
		RisSegment(plots[seg], plots[seg + 1], drawColor);
	for (var order = 0; order < RisState.segs.GetChildCount(); ++order) {
		var child = RisState.segs.GetChild(order);
		RisSchedule(order * RisState.slice, function (panel) {
			if (panel && panel.IsValid() && panel.RisReveal)
				panel.RisReveal();
		}.bind(this, child));
	}

	var graphWidth = timeline.length / RisState.xRange * 100;
	RisDress(RisState.guides, 'width', graphWidth + '%');
	RisDress(RisState.living, 'width', (100 - graphWidth) + '%');

	RisSchedule(RisCfg.reveal, function () {
		RisShowWinner();
	});

	var freezetime = Number(RisSetting('mp_freezetime')) || 5;
	var restart = Number(RisSetting('mp_round_restart_delay')) || 5;
	RisSchedule(restart + freezetime - 1, function () {
		RisState.listening = false;
	});
};

var RisStartingDot = function (plotPoint, chance) {
	var outer = RisPanel(RisState.plot, 'RisStart');
	RisDress(outer, 'width', '50px');
	RisDress(outer, 'height', '100px');
	RisDress(outer, 'x', (plotPoint[0] - 25) + 'px');
	RisDress(outer, 'y', (plotPoint[1] - 50) + 'px');
	RisDress(outer, 'overflow', 'noclip');
	var dot = RisPanel(outer, 'RisStartDot');
	RisDress(dot, 'width', '24px');
	RisDress(dot, 'height', '24px');
	RisDress(dot, 'horizontalAlign', 'center');
	RisDress(dot, 'verticalAlign', 'center');
	RisDress(dot, 'borderRadius', '30px');
	RisDress(dot, 'backgroundColor', 'gray');
	var mark = $.CreatePanel('Label', dot, 'RisStartMark');
	mark.hittest = false;
	RisDress(mark, 'width', '100%');
	RisDress(mark, 'height', '100%');
	RisDress(mark, 'horizontalAlign', 'center');
	RisDress(mark, 'verticalAlign', 'center');
	RisDress(mark, 'textAlign', 'center');
	RisDress(mark, 'fontFamily', 'Stratum2');
	RisDress(mark, 'fontSize', '14px');
	RisDress(mark, 'color', 'white');
	RisDress(mark, 'textShadow', '0px 0px 2px black');
	mark.text = '$';
	RisDotLabel(outer, chance + '%', '#cccccc');
};

var RisHide = function () {
	RisState.gen += 1;
	RisState.listening = false;
	if (RisState.root && RisState.root.IsValid())
		RisDress(RisState.root, 'visibility', 'collapse');
};

if (typeof RisEvents === 'undefined') {
	var RisEvents = true;

	$.RegisterForUnhandledEvent('HudWinPanel_ShowRoundEndReport', function (msg) {
		try {
			RisShow(msg);
		} catch (error) {
					}
	});

	$.RegisterForUnhandledEvent('HudWinPanel_HideRoundEndReport', function () {
		try {
			RisHide();
		} catch (error) {
					}
	});

	$.RegisterForUnhandledEvent('Player_Hurt', function (attacker, victim, damage) {
		if (!RisState.listening)
			return;
		try {
			if (String(attacker) === String(RisState.local))
				RisUpdateDamage(victim, Number(damage) || 0, 0);
			else if (String(victim) === String(RisState.local))
				RisUpdateDamage(attacker, 0, Number(damage) || 0);
		} catch (error) {
					}
	});

	$.RegisterForUnhandledEvent('Player_Death', function (xuid) {
		if (!RisState.listening)
			return;
		try {
			var outer = contextPanel.FindChildTraverse('RisEvent-x' + xuid);
			var death = outer && outer.FindChildTraverse('RisDeath');
			if (death)
				RisDress(death, 'opacity', '1.0');
		} catch (error) {
		}
	});
}
]===],
    ["settings.js"] = [===[var ScaleformPalette = [
	'#F5FFC0',
	'#FFFFFF',
	'#C4ECFE',
	'#6E9CFB',
	'#F294FF',
	'#FF6057',
	'#FFA557',
	'#FEFD55',
	'#78FF51',
	'#57FFBD',
	'#FFADC4',
];

var TeamColorCt = '#96c8fa';
var TeamColorT = '#eabe54';
var PaletteOffset = 1;
var TeammateColorIndex = 12;

var SettingsApi = (function () {
	try {
		return (typeof GameInterfaceAPI !== 'undefined' && GameInterfaceAPI.GetSettingString)
			? GameInterfaceAPI : null;
	} catch (error) {
		return null;
	}
})();

var Setting = function (name) {
	if (!SettingsApi)
		return null;
	try {
		var value = SettingsApi.GetSettingString(name);
		return (value === null || value === undefined || value === '') ? null : value;
	} catch (error) {
		return null;
	}
};

var SettingNumber = function (name, fallback) {
	var value = parseFloat(Setting(name));
	return isFinite(value) ? value : fallback;
};

var HudColorIndex = function () {
	var fromConvar = parseInt(Setting('cl_hud_color'), 10);
	if (isFinite(fromConvar))
		return fromConvar;
	for (var at = contextPanel; at; at = at.GetParent())
		for (var index = 0; index <= TeammateColorIndex; ++index)
			if (at.BHasClass('csgo-hud__color-' + index))
				return index;
	return 0;
};

var TeamTint = function () {
	if (contextPanel.BHasClass('HUD--team--terrorist'))
		return TeamColorT;
	return TeamColorCt;
};

var HudColor = function (index) {
	if (index === 0 || index === TeammateColorIndex)
		return TeamTint();
	var slot = index - PaletteOffset;
	if (slot < 0 || slot >= ScaleformPalette.length)
		return TeamTint();
	return ScaleformPalette[slot];
};

var RadarBorderAlpha = '19';
var DashboardTextAlpha = 'B2';

var RadarBorderWidth = '2px';
var RadarBorderOpacity = '0.50';

var ApplyRadarBorders = function (hex) {
	var painted = 0;
	for (var id of ['Radar__Round--Border', 'Radar__Square--Border']) {
		var border = contextPanel.FindChildTraverse(id);
		if (!border)
			continue;
		border.style.borderRadius = (id === 'Radar__Round--Border') ? '50% / 50%' : '0';
		border.style.borderWidth = RadarBorderWidth;
		border.style.borderStyle = 'solid';
		border.style.borderColor = hex + RadarBorderAlpha;
		border.style.opacity = RadarBorderOpacity;
		++painted;
	}
	return painted;
};

var TintNeutralText = true;

var NeutralTextIds = [
	'MoneyText',
	'AmmoClip',
	'AmmoSlash',
	'AmmoCount',
];

var TintClass = 'hud-colored';
var TintFillIds = ['HAHealthFill', 'HAArmorFill'];
var TintWashIds = ['AmmoMag', 'HAHealthIcon', 'HAArmorIcon'];
var HudTextColor = (typeof HudTextColor === 'undefined') ? '#ffffff' : HudTextColor;

var ApplyTextColor = function (hex) {
	var painted = 0;
	var paint = function (panel) {
		if (!panel)
			return;
		if (panel.TextColor === hex)
			return;
		panel.TextColor = hex;
		panel.style.color = hex;
		++painted;
	};

	for (var id of NeutralTextIds)
		paint(contextPanel.FindChildTraverse(id));
	for (var opted of contextPanel.FindChildrenWithClassTraverse(TintClass))
		paint(opted);
	return painted;
};

var ApplyFillColor = function (hex) {
	var painted = 0;
	for (var id of TintFillIds) {
		var fill = contextPanel.FindChildTraverse(id);
		if (!fill || fill.BHasClass('ha-critical') || fill.FillColor === hex)
			continue;
		fill.FillColor = hex;
		fill.style.backgroundColor = hex;
		++painted;
	}
	return painted;
};

var ApplyWashColor = function (hex) {
	var painted = 0;
	for (var id of TintWashIds) {
		var image = contextPanel.FindChildTraverse(id);
		if (!image || image.WashColor === hex)
			continue;
		image.WashColor = hex;
		image.style.washColor = hex;
		++painted;
	}
	return painted;
};

var PlateAlphaFallback = 1.0;
var PlateAlphaValue = (typeof PlateAlphaValue === 'undefined') ? 1.0 : PlateAlphaValue;
var ApplyPlateAlpha = function (alpha) {
	if (typeof PaintArt === 'undefined')
		return 0;
	var painted = 0;
	var repaint = function (panel, token, extra) {
		if (panel && PaintArt(panel, token, extra))
			++painted;
	};
	var text = String(alpha);

	repaint(contextPanel.FindChildTraverse('DashboardLabel'), 'topleft', {opacity: text});

	var health = contextPanel.FindChildTraverse('HAHealth');
	if (health && !health.BHasClass('ha-critical')) {
		var hpSize = (typeof HaBox !== 'undefined' && HaBox && HaBox.hpBgSize) || undefined;
		repaint(health, 'hpplate', hpSize ? {size: hpSize, opacity: text} : {opacity: text});
	}
	repaint(contextPanel.FindChildTraverse('HAArmor'), 'armorplate', {opacity: text});
	repaint(contextPanel.FindChildTraverse('Ammo'), 'ammoplate', {opacity: text});
	if (typeof PlateImgOpacity !== 'undefined')
		PlateImgOpacity = text;
	return painted;
};

var SettingsPollSeconds = 0.5;
var LastHudColor = null;
var LastPlateAlpha = null;
var SettingsSaid = {};
var ApplySettings = function (why) {
	var index = HudColorIndex();
	var hex = HudColor(index);
	var textHex = (TintNeutralText && index !== 0 && index !== TeammateColorIndex) ? hex : '#ffffff';
	HudTextColor = textHex;
	var alpha = SettingNumber('cl_hud_radar_background_alpha', PlateAlphaFallback);
	alpha = Math.max(0, Math.min(1, alpha));

	var stamp = hex + '|' + textHex;
	var colorChanged = stamp !== LastHudColor;
	var alphaChanged = alpha !== LastPlateAlpha;
	if (!colorChanged && !alphaChanged && why === 'poll')
		return;

	var said = SettingsSaid;
	var failed = null;
	var section = function (name, fn) {
		try {
			return fn();
		} catch (error) {
			if (!said[name]) {
				said[name] = true;
							}
			failed = failed ? failed + ',' + name : name;
			return null;
		}
	};

	var borders = section('radar', function () {
		return ApplyRadarBorders(hex);
	});

	section('location', function () {
		var dashboard = contextPanel.FindChildTraverse('DashboardLabel');
		if (dashboard)
			dashboard.style.color = hex + DashboardTextAlpha;
		return true;
	});

	var tinted = section('text', function () {
		return ApplyTextColor(textHex);
	});
	var fills = section('fills', function () {
		return ApplyFillColor(textHex);
	});
	var washes = section('wash', function () {
		return ApplyWashColor(textHex);
	});
	var plate = alphaChanged
		? section('plates', function () {
			PlateAlphaValue = alpha;
			var painted = ApplyPlateAlpha(alpha);
			if (typeof MoneyApplyAlpha === 'function')
				MoneyApplyAlpha(alpha);
			return painted;
		})
		: null;

	if (!failed) {
		LastHudColor = stamp;
		LastPlateAlpha = alpha;
	}

};

var SettingsGeneration = (typeof SettingsGeneration === 'undefined' ? 0 : SettingsGeneration) + 1;

var SettingsTick = function (generation, why) {
	if (generation !== SettingsGeneration)
		return;
	try {
		ApplySettings(why);
	} catch (error) {
			}
	$.Schedule(SettingsPollSeconds, function () {
		SettingsTick(generation, 'poll');
	});
};

$.Schedule(0.0, (function (generation) {
	return function () {
		SettingsTick(generation, 'load');
	};
})(SettingsGeneration));
]===],
    ["specpanel.js"] = [===[var Sp = {
	width: 522,
	height: 99,
	bottom: 68 - 16,
	plateOpacity: '0.6',

	avatar: 78,
	avatarTop: 1,
	avatarInset: 3,
	avatarBg: 'gradient( linear, 0% 0%, 0% 100%, from( #666666 ), to( #181818 ) )',

	nameSize: 26,
	nameLeft: 83,
	nameLift: 20,
	nameRight: 20,
	nameCt: '#88a4d1',
	nameT: '#d4c072',
	nameNone: '#ffffff',

	stripHeight: 24,
	stripBg: 'gradient( linear, 0% 0%, 100% 0%, from( #00000000 ), color-stop( 0.26, #00000000 ),' + ' color-stop( 0.45, #00000079 ), to( #00000079 ) )',
	weaponSize: 18,
	weaponRight: 9,
	weaponBottom: 1,

	fade: 0.2,
	park: -3000,
};

var SpBorrow = {id: 'HudSpecplayer__Avatar'};
var SpSources = {name: {cls: 'HudSpecplayer__player-name'}, weapon: {id: 'WeaponNameLabel'}};
var SpFailures = (typeof SpFailures === 'undefined' ? {} : SpFailures);

var SpSet = function (panel, property, value) {
	if (!panel)
		return;
	try {
		panel.style[property] = value;
	} catch (error) {
		if (!SpFailures[property]) {
			SpFailures[property] = true;
					}
	}
};

var SpFind = function (root, want) {
	if (!root)
		return null;
	return want.id ? root.FindChildTraverse(want.id)
		: root.FindChildrenWithClassTraverse(want.cls)[0] || null;
};

var SpTeam = function (from) {
	for (var at = from; at; at = at.GetParent()) {
		if (at.BHasClass('HUD--team--ct'))
			return 'ct';
		if (at.BHasClass('HUD--team--terrorist'))
			return 't';
	}
	return null;
};

var SpWatching = function (owner) {
	if (owner.FindChildrenWithClassTraverse('HudSpecplayerRoot--visible').length)
		return true;
	for (var at = owner; at; at = at.GetParent())
		if (at.BHasClass('HUD--spectating-target'))
			return true;
	return false;
};

var SpHudDiffers = function () {
	try {
		var local = GameStateAPI.GetLocalPlayerXuid();
		var hud = GameStateAPI.GetHudPlayerXuid();
		return !!(hud && String(hud) !== String(local));
	} catch (error) {
		return false;
	}
};

var SpOwner = contextPanel.FindChildTraverse('jsHudHealthArmorAmmoMore');

var SpRelease = function (host, fallbackParent) {
	if (!host)
		return;
	var strays = host.FindChildrenWithClassTraverse('spec-borrowed');
	for (var at = 0; at < strays.length; ++at) {
		try {
			strays[at].SetParent(fallbackParent);
		} catch (error) {
		}
	}
};

var SpOld = SpOwner ? SpOwner.FindChildTraverse('Spec') : null;
if (SpOld) {
	var SpCircle = SpOwner.FindChildrenWithClassTraverse('hud-HA-center__circle')[0];
	SpRelease(SpOld, SpCircle || SpOwner);
	SpOld.DeleteAsync(0);
}

var SpOldNote = contextPanel.FindChildTraverse('SpecDebug');
if (SpOldNote)
	SpOldNote.DeleteAsync(0);

var SpVoid = contextPanel.FindChildTraverse('SpecVoid');
if (!SpVoid && SpOwner) {
	SpVoid = $.CreatePanel('Panel', SpOwner, 'SpecVoid');
	SpVoid.hittest = false;
	SpSet(SpVoid, 'width', '0px');
	SpSet(SpVoid, 'height', '0px');
	SpSet(SpVoid, 'visibility', 'collapse');
}

var SpBuild = function (owner) {
	var plate = $.CreatePanel('Panel', owner, 'Spec');
	plate.hittest = false;
	plate.hittestchildren = false;
	SpSet(plate, 'width', Sp.width + 'px');
	SpSet(plate, 'height', Sp.height + 'px');
	SpSet(plate, 'horizontalAlign', 'center');
	SpSet(plate, 'verticalAlign', 'bottom');
	SpSet(plate, 'marginBottom', Sp.bottom + 'px');
	SpSet(plate, 'zIndex', '20');
	SpSet(plate, 'overflow', 'noclip');
	SpSet(plate, 'opacity', '0.0');
	plate.SpUp = false;
	SpSet(plate, 'transitionProperty', 'opacity');
	SpSet(plate, 'transitionDuration', Sp.fade + 's');
	SpSet(plate, 'transitionTimingFunction', 'ease-in-out');
	PaintArt(plate, 'gotvct', {opacity: Sp.plateOpacity});

	var SpStrip = $.CreatePanel('Panel', plate, 'SpecStrip');
	SpStrip.hittest = false;
	SpSet(SpStrip, 'width', '100%');
	SpSet(SpStrip, 'height', Sp.stripHeight + 'px');
	SpSet(SpStrip, 'horizontalAlign', 'right');
	SpSet(SpStrip, 'verticalAlign', 'bottom');
	SpSet(SpStrip, 'backgroundColor', Sp.stripBg);

	var SpFrame = $.CreatePanel('Panel', plate, 'SpecAvatar');
	SpFrame.hittest = false;
	SpSet(SpFrame, 'width', Sp.avatar + 'px');
	SpSet(SpFrame, 'height', Sp.avatar + 'px');
	SpSet(SpFrame, 'horizontalAlign', 'left');
	SpSet(SpFrame, 'verticalAlign', 'top');
	SpSet(SpFrame, 'marginTop', Sp.avatarTop + 'px');
	SpSet(SpFrame, 'backgroundColor', Sp.avatarBg);

	SpReclaimAvatar(owner, plate);

	var SpNameLabel = $.CreatePanel('Label', plate, 'SpecName');
	SpNameLabel.hittest = false;
	SpNameLabel.AddClass('additive');
	SpSet(SpNameLabel, 'width', '100%');
	SpSet(SpNameLabel, 'maxWidth', (Sp.width - Sp.nameLeft - Sp.nameRight) + 'px');
	SpSet(SpNameLabel, 'height', (Sp.nameSize + 4) + 'px');
	SpSet(SpNameLabel, 'horizontalAlign', 'left');
	SpSet(SpNameLabel, 'verticalAlign', 'center');
	SpSet(SpNameLabel, 'marginLeft', Sp.nameLeft + 'px');
	SpSet(SpNameLabel, 'marginBottom', Sp.nameLift + 'px');
	SpSet(SpNameLabel, 'textAlign', 'left');
	SpSet(SpNameLabel, 'fontFamily', 'Stratum2');
	SpSet(SpNameLabel, 'fontWeight', 'bold');
	SpSet(SpNameLabel, 'fontSize', Sp.nameSize + 'px');
	SpSet(SpNameLabel, 'lineHeight', Sp.nameSize + 'px');
	SpSet(SpNameLabel, 'letterSpacing', '0px');
	SpSet(SpNameLabel, 'color', Sp.nameNone);
	SpSet(SpNameLabel, 'textOverflow', 'ellipsis');

	var SpWeaponLabel = $.CreatePanel('Label', plate, 'SpecWeapon', {html: 'true'});
	SpWeaponLabel.hittest = false;
	SpSet(SpWeaponLabel, 'width', (Sp.width - Sp.nameLeft) + 'px');
	SpSet(SpWeaponLabel, 'horizontalAlign', 'right');
	SpSet(SpWeaponLabel, 'verticalAlign', 'center');
	SpSet(SpWeaponLabel, 'marginBottom', Sp.weaponBottom + 'px');
	SpSet(SpWeaponLabel, 'paddingRight', Sp.weaponRight + 'px');
	SpSet(SpWeaponLabel, 'textAlign', 'right');
	SpSet(SpWeaponLabel, 'fontFamily', 'Stratum2');
	SpSet(SpWeaponLabel, 'fontWeight', 'normal');
	SpSet(SpWeaponLabel, 'fontSize', Sp.weaponSize + 'px');
	SpSet(SpWeaponLabel, 'lineHeight', Sp.weaponSize + 'px');
	SpSet(SpWeaponLabel, 'letterSpacing', '0px');
	SpSet(SpWeaponLabel, 'color', Sp.nameNone);
	SpSet(SpWeaponLabel, 'textOverflow', 'ellipsis');

	return plate;
};

var SpRead = function (owner, want) {
	var panel = SpFind(owner, want);
	if (!panel)
		return '';
	var text = panel.text || '';
	var first = text.charAt(0);
	return (first === '{' || first === '#') ? '' : text;
};

var SpMarkup = function (text) {
	return text.replace(/<img[^>]*>/gi, '').replace(/\s+/g, ' ').trim();
};

var SpReclaimAvatar = function (owner, plate) {
	var frame = plate ? plate.FindChildTraverse('SpecAvatar') : null;
	var avatar = SpFind(owner, SpBorrow);
	if (!avatar || !frame)
		return;
	if (avatar.GetParent() !== frame) {
		if (!avatar.SpHome || !avatar.SpHome.IsValid())
			avatar.SpHome = avatar.GetParent();
		avatar.AddClass('spec-borrowed');
		avatar.SetParent(frame);
	}
	var faces = avatar.FindChildrenWithClassTraverse('HudSpecplayerRoot__avatar');
	var face = Sp.avatar - 2 * Sp.avatarInset;
	for (var at = 0; at < faces.length; ++at) {
		SpSet(faces[at], 'width', face + 'px');
		SpSet(faces[at], 'height', face + 'px');
		SpSet(faces[at], 'borderRadius', '0px');
	}
};

var SpParkStock = function (owner) {
	if (SpVoid && !SpVoid.IsValid())
		SpVoid = contextPanel.FindChildTraverse('SpecVoid');
	if (!SpVoid && SpOwner && SpOwner.IsValid()) {
		SpVoid = $.CreatePanel('Panel', SpOwner, 'SpecVoid');
		SpVoid.hittest = false;
		SpSet(SpVoid, 'width', '0px');
		SpSet(SpVoid, 'height', '0px');
		SpSet(SpVoid, 'visibility', 'collapse');
	}
	if (!SpVoid)
		return;
	for (var victim of ['jsHudSpecplayer__Bg', 'HudHighlightClip']) {
		var panel = owner.FindChildTraverse(victim);
		if (panel && panel.GetParent() !== SpVoid) {
			panel.SetParent(SpVoid);
		}
		if (panel) {
			SpSet(panel, 'visibility', 'collapse');
			SpSet(panel, 'y', Sp.park + 'px');
		}
	}
};

if (SpOwner)
	SpBuild(SpOwner);

var SpGeneration = (typeof SpGeneration === 'undefined' ? 0 : SpGeneration) + 1;

var SpTick = function (generation) {
	if (generation !== SpGeneration)
		return;
	try {
		SpWatch();
	} catch (error) {
			}
	$.Schedule(0.25, function () {
		SpTick(generation);
	});
};

var SpWatch = function () {
	var owner = contextPanel.FindChildTraverse('jsHudHealthArmorAmmoMore');
	if (!owner)
		return;

	var plate = owner.FindChildTraverse('Spec');
	if (!plate || !plate.IsValid())
		plate = SpBuild(owner);

	var watching = SpWatching(owner) || SpHudDiffers();
	if (plate) {
		if (plate.SpUp !== watching) {
			plate.SpUp = watching;
			SpSet(plate, 'opacity', watching ? '1.0' : '0.0');
		}
		if (!watching)
			return;

		var name = SpRead(owner, SpSources.name);
		var weapon = SpMarkup(SpRead(owner, SpSources.weapon));
		var team = SpTeam(owner);

		var nameLabel = plate.FindChildTraverse('SpecName');
		if (nameLabel && nameLabel.text !== name)
			nameLabel.text = name;
		var weaponLabel = plate.FindChildTraverse('SpecWeapon');
		if (weaponLabel && weaponLabel.SpWeaponText !== weapon) {
			weaponLabel.SpWeaponText = weapon;
			weaponLabel.text = weapon;
		}

		if (plate.SpSide !== team) {
			plate.SpSide = team;
			PaintArt(plate, team === 't' ? 'gotvt' : 'gotvct', {opacity: Sp.plateOpacity});
			if (nameLabel)
				SpSet(nameLabel, 'color', team === 'ct' ? Sp.nameCt
					: (team === 't' ? Sp.nameT : Sp.nameNone));
		}
	}

	try {
		SpParkStock(owner);
	} catch (error) {
			}
	try {
		SpReclaimAvatar(owner, plate);
	} catch (error) {
			}
};

SpTick(SpGeneration);
]===],
    ["teamcolor.js"] = [===[var TeamColor = (function () {

	var Fallback = ['100,100,100', '199,187,139', '168,122,224', '116,172,87', '103,167,244', '234,124,68'];

	var Convar = function (name) {
		try {
			return GameInterfaceAPI.GetSettingString(name);
		} catch (error) {
			return '';
		}
	};

	var AsRGB = function (raw, fallback) {
		if (raw && String(raw).indexOf(' ') >= 0)
			return String(raw).split(' ').join(',');
		return fallback;
	};

	var colorRGB = [
		Fallback[0],
		AsRGB(Convar('cl_teammate_color_1'), Fallback[1]),
		AsRGB(Convar('cl_teammate_color_2'), Fallback[2]),
		AsRGB(Convar('cl_teammate_color_3'), Fallback[3]),
		AsRGB(Convar('cl_teammate_color_4'), Fallback[4]),
		AsRGB(Convar('cl_teammate_color_5'), Fallback[5]),
	];

	var GetTeamColor = function (index) {
		var at = Number(index);
		if (at >= 0 && at <= 4)
			return colorRGB[at + 1];
		return colorRGB[0];
	};

	var GetTeamColorCss = function (index) {
		return 'rgb(' + GetTeamColor(index) + ')';
	};

	return {
		GetTeamColor: GetTeamColor,
		GetTeamColorCss: GetTeamColorCss,
	};
})();
]===],
    ["teamcounter.js"] = [===[var TcRoot = function (counter) {
	return counter || contextPanel.FindChildTraverse('HudTeamCounter');
};

var SetFailures = {};

var Set = function (panel, property, value) {
	try {
		panel.style[property] = value;
	} catch (error) {
		if (!SetFailures[property]) {
			SetFailures[property] = true;
					}
	}
};

var Tc = {
	plate: '#000000d4',
	timerSize: '23px',
	scoreSize: '22px',
	scoreCt: '#6f9ec4',
	scoreT: '#b99636',
	scoreGap: '1px',
	aliveWidth: '54px',
	aliveHeight: '54px',
	aliveGap: '3px',
	countSize: '40px',
	aliveTextSize: '13px',
	aliveTextColor: '#999999',
	timerHeight: '27px',
	scoreRowHeight: '27px',
	scoreBgHeight: '27px',
	scoreBgTop: '1px',
	columnWidth: 75,
	bombY: '-19px',
	bombHeight: '84px',
};

var ChromeClasses = ['equipinfo__bg-container', 'equipinfo__container', 'healthbar-container',
	'healthbar__bg', 'healthbar__health-number', 'equipinfo__row--health', 'AvatarL__HealthBar',
	'AvatarL_BG', 'AvatarL__name', 'prdr__root'];

var ChromeIds = ['PlayerCount'];

var HideChrome = function (counter) {
	var root = TcRoot(counter);
	if (!root)
		return;
	for (var group of ChromeClasses) {
		var panels = root.FindChildrenWithClassTraverse(group);
		for (var at = 0; at < panels.length; ++at) {
			Set(panels[at], 'visibility', 'collapse');
			panels[at].RemoveClass(group);
		}
	}
	for (var id of ChromeIds) {
		var panel = root.FindChildTraverse(id);
		if (panel)
			Set(panel, 'visibility', 'collapse');
	}
};

var StyleScore = function (counter) {
	var root = TcRoot(counter);
	if (!root)
		return;
	var timer = root.FindChildTraverse('TimerText');
	if (timer) {
		Set(timer, 'fontFamily', 'Stratum2 Bold Monodigit');
		Set(timer, 'fontSize', Tc.timerSize);
		Set(timer, 'color', '#ffffff');
	}
	var timerBox = root.FindChildTraverse('Timer');
	if (timerBox)
		Set(timerBox, 'backgroundColor', Tc.plate);
	var gameTime = root.FindChildTraverse('GameTime');
	if (gameTime)
		Set(gameTime, 'height', Tc.timerHeight);

	var gap = parseInt(Tc.scoreGap, 10) || 0;

	var scoreBgRight = Math.floor((Tc.columnWidth - gap) / 2);
	var scoreBgLeft = Tc.columnWidth - gap - scoreBgRight;
	var column = root.FindChildTraverse('ScoreAndTimeAndBomb');
	if (column)
		Set(column, 'width', Tc.columnWidth + 'px');
	if (timer)
		Set(timer, 'width', (Tc.columnWidth - 2) + 'px');

	for (var side of [['ScoreCT', Tc.scoreCt], ['ScoreT', Tc.scoreT]]) {
		var score = root.FindChildTraverse(side[0]);
		if (!score)
			continue;
		Set(score, 'fontFamily', 'Stratum2 Bold Monodigit');
		Set(score, 'fontSize', Tc.scoreSize);
		Set(score, 'color', side[1]);
		score.RemoveClass('additive');
	}

	for (var bgSide of [['GameScore__BGL', 'marginRight', scoreBgLeft], ['GameScore__BGR', 'marginLeft', scoreBgRight]])
		for (var bg of root.FindChildrenWithClassTraverse(bgSide[0])) {
			Set(bg, 'backgroundColor', Tc.plate);
			Set(bg, bgSide[1], Tc.scoreGap);
			Set(bg, 'height', Tc.scoreBgHeight);
			Set(bg, 'marginTop', Tc.scoreBgTop);
			Set(bg, 'width', bgSide[2] + 'px');
		}
	var scoreRow = root.FindChildTraverse('GameScore');
	if (scoreRow) {
		Set(scoreRow, 'marginTop', Tc.scoreGap);
		Set(scoreRow, 'height', Tc.scoreRowHeight);
	}

	var bombStatus = root.FindChildTraverse('BombStatus');
	if (bombStatus) {
		Set(bombStatus, 'y', Tc.bombY);
		Set(bombStatus, 'height', Tc.bombHeight);
	}
};

var CountSide = function (box, counter) {
	for (var at = box; at && at !== counter; at = at.GetParent()) {
		if (at.BHasClass('team__large_container--left'))
			return 'left';
		if (at.BHasClass('team__large_container--right'))
			return 'right';
	}
	return null;
};

var StyleCompact = function (counter, compact) {
	var root = TcRoot(counter);
	if (!root)
		return;

	for (var rowId of ['TeamLargeCT', 'TeamLargeT']) {
		var row = root.FindChildTraverse(rowId);
		if (row)
			Set(row, 'visibility', compact ? 'collapse' : 'visible');
	}

	var boxes = root.FindChildrenWithClassTraverse('TeamLarge__PlayerCount');
	for (var fresh = 0; fresh < boxes.length; ++fresh) {
		var side = CountSide(boxes[fresh], root);
		if (!side)
			continue;
		boxes[fresh].AddClass(side === 'left' ? 'alive-ct' : 'alive-t');
		boxes[fresh].RemoveClass('TeamLarge__PlayerCount');
	}

	var sides = [['alive-ct', 'alivect', 'right'], ['alive-t', 'alivet', 'left']];
	for (var pair of sides) {
		var found = root.FindChildrenWithClassTraverse(pair[0]);
		for (var at = 0; at < found.length; ++at) {
			var box = found[at];
			var parent = box.GetParent();
			var direct = parent && (parent.BHasClass('horizontal-align-right')
				|| parent.BHasClass('team__large_container--left')
				|| parent.BHasClass('team__large_container--right')
				|| (parent.GetParent() && (parent.GetParent().BHasClass('team__large_container--left')
					|| parent.GetParent().BHasClass('team__large_container--right'))));
			if (!direct) {
				Set(box, 'visibility', 'collapse');
				continue;
			}
			Set(box, 'visibility', 'visible');
			Set(box, 'width', Tc.aliveWidth);
			Set(box, 'height', Tc.aliveHeight);
			Set(box, 'horizontalAlign', pair[2]);
			Set(box, 'verticalAlign', 'top');
			Set(box, 'marginLeft', Tc.aliveGap);
			Set(box, 'marginRight', Tc.aliveGap);
			Set(box, 'opacity', compact ? '1.0' : '0.0');
			PaintArt(box, pair[1]);
			Set(box, 'fontFamily', 'Stratum2 Bold Monodigit');
			Set(box, 'fontSize', Tc.countSize);
			Set(box, 'color', '#ffffff');
			Set(box, 'textShadow', '0px 0px 2px 4.0 #000000');
			Set(box, 'textAlign', 'center');
			Set(box, 'paddingTop', '2px');

			for (var alive of box.Children()) {
				Set(alive, 'fontFamily', 'Stratum2');
				Set(alive, 'fontWeight', 'light');
				Set(alive, 'fontSize', Tc.aliveTextSize);
				Set(alive, 'color', Tc.aliveTextColor);
				Set(alive, 'opacity', '0.57');
				Set(alive, 'textShadow', '1px 1px 1px 2.0 #000000');
				Set(alive, 'textAlign', 'center');
				Set(alive, 'horizontalAlign', 'center');
				Set(alive, 'verticalAlign', 'top');
				Set(alive, 'marginTop', '37px');
				Set(alive, 'marginLeft', '0px');
				Set(alive, 'marginRight', '0px');
				Set(alive, 'height', '14px');
				Set(alive, 'width', '100%');
			}
		}
	}
};

var TileTeam = function (tile, counter) {
	for (var at = tile; at && at !== counter; at = at.GetParent()) {
		if (at.id === 'TeamLargeCT')
			return 'ct';
		if (at.id === 'TeamLargeT')
			return 't';
	}
	return null;
};

var StyleAvatars = function (counter) {
	var root = TcRoot(counter);
	if (!root)
		return;
	var tiles = root.FindChildrenWithClassTraverse('AvatarLargeSnippet');
	for (var at = 0; at < tiles.length; ++at) {
		var tile = tiles[at];
		var team = TileTeam(tile, root);
		var imageBg = tile.FindChildTraverse('AvatarL__ImageBG');
		if (imageBg && team) {
			Set(imageBg, 'border', '0px solid #00000000');
			PaintArt(imageBg, team === 'ct' ? 'teamct' : 'teamt',
				{size: '92% 86%', position: '50% 25%'});
		}
		var skull = tile.FindChildTraverse('Skull');
		if (skull)
			PaintArt(skull, 'aliveskull');
	}
};

var CounterApply = function () {
	var counter = contextPanel.FindChildTraverse('HudTeamCounter');
	if (!counter)
		return;
	var compact = counter.BHasClass('PlayerCountInsteadOfAvatars');
	if (counter.BHasClass('counter-compact') !== compact) {
		if (compact)
			counter.AddClass('counter-compact');
		else
			counter.RemoveClass('counter-compact');
	}
	StyleScore(counter);
	StyleCompact(counter, compact);
	StyleAvatars(counter);
	HideChrome(counter);
};

CounterApply();

var CounterGeneration = (typeof CounterGeneration === 'undefined' ? 0 : CounterGeneration) + 1;

var CounterTick = function (generation) {
	if (generation !== CounterGeneration)
		return;
	try {
		CounterApply();
	} catch (error) {
			}
	$.Schedule(0.25, function () {
		CounterTick(generation);
	});
};

$.Schedule(0.25, (function (generation) {
	return function () {
		CounterTick(generation);
	};
})(CounterGeneration));
if (typeof CounterEvents === 'undefined') {
	var CounterEvents = true;
	var CounterOnEvent = function (what) {
		try {
			CounterApply();
		} catch (error) {
					}
		$.Schedule(0.0, function () {
			try {
				CounterApply();
			} catch (error) {
							}
		});
	};
	for (var eventName of ['OnRoundStart', 'OnRoundFreezeTimeEnd', 'Player_Death']) {
		$.RegisterForUnhandledEvent(eventName, (function (name) {
			return function () {
				CounterOnEvent(name);
			};
		})(eventName));
	}
}
]===],
    ["voice.js"] = [===[var VoiceGeneration = (typeof VoiceGeneration === 'undefined' ? 0 : VoiceGeneration) + 1;

var VoiceDress = function (notice) {
	var texts = notice.FindChildrenWithClassTraverse('VoiceText');
	for (var at = 0; at < texts.length; ++at) {
		try {
			texts[at].style.color = '#7099DA';
			texts[at].style.fontSize = '22px';
			texts[at].style.fontWeight = 'medium';
			texts[at].style.letterSpacing = '0px';
			texts[at].style.textShadow = '1px 1px 0px #000000';
		} catch (error) {
						return;
		}
	}
};

var VoiceTick = function (generation) {
	if (generation !== VoiceGeneration)
		return;
	try {
		var host = contextPanel.FindChildTraverse('VoicePanel');
		if (host) {
			var notices = host.FindChildrenWithClassTraverse('VoiceNotice');
			for (var at = 0; at < notices.length; ++at) {
				if (!notices[at].BHasClass('dressed')) {
					notices[at].AddClass('dressed');
					VoiceDress(notices[at]);
				}
			}
		}
	} catch (error) {
			}
	$.Schedule(0.25, function () {
		VoiceTick(generation);
	});
};

$.Schedule(0.25, (function (generation) {
	return function () {
		VoiceTick(generation);
	};
})(VoiceGeneration));
]===],
    ["vote.js"] = [===[var VoteBox = {
	width: '330px',
	baseBg: '#171717',
	headerBg: 'gradient( linear, 0% 0%, 100% 0%, from( #313131 ), color-stop( 0.4, #313131 ),'
		+ ' to( #171717 ) )',
	headerBorder: '2px solid #171717',
	headerPadding: '6px 0px 7px 8px',
	headerIconWidth: '29px',
	headerIconHeight: '28px',
	headerLabelSize: '21px',
	bodyBg: '#171717',
	bodyLabelColor: '#cfcdaa',
	bodyLabelSize: '20px',
	bodyLabelLine: '22px',
	boxesHeight: '94px',
	boxHeight: '43px',
	boxBg: 'gradient( linear, 0% 0%, 100% 0%, from( #383838 ), color-stop( 0.5, #363636 ),'
		+ ' to( #272727 ) )',
	countSize: '34px',
	yesColor: 'green',
	noColor: 'red',
	footerBg: '#000000FD',
	footerSize: '25px',
};

var VoteSet = function (panel, property, value) {
	if (!panel)
		return;
	try {
		panel.style[property] = value;
	} catch (error) {
			}
};

var VoteKillDots = function (panel, depth) {
	if (!panel || depth > 12)
		return;
	VoteSet(panel, 'backgroundImage', 'none');
	VoteSet(panel, 'backgroundImgOpacity', '0');
	var kids = panel.Children();
	for (var kid = 0; kid < kids.length; ++kid)
		VoteKillDots(kids[kid], depth + 1);
};

var VoteDress = function (root) {
	VoteSet(root, 'backgroundColor', VoteBox.baseBg);
	VoteSet(root, 'worldBlur', 'none');
	VoteSet(root, 'boxShadow', '0px 0px 1px 0px #ffffff30');
	VoteKillDots(root, 0);

	var VoteHeaders = root.FindChildrenWithClassTraverse('hud-vote-header');
	for (var VoteHeaderAt = 0; VoteHeaderAt < VoteHeaders.length; ++VoteHeaderAt) {
		var VoteHeader = VoteHeaders[VoteHeaderAt];
		VoteSet(VoteHeader, 'backgroundColor', VoteBox.headerBg);
		VoteSet(VoteHeader, 'borderTop', VoteBox.headerBorder);
		VoteSet(VoteHeader, 'borderLeft', VoteBox.headerBorder);
		VoteSet(VoteHeader, 'borderRight', VoteBox.headerBorder);
		VoteSet(VoteHeader, 'padding', VoteBox.headerPadding);

		var VoteIcon = VoteHeader.FindChildTraverse('VoteHeaderIcon');
		if (VoteIcon) {
			VoteSet(VoteIcon, 'width', VoteBox.headerIconWidth);
			VoteSet(VoteIcon, 'height', VoteBox.headerIconHeight);
			VoteSet(VoteIcon, 'brightness', '1.3');
			if (VoteHeader.BHasClass('vote-header-passed'))
				VoteIcon.SetImage(ArtUrl('yesvote'));
			else if (VoteHeader.BHasClass('vote-header-failed'))
				VoteIcon.SetImage(ArtUrl('novote'));
		}

		var VoteHeaderLabels = VoteHeader.FindChildrenWithClassTraverse('hud-vote-header__label');
		for (var VoteLabelAt = 0; VoteLabelAt < VoteHeaderLabels.length; ++VoteLabelAt) {
			VoteSet(VoteHeaderLabels[VoteLabelAt], 'fontSize', VoteBox.headerLabelSize);
			VoteSet(VoteHeaderLabels[VoteLabelAt], 'letterSpacing', '0px');
			VoteSet(VoteHeaderLabels[VoteLabelAt], 'fontWeight', 'normal');
		}
	}

	var VoteBodies = root.FindChildrenWithClassTraverse('hud-vote-body');
	for (var VoteBodyAt = 0; VoteBodyAt < VoteBodies.length; ++VoteBodyAt) {
		var VoteBody = VoteBodies[VoteBodyAt];
		VoteSet(VoteBody, 'backgroundColor', VoteBox.bodyBg);
		if (VoteBody.BHasClass('additive'))
			VoteBody.RemoveClass('additive');
		var VoteDescs = VoteBody.FindChildrenWithClassTraverse('hud-vote-body__label');
		for (var VoteDescAt = 0; VoteDescAt < VoteDescs.length; ++VoteDescAt) {
			VoteSet(VoteDescs[VoteDescAt], 'color', VoteBox.bodyLabelColor);
			VoteSet(VoteDescs[VoteDescAt], 'fontSize', VoteBox.bodyLabelSize);
			VoteSet(VoteDescs[VoteDescAt], 'lineHeight', VoteBox.bodyLabelLine);
			VoteSet(VoteDescs[VoteDescAt], 'letterSpacing', '0px');
			VoteSet(VoteDescs[VoteDescAt], 'fontWeight', 'normal');
		}

		VoteDressBox(VoteBody.FindChildrenWithClassTraverse('hud-vote-yesbox')[0], VoteBox.yesColor,
			'yesvote');
		VoteDressBox(VoteBody.FindChildrenWithClassTraverse('hud-vote-nobox')[0], VoteBox.noColor,
			'novote');

		var VoteColumn = VoteBody.FindChildrenWithClassTraverse('hud-vote-boxes')[0];
		if (VoteColumn) {
			VoteSet(VoteColumn, 'horizontalAlign', 'right');
			VoteSet(VoteColumn, 'height', VoteBox.boxesHeight);
			VoteSet(VoteColumn, 'flowChildren', 'down');
		}
	}

	var VoteFooters = root.FindChildrenWithClassTraverse('hud-vote-footer');
	for (var VoteFooterAt = 0; VoteFooterAt < VoteFooters.length; ++VoteFooterAt) {
		VoteSet(VoteFooters[VoteFooterAt], 'backgroundColor', VoteBox.footerBg);
		if (VoteFooters[VoteFooterAt].BHasClass('additive'))
			VoteFooters[VoteFooterAt].RemoveClass('additive');
		var VoteFooterLabels = VoteFooters[VoteFooterAt].FindChildrenWithClassTraverse(
			'footer__vote-binding-label');
		for (var VoteBindAt = 0; VoteBindAt < VoteFooterLabels.length; ++VoteBindAt) {
			VoteSet(VoteFooterLabels[VoteBindAt], 'fontSize', VoteBox.footerSize);
			VoteSet(VoteFooterLabels[VoteBindAt], 'fontWeight', 'medium');
			VoteSet(VoteFooterLabels[VoteBindAt], 'letterSpacing', '0px');
		}
	}
};

var VoteDressBox = function (box, colour, art) {
	if (!box)
		return;
	VoteSet(box, 'height', VoteBox.boxHeight);
	VoteSet(box, 'backgroundColor', VoteBox.boxBg);
	var kids = box.Children();
	for (var kid = 0; kid < kids.length; ++kid) {
		if (kids[kid].paneltype === 'Image')
			kids[kid].SetImage(ArtUrl(art));
		else if (kids[kid].paneltype === 'Label') {
			VoteSet(kids[kid], 'fontSize', VoteBox.countSize);
			VoteSet(kids[kid], 'fontWeight', 'bold');
			VoteSet(kids[kid], 'textAlign', 'center');
			VoteSet(kids[kid], 'color', colour);
		}
	}
};

var VoteGeneration = (typeof VoteGeneration === 'undefined' ? 0 : VoteGeneration) + 1;

var VoteTick = function (generation) {
	if (generation !== VoteGeneration)
		return;
	try {
		var root = contextPanel.FindChildrenWithClassTraverse('hud-vote')[0];
		if (root) {
			if (!root.BHasClass('vote-dressed')) {
				root.AddClass('vote-dressed');
				VoteDress(root);
			}
			var wanted = root.BHasClass('hud-vote-type--auto-instant-surrender')
				? '480px' : VoteBox.width;
			if (root.LastWidth !== wanted) {
				root.LastWidth = wanted;
				VoteSet(root, 'width', wanted);
			}
		}
	} catch (error) {
			}
	$.Schedule(0.25, function () {
		VoteTick(generation);
	});
};

$.Schedule(0.0, (function (generation) {
	return function () {
		VoteTick(generation);
	};
})(VoteGeneration));
]===],
    ["weapon_select.js"] = [===[var Ws = {
	blockRaise: 68,
	iconScale: 0.85,
	iconNudge: 6,
	iconDim: '#606060',
	iconLit: '#ffffff',

	plateOpacity: '0.58',

	plateWidth: '216px',
	plateRight: 0,

	keySize: 18,
	keyOpacity: '0.92',
	nameSize: 18,
	nameSpacing: '-0.4px',
	nameTop: 1,
	ownedColor: '#BFBFBF',
	ownedOpacity: '0.95',
	countSize: 16,
	countBottom: 5,
	keySource: 'bind',
	keyChars: 1,
	shadow: '0px 0px 0px #00000000',
	kitWidth: 43,
	kitHeight: 45,
	kitRight: 16,
	kitGap: 9,
	line: 84,
};

var WsList = contextPanel.FindChildTraverse('weapon-selection-list');
var WsAlways = contextPanel.FindChildTraverse('id-weapon-selection-list__always-on-container');
var WsClassic = null;
for (var WsAt = WsAlways || WsList; WsAt; WsAt = WsAt.GetParent())
	if (WsAt.BHasClass('weapon-selection-classic')) {
		WsClassic = WsAt;
		break;
	}

var WsRarityConvar = 'cl_weapon_selection_rarity_color';
try {
	var WsRarityWas = GameInterfaceAPI.GetSettingString(WsRarityConvar);
	if (WsRarityWas === '1') {
	} else {
		GameInterfaceAPI.ConsoleCommand(WsRarityConvar + ' 1');
	}
} catch (WsRarityError) {
	}

var WsRarityLogged = false;
var WsOwnerLogged = false;

var WsOldDefuse = contextPanel.FindChildTraverse('Defuse');
if (WsOldDefuse)
	WsOldDefuse.DeleteAsync(0);

if (WsClassic) {
	var WsDefuseIcon = $.CreatePanel('Image', WsClassic, 'Defuse');
	WsDefuseIcon.hittest = false;
	WsDefuseIcon.SetImage('s2r://panorama/images/icons/ui/defuser_white.vsvg');
	WsDefuseIcon.style.width = Ws.kitWidth + 'px';
	WsDefuseIcon.style.height = Ws.kitHeight + 'px';
	WsDefuseIcon.style.horizontalAlign = 'right';
	WsDefuseIcon.style.marginRight = Ws.kitRight + 'px';
	WsDefuseIcon.style.marginBottom = Ws.kitGap + 'px';
	WsDefuseIcon.style.washColor = '#ffffff';
	WsDefuseIcon.style.visibility = 'collapse';
	var WsBottom = WsClassic.GetChild(0);
	if (WsBottom && WsBottom !== WsDefuseIcon)
		WsClassic.MoveChildBefore(WsDefuseIcon, WsBottom);
}

var WsOnce = function (panel, marker, write) {
	if (!panel || panel.BHasClass(marker))
		return false;
	panel.AddClass(marker);
	write(panel);
	return true;
};

var WsSlots = ['gear-slot--0', 'gear-slot--1', 'gear-slot--2', 'gear-slot--3', 'gear-slot--4'];
var WsRarityClasses = ['weapon-selection-item--rarity-0', 'weapon-selection-item--rarity-1',
	'weapon-selection-item--rarity-2', 'weapon-selection-item--rarity-3',
	'weapon-selection-item--rarity-4', 'weapon-selection-item--rarity-5',
	'weapon-selection-item--rarity-6', 'weapon-selection-item--rarity-7',
	'weapon-selection-item--rarity-99'];
var WsRarityColors = ['#ffffff', '#b0c3d9', '#5e98d9', '#4b69ff', '#8847ff', '#d32ce6', '#eb4b4b',
	'#e4ae39', '#ffd700'];

var WsWhich = function (panel, names) {
	for (var at = 0; at < names.length; ++at)
		if (panel.BHasClass(names[at]))
			return at;
	return -1;
};

if (WsClassic)
	WsClassic.style.transform = 'translateY(-' + Ws.blockRaise + 'px)';

var WsPips = function () {
	if (!WsAlways || !WsAlways.IsValid())
		return;
	for (var pip of WsAlways.FindChildrenWithClassTraverse('grenade-pip_container'))
		WsOnce(pip, 'ws-pip', function (panel) {
			panel.style.visibility = 'collapse';
		});
};

var WsGlow = function () {
	if (!WsAlways || !WsAlways.IsValid())
		return;
	for (var glow of WsAlways.FindChildrenWithClassTraverse('hud-bottom-row-background--right--objective'))
		WsOnce(glow, 'ws-glow-column', function (panel) {
			panel.style.x = '0px';
		});
};

var WsDefuse = function () {
	if (WsAlways && WsAlways.IsValid())
		for (var row of WsAlways.FindChildrenWithClassTraverse('kit'))
			WsOnce(row, 'ws-kit-hidden', function (panel) {
				panel.style.visibility = 'collapse';
			});

	var icon = contextPanel.FindChildTraverse('Defuse');
	if (!icon)
		return;
	var kit = false;
	for (var at = icon; at && !kit; at = at.GetParent())
		kit = at.BHasClass('HUD--has-kit');

	if (icon.BHasClass('ws-haskit') !== kit) {
		icon.SetHasClass('ws-haskit', kit);
		icon.style.visibility = kit ? 'visible' : 'collapse';
	}
};

var WsBand = function () {
	if (!WsAlways || !WsAlways.IsValid())
		return;

	var nades = 0;
	var bombs = 0;
	var bombRow = null;
	for (var row of WsAlways.FindChildrenWithClassTraverse('weapon-row')) {
		var items = row.FindChildrenWithClassTraverse('weapon-selection-item').length;
		if (row.BHasClass('gear-slot--3'))
			nades += items;
		else if (row.BHasClass('gear-slot--4')) {
			bombRow = row;
			bombs += items;
		}
	}
	var lines = (nades > 0 ? 1 : 0) + (bombs > 0 ? 1 : 0);

	var drop = lines > 1 ? Ws.line : 0;
	if (bombRow && bombRow.WsDrop !== drop) {
		bombRow.WsDrop = drop;
		bombRow.style.transform = 'translateY(' + drop + 'px)';
	}

	if (WsAlways.WsLines !== lines) {
		WsAlways.WsLines = lines;
		WsAlways.style.visibility = lines > 0 ? 'visible' : 'collapse';
		WsAlways.style.height = (Math.max(lines, 1) * Ws.line) + 'px';
	}
};

var WsEmbeddedDone = false;
var WsEmbeddedTicks = 0;

var WsEmbedded = function () {
	if (WsEmbeddedDone || (WsEmbeddedTicks++ % 10) !== 0)
		return;
	var panel = contextPanel.FindChildTraverse('EmbeddedHudWeaponSelection');
	if (!panel)
		return;
	panel.style.visibility = 'collapse';
	WsEmbeddedDone = true;
};

var WsRow = function (row) {
	var slot = WsWhich(row, WsSlots);
	WsOnce(row, 'ws-row-inset', function (panel) {
		panel.style.marginRight = '0px';
		for (var container of panel.FindChildrenWithClassTraverse('weapon-row-horiz-container'))
			container.style.marginRight = '6px';
	});

	for (var background of row.FindChildrenWithClassTraverse('weapon-row-background'))
		WsOnce(background, 'ws-plate', function (panel) {
			panel.style.width = Ws.plateWidth;
			panel.style.horizontalAlign = 'right';
			panel.style.marginRight = Ws.plateRight + 'px';
			PaintArt(panel, 'weaponplate', {size: '100% 100%', opacity: Ws.plateOpacity});
		});

	for (var number of row.FindChildrenWithClassTraverse('weapon-row-number')) {
		WsOnce(number, 'ws-key-2', function (panel) {
			panel.style.fontSize = Ws.keySize + 'px';
			panel.style.fontWeight = 'bold';
			panel.style.opacity = Ws.keyOpacity;
			panel.style.textShadow = Ws.shadow;
			panel.style.whiteSpace = 'nowrap';
			panel.style.textOverflow = 'noclip';
			panel.style.overflow = 'noclip';
		});
		var current = String(number.text || '').trim();
		var want = null;
		if (Ws.keySource === 'slot')
			want = slot >= 0 ? String(slot + 1) : null;
		else if (Ws.keyChars > 0)
			want = current.substring(0, Ws.keyChars);
		if (want && number.text !== want)
			number.text = want;
	}

	var iconTransform = 'scale3d(' + Ws.iconScale + ',' + Ws.iconScale + ',1)'
		+ (slot >= 3 ? ' translateY(' + Ws.iconNudge + 'px)' : '');

	for (var item of row.FindChildrenWithClassTraverse('weapon-selection-item')) {
		var selected = item.BHasClass('weapon-selection-item--selected');
		var rarity = WsWhich(item, WsRarityClasses);

		if (selected && !WsRarityLogged) {
			WsRarityLogged = true;
		}

		for (var icon of item.FindChildrenWithClassTraverse('weapon-selection-item-icon-main')) {
			WsOnce(icon, 'ws-icon', function (panel) {
				panel.style.transform = iconTransform;
				panel.style.opacity = '1.0';
				panel.style.overflow = 'noclip';
				if (slot >= 3)
					try {
						panel.style.preTransformScale2d = '-1, 1';
					} catch (error) {
											}
			});
			var wash = selected ? Ws.iconLit : Ws.iconDim;
			if (icon.WsWash !== wash) {
				icon.WsWash = wash;
				icon.style.washColor = wash;
			}
		}

		for (var box of item.FindChildrenWithClassTraverse('weapon-selection-item-icon'))
			WsOnce(box, 'ws-iconbox', function (panel) {
				panel.style.overflow = 'noclip';
			});

		var nameColor = selected && rarity >= 0 ? WsRarityColors[rarity] : '#ffffff';
		var plainName = '';
		for (var name of item.FindChildrenWithClassTraverse('weapon-selection-item-name-text')) {
			plainName = String(name.text || '');
			WsOnce(name, 'ws-name-2', function (panel) {
				panel.style.fontFamily = 'Stratum2';
				panel.style.fontWeight = 'bold';
				panel.style.fontSize = Ws.nameSize + 'px';
				panel.style.letterSpacing = Ws.nameSpacing;
				panel.style.marginTop = Ws.nameTop + 'px';
				panel.style.textOverflow = 'noclip';
				panel.style.textShadow = Ws.shadow;
			});
			if (name.WsColor !== nameColor) {
				name.WsColor = nameColor;
				name.style.color = nameColor;
			}
		}

		for (var owned of item.FindChildrenWithClassTraverse('weapon-selection-item-name-text-owned')) {
			WsOnce(owned, 'ws-owned-2', function (panel) {
				panel.style.fontFamily = 'Stratum2';
				panel.style.fontWeight = 'bold';
				panel.style.fontSize = Ws.nameSize + 'px';
				panel.style.letterSpacing = Ws.nameSpacing;
				panel.style.marginTop = Ws.nameTop + 'px';
				panel.style.textOverflow = 'noclip';
				panel.style.textShadow = Ws.shadow;
				panel.style.color = Ws.ownedColor;
				panel.style.opacity = Ws.ownedOpacity;
			});

			if (!selected || rarity < 0)
				continue;
			var ownedRaw = String(owned.text || '');
			var plainText = plainName && plainName.charAt(0) !== '{' && plainName.charAt(0) !== '#' ? plainName : '';
			var cut = plainText ? ownedRaw.indexOf(plainText) : -1;
			if (ownedRaw.indexOf('<font') >= 0 || cut < 0) {
				if (!WsOwnerLogged) {
					WsOwnerLogged = true;
				}
				continue;
			}
			var want = ownedRaw.slice(0, cut) + '<font color="' + nameColor + '">' + plainText + '</font>'
				+ ownedRaw.slice(cut + plainText.length);
			if (owned.WsOwnedWant !== want) {
				owned.WsOwnedWant = want;
				owned.text = want;
			}
			if (!WsOwnerLogged) {
				WsOwnerLogged = true;
			}
		}

		for (var count of item.FindChildrenWithClassTraverse('weapon-selection-item-count'))
			WsOnce(count, 'ws-count-2', function (panel) {
				panel.style.fontSize = Ws.countSize + 'px';
				panel.style.marginBottom = Ws.countBottom + 'px';
				panel.style.textShadow = Ws.shadow;
			});
	}
};

var WsGeneration = (typeof WsGeneration === 'undefined' ? 0 : WsGeneration) + 1;

var WsTick = function (generation) {
	if (generation !== WsGeneration)
		return;
	try {
		WsPips();
		WsBand();
		WsEmbedded();
		WsGlow();
		WsDefuse();
		for (var container of [WsAlways, WsList]) {
			if (!container || !container.IsValid())
				continue;
			for (var row of container.FindChildrenWithClassTraverse('weapon-row'))
				WsRow(row);
		}
	} catch (error) {
			}
	$.Schedule(0.1, function () {
		WsTick(generation);
	});
};

$.Schedule(0.0, (function (generation) {
	return function () {
		WsTick(generation);
	};
})(WsGeneration));
]===],
    ["weaponammo.js"] = [===[var WaOwner = contextPanel.FindChildTraverse('jsHudHealthArmorAmmoMore');
if (!WaOwner) {
	for (var WaAt = contextPanel.FindChildTraverse('hud-WPN-main'); WaAt; WaAt = WaAt.GetParent()) {
		if (WaAt.GetParent() === contextPanel) {
			WaOwner = WaAt;
			break;
		}
	}
}

var Wa = {
	plateWidth: 340,
	plateHeight: 59,
	rightGap: 0,
	bottomGap: 0,

	clipRight: 160,
	clipWidth: 72,
	clipY: 0,
	clipSize: 44,
	reserveRight: 110,
	reserveY: 2,
	reserveSize: 24,
	slashOpacity: '0.4',
	slashGap: 4,
	magWidth: 20,
	magGap: 4,
	magY: 1,

	color: '#ffffff',
	shadow: '0px 0px 3px 0.0 #000000DD',
	lowShadow: '0px 0px 9px 2.5 #DD0000',
	letterSpacing: 0,
};

var WaMags = ['magazine', 'banana_mag', 'shotgun_shell', 'box', 'revolver_loader', 'bizon_tube', 'p90'];
var WaMagClasses = WaMags.map(function (type) {
	return 'HUD--ammo-reserve--' + type;
});

var WaMagSrc = function (type) {
	return 's2r://panorama/images/hud/ammo_reserve_' + type + '.vsvg';
};

var WaAncestor = function (panel, names) {
	for (var at = panel; at; at = at.GetParent())
		for (var n = 0; n < names.length; ++n)
			if (at.BHasClass(names[n]))
				return names[n];
	return null;
};

var WaMain = WaOwner ? WaOwner.FindChildTraverse('hud-WPN-main') : null;
var WaSrcClip = null;
var WaSrcReserve = null;
if (WaMain) {
	WaMain.style.opacity = '0.0';
	var WaClipGroup = WaMain.FindChildrenWithClassTraverse('hud-WPN-text')[0];
	if (WaClipGroup)
		WaSrcClip = WaClipGroup.FindChildrenWithClassTraverse('hud-HA-health_or_ammo-label')[0];
	WaSrcReserve = WaMain.FindChildTraverse('HudReserveAmmoCounter');
}

var WaOldRoot = contextPanel.FindChildTraverse('Ammo');
if (WaOldRoot)
	WaOldRoot.DeleteAsync(0);

if (WaMain) {
	var WaRoot = $.CreatePanel('Panel', contextPanel, 'Ammo');
	WaRoot.hittest = false;
	WaRoot.style.width = Wa.plateWidth + 'px';
	WaRoot.style.height = Wa.plateHeight + 'px';
	WaRoot.style.horizontalAlign = 'right';
	WaRoot.style.verticalAlign = 'bottom';
	WaRoot.style.marginRight = Wa.rightGap + 'px';
	WaRoot.style.marginBottom = Wa.bottomGap + 'px';
	WaRoot.style.zIndex = '20';
	WaRoot.style.visibility = 'collapse';
	PaintArt(WaRoot, 'ammoplate');

	var WaClip = $.CreatePanel('Label', WaRoot, 'AmmoClip');
	WaClip.hittest = false;
	WaClip.style.width = Wa.clipWidth + 'px';
	WaClip.style.horizontalAlign = 'right';
	WaClip.style.verticalAlign = 'center';
	WaClip.style.marginRight = Wa.clipRight + 'px';
	WaClip.style.y = Wa.clipY + 'px';
	WaClip.style.fontFamily = 'Stratum2';
	WaClip.style.fontWeight = 'bold';
	WaClip.style.fontSize = Wa.clipSize + 'px';
	WaClip.style.lineHeight = Wa.clipSize + 'px';
	WaClip.style.color = Wa.color;
	WaClip.style.letterSpacing = Wa.letterSpacing + 'px';
	WaClip.style.textShadow = Wa.shadow;
	WaClip.style.textAlign = 'right';
	WaClip.style.textOverflow = 'shrink';

	var WaReserve = $.CreatePanel('Panel', WaRoot, 'AmmoReserve');
	WaReserve.hittest = false;
	WaReserve.style.flowChildren = 'right';
	WaReserve.style.width = 'fit-children';
	WaReserve.style.height = 'fit-children';
	WaReserve.style.horizontalAlign = 'right';
	WaReserve.style.verticalAlign = 'center';
	WaReserve.style.marginRight = (Wa.reserveRight - Wa.magWidth - Wa.magGap) + 'px';
	WaReserve.style.y = Wa.reserveY + 'px';

	var WaSlash = $.CreatePanel('Label', WaReserve, 'AmmoSlash');
	WaSlash.hittest = false;
	WaSlash.style.verticalAlign = 'center';
	WaSlash.style.fontFamily = 'Stratum2';
	WaSlash.style.fontWeight = 'bold';
	WaSlash.style.fontSize = Wa.reserveSize + 'px';
	WaSlash.style.lineHeight = Wa.reserveSize + 'px';
	WaSlash.style.color = Wa.color;
	WaSlash.style.opacity = Wa.slashOpacity;
	WaSlash.style.textShadow = Wa.shadow;
	WaSlash.style.marginRight = Wa.slashGap + 'px';
	WaSlash.text = '/';

	var WaCount = $.CreatePanel('Label', WaReserve, 'AmmoCount');
	WaCount.hittest = false;
	WaCount.style.verticalAlign = 'center';
	WaCount.style.fontFamily = 'Stratum2';
	WaCount.style.fontWeight = 'bold';
	WaCount.style.fontSize = Wa.reserveSize + 'px';
	WaCount.style.lineHeight = Wa.reserveSize + 'px';
	WaCount.style.color = Wa.color;
	WaCount.style.letterSpacing = Wa.letterSpacing + 'px';
	WaCount.style.textShadow = Wa.shadow;
	WaCount.style.textAlign = 'right';
	WaCount.style.marginRight = Wa.magGap + 'px';

	var WaMag = $.CreatePanel('Image', WaReserve, 'AmmoMag');
	WaMag.hittest = false;
	WaMag.SetImage(WaMagSrc('magazine'));
	WaMag.style.width = Wa.magWidth + 'px';
	WaMag.style.height = Wa.magWidth + 'px';
	WaMag.style.verticalAlign = 'center';
	WaMag.style.y = Wa.magY + 'px';
	WaMag.style.washColor = Wa.color;

}

var WaGeneration = (typeof WaGeneration === 'undefined' ? 0 : WaGeneration) + 1;
var WaRead = function (label) {
	if (!label)
		return null;
	try {
		var value = parseInt(label.text, 10);
		return isFinite(value) ? value : null;
	} catch (error) {
		return null;
	}
};

var WaTick = function (generation) {
	if (generation !== WaGeneration)
		return;
	try {
		var owner = contextPanel.FindChildTraverse('jsHudHealthArmorAmmoMore');
		var root = contextPanel.FindChildTraverse('Ammo');
		var main = contextPanel.FindChildTraverse('hud-WPN-main');
		if (owner && root && main) {
			var active = owner.BHasClass('HUD--HA--active');
			if (root.BHasClass('ammo-active') !== active) {
				root.SetHasClass('ammo-active', active);
				root.style.visibility = active ? 'visible' : 'collapse';
			}

			var clipLabel = contextPanel.FindChildTraverse('AmmoClip');
			var reserveRow = contextPanel.FindChildTraverse('AmmoReserve');
			var countLabel = contextPanel.FindChildTraverse('AmmoCount');
			var magIcon = contextPanel.FindChildTraverse('AmmoMag');

			var holding = !!WaAncestor(main, ['HUD--holding-0ammo', 'HUD--holding-1ammo']);
			if (clipLabel && reserveRow && clipLabel.BHasClass('ammo-empty') !== holding) {
				clipLabel.SetHasClass('ammo-empty', holding);
				clipLabel.style.visibility = holding ? 'collapse' : 'visible';
				reserveRow.style.visibility = holding ? 'collapse' : 'visible';
			}

			if (!holding) {
				var clip = WaRead(WaSrcClip);
				if (clipLabel && clip !== null && clipLabel.Value !== clip) {
					clipLabel.Value = clip;
					clipLabel.text = String(clip);
					var low = !!WaAncestor(main, ['HUD--ammo-clip--low']);
					if (clipLabel.Low !== low) {
						clipLabel.Low = low;
						clipLabel.style.textShadow = low ? Wa.lowShadow : Wa.shadow;
					}
				}

				var reserve = WaRead(WaSrcReserve);
				if (countLabel && reserve !== null && countLabel.Value !== reserve) {
					countLabel.Value = reserve;
					countLabel.text = String(reserve);
				}
				if (magIcon) {
					var found = WaAncestor(main, WaMagClasses);
					var type = found ? found.substring('HUD--ammo-reserve--'.length) : 'magazine';
					if (magIcon.Mag !== type) {
						magIcon.Mag = type;
						magIcon.SetImage(WaMagSrc(type));
					}
				}
			}
		}
	} catch (error) {
			}
	$.Schedule(0.1, function () {
		WaTick(generation);
	});
};

$.Schedule(0.0, (function (generation) {
	return function () {
		WaTick(generation);
	};
})(WaGeneration));
]===],
    ["winpanel.js"] = [===[var Win = {
	y: 112,
	width: 818,
	height: 126,
	titleSize: 38,
	titleTop: 9,
	titleColor: '#b9bfc5',
	mvpLeft: 21,
	mvpBottom: 6,
	avatar: 60,
	avatarBg: 'gradient( linear, 0% 0%, 0% 100%, from( #7d7d7d ), to( #464646) )',
	avatarShadow: '#000000A5 0px 0px 3px 2px',
	star: 16,
	starColor: '#ffd856',
	nameSize: 20,
	nameColor: '#c4c4c471',
	kitSize: 15,
	kitColor: '#bcbcbc9A',
	funfactSize: 19,
	funfactColor: '#FFFFFFC1',
	funfactBg: '#000000AE',
	flash: 0.4,
	flashIn: 0.16,
	fact: 0.22,
	factDrop: 110,
	hide: 0.2,
};

var WinDrawBg = 'gradient( linear, 100% 0%, 0% 0%, from( #00000000 ), color-stop( 0.20, #00000099 ),'
	+ ' color-stop( 0.50, #000000e6 ), color-stop( 0.80, #00000099 ), to( #00000000 ) )';

var WinNoShadow = '0px 0px 0px #00000000';

var WinFirst = function (root, cls) {
	if (!root)
		return null;
	var found = root.FindChildrenWithClassTraverse(cls);
	return found.length ? found[0] : null;
};

var WinOnce = function (panel, marker) {
	if (!panel || panel.BHasClass(marker))
		return false;
	panel.AddClass(marker);
	return true;
};

var WinHasClass = function (from, name) {
	for (var at = from; at; at = at.GetParent()) {
		if (at.BHasClass(name))
			return true;
		if (at === contextPanel)
			break;
	}
	return false;
};

var WinCollapse = function (panel) {
	if (WinOnce(panel, 'win-hidden'))
		panel.style.visibility = 'collapse';
};

var WinTeam = function (root) {
	if (WinHasClass(root, 'WinPanelRoot--Win--CT'))
		return 'ct';
	if (WinHasClass(root, 'WinPanelRoot--Win--T'))
		return 't';
	return 'draw';
};

var WinTitle = function (result) {
	return WinFirst(result, 'win-title') || WinFirst(result, 'WinPanel__Result__Title');
};

var WinTitleCache = (typeof WinTitleCache === 'undefined' ? {} : WinTitleCache);

var WinLocalize = function (token) {
	var text = $.Localize(token);
	return (text && text.length > 1 && text.charAt(0) !== '#') ? text : null;
};

var WinTitleText = function (team) {
	if (team === 'draw')
		return null;
	if (WinTitleCache[team])
		return WinTitleCache[team];
	var whole = team === 'ct'
		? (WinLocalize('#SFUI_Winpanel_ct_win') || WinLocalize('#SFUI_WinPanel_ct_win'))
		: (WinLocalize('#SFUI_Winpanel_t_win') || WinLocalize('#SFUI_WinPanel_t_win'));
	if (!whole) {
		var side = WinLocalize(team === 'ct' ? '#counter-terrorists' : '#terrorists')
			|| (team === 'ct' ? 'Counter-Terrorists' : 'Terrorists');
		whole = side + ' Win';
	}
	WinTitleCache[team] = whole;
	return whole;
};

var WinDressPlate = function (root, result) {
	if (!WinOnce(result, 'win-plate-3'))
		return;
	result.style.width = Win.width + 'px';
	result.style.height = Win.height + 'px';
	result.style.border = '0px solid #00000000';
	result.style.borderRadius = '0px';
	try {
		result.style.worldBlur = 'none';
	} catch (error) {
			}
	var section = WinFirst(root, 'WinPanelTopSection');
	if (section) {
		section.style.width = Win.width + 'px';
		section.style.marginBottom = '0px';
	}
	var contents = WinFirst(root, 'WinPanelTopSection__Contents');
	if (contents)
		contents.style.width = Win.width + 'px';

	var white = WinFirst(result, 'WinPanel__Result__white');
	if (white) {
		white.RemoveClass('win-hidden');
		white.style.visibility = 'visible';
		white.style.transitionProperty = 'opacity';
		white.style.transitionDuration = '0.06s';
		white.style.transitionDelay = '0s';
		white.style.opacity = '0.0';
		var first = result.GetChild(0);
		if (first && first !== white)
			result.MoveChildBefore(white, first);
	}
};

var WinDressTitle = function (title) {
	if (!title)
		return;
	title.AddClass('win-title');
	if (!WinOnce(title, 'win-title-2'))
		return;
	title.RemoveClass('WinPanel__Result__Title');
	title.style.fontFamily = 'Stratum2';
	title.style.fontSize = Win.titleSize + 'px';
	title.style.fontWeight = 'bold';
	title.style.color = Win.titleColor;
	title.style.washColor = '#FFFFFF';
	title.style.textShadow = WinNoShadow;
	title.style.width = '100%';
	title.style.height = (Win.titleSize + 22) + 'px';
	title.style.verticalAlign = 'top';
	title.style.horizontalAlign = 'center';
	title.style.textAlign = 'center';
	title.style.marginTop = Win.titleTop + 'px';
	title.style.marginBottom = '0px';
};

var WinPulse = function (plate, white, up) {
	try {
		if (!plate.BHasClass('win-shown'))
			return;
		plate.style.brightness = up ? '2.0' : '1.0';
		if (white)
			white.style.opacity = up ? '0.4' : '0.0';
	} catch (error) {
			}
};

var WinFadePlate = function (plate, white, shown) {
	if (!plate)
		return;
	if (WinOnce(plate, 'win-fade-1')) {
		plate.style.transform = 'translateY(0px)';
		plate.style.transform = 'none';
		plate.style.transitionProperty = 'opacity, brightness';
		plate.style.transitionDuration = Win.flashIn + 's, 0.06s';
		plate.style.transitionTimingFunction = 'linear';
		plate.style.transitionDelay = '0s';
		plate.style.opacity = '0.0';
		plate.style.brightness = '1.0';
		plate.RemoveClass('win-shown');
	}
	if (plate.BHasClass('win-shown') === shown)
		return;
	plate.SetHasClass('win-shown', shown);
	plate.style.transitionDuration = (shown ? Win.flashIn : Win.hide) + 's, 0.06s';
	plate.style.opacity = shown ? '1.0' : '0.0';
	if (!shown) {
		plate.style.brightness = '1.0';
		if (white)
			white.style.opacity = '0.0';
		return;
	}
	$.Schedule(Win.flash * 0.5, function () {
		WinPulse(plate, white, true);
	});
	$.Schedule(Win.flash * 0.75, function () {
		WinPulse(plate, white, false);
	});
};

var WinSlideRow = function (panel, shown) {
	if (!panel)
		return;

	if (WinOnce(panel, 'win-slide-4')) {

		panel.style.animationName = 'none';
		var stockText = panel.FindChildTraverse('FunFactText');
		if (stockText)
			stockText.style.animationName = 'none';
		panel.style.transitionProperty = 'opacity, transform';
		panel.style.transitionDuration = '0.1s, ' + Win.fact + 's';
		panel.style.transitionTimingFunction = 'linear, ease-out';
		panel.style.transitionDelay = '0s';
		panel.style.transform = 'translateY(' + Win.factDrop + 'px)';
		panel.style.opacity = '0.0';
		panel.RemoveClass('win-shown');
		return;
	}
	if (panel.BHasClass('win-shown') === shown)
		return;
	panel.SetHasClass('win-shown', shown);
	panel.style.transform = shown ? 'translateY(0px)' : 'translateY(' + Win.factDrop + 'px)';
	panel.style.opacity = shown ? '1.0' : '0.0';
};

var WinDressFunfact = function (root) {
	var funfact = root.FindChildTraverse('Funfact');
	var contents = WinFirst(root, 'WinPanelTopSection__Contents');
	if (!funfact || !contents || !WinOnce(funfact, 'win-funfact-2'))
		return;
	if (funfact.GetParent() !== contents) {
		funfact.SetParent(contents);
		var surrender = root.FindChildTraverse('Surrender');
		if (surrender)
			contents.MoveChildBefore(funfact, surrender);
	}
	funfact.style.width = '99.75%';
	funfact.style.horizontalAlign = 'center';
	funfact.style.backgroundColor = Win.funfactBg;
	funfact.style.marginTop = '2px';
	funfact.style.marginLeft = '2px';
	funfact.style.marginRight = '2px';
	funfact.style.padding = '6px 6px 8px 6px';
	funfact.style.height = (Win.funfactSize + 20) + 'px';

	var text = root.FindChildTraverse('FunFactText');
	if (text) {
		text.style.fontSize = Win.funfactSize + 'px';
		text.style.fontWeight = 'medium';
		text.style.color = Win.funfactColor;
		text.style.letterSpacing = '-0.2px';
		text.style.textAlign = 'center';
		text.style.width = '100%';
		text.style.height = (Win.funfactSize + 6) + 'px';
		text.style.margin = '0px';
		text.style.textShadow = WinNoShadow;
	}
};

var WinDressMvp = function (root, result) {
	var mvp = root.FindChildTraverse('MVP');
	if (mvp && WinOnce(mvp, 'win-mvp-2')) {
		if (mvp.GetParent() !== result)
			mvp.SetParent(result);
		mvp.style.verticalAlign = 'bottom';
		mvp.style.horizontalAlign = 'left';
		mvp.style.marginLeft = Win.mvpLeft + 'px';
		mvp.style.marginBottom = Win.mvpBottom + 'px';
		mvp.style.opacity = '1.0';
		mvp.style.transitionDuration = '0.0s';
	}
	if (mvp && mvp.GetParent() === result)
		WinCollapse(WinFirst(root, 'MVP_section'));

	var row = WinFirst(root, 'MVP__Winner');
	if (row && WinOnce(row, 'win-mvp-row')) {
		row.style.height = (Win.avatar + 6) + 'px';
		var icons = WinFirst(root, 'MVP__Winner_Icons');
		if (icons)
			icons.style.height = '100%';
	}

	var avatar = root.FindChildTraverse('MVPAvatar');
	if (avatar && WinOnce(avatar, 'win-avatar')) {
		avatar.style.width = Win.avatar + 'px';
		avatar.style.height = Win.avatar + 'px';
		avatar.style.verticalAlign = 'bottom';
		avatar.style.marginBottom = '3px';
		avatar.style.marginRight = '8px';
		avatar.style.backgroundColor = Win.avatarBg;
		avatar.style.boxShadow = Win.avatarShadow;
	}
	WinCollapse(root.FindChildTraverse('jsHonorIcon'));
};

var WinDressText = function (root) {
	var name = WinFirst(root, 'MVP__WinnerName');
	var reason = WinFirst(root, 'MVP__Reason');
	var row = name ? name.GetParent() : null;

	if (name && WinOnce(name, 'win-name-2')) {
		name.style.fontFamily = 'Stratum2';
		name.style.fontSize = Win.nameSize + 'px';
		name.style.fontWeight = 'medium';
		name.style.color = Win.nameColor;
		name.style.width = 'fit-children';
		name.style.maxWidth = '360px';
		name.style.height = (Win.nameSize + 6) + 'px';
		name.style.verticalAlign = 'middle';
		name.style.paddingLeft = '2px';
		name.style.brightness = '1.0';
		name.style.textShadow = WinNoShadow;
	}

	if (reason && row && WinOnce(reason, 'win-reason-2')) {
		if (reason.GetParent() !== row)
			reason.SetParent(row);
		reason.style.fontFamily = 'Stratum2';
		reason.style.backgroundColor = '#00000000';
		reason.style.color = Win.nameColor;
		reason.style.fontSize = Win.nameSize + 'px';
		reason.style.fontWeight = 'medium';
		reason.style.width = 'fit-children';
		reason.style.height = (Win.nameSize + 6) + 'px';
		reason.style.verticalAlign = 'middle';
		reason.style.padding = '0px';
		reason.style.marginLeft = '4px';
	}

	if (name && reason) {
		var rawName = String(name.text);
		if (rawName !== '' && rawName.indexOf('MVP: ') !== 0)
			name.text = 'MVP: ' + rawName;
		var rawReason = String(reason.text);
		if (rawReason.indexOf('MVP') === 0)
			reason.text = rawReason.substring(3).replace(/^[\s:.-]+/, '');
	}

	if (row && name && !root.FindChildTraverse('MvpStar')) {
		var star = $.CreatePanel('Image', row, 'MvpStar');
		star.SetImage('s2r://panorama/images/icons/ui/star.vsvg');
		star.style.width = Win.star + 'px';
		star.style.height = Win.star + 'px';
		star.style.verticalAlign = 'middle';
		star.style.margin = '0px 2px 3px 0px';
		star.style.washColor = Win.starColor;
		row.MoveChildBefore(star, name);
	}

	for (var kit of root.FindChildrenWithClassTraverse('MVP__MusicKitText')) {
		if (!WinOnce(kit, 'win-kit'))
			continue;
		kit.style.fontSize = Win.kitSize + 'px';
		kit.style.fontWeight = 'light';
		kit.style.color = Win.kitColor;
		kit.style.brightness = '1.0';
		kit.style.textShadow = WinNoShadow;
		kit.style.width = 'fit-children';
		kit.style.maxWidth = '400px';
		kit.style.marginRight = '6px';
	}

	var kitBlock = root.FindChildTraverse('MVPMusicKit');
	if (kitBlock && WinOnce(kitBlock, 'win-kit-row')) {
		kitBlock.style.flowChildren = 'right';
		kitBlock.style.width = 'fit-children';
	}

	var kitIcon = root.FindChildTraverse('MVPMusicKitIcon');
	if (kitIcon && kitBlock && WinOnce(kitIcon, 'win-kit-icon')) {
		if (kitIcon.GetParent() !== kitBlock) {
			kitIcon.SetParent(kitBlock);
			var kitName = root.FindChildTraverse('MVPMusicKitName');
			if (kitName)
				kitBlock.MoveChildBefore(kitIcon, kitName);
		}
		kitIcon.style.width = 'fit-children';
		kitIcon.style.height = '34px';
		kitIcon.style.transform = 'translateY(0px) translateX(0px)';
		kitIcon.style.verticalAlign = 'bottom';
		kitIcon.style.marginTop = '1px';
		kitIcon.style.marginRight = '4px';
	}

	var surrender = root.FindChildTraverse('Surrender');
	if (surrender && WinOnce(surrender, 'win-surrender')) {
		surrender.style.width = '100%';
		surrender.style.fontSize = '16px';
		surrender.style.color = 'white';
		surrender.style.textAlign = 'center';
	}
};

var WinStep = function (what, step) {
	try {
		step();
	} catch (error) {
			}
};

var WinApply = function () {
	var root = contextPanel.FindChildTraverse('HudWinPanel');
	if (!root)
		return;
	var result = WinFirst(root, 'WinPanel__Result');
	if (!result)
		return;

	if (WinOnce(root, 'win-root'))
		root.style.y = Win.y + 'px';

	WinStep('plate', function () {
		WinDressPlate(root, result);
	});
	WinStep('title', function () {
		WinDressTitle(WinTitle(result));
	});
	WinStep('funfact', function () {
		WinDressFunfact(root);
	});
	WinStep('mvp', function () {
		WinDressMvp(root, result);
	});
	WinStep('text', function () {
		WinDressText(root);
	});

	for (var cls of ['WinPanel__Result__double-arrows', 'WinPanel__Result__glitch', 'MVP__white']) {
		for (var decor of root.FindChildrenWithClassTraverse(cls))
			WinCollapse(decor);
	}
	WinCollapse(root.FindChildTraverse('id-match-mvp-map-container'));
	var team = WinTeam(result);
	var artMarker = 'win-art-' + team;
	if (!result.BHasClass(artMarker)) {
		for (var was of ['win-art-ct', 'win-art-t', 'win-art-draw'])
			result.RemoveClass(was);
		result.AddClass(artMarker);
		if (team === 'draw') {
			result.style.backgroundImage = 'none';
			result.style.backgroundColor = WinDrawBg;
			result.ArtStamp = null;
		} else {
			PaintArt(result, team === 'ct' ? 'winpanelct' : 'winpanelt', {size: '100% 100%'});
		}
	}

	var mvp = root.FindChildTraverse('MVP');
	if (mvp) {
		var showMvp = WinHasClass(result, 'winpanel-mvp--show');
		if (mvp.BHasClass('win-mvp-shown') !== showMvp) {
			mvp.SetHasClass('win-mvp-shown', showMvp);
			mvp.style.visibility = showMvp ? 'visible' : 'collapse';
		}
	}

	var kitIcon = root.FindChildTraverse('MVPMusicKitIcon');
	if (kitIcon) {
		var showKit = WinHasClass(result, 'MVP__MusicKit--show');
		if (kitIcon.BHasClass('win-kit-shown') !== showKit) {
			kitIcon.SetHasClass('win-kit-shown', showKit);
			kitIcon.style.visibility = showKit ? 'visible' : 'collapse';
		}
	}

	var visible = WinHasClass(result, 'winpanel-basic-round-result-visible');
	var title = WinTitle(result);

	if (title) {
		var want = WinTitleText(team);
		if (want && title.text !== want)
			title.text = want;
	}

	WinFadePlate(result, WinFirst(result, 'WinPanel__Result__white'), visible);
	WinSlideRow(root.FindChildTraverse('Funfact'),
		visible && WinHasClass(result, 'winpanel-funfacts--show'));

	if (root.BHasClass('win-visible') !== visible) {
		root.SetHasClass('win-visible', visible);
	}
};

var WinGeneration = (typeof WinGeneration === 'undefined' ? 0 : WinGeneration) + 1;

var WinTick = function (generation) {
	if (generation !== WinGeneration)
		return;
	try {
		WinApply();
	} catch (error) {
			}
	$.Schedule(0.1, function () {
		WinTick(generation);
	});
};

WinTick(WinGeneration);
]===],
}

local JS_ORDER = {
    "alerts.js",
    "art.js",
    "autodisconnect.js",
    "base.js",
    "damageindicator.js",
    "deathnotices.js",
    "dmbonus.js",
    "freezepanel.js",
    "gamerules_constants.js",
    "healtharmor.js",
    "icon.js",
    "joinpanel.js",
    "killcount.js",
    "messages.js",
    "money.js",
    "progressbar.js",
    "radar.js",
    "reticle.js",
    "ris.js",
    "settings.js",
    "specpanel.js",
    "teamcolor.js",
    "teamcounter.js",
    "voice.js",
    "vote.js",
    "weapon_select.js",
    "weaponammo.js",
    "winpanel.js",
}

local kLoadDelayMs = 1500
local g_loadedHud = nil
local g_pendingHud = nil
local g_hudSeenAt = 0
local g_lastLoadAt = 0

local function load_all_scripts(hud)
    if not hud then return end
    local art_clean = get_art_dir():gsub("\\", "/") .. "/"
    panorama.RunScript(string.format([[
        var ArtBasePath = "%s";
        if (typeof ArtFiles !== 'undefined') {
            ArtUrl = function(token) {
                return 'raw://' + ArtBasePath + (ArtFiles[token] || token);
            };
        }
    ]], art_clean), hud)

    for _, name in ipairs(JS_ORDER) do
        local source = BUNDLED_SCRIPTS[name]
        if source and #source > 0 then
            local wrapped_js = "try {\nvar contextPanel = $.GetContextPanel();\n"
                .. source
                .. "\n} catch (error) { $.Msg('[hud] " .. name .. ": ' + error); }"
            panorama.RunScript(wrapped_js, hud)
        end
    end
end

local function force_reload()
    g_loadedHud = nil
    g_pendingHud = nil
    local hud = panorama.FindPanel("CSGOHud")
    if hud and ui_enabled:Get() and assets_ready then
        load_all_scripts(hud)
        g_loadedHud = hud
        g_lastLoadAt = tonumber(fnGetTickCount64())
    end
end

menu.Button("Reskin", force_reload)
menu.Button("Redownload Assets", function()
    for _, name in ipairs(ART_FILES) do
        file.Delete("scaleform/art/" .. name)
    end
    ensure_assets(force_reload)
end)

local function tick_hud_lifecycle()
    if not ui_enabled:Get() or not assets_ready then
        g_loadedHud = nil
        g_pendingHud = nil
        return
    end
    local hud = panorama.FindPanel("CSGOHud")
    if not hud then
        g_loadedHud = nil
        g_pendingHud = nil
        return
    end
    local now = tonumber(fnGetTickCount64())
    if hud ~= g_loadedHud then
        if hud ~= g_pendingHud then
            g_pendingHud = hud
            g_hudSeenAt = now
        elseif (now - g_hudSeenAt) >= kLoadDelayMs then
            load_all_scripts(hud)
            g_loadedHud = hud
            g_lastLoadAt = now
        end
    end
end

events.On("frame_stage", function(stage)
    if stage == 6 then
        tick_hud_lifecycle()
    end
end)

events.On("round_start", function()
    if ui_enabled:Get() and assets_ready then
        g_loadedHud = nil
    end
end)

ensure_assets(force_reload)
