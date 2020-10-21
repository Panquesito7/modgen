-- collect nodes with on_timer attributes
local node_names_with_timer = {}
minetest.register_on_mods_loaded(function()
  for _,node in pairs(minetest.registered_nodes) do
    if node.on_timer then
      table.insert(node_names_with_timer, node.name)
    end
  end
  minetest.log("action", "[modgen] collected " .. #node_names_with_timer .. " items with node timers")
end)

local air_content_id = minetest.get_content_id("air")
local ignore_content_id = minetest.get_content_id("ignore")

function modgen.serialize_part(pos)
  local pos1, pos2 = modgen.get_mapblock_bounds(pos)

  assert((pos2.x - pos1.x) == 15)
  assert((pos2.y - pos1.y) == 15)
  assert((pos2.z - pos1.z) == 15)

  local manip = minetest.get_voxel_manip()
  local e1, e2 = manip:read_from_map(pos1, pos2)
  local area = VoxelArea:new({MinEdge=e1, MaxEdge=e2})

  local node_data = manip:get_data()
  local param1 = manip:get_light_data()
  local param2 = manip:get_param2_data()

  assert(#node_data == 4096)
  assert(#param1 == 4096)
  assert(#param2 == 4096)

  local node_id_count = {}

  -- prepare data structure
  local data = {
    node_ids = {},
    param1 = {},
    param2 = {},
    node_mapping = {}, -- name -> id
    metadata = {},
    has_metadata = false
  }

  -- loop over all blocks and fill cid,param1 and param2
  for z=pos1.z,pos2.z do
  for y=pos1.y,pos2.y do
  for x=pos1.x,pos2.x do
    local i = area:index(x,y,z)

    local node_id = node_data[i]
    if node_id == ignore_content_id then
      -- replace ignore blocks with air
      node_id = air_content_id
    end

    table.insert(data.node_ids, node_id)
    table.insert(data.param1, param1[i])
    table.insert(data.param2, param2[i])

    local count = node_id_count[node_id] or 0
    node_id_count[node_id] = count + 1
  end
  end
  end

  -- gather node id mapping
  for node_id in pairs(node_id_count) do
    local node_name = minetest.get_name_from_content_id(node_id)
    data.node_mapping[node_name] = node_id
  end

  -- serialize metadata
  local pos_with_meta = minetest.find_nodes_with_meta(pos1, pos2)
  for _, meta_pos in ipairs(pos_with_meta) do
    local relative_pos = vector.subtract(meta_pos, pos1)
    local meta = minetest.get_meta(meta_pos):to_table()

    -- Convert metadata item stacks to item strings
    for _, invlist in pairs(meta.inventory) do
      for index = 1, #invlist do
        local itemstack = invlist[index]
        if itemstack.to_string then
          data.has_metadata = true
          invlist[index] = itemstack:to_string()
        end
      end
    end

    data.metadata.meta = data.metadata.meta or {}
    data.metadata.meta[minetest.pos_to_string(relative_pos)] = meta
  end

  -- serialize node timers
  if #node_names_with_timer > 0 then
    data.metadata.timers = {}
    local list = minetest.find_nodes_in_area(pos1, pos2, node_names_with_timer)
    for _, timer_pos in pairs(list) do
      local timer = minetest.get_node_timer(timer_pos)
      local relative_pos = vector.subtract(timer_pos, pos1)
      if timer:is_started() then
        data.has_metadata = true
        data.metadata.timers[minetest.pos_to_string(relative_pos)] = {
          timeout = timer:get_timeout(),
          elapsed = timer:get_elapsed()
        }
      end
    end

  end

  return data
end
