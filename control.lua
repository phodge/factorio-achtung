--require "utils"

-- these are the types of entities we need to keep an eye on
local interesting = {
  "burner-mining-drill",
  "electric-mining-drill",
  "stone-furnace",
  "steel-furnace",
  "boiler",
  "burner-inserter",
}

local ents_minedout = nil
local ents_cache = nil

function toggle_achtung_ui(player)
  if player.gui.top.achtung_ui then
    player.gui.top.achtung_ui.destroy()
  else
    local frame = player.gui.top.add{
      type="flow",
      name="achtung_ui",
      direction="vertical",
    }
    frame.add{
      type="frame",
      name="empty_list",
      direction="vertical",
      caption={"cap-mined-out"}
    }
    frame.add{
      type="frame",
      name="nofuel_list",
      direction="vertical",
      caption={"cap-no-fuel"}
    }
    frame.add{
      type="frame",
      name="lowresource_list",
      direction="vertical",
      caption={"cap-low-resources"}
    }
    frame.empty_list.style.visible = false
    frame.nofuel_list.style.visible = false
    frame.lowresource_list.style.visible = false
    update_achtung_ui(player)
  end
end

function update_achtung_ui(player)
  local frame = player.gui.top.achtung_ui

  -- initialise the list of empty miners
  if ents_minedout == nil then
    ents_minedout = {}
  end

  -- create caches of miners that exist in the game
  if ents_cache == nil then
    ents_cache = {}

    -- find all interesting entities on the map and add them to our list
    for _, name in pairs(interesting) do
      local found = game.surfaces[1].find_entities_filtered{force="player", name=name}
      for _, entity in pairs(found) do
        -- is this entity currently mining any resources?
        local resources = get_qty_remaining(entity)
        local origresource = false
        if resources then
          origresource = _keys(resources)[1]
        end
        table.insert(ents_cache, {entity, origresource})
      end
    end
  end

  -- count how much quantity is left in each mine
  local warninglevel = 500

  -- different things we want to warn about:
  
  -- 1) things that might run out of resources to mine
  -- NOTE: the entities themselves are in the ents_minedout table

  -- 2) things that might run out of fuel
  local nofuel = {}

  -- 3) things that might get low on resources to mine (these are grouped by qty remaining)
  local lowresources = {}

  -- construct a mapping of [qty: list] where each list contains a size-3 tuples of
  -- {entity-name, surface, pos}, where each entry is for a specific miner has less than
  -- [warninglevel] resources left to mine

  for key, _set in pairs(ents_cache) do
    local entity = _set[1]
    local origresource = _set[2]

    if entity.valid then
      -- how much is left in this entity?
      local resources, total = get_qty_remaining(entity)

      if resources and (total == 0) then
        -- add the entity to the global list of empty miners
        table.insert(ents_minedout, {entity, origresource})
        -- make sure we remove the entity from this table
        ents_cache[key] = nil
      else
        -- if the entity has run out of fuel, add it to the no-fuel table
        fuel_inventory = entity.get_fuel_inventory()
        if fuel_inventory and fuel_inventory.is_empty() then
          local fuels = {}
          if resources then
            fuels = _keys(resources)
            table.sort(fuels)
          end

          local key = entity.name.."|"..table.concat(fuels, ",")
          if nofuel[key] == nil then
            nofuel[key] = 1
          else
            nofuel[key] = nofuel[key] + 1
          end
        end

        -- what's the total resources left to be mined in this thing? (resources will be false if
        -- it's not something that mines resources)
        if resources then
          -- if the mineable resources remaining is below the warning level, add it to the lowminers
          -- table
          if total < warninglevel then
            if lowresources[total] == nil then
              lowresources[total] = {}
            end

            table.insert(lowresources[total], {entity.name, total, resources})
          end
        end
      end
    else
      -- remove the entity from our cache
      ents_cache[key] = nil
    end
  end

  -- recreate the list of things with no fuel
  render_empty(player, frame)
  render_totals(player, frame.nofuel_list, nofuel)
  render_lowresources(player, frame, lowresources)
end
function oldstuffimaywant()
  -- build UI elements

  -- make a new list with the quantities we want to show
  local quantities = {}
  for qty, _ in pairs(lowminers) do
    table.insert(quantities, qty)
  end
  table.sort(quantities)

  -- destroy the entity list so that we can recreate it
  frame.entity_list.destroy()
  if not #quantities then
    -- if there's nothing to show, hide the UI element
    frame.style.visible = false
    return
  end
  frame.style.visible = true

  frame.add{
    type="table",
    name="entity_list",
    colspan=2
  }
  local list = frame.entity_list
  --list.style.top_padding = 10
  --list.style.left_padding = 10

  -- add a label to the list for each miner
  local shown = 0
  for q = 1, #quantities do
    local qty = quantities[q]
    for _, entry in pairs(lowminers[qty]) do
      if shown > 5 then break end
      shown = shown + 1
      local name = entry[1]
      local surface = entry[2]
      local pos = entry[3]

      -- add a sprite for the thing that is low
      local btnname = string.format("sprite_%d", shown)
      list.add{
        -- put the sprite in a frame so it looks nicer
        type="frame",
        name=btnname,
        -- caption={"__1__: __2__", name, string.format("%d", qty)}
        --caption={"something-is-low", "string1", "string2"}
      }
      list[btnname].add{type="sprite", name="thesprite", sprite=string.format("entity/%s", name)}

      -- add a caption that shows how much stuff is left
      list.add{
        type="label",
        name=string.format("quantity_%d", shown),
        caption=string.format("%d", qty),
      }
    end
    if shown > 5 then break end
  end
end

