--[[

	TechAge
	=======

	Copyright (C) 2019-2020 Joachim Stolberg

	GPL v3
	See LICENSE.txt for more information
	
	Liquid lib

]]--

local M = minetest.get_meta
local S = techage.S
local P2S = minetest.pos_to_string
local LQD = function(pos) return (minetest.registered_nodes[techage.get_node_lvm(pos).name] or {}).liquid end

local BLOCKING_TIME = 0.3 -- 300ms

techage.liquid = {}
local LiquidDef = {}
local ContainerDef = {}

local function help(x, y)
	local tooltip = S("To add liquids punch\nthe tank\nwith a liquid container")
	return "label["..x..","..y..";"..minetest.colorize("#000000", minetest.formspec_escape("[?]")).."]"..
		"tooltip["..x..","..y..";0.5,0.5;"..tooltip..";#0C3D32;#FFFFFF]"
end

function techage.liquid.formspec(pos, nvm)
	local title = S("Liquid Tank")
	local itemname = "techage:liquid"
	if nvm.liquid and nvm.liquid.amount and nvm.liquid.amount > 0 and nvm.liquid.name then
		itemname = nvm.liquid.name.." "..nvm.liquid.amount
	end
	return "size[4,2]"..
		default.gui_bg..
		default.gui_bg_img..
		default.gui_slots..
		"box[0,-0.1;3.8,0.5;#c6e8ff]"..
		"label[1,-0.1;"..minetest.colorize("#000000", title).."]"..
		help(3.4, -0.1)..
		techage.item_image(1.5, 1, itemname)
end	

--function techage.liquid.move_item(pos, stack, size, formspec)
--	local nvm = techage.get_nvm(pos)
--	local inv = M(pos):get_inventory()
--	if liquid.is_container_empty(stack:get_name()) then
--		fill_container(pos, inv)
--	else
--		empty_container(pos, inv, size)
--	end
--	M(pos):set_string("formspec", formspec(pos, nvm))
--end
	
function techage.liquid.is_empty(pos)
	local nvm = techage.get_nvm(pos)
	local inv = minetest.get_meta(pos):get_inventory()
	return inv:is_empty("src") and inv:is_empty("dst") and (not nvm.liquid or (nvm.liquid.amount or 0) == 0)
end

techage.liquid.tubing = {
--	on_pull_item = function(pos, in_dir, num)
--		local inv = M(pos):get_inventory()
--		if not inv:is_empty("dst") then
--			local taken = techage.get_items(inv, "dst", num) 
--			if not inv:is_empty("src") then
--				fill_container(pos, inv)
--			end
--			return taken
--		end
--	end,
--	on_push_item = function(pos, in_dir, stack)
--		local inv = M(pos):get_inventory()
--		if inv:room_for_item("src", stack) then
--			inv:add_item("src", stack)
--			if liquid.is_container_empty(stack:get_name()) then
--				fill_container(pos, inv)
--			else
--				empty_container(pos, inv)
--			end
--			return true
--		end
--		return false
--	end,
--	on_unpull_item = function(pos, in_dir, stack)
--		local meta = M(pos)
--		local inv = meta:get_inventory()
--		return techage.put_items(inv, "dst", stack)
--	end,
	on_recv_message = function(pos, src, topic, payload)
		if topic == "load" then
			local nvm = techage.get_nvm(pos)
			return techage.power.percent(LQD(pos).capa, (nvm.liquid and nvm.liquid.amount) or 0)
		elseif topic == "size" then
			return LQD(pos).capa
		else
			return "unsupported"
		end
	end,
}	

-- like: register_liquid("techage:ta3_barrel_oil", "techage:ta3_barrel_empty", 10, "techage:oil")
function techage.register_liquid(full_container, empty_container, container_size, inv_item)
	LiquidDef[full_container] = {container = empty_container, size = container_size, inv_item = inv_item}
	ContainerDef[empty_container] = ContainerDef[empty_container] or {}
	ContainerDef[empty_container][inv_item] = full_container
end

local function get_liquid_def(full_container)
	return LiquidDef[full_container]
end
	
local function get_container_def(container_name)
	return ContainerDef[container_name]
end

local function is_container_empty(container_name)
	return ContainerDef[container_name]
end

local function get_full_container(empty_container, inv_item)
	return ContainerDef[empty_container] and ContainerDef[empty_container][inv_item]
end

