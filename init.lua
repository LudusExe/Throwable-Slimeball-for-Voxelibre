-- Adds vector.reflect
if not vector.reflect then
    vector.reflect = function(v, n)
        local dot = vector.dot(v, n)
        return vector.subtract(v, vector.multiply(n, 2 * dot))
    end
end

local THROWABLE_ITEMS = {
    ["mcl_mobitems:slimeball"] = {
        entity = "throw_slimeballs:thrown_slimeball",
        texture = "mcl_mobitems:slimeball",
    },
    ["mcl_mobitems:magma_cream"] = {
        entity = "throw_slimeballs:thrown_slimeball",
        texture = "mcl_mobitems:magma_cream",
    },
}

local THROW_SPEED = 15
local GRAVITY = vector.new(0, -9.8, 0)
local LIFETIME = 3.5
local SLOW_DURATION = 3
local PARTICLE_TEXTURE = "slime_particle.png"

-- Effetto particelle
local function spawn_particles(pos)
    minetest.add_particlespawner({
        amount = 20,
        time = 0.5,
        minpos = vector.subtract(pos, 0.5),
        maxpos = vector.add(pos, 0.5),
        minvel = {x = 0, y = 1.5, z = 0},
        maxvel = {x = 0, y = 2, z = 0},
        minacc = GRAVITY,
        maxacc = GRAVITY,
        minexptime = 0.5,
        maxexptime = 1,
        minsize = 0.5,
        maxsize = 5,
        texture = PARTICLE_TEXTURE,
        glow = 5,
    })
end

local function place_fire(pos)
    local rounded_pos = vector.round(pos)
    local node = minetest.get_node_or_nil(rounded_pos)
    if node and node.name == "air" then
        minetest.set_node(rounded_pos, {name = "mcl_fire:fire"})
    end
end

local function apply_slowness(entity, duration)
    if not entity then return end
    local luaent = entity:get_luaentity()
    if not luaent then return end

    local now = minetest.get_us_time() / 1e6
    local target_time = now + duration

    if luaent._slowed_until and luaent._slowed_until > now then
        luaent._slowed_until = target_time
        return
    end

    local orig_speed = luaent.walk_speed or 1
    local orig_velocity = entity:get_velocity() or {x = 0, y = 0, z = 0}

    luaent._slowed_orig_speed = orig_speed
    luaent._slowed_until = target_time
    luaent.walk_speed = orig_speed * 0.25
    entity:set_velocity(vector.multiply(orig_velocity, 0.25))

    spawn_particles(entity:get_pos())

    local function check_restore()
        if not entity or not entity:get_pos() then return end
        local le = entity:get_luaentity()
        if not le then return end

        local now_check = minetest.get_us_time() / 1e6
        if le._slowed_until and now_check >= le._slowed_until then
            le.walk_speed = le._slowed_orig_speed or 1
            le._slowed_until = nil
            le._slowed_orig_speed = nil
        else
            minetest.after(0.5, check_restore)
        end
    end

    minetest.after(0.5, check_restore)
end

minetest.register_entity("throw_slimeballs:thrown_slimeball", {
    initial_properties = {
        physical = false,
        collide_with_objects = false,
        pointable = false,
        collisionbox = {0, 0, 0, 0, 0, 0},
        visual = "wielditem",
        visual_size = {x = 0.3, y = 0.3},
        textures = {"mcl_mobitems:slimeball"},
    },

    velocity = nil,
    timer = 0,
    itemname = "mcl_mobitems:slimeball",

    set_velocity = function(self, vel)
        self.velocity = vel
    end,

    on_step = function(self, dtime)
        local pos = self.object:get_pos()
        if not self.velocity or not pos then return end

        self.timer = self.timer + dtime
        local next_pos = vector.add(pos, vector.multiply(self.velocity, dtime))
        local ray = minetest.raycast(pos, next_pos, true, true)

        local is_magma = (self.itemname == "mcl_mobitems:magma_cream")

        for pointed in ray do
            if pointed.type == "object" then
                local obj = pointed.ref
                if obj and not obj:is_player() then
                    apply_slowness(obj, SLOW_DURATION)
                    minetest.sound_play("mcl_mobs_slime_small", {pos = pos, gain = 0.5})
                    if is_magma then
                        place_fire(obj:get_pos())
                        -- the magma cream slide instead of bouncing, feature?
                    else
                        self.object:remove()
                        return
                    end
                end
            elseif pointed.type == "node" then
                local normal = vector.normalize(vector.direction(pointed.under, pointed.above))
                self.velocity = vector.reflect(vector.multiply(self.velocity, 0.6), normal)
                if is_magma then
                    place_fire(pointed.above)
                else
                    return
                end
            end
        end

        self.velocity = vector.add(self.velocity, vector.multiply(GRAVITY, dtime))
        self.object:set_pos(next_pos)

        if self.timer > LIFETIME then
            minetest.add_item(pos, self.itemname)
            self.object:remove()
        end
    end,
})

for itemname, data in pairs(THROWABLE_ITEMS) do
    minetest.override_item(itemname, {
        on_use = function(itemstack, user)
            if not user or not user:is_player() then return itemstack end

            local dir = vector.normalize(user:get_look_dir())
            local start_pos = vector.add(user:get_pos(), {x = 0, y = 1.5, z = 0})
            local entity = minetest.add_entity(start_pos, data.entity)

            if entity then
                local luaentity = entity:get_luaentity()
                if luaentity then
                    luaentity:set_velocity(vector.multiply(dir, THROW_SPEED))
                    luaentity.itemname = itemname
                    entity:set_properties({ textures = {data.texture or itemname} })
                end
            end

            itemstack:take_item()
            return itemstack
        end
    })
end
