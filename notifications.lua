local S = minetest.get_translator("mailbox")
local storage = minetest.get_mod_storage()


local function show_notification(name, pos)
    minetest.chat_send_player(name, S("You have new goods in your mailbox at @1", minetest.pos_to_string(pos)))
end


local pending_notifications = minetest.deserialize(storage:get_string("pending_notifications") or "return {}") or {}


local function save_pending()
    storage:set_string("pending_notifications", minetest.serialize(pending_notifications))
end


local function make_key(name, pos)
    return string.format("%s@%s", name, minetest.pos_to_string(pos))
end


local function parse_key(key)
    local name, pos_str = key:match("^(.-)@(.+)$")
    local pos = minetest.string_to_pos(pos_str)
    return name, pos
end


local function send_or_queue_notification(name, pos)
    local meta = minetest.get_meta(pos)
    if not minetest.is_yes(meta:get_string("notify")) then
        return
    end
    if minetest.get_player_by_name(name) then
        show_notification(name, pos)
    elseif minetest.player_exists(name) then
        local key = make_key(name, pos)
        pending_notifications[key] = true
        save_pending()
    end
end


minetest.register_on_joinplayer(
    function(player)
        local name = player:get_player_name()

        for key in pairs(pending_notifications) do
            local pname, pos = parse_key(key)
            if pname == name then
                show_notification(name, pos)
                pending_notifications[key] = nil
            end
        end
        save_pending()
    end
)


return {
    send_or_queue_notification = send_or_queue_notification
}