local function fill_container(pos, inv, empty_container)
	local nvm = techage.get_nvm(pos)
	nvm.liquid = nvm.liquid or {}
	nvm.liquid.amount = nvm.liquid.amount or 0
	local full_container = get_full_container(empty_container, nvm.liquid.name)
	if empty_container and full_container then
		local ldef = get_liquid_def(full_container)
		if ldef and nvm.liquid.amount - ldef.size >= 0 then 
			if inv:room_for_item("dst", {name = full_container}) then
				inv:add_item("dst", {name = full_container})
				nvm.liquid.amount = nvm.liquid.amount - ldef.size
				if nvm.liquid.amount == 0 then
					nvm.liquid.name = nil
				end
				return true
			end
		end
	end
	-- undo
	inv:add_item("src", {name = empty_container})
	return false
end

local function empty_container(pos, inv, full_container)
	local nvm = techage.get_nvm(pos)
	nvm.liquid = nvm.liquid or {}
	nvm.liquid.amount = nvm.liquid.amount or 0
	local tank_size = LQD(pos).capa or 0
	local ldef = get_liquid_def(full_container)
	--print("ldef", dump(ldef), "tank_size", tank_size)
	if ldef and (not nvm.liquid.name or ldef.inv_item == nvm.liquid.name) then
		if nvm.liquid.amount + ldef.size <= tank_size then 
			if inv:room_for_item("dst", {name = ldef.container}) then
				inv:add_item("dst", {name = ldef.container})
				nvm.liquid.amount = nvm.liquid.amount + ldef.size
				nvm.liquid.name = ldef.inv_item
				return true
			end
		end
	end
	-- undo
	inv:add_item("src", {name = full_container})
	return false
end

-- check if the given empty container can be replaced by a full
-- container and added to the players inventory
local function fill_on_punch(nvm, empty_container, item_count, puncher)
	nvm.liquid = nvm.liquid or {}
	nvm.liquid.amount = nvm.liquid.amount or 0
	local full_container = get_full_container(empty_container, nvm.liquid.name)
	if empty_container and full_container then
		local item = {name = full_container}
		local ldef = get_liquid_def(full_container)
		if ldef and nvm.liquid.amount - ldef.size >= 0 then 
			if item_count > 1 then -- can't be simply replaced?
				-- check for extra free space
				local inv = puncher:get_inventory()
				if inv:room_for_item("main", {name = full_container}) then
					-- add full container and return
					-- the empty once - 1
					inv:add_item("main", {name = full_container})	
					item = {name = empty_container, count = item_count - 1}
				else
					return -- no free space
				end
			end
			nvm.liquid.amount = nvm.liquid.amount - ldef.size
			if nvm.liquid.amount == 0 then 
				nvm.liquid.name = nil 
			end
			return item -- to be added to the players inv.
		end
	end
end

local function empty_on_punch(pos, nvm, full_container)
	nvm.liquid = nvm.liquid or {}
	nvm.liquid.amount = nvm.liquid.amount or 0
	local ldef = get_liquid_def(full_container)
	if ldef then 
		local tank_size = LQD(pos).capa or 0
		if not nvm.liquid.name or ldef.inv_item == nvm.liquid.name then
			if nvm.liquid.amount + ldef.size <= tank_size then 
				nvm.liquid.amount = nvm.liquid.amount + ldef.size
				nvm.liquid.name = ldef.inv_item
				return {name = ldef.container}
			end
		end
	end
end

function techage.liquid.on_punch(pos, node, puncher, pointed_thing)
	local nvm = techage.get_nvm(pos)
	local mem = techage.get_mem(pos)
	mem.blocking_time = mem.blocking_time or 0
	if mem.blocking_time > techage.SystemTime then
		return
	end
	
	local wielded_item = puncher:get_wielded_item():get_name()
	local item_count = puncher:get_wielded_item():get_count()
	local new_item = fill_on_punch(nvm, wielded_item, item_count, puncher) 
			or empty_on_punch(pos, nvm, wielded_item)
	if new_item then
		puncher:set_wielded_item(new_item)
		M(pos):set_string("formspec", techage.fuel.formspec(pos, nvm))
		mem.blocking_time = techage.SystemTime + BLOCKING_TIME
		return
	end
end

function techage.register_liquid(full_container, empty_container, container_size, inv_item)
	LiquidDef[full_container] = {container = empty_container, size = container_size, inv_item = inv_item}
	ContainerDef[empty_container] = ContainerDef[empty_container] or {}
	ContainerDef[empty_container][inv_item] = full_container
end

techage.liquid.get_liquid_def = get_liquid_def
techage.liquid.get_container_def = get_container_def
techage.liquid.is_container_empty = is_container_empty
techage.liquid.get_full_container = get_full_container
techage.liquid.fill_container = fill_container
techage.liquid.empty_container = empty_container
techage.liquid.fill_on_punch = fill_on_punch
techage.liquid.empty_on_punch = empty_on_punch