-- update display once per second
script.on_event(defines.events.on_tick, function(event)
  if (game.tick % 60 == 0) then
    for _, player in pairs(game.players) do
      if player.gui.top.achtung_ui then
        update_achtung_ui(player)
      end
    end
  end
end)

-- callbacks to register new entities as they are constructed
script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity},
                function(e) entity_created(e.created_entity) end)
script.on_event(defines.events.on_trigger_created_entity,
                function(e) entity_created(e.entity) end)


script.on_event(defines.events.on_player_created, function(event)
  toggle_achtung_ui(game.players[event.player_index])
end)
script.on_configuration_changed(function(data)
  if data.mod_changes["Achtung"] and not data.mod_changes["Achtung"].old_version then
    for _, player in pairs(game.players) do
      toggle_achtung_ui(player)
    end
  end
end)

script.on_load(function()
  ents_minedout = nil
  ents_cache = nil
end)

function get_qty_remaining(miner)
  -- returns a table of {<resource-name> = <quantity>}
  local pos = miner.position
  local startpos = nil
  local endpos = nil

  -- what's the grid location of this burner?
  if miner.name == "burner-mining-drill" then
    -- burner-miners are positioned in directly between all the tiles
    startpos = {x=pos.x - 1, y=pos.y - 1}
    endpos = {x=pos.x + 1, y=pos.y + 1}
  elseif miner.name == "electric-mining-drill" then
    startpos = {x=math.floor(pos.x) -2 , y=math.floor(pos.y) - 2}
    endpos = {x=startpos.x + 5, y=startpos.y + 5}
  else
    -- this is not a thing that can mine stuff
    return false
  end

  return get_mineral_count(miner.surface, startpos, endpos)
end

function get_mineral_count(surface, startpos, endpos)
  -- grab all the resource entities inside that area
  local resources = surface.find_entities_filtered{
    area={startpos, endpos},
    type="resource",
  }
  local total = 0
  local ret = {}
  for _, entity in pairs(resources) do
    --if name == "stone" or name == "copper-ore" or name =="coal" or name == "iron-ore" then
    if entity.minable then
      local name = entity.name
      total = total + entity.amount
      if ret[name] == nil then
        ret[name] = entity.amount
      else
        ret[name] = ret[name] + entity.amount
      end
    end
  end
  return ret, total
end

function entity_created(entity)
  if ents_cache == nil then
    return
  end
  for _, name in pairs(interesting) do
    if entity.name == name then
      local origresource = false
      if resources then
        origresource = _keys(resources)[1]
      end
      table.insert(ents_cache, {entity, origresource})
      return
    end
  end
end

function render_empty(player, frame)
  -- how many of each type are there?
  local totals = {}
  for key, _set in pairs(ents_minedout) do
    local miner = _set[1]
    local origresource = _set[2]
    if miner.valid then
      local key2 = miner.name.."|"..(origresource or "")
      if totals[key2] == nil then
        totals[key2] = 1
      else
        totals[key2] = totals[key2] + 1
      end
    else
      -- clean up empty miners that no longer exist
      ents_minedout[key] = nil
    end
  end

  render_totals(player, frame.empty_list, totals)
end

function render_totals(player, guilist, totals)
  -- destroy all children of the GUI element
  for _, name in pairs(guilist.children_names) do
    guilist[name].destroy()
  end

  -- make a child for each type of element we want to show
  local shown = false
  for key, count in pairs(totals) do
    parts = _split(key, "|")
    minername = parts[1]
    -- make a pair for the the thing that's empty
    shown = true
    local info = guilist.add{type="flow", direction="horizontal", name=key}
    info.add{type="sprite", name="thesprite", sprite=string.format("entity/%s", minername)}
    info.add{type="label", name="thelabel", caption=string.format("x %d", count)}
    -- if we have some fuels, also show them
    if parts[2] then
      for i, fuelname in pairs(_split(parts[2], ',')) do
        info.add{type="sprite", name="fuel_"..fuelname, sprite="entity/"..fuelname}
      end
    end
  end

  guilist.style.visible = shown
end

function render_lowresources(player, frame, lowresources)
  local guilist = frame.lowresource_list

  -- destroy all children of the GUI element
  for _, name in pairs(guilist.children_names) do
    guilist[name].destroy()
  end

  -- make a new list with the quantities we want to show
  local quantities = {}
  for qty, _ in pairs(lowresources) do
    table.insert(quantities, qty)
  end
  table.sort(quantities)

  -- don't show more than this many low miners
  local max = 10
  local shown = 0
  for _, qty in pairs(quantities) do
    if shown >= max then
      break
    end
    for _, entry in pairs(lowresources[qty]) do
      if shown >= max then
        break
      end
      local entityname = entry[1]
      local total = entry[2]
      local resources = entry[3]
      shown = shown + 1
      -- make a gui flow for this specific entity
      local info = guilist.add{type="flow", direction="horizontal", name="entity_"..shown}
      info.add{type="sprite", name="thesprite", sprite="entity/"..entityname}
      -- how much of each resource is left?
      for resourcename, amount in pairs(resources) do
        info.add{type="label", name="qty_"..resourcename, caption=string.format("%d x", amount)}
        info.add{type="sprite", name="sprite_"..resourcename, sprite="entity/"..resourcename}
      end
    end
  end

  guilist.style.visible = shown > 0
end

function _keys(input)
  local ret = {}
  for key, _ in pairs(input) do
    table.insert(ret, key)
  end
  return ret
end
function _split(input, sep)
  local ret = {}
  for match in string.gmatch(input, "([^"..sep.."]+)") do
    table.insert(ret, match)
  end
  return ret
end
