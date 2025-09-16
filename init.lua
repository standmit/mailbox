-- mailbox/init.lua
-- Inbox for items
--[[
	Mailbox: Inbox for items
    Copyright (c) 2015-2016  kilbith <jeanpatrick.guerrero@gmail.com>
    Copyright (c) 2016       James Stevenson
    Copyright (c) 2017-2021  Gabriel Pérez-Cerezo <gabriel@gpcf.eu>
    Copyright (c) 2024       1F616EMO <root@1f616emo.xyz>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

local minetest = minetest

local mailbox = {}
_G.mailbox = mailbox

local S = minetest.get_translator("mailbox")
local FS = function(...) return minetest.formspec_escape(S(...)) end

local formspec_bg = ""
local get_hotbar_bg = function() return "" end
if minetest.global_exists("default") then
    formspec_bg = default.gui_bg .. default.gui_bg_img .. default.gui_slots
    get_hotbar_bg = default.get_hotbar_bg
end

local function noop() end

mailbox.UNRENT_FAIL_REASONS = {
    ERR_NOT_EMPTY = S("The mailbox isn't empty."),
    ERR_NO_PRIVILEGE = S("You are not allowed to unrent this mailbox."),
}

local function can_manage(pos, player)
    local meta = minetest.get_meta(pos)
    local owner = meta:get_string("owner")
    local pname = player:get_player_name()
    if owner ~= ""
        and owner ~= pname
        and not minetest.check_player_privs(pname, { protection_bypass = true }) then
        return false
    end
    return true
end

local function can_set_owner(player)
    local pname = player:get_player_name()
    return minetest.check_player_privs(pname, { protection_bypass = true })
end

function mailbox.set_owner(pos, pname)
    local node = minetest.get_node(pos)
    local meta = minetest.get_meta(pos)
    meta:set_string("owner", pname)
    if pname == "" then
        meta:set_string("infotext", S("Free Mailbox, right-click to claim"))
        node.name = "mailbox:mailbox_free"
        minetest.swap_node(pos, node)
    else
        meta:set_string("infotext", S("@1's Mailbox", pname))
        if node.name == "mailbox:mailbox_free" then
            node.name = "mailbox:mailbox"
            minetest.swap_node(pos, node)
        end
    end
end

function mailbox.rent_mailbox(pos, player)
    return mailbox.set_owner(pos, player:get_player_name())
end

function mailbox.unrent(pos, player, force, drop_pos)
    local meta = minetest.get_meta(pos)
    if not can_manage(pos, player) then
        return false, "ERR_NO_PRIVILEGE"
    end

    local inv = meta:get_inventory()
    if not force then
        if not inv:is_empty("mailbox") then
            return false, "ERR_NOT_EMPTY"
        end
    end

    drop_pos = drop_pos or pos
    for _, stack in pairs(inv:get_list("mailbox")) do
        minetest.add_item(drop_pos, stack)
    end

    inv:set_list("mailbox", {})
    mailbox.set_owner(pos, "")

    return true
end

local on_construct = function(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	inv:set_size("mailbox", 8 * 4)
	inv:set_size("drop", 1)
end

local after_place_node = function(pos, player)
	local pname = player:get_player_name()
    mailbox.set_owner(pos, pname)
end

local show_formspec = function(pos, owner, pname, pl_can_manage)
    local spos = pos.x .. "," .. pos.y .. "," .. pos.z
    local formspec = "size[8,5.5]" .. formspec_bg .. default.get_hotbar_bg(0, 1.5) ..
        "label[0,0;" .. FS("Send your goods\nto @1", owner) .. " :]" ..
        "list[nodemeta:" .. spos .. ";drop;3.5,0;1,1;]" ..
        "list[current_player;main;0,1.5;8,1;]" ..
        "list[current_player;main;0,2.75;8,3;8]" ..
        "listring[nodemeta:" .. spos .. ";drop]" ..
        "listring[current_player;main]"
    if pl_can_manage then
        formspec = formspec .. "button_exit[6,0;2,1;manage;" .. FS("Manage") .. "]"
    end
    minetest.show_formspec(pname, "mailbox:mailbox_" .. spos, formspec)
end

local show_manage_formspec = function(pos, pname, selected)
    local spos = pos.x .. "," .. pos.y .. "," .. pos.z
    local formspec = "size[8,9.5]" .. formspec_bg .. get_hotbar_bg(0, 5.5) ..
		"checkbox[0,0;books_only;" .. FS("Only allow written books") .. ";" .. selected .. "]" ..
		"list[nodemeta:" .. spos .. ";mailbox;0,1;8,4;]" ..
		"list[current_player;main;0,5.5;8,1;]" ..
		"list[current_player;main;0,6.75;8,3;8]" ..
		"listring[nodemeta:" .. spos .. ";mailbox]" ..
		"listring[current_player;main]" ..
		"button_exit[5,0;2,1;unrent;" .. FS("Unrent") .. "]" ..
		"button_exit[7,0;1,1;exit;X]"
    minetest.show_formspec(pname, "mailbox:mailbox_" .. spos, formspec)
end

local show_change_owner_formspec = function(pos, pname)
    local spos = pos.x .. "," .. pos.y .. "," .. pos.z
    local formspec = "field[new_owner;" .. FS("New owner:") .. ";]"
    minetest.show_formspec(pname, "mailbox:mailbox_" .. spos, formspec)
end

local on_rightclick = function(pos, node, player, itemstack, pointed_thing)
    if not player:is_player() then return end

    local nodename = node.name
    if itemstack:get_name() == "mailbox:unrenter" then
        local drop_pos = pointed_thing.above
        mailbox.unrent(pos, player, true, drop_pos)
        return itemstack
    end

    local pname = player:get_player_name()
    local meta = minetest.get_meta(pos)
    local owner = meta:get_string("owner")
    if owner == pname then
        -- Owner formspec
        local selected = nodename == "mailbox:letterbox" and "true" or "false"
        show_manage_formspec(pos, pname, selected)
    else
        -- Mailer formspec
        show_formspec(pos, owner, pname, can_manage(pos, player))
    end
end

local on_punch = function(pos, node, player, pointed_thing)
    if not player:is_player() then
        return minetest.node_punch(pos, node, player, pointed_thing)
    end

    local wielded = player:get_wielded_item()
    if wielded:get_name() ~= "mailbox:unrenter" then
        return minetest.node_punch(pos, node, player, pointed_thing)
    end

    local pname = player:get_player_name()
    if not can_set_owner(player) then
        minetest.chat_send_player(pname, S("You cannot set owner of mailboxes for others."))
        return
    end

    show_change_owner_formspec(pos, pname)
end

local free_on_rightclick = function(pos, _, player, itemstack)
    if not player:is_player() then return end
    if itemstack:get_name() == "mailbox:unrenter" then return end

    mailbox.rent_mailbox(pos, player)
end

local can_dig = function(pos, player)
	if not can_manage(pos, player) then
        return false
    end

    local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	return inv:is_empty("mailbox")
end

local allowed_books = {
    ["default:book_written"] = true,
    ["mcl_books:written_book"] = true,
}

local allow_metadata_inventory_put = function(pos, listname, _, stack, player)
    if listname == "mailbox" then
        return can_manage(pos, player) and stack:get_count() or 0
    elseif listname == "drop" then
        local node = minetest.get_node(pos)
        if node.name == "mailbox:letterbox" and not allowed_books[stack:get_name()] then
            minetest.chat_send_player(player:get_player_name(), S("Only written books are accepted."))
            return 0
        end
        local meta = minetest.get_meta(pos)
        local inv = meta:get_inventory()
        if inv:room_for_item("mailbox", stack) then
            return stack:get_count()
        else
            minetest.chat_send_player(player:get_player_name(), S("Mailbox full."))
        end
    end
    return 0
end

local on_metadata_inventory_put = function(pos, listname, _, stack)
	if listname == "drop" then
        local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
        inv:set_stack("drop", 1, inv:add_item("mailbox", stack))
	end
end

local allow_metadata_inventory_move = function(pos, from_list, _, to_list, _, count, player)
    if from_list ~= to_list then
        return 0
    elseif from_list == "mailbox" then
        return can_manage(pos, player) and count or 0
    elseif from_list == "drop" then
        return count
    end
    return 0
end

local allow_metadata_inventory_take = function(pos, listname, _, stack, player)
    if listname == "mailbox" then
        return can_manage(pos, player) and stack:get_count() or 0
    elseif listname == "drop" then
        return stack:get_count()
    end
    return 0
end

local after_dig_node = nil
local mail_pipeworks = nil
if minetest.global_exists("pipeworks") then
    mail_pipeworks = {
		insert_object = function(pos, _, stack, _)
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			return inv:add_item("mailbox", stack)
		end,
		can_insert = function(pos, _, stack, _)
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			return inv:room_for_item("mailbox", stack)
		end,
		input_inventory = "mailbox",
		connect_sides = { left = 1, right = 1, back = 1, bottom = 1, top = 1 },
	}

    local old_after_place_node = after_place_node
	after_place_node = function(...)
		old_after_place_node(...)
		pipeworks.scan_for_tube_objects(...)
	end

    after_dig_node = pipeworks.after_dig
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if not formname:match("mailbox:mailbox_") then
		return
	end
    local pos = minetest.string_to_pos(formname:sub(17))
    local node = minetest.get_node(pos)
    local pname = player:get_player_name()
    local nodegroup = minetest.get_item_group(node.name, "mailbox")
    if fields.new_owner and nodegroup ~= 0 then
        if not can_set_owner(player) then
            minetest.chat_send_player(pname, S("You cannot set owner of mailboxes for others."))
            return true
        end

        mailbox.set_owner(pos, fields.new_owner)
    elseif nodegroup ~= 1 then
        minetest.chat_send_player(pname, S("The node you were working on is no longer a mailbox."))
    elseif fields.unrent then
		local status, reason = mailbox.unrent(pos, player)
        if not status then
            minetest.chat_send_player(pname, mailbox.UNRENT_FAIL_REASONS[reason])
        end
        return true
	elseif fields.books_only then
        if not can_manage(pos, player) then
            minetest.chat_send_player(pname, S("You can't manage this mailbox."))
            return true
        end
        node.name = node.name == "mailbox:mailbox" and "mailbox:letterbox" or "mailbox:mailbox"
        minetest.swap_node(pos, node)
    elseif fields.manage then
        if not can_manage(pos, player) then
            minetest.chat_send_player(pname, S("You can't manage this mailbox."))
            return true
        end
        local selected = node.name == "mailbox:letterbox" and "true" or "false"
        show_manage_formspec(pos, pname, selected)
	end
    return true
end)

minetest.register_node("mailbox:mailbox", {
	description = S("Mailbox"),
	tiles = {
		"mailbox_mailbox_top.png", "mailbox_mailbox_bottom.png",
		"mailbox_mailbox_side.png", "mailbox_mailbox_side.png",
		"mailbox_mailbox.png", "mailbox_mailbox.png",
	},
	groups = {
        mailbox = 1,
        cracky = 3,
        oddly_breakable_by_hand = 1,
        tubedevice = 1,
        tubedevice_receiver = 1
    },
	on_rotate = minetest.global_exists("screwdriver") and screwdriver.rotate_simple or nil,
	sounds = xcompat.sounds.node_sound_stone_defaults(),
	paramtype2 = "facedir",
    on_construct = on_construct,
	after_place_node = after_place_node,
	after_dig_node = after_dig_node,
	on_rightclick = on_rightclick,
    on_punch = on_punch,
	can_dig = can_dig,
	on_metadata_inventory_put = on_metadata_inventory_put,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	tube = mail_pipeworks,
    on_blast = noop,
})

minetest.register_node("mailbox:mailbox_free", {
	description = S("Mailbox for Rent"),
	tiles = {
		"mailbox_mailbox_free_top.png", "mailbox_mailbox_free_bottom.png",
		"mailbox_mailbox_free_side.png", "mailbox_mailbox_free_side.png",
		"mailbox_mailbox_free.png", "mailbox_mailbox_free.png",
	},
	groups = {
        mailbox = 2,
        cracky = 3,
        oddly_breakable_by_hand = 1,
        tubedevice = 1,
        tubedevice_receiver = 1
    },
	on_rotate = minetest.global_exists("screwdriver") and screwdriver.rotate_simple or nil,
	sounds = xcompat.sounds.node_sound_stone_defaults(),
	paramtype2 = "facedir",
	drop = "mailbox:mailbox",
    on_construct = on_construct,
	on_rightclick = free_on_rightclick,
})

minetest.register_node("mailbox:letterbox", {
	tiles = {
		"mailbox_letterbox_top.png", "mailbox_letterbox_bottom.png",
		"mailbox_letterbox_side.png", "mailbox_letterbox_side.png",
		"mailbox_letterbox.png", "mailbox_letterbox.png",
	},
	groups = {
        mailbox = 1,
		cracky = 3,
		oddly_breakable_by_hand = 1,
		not_in_creative_inventory = 1,
		tubedevice = 1,
		tubedevice_receiver = 1
	},
	on_rotate = minetest.global_exists("screwdriver") and screwdriver.rotate_simple or nil,
	sounds = xcompat.sounds.node_sound_stone_defaults(),
	paramtype2 = "facedir",
	drop = "mailbox:mailbox",
    on_construct = on_construct,
	after_place_node = after_place_node,
	after_dig_node = after_dig_node,
	on_rightclick = on_rightclick,
    on_punch = on_punch,
	can_dig = can_dig,
	on_metadata_inventory_put = on_metadata_inventory_put,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	tube = mail_pipeworks,
})

minetest.register_tool("mailbox:unrenter", {
    short_description = S("Mailbox owner modifier"),
	description = table.concat({
        S("Mailbox owner modifier"),
        S("Punch: Change owner"),
        S("Right-click: Move owner out")
    }, "\n"),
	inventory_image = "mailbox_unrent.png",
})

local materials = xcompat.materials
minetest.register_craft({
	output = "mailbox:mailbox",
	recipe = {
		{ materials.steel_ingot, materials.steel_ingot, materials.steel_ingot },
		{ materials.book,        materials.chest,       materials.book },
		{ materials.steel_ingot, materials.steel_ingot, materials.steel_ingot }
	}
})


minetest.register_lbm({
    name = "mailbox:update_translation_1",
    nodenames = {
        "mailbox:mailbox",
        "mailbox:mailbox_free"
    },
    run_at_every_load = false,
    action = function(pos, node)
        local meta = minetest.get_meta(pos)
        local pname = meta:get_string("owner") or ""
        if pname == "" then
            meta:set_string("infotext", S("Free Mailbox, right-click to claim"))
        else
            meta:set_string("infotext", S("@1's Mailbox", pname))
        end
    end
})

