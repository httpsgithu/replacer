-- how many patterns are stored in the history? those don't take up much space,
-- but a too long list might not be overly helpful for the players either
replacer.max_hist_size = 20


-- turn stored metadata string (<node_name> <param1> <param2>) into something readable by human beeings
replacer.human_readable_metadata = function(metadata)
	if(not(metadata)) then
		return "(nothing)"
	end
	-- data is stored in the form "<nodename> <param1> <param2>"
	local parts = string.split(metadata, " ")
	if(not(parts) or #parts < 3) then
		return "(corrupted data)"
	end
	local node_name = parts[1]
	local param2 = parts[3]

	local def = minetest.registered_nodes[ node_name ]
	if(not(def)) then
		return "(unknown node)"
	end
	local text = "'"..tostring(def.description or "- no description -").."'"
	if(not(def.description) or def.description == "") then
		text = "- no description -"
	end
	-- facedir is probably the most commonly used rotation variant
	if( def.paramtype2 == "facedir"
	 or def.paramtype2 == "colorfacedir") then
		local axis_names = {"y+ (Ground)", "z+ (North)", "z- (South)",
				    "x+ (East)", "x- (West)", "y- (Sky)"}
		text = text.." Rotated: "..tostring(param2 % 4)..
			" around axis: "..tostring( axis_names[ math.floor( (param2%24) / 4 ) + 1 ])
	-- wallmounted is diffrent
	elseif( def.paramtype2 == "wallmounted"
	     or def.paramtype2 == "colorwallmounted") then
		local axis_names = {"y+ (Ground)", "y- (Sky)",
				    "z+ (North)", "z- (South)",
				    "x+ (East)", "x- (West)"}
		text = text.." Mounted at wall: "..tostring( axis_names[ (param2 % 6)+ 1 ])
	end
	return text
end


-- set the replacer to a new pattern
replacer.set_to = function(player_name, metadata, player, itemstack)
	if(not(player_name) or not(player) or not(itemstack)) then
		return itemstack
	end
	-- fallback if nothing is given
	if(not(metadata)) then
		metadata = "default:dirt 0 0"
	end
	itemstack:set_metadata( metadata )

	local set_to = replacer.human_readable_metadata(metadata)
	-- change the description of the tool so that it's easier to see which replacer (if you
	-- have more than one in your inv) is set to which node
	local meta = itemstack:get_meta()
	meta:set_string("description", "Node replacement tool set to:\n"..set_to..
					"\n["..tostring(metadata).."]")

	minetest.chat_send_player(player_name, "Node replacement tool set to: "..set_to..
					"["..tostring(metadata).."].")

	replacer.add_to_hist(player_name, metadata)
	return itemstack -- nothing consumed but data changed
end


-- keep a history of stored patterns for each player (not for each replacer);
-- this history is not saved over server shutdown
replacer.add_to_hist = function(player_name, metadata )
	if(not(player_name) or not(metadata) or metadata == "") then
		return
	end
	if(not(replacer.history)) then
		replacer.history = {}
	end
	if(not(replacer.history[ player_name ])) then
		replacer.history[ player_name ] = {}
	end
	local index = table.indexof( replacer.history[ player_name ], metadata )
	-- only add new entries; do not store duplicates
	if(index and index > -1) then
		return
	end
	-- remove the oldest entry
	if(#replacer.history[ player_name ] >= replacer.max_hist_size) then
		table.remove(replacer.history[ player_name ], 1)
	end
	table.insert(replacer.history[ player_name ], metadata)
end


-- show a formspec with a history of stored patterns to select from
replacer.get_formspec = function(player_name, current_metadata, player)
	-- is the player in creative mode?
	local in_creative_mode = (minetest.settings:get_bool("creative_mode")
				or minetest.check_player_privs(player_name, {creative=true}))
	-- count how many blocks of each type the player has in his inventory
	local counted_inv = {}
	if(not(in_creative_mode)) then
		local inv_main = player:get_inventory():get_list("main")
		for i, v in ipairs(inv_main) do
			local stack_name = v:get_name()
			if(not(counted_inv[ stack_name ])) then
				counted_inv[ stack_name ] = 0
			end
			counted_inv[ stack_name ] = counted_inv[ stack_name ] + v:get_count()
		end
	end

	local formspec = "size[14,8]"..
		"label[4,0;Node Replacement Tool Setup and History]"..
		"button_exit[6,7.2;2,0.8;quit;Exit]"..
		"label[0.2,0.6;Click here to set the replacer to a pattern you have stored before:]"..
		"tablecolumns[color;"..
			"text,align=right,tooltip=Amount of nodes of this type left in your inventory:"..
			";text,align=left,tooltip=Stored pattern:]"..
			"table[0.2,1.0;13,6;replacer_history;"
	-- make sure all variables exist and the current entry is stored
	replacer.add_to_hist(player_name, current_metadata)
	local hist_entries = {}
	local selected = 1
	for i, v in ipairs(replacer.history[ player_name ]) do
		if(v == current_metadata) then
			selected = i
		end
		local amount_left = "#00FF00,infinite supply:"
		if(not(in_creative_mode)) then
			-- which item are we looking for?
			local parts = v:split(" ")
			if(not(parts) or #parts<1) then
				parts = {"does not exist"}
			-- TODO: handle this in a more general way
			elseif(parts[1] == "default:dirt_with_grass") then
				parts[1] = "default:dirt"
			end
			if(counted_inv[ parts[1] ]) then
				amount_left = "#00FF00,"..tostring(counted_inv[ parts[1] ]).." available:"
			else
				amount_left = "#FF0000,none left!"
			end
		end
		hist_entries[ i ] = tostring(amount_left)..","..
			minetest.formspec_escape(replacer.human_readable_metadata(v).." ["..v.."]")
	end
	return formspec..table.concat(hist_entries, ",")..";"..tostring(selected).."]"
end


-- the player has interacted with our formspec
minetest.register_on_player_receive_fields( function(player, formname, fields)
	if(not(formname) or formname ~= "replacer:menu") then
		return false
	end
	local player_name = player:get_player_name()
	-- the player clicked on an entry in the history
	if(fields and fields.replacer_history
	   and replacer.history and replacer.history[ player_name ]) then
		-- find out which line it was
		local selected = minetest.explode_table_event(fields.replacer_history)
		if(selected and (selected.type == "CHG" or selected.type == "DLC")
		   and selected.row <= #replacer.history[ player_name ]) then
			local itemstack = player:get_wielded_item()
			itemstack = replacer.set_to(player_name,
				replacer.history[ player_name ][ selected.row ],
				player, itemstack)
			player:set_wielded_item(itemstack)
			return true
		end
	end
	return true
end